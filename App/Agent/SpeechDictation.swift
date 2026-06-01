#if os(iOS)
import AVFoundation
import Foundation
import Observation
import Speech

/// Live speech-to-text for the agent composer. Publishes a `transcript` the view
/// mirrors into the input field while listening.
@MainActor
@Observable
final class SpeechDictation {
    enum State: Equatable { case idle, listening, denied }
    private(set) var state: State = .idle
    private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if state == .listening { stop() } else { await start() }
    }

    private func start() async {
        guard let recognizer, recognizer.isAvailable else { state = .denied; return }
        let speechAuth = await withCheckedContinuation {
            (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            // @Sendable so the off-main completion isn't treated as main-actor-isolated.
            SFSpeechRecognizer.requestAuthorization { @Sendable status in cont.resume(returning: status) }
        }
        guard speechAuth == .authorized else { state = .denied; return }
        let micAuth = await AVAudioApplication.requestRecordPermission()
        guard micAuth else { state = .denied; return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // A zero/invalid hardware format would crash installTap, bail gracefully.
            guard format.sampleRate > 0, format.channelCount > 0 else { stop(); return }

            input.removeTap(onBus: 0)
            // The realtime tap runs off-main; capture the request without main-actor isolation.
            nonisolated(unsafe) let bufferSink = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                bufferSink.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            state = .denied
            return
        }

        transcript = ""
        state = .listening
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            // The handler is nonisolated; pull out only Sendable values, then hop to
            // the main actor with an explicit weak capture (avoids "sending self").
            let text = result?.bestTranscription.formattedString
            let isDone = error != nil || (result?.isFinal ?? false)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if isDone { self.stop() }
            }
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
    }
}
#endif
