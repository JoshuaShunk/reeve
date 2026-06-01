#if os(iOS)
import BackgroundTasks
import Foundation

/// Keeps a long-running agent task alive after the user leaves the app, using
/// iOS 26's `BGContinuedProcessingTask`. The system shows progress in the
/// Dynamic Island (or a banner on non-Dynamic-Island devices) and lets the user
/// cancel; while the task runs, the process isn't suspended, so the agent's
/// in-app work continues.
///
/// We don't move the agent loop into the launch handler, the loop keeps running
/// in the chat. This task is a keep-alive that mirrors progress and completes
/// when the agent signals it's done (or the user/system cancels). On iOS < 26
/// nothing here runs; the foreground-driven Live Activity still covers progress.
///
/// Identifier is derived from the bundle id so it works for any signing config;
/// `BGTaskSchedulerPermittedIdentifiers` in Info.plist uses the matching wildcard
/// `$(PRODUCT_BUNDLE_IDENTIFIER).agent.*`.
@available(iOS 26.0, *)
final class AgentBackgroundTask: @unchecked Sendable {
    static let shared = AgentBackgroundTask()

    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "com.reeveapp") + ".agent.run"
    }

    /// Set by the agent model when a task begins so the system's Cancel button
    /// (and task expiration) can stop the agent.
    var cancelHandler: (@Sendable () -> Void)?

    // Progress mirror. Written by the agent model and read by the launch handler;
    // both touch it on the main queue (the handler is registered `using: .main`).
    private var title = "Reeve Agent"
    private var subtitle = "Working…"
    private var step = 0
    private var finished = true
    private var registered = false

    /// Register the launch handler. Call once, during app launch.
    func registerOnce() {
        guard !registered else { return }
        registered = true
        _ = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.identifier, using: .main
        ) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false); return
            }
            self?.run(task)
        }
    }

    /// Submit a request to begin/continue work. Best-effort: if the scheduler
    /// declines (load, unsupported), the foreground Live Activity still works.
    func begin(title: String) {
        self.title = title
        self.subtitle = "Starting…"
        self.step = 0
        self.finished = false
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.identifier, title: title, subtitle: "Working…"
        )
        request.strategy = .queue
        try? BGTaskScheduler.shared.submit(request)
    }

    func update(subtitle: String, step: Int) {
        self.subtitle = subtitle
        self.step = step
    }

    func end() { finished = true }

    private func run(_ task: BGContinuedProcessingTask) {
        task.expirationHandler = { [weak self] in self?.cancelHandler?() }
        // Open-ended work: keep the bar indeterminate but advance the count so the
        // system UI shows forward motion.
        task.progress.totalUnitCount = 0
        Task { @MainActor in
            var lastStep = -1
            while !self.finished {
                if self.step != lastStep {
                    task.updateTitle(self.title, subtitle: self.subtitle)
                    task.progress.completedUnitCount = Int64(self.step)
                    lastStep = self.step
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            task.updateTitle(self.title, subtitle: "Finished")
            task.setTaskCompleted(success: true)
        }
    }
}
#endif
