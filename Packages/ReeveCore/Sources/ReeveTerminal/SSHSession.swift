import Citadel
import Foundation
import NIOCore
import Observation

public enum SSHSessionError: LocalizedError {
    case notConnected
    case timedOut
    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected."
        case .timedOut: "The command did not finish in time."
        }
    }
}

/// Holds the non-Sendable `SSHClient` off the main actor. `SSHClient` is backed
/// by a thread-safe SwiftNIO channel and Citadel opens a fresh channel per
/// command, so access is safe; we additionally serialise calls through the
/// `@MainActor` view model (which disables input while a command is running).
/// Binding the client to a local `let` before each call keeps the Swift 6 region
/// checker happy (the value being sent is task-local, not shared mutable state).
final class SSHConnection: @unchecked Sendable {
    private var client: SSHClient?

    func connect(host: String, port: Int, username: String, password: String) async throws {
        let connected = try await SSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: .passwordBased(username: username, password: password),
            hostKeyValidator: .acceptAnything(),   // self-hosted homelab; key isn't pre-known
            reconnect: .never
        )
        client = connected
    }

    func execute(_ command: String) async throws -> String {
        guard let client else { throw SSHSessionError.notConnected }
        let buffer = try await client.executeCommand(command, mergeStreams: true)
        return String(buffer: buffer)
    }

    func close() async {
        let existing = client
        client = nil
        try? await existing?.close()
    }
}

/// One-shot helper: connect over SSH, run a single command, return its combined
/// stdout+stderr, then disconnect. Used by the agent to execute commands inside a
/// guest (via `pct exec` / `qm guest exec` on the node) without standing up a
/// persistent terminal session.
///
/// If `timeoutSeconds > 0` the call is abandoned after that many seconds and the
/// connection is torn down (which closes the remote channel). This is a safety
/// net for a command that never returns; callers should *also* bound the command
/// remotely (e.g. coreutils `timeout`) so any child processes are signalled.
public func runSSHCommand(
    host: String, port: Int = 22, username: String, password: String,
    command: String, timeoutSeconds: Int = 0
) async throws -> String {
    let connection = SSHConnection()
    try await connection.connect(host: host, port: port, username: username, password: password)
    do {
        let output: String
        if timeoutSeconds > 0 {
            output = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await connection.execute(command) }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                    throw SSHSessionError.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } else {
            output = try await connection.execute(command)
        }
        await connection.close()
        return output
    } catch {
        await connection.close()   // tears down the channel, aborting an in-flight command
        throw error
    }
}

/// A persistent SSH connection that runs commands and accumulates a transcript.
/// Uses exec channels (not a full PTY), which keeps output clean, most CLI tools
/// don't emit colour/escape codes when stdout isn't a TTY, and avoids needing a
/// terminal emulator. Working directory persists across commands via a wrapper.
@MainActor
@Observable
public final class SSHSession {
    public enum Status: Sendable, Equatable {
        case disconnected, connecting, connected
        case failed(String)
    }

    public private(set) var status: Status = .disconnected
    public private(set) var transcript: String = ""
    public private(set) var workingDirectory: String = "~"
    public private(set) var isBusy = false

    private let host: String
    private let port: Int
    private let username: String
    private let password: String
    private let connection = SSHConnection()
    private var cwd = ""   // empty → resolves to $HOME on first command

    public init(host: String, port: Int = 22, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    public func connect() async {
        if case .connected = status { return }
        status = .connecting
        do {
            try await connection.connect(
                host: host, port: port, username: username, password: password
            )
            status = .connected
            append("Connected to \(username)@\(host)\n")
        } catch {
            status = .failed(Self.describe(error))
            append("Connection failed: \(Self.describe(error))\n")
        }
    }

    public func disconnect() async {
        await connection.close()
        status = .disconnected
    }

    /// Run a command on the persistent connection, echoing it and its output into
    /// the transcript. `cd` persists because we re-enter the tracked directory and
    /// report the resulting `pwd` via a sentinel that we strip from the output.
    public func run(_ command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        append("\(promptString) \(trimmed)\n")

        guard case .connected = status else {
            append("Not connected.\n")
            return
        }
        isBusy = true
        defer { isBusy = false }

        let marker = "__HL_CWD__"
        let cdPrefix = cwd.isEmpty ? "cd 2>/dev/null" : "cd \(shellQuote(cwd)) 2>/dev/null"
        let wrapped = "\(cdPrefix); \(trimmed)\nprintf '\\n\(marker)%s\\n' \"$(pwd)\""
        do {
            var text = try await connection.execute(wrapped)
            if let range = text.range(of: marker) {
                let after = text[range.upperBound...]
                if let newline = after.firstIndex(of: "\n") {
                    cwd = String(after[..<newline])
                    workingDirectory = cwd
                }
                text = String(text[..<range.lowerBound])
            }
            append(text)
            if !text.hasSuffix("\n") { append("\n") }
        } catch {
            append("\(Self.describe(error))\n")
        }
    }

    public func clear() { transcript = "" }

    private var promptString: String {
        let dir = (workingDirectory as NSString).lastPathComponent
        return "\(username)@\(host):\(dir.isEmpty ? "~" : dir)$"
    }

    private func append(_ text: String) { transcript += text }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
