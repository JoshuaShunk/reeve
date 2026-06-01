#if os(iOS)
import SwiftTerm
import SwiftUI
import UIKit

/// A SwiftUI terminal backed by SwiftTerm, driven by a `PTYTerminalSession`.
/// Keystrokes go to the session's stdin; the session's output feeds the emulator.
public struct SSHTerminalView: UIViewRepresentable {
    private let session: PTYTerminalSession

    public init(session: PTYTerminalSession) { self.session = session }

    public func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator
        terminal.backgroundColor = .black
        context.coordinator.attach(to: terminal)
        return terminal
    }

    public func updateUIView(_ uiView: TerminalView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    public final class Coordinator: NSObject, TerminalViewDelegate {
        private let session: PTYTerminalSession
        private weak var terminal: TerminalView?
        private var started = false
        private var pumpTask: Task<Void, Never>?

        init(session: PTYTerminalSession) { self.session = session }

        @MainActor func attach(to terminal: TerminalView) {
            self.terminal = terminal
            guard !started else { return }
            started = true
            let cols = max(Int(terminal.getTerminal().cols), 80)
            let rows = max(Int(terminal.getTerminal().rows), 24)
            session.start(cols: cols, rows: rows)
            pumpTask = Task { @MainActor in
                for await data in session.output {
                    terminal.feed(byteArray: ArraySlice(data))
                }
            }
        }

        deinit { pumpTask?.cancel(); session.stop() }

        // MARK: TerminalViewDelegate

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            session.sendInput(Data(data))
        }
        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        public func setTerminalTitle(source: TerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func scrolled(source: TerminalView, position: Double) {}
        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        public func bell(source: TerminalView) {}
        public func clipboardCopy(source: TerminalView, content: Data) {}
        public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
#endif
