import Foundation
import ReeveModels
import ReevePersistence
import ReeveTerminal
import Observation

/// Loads node hardware temperatures/fan speeds over SSH (`sensors -j`) and caches
/// them per node, shared across the dashboard and node-detail screens via
/// `AppModel`. Proxmox doesn't expose sensors through its REST API, so this reuses
/// the same SSH credentials the console and agent use; it degrades gracefully when
/// SSH isn't configured or `lm-sensors` isn't installed.
@MainActor
@Observable
final class SensorsStore {
    enum State: Sendable, Equatable {
        case unknown                    // not attempted yet
        case unavailable                // no SSH credentials for this server
        case empty                      // SSH worked but no sensors were reported
        case loaded(NodeSensors)
        case failed(String)

        var sensors: NodeSensors? {
            if case .loaded(let value) = self { return value }
            return nil
        }
    }

    private var states: [String: State] = [:]
    private var lastFetched: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private let credentials = SSHCredentialStore()

    /// How long a reading stays fresh before a background refresh re-fetches it.
    /// Keeps the dashboard's fast refresh loop from opening an SSH session every tick.
    private let freshness: TimeInterval = 60

    func state(forNode node: String) -> State { states[node] ?? .unknown }
    func sensors(forNode node: String) -> NodeSensors? { states[node]?.sensors }

    /// Refresh a node's sensors over SSH. No-ops if a fetch is already running for
    /// that node; skips a network round-trip if a reading is still fresh unless
    /// `force` is set (pull-to-refresh / first appearance).
    func refresh(profile: ServerProfile, node: String, force: Bool = false) async {
        guard !node.isEmpty, !inFlight.contains(node) else { return }
        if !force, let last = lastFetched[node], Date().timeIntervalSince(last) < freshness,
           states[node]?.sensors != nil || states[node] == .empty {
            return
        }
        guard let credential = credentials.credential(for: profile.id),
              let password = credentials.password(for: profile.id) else {
            states[node] = .unavailable
            return
        }

        inFlight.insert(node)
        defer { inFlight.remove(node) }
        do {
            let output = try await runSSHCommand(
                host: credential.host, port: credential.port,
                username: credential.username, password: password,
                command: "sensors -j 2>/dev/null", timeoutSeconds: 12
            )
            states[node] = NodeSensors.parse(sensorsJSON: output).map(State.loaded) ?? .empty
        } catch {
            states[node] = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
        lastFetched[node] = Date()
    }
}
