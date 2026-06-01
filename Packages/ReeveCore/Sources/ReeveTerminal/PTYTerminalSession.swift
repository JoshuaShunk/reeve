import Citadel
import Foundation
import NIOCore
import NIOSSH

/// Wraps a non-Sendable `TTYStdinWriter` so it can be captured by the writer task.
/// The underlying NIO channel is thread-safe; access is serialised through a task.
private struct WriterBox: @unchecked Sendable {
    let writer: TTYStdinWriter
}

/// A full interactive PTY over SSH, suitable for driving a terminal emulator.
/// Exposes an `output` byte stream (consumed on the main actor by the terminal
/// view) and `sendInput` for keystrokes. Optionally runs an initial command,
/// e.g. `pct enter 103` or `qm terminal 106` for an in-guest console.
@available(macOS 15.0, *)
public final class PTYTerminalSession: @unchecked Sendable {
    public let output: AsyncStream<Data>
    private let outputCont: AsyncStream<Data>.Continuation
    private let input: AsyncStream<Data>
    private let inputCont: AsyncStream<Data>.Continuation

    private let host: String
    private let port: Int
    private let username: String
    private let password: String
    private let initialCommand: String?
    private var task: Task<Void, Never>?

    public init(
        host: String, port: Int = 22, username: String, password: String,
        initialCommand: String? = nil
    ) {
        self.host = host; self.port = port
        self.username = username; self.password = password
        self.initialCommand = initialCommand
        (output, outputCont) = AsyncStream<Data>.makeStream()
        (input, inputCont) = AsyncStream<Data>.makeStream()
    }

    public func sendInput(_ data: Data) { inputCont.yield(data) }

    public func stop() {
        task?.cancel()
        inputCont.finish()
    }

    public func start(cols: Int, rows: Int) {
        task = Task.detached { [self] in
            do {
                let client = try await SSHClient.connect(
                    host: host, port: port,
                    authenticationMethod: .passwordBased(username: username, password: password),
                    hostKeyValidator: .acceptAnything(),
                    reconnect: .never
                )
                let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([.ECHO: 1])
                )
                try await client.withPTY(request) { inbound, outbound in
                    let box = WriterBox(writer: outbound)
                    let writer = Task { [input, initialCommand] in
                        if let initialCommand {
                            try? await box.writer.write(ByteBuffer(string: initialCommand + "\n"))
                        }
                        for await chunk in input {
                            var buffer = ByteBuffer()
                            buffer.writeBytes(chunk)
                            try? await box.writer.write(buffer)
                        }
                    }
                    defer { writer.cancel() }
                    for try await event in inbound {
                        switch event {
                        case .stdout(let buffer), .stderr(let buffer):
                            outputCont.yield(Data(buffer.readableBytesView))
                        }
                    }
                }
                try? await client.close()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                outputCont.yield(Data("\r\n[connection closed: \(message)]\r\n".utf8))
            }
            outputCont.finish()
        }
    }
}
