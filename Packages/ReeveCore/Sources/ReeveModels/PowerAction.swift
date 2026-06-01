import Foundation

/// Guest power operations. Each maps to `POST …/{kind}/{vmid}/status/{action}`.
/// Requires the `VM.PowerMgmt` privilege on the token.
public enum PowerAction: String, Sendable, CaseIterable, Identifiable {
    case start
    case shutdown   // graceful ACPI shutdown
    case stop       // hard power-off
    case reboot

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .start: "Start"
        case .shutdown: "Shut Down"
        case .stop: "Stop"
        case .reboot: "Reboot"
        }
    }

    /// Whether this action is destructive enough to warrant a confirmation prompt.
    public var isDisruptive: Bool { self != .start }

    public var symbol: String {
        switch self {
        case .start: "play.fill"
        case .shutdown: "moon.fill"
        case .stop: "stop.fill"
        case .reboot: "arrow.clockwise"
        }
    }
}

/// Minimal `GET /version` payload, used to test a connection.
public struct PVEVersion: Decodable, Sendable {
    public let version: String
    public let release: String?
    public let repoid: String?
}
