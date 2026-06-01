import Foundation

// MARK: - Uniform result model
//
// Every service integration maps its own API onto these generic value types, so
// the SwiftUI list/detail (and later the widget) render *any* service with no
// bespoke views. All Codable + Sendable so results cache and cross the App Group.

public enum Health: String, Codable, Sendable, CaseIterable {
    case ok, warn, down, unknown
}

/// One labelled metric. `value` is pre-formatted for display by the integration
/// (it knows the units/locale); `raw` is retained for sorting/thresholds/charts.
public struct Stat: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var value: String
    public var unit: String?
    public var raw: Double?
    public var emphasis: Emphasis

    public enum Emphasis: String, Codable, Sendable { case normal, highlighted }

    public init(
        id: String, label: String, value: String, unit: String? = nil,
        raw: Double? = nil, emphasis: Emphasis = .normal
    ) {
        self.id = id; self.label = label; self.value = value
        self.unit = unit; self.raw = raw; self.emphasis = emphasis
    }

    public var displayValue: String { unit.map { "\(value)\($0)" } ?? value }
}

/// A free-form key/value row for the detail screen.
public struct DetailRow: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var label: String
    public var value: String
    public init(id: String, label: String, value: String) {
        self.id = id; self.label = label; self.value = value
    }
}

/// The uniform snapshot every integration returns.
public struct ServiceStatus: Codable, Sendable, Hashable {
    public var health: Health
    public var summary: String?
    public var stats: [Stat]
    public var details: [DetailRow]
    public var fetchedAt: Date
    public var version: String?

    public init(
        health: Health, summary: String? = nil, stats: [Stat] = [],
        details: [DetailRow] = [], fetchedAt: Date = Date(), version: String? = nil
    ) {
        self.health = health; self.summary = summary; self.stats = stats
        self.details = details; self.fetchedAt = fetchedAt; self.version = version
    }

    public var highlightedStats: [Stat] { stats.filter { $0.emphasis == .highlighted } }
}

/// What the UI binds to per instance.
public enum ServiceState: Sendable {
    case loading
    case loaded(ServiceStatus)
    case failed(message: String, at: Date)
}

// MARK: - Type metadata (declared as data, drives generic UI)

public enum ServiceCategory: String, Codable, Sendable, CaseIterable {
    case dns, media, storage, automation, monitoring, network, containers, other

    public var label: String {
        switch self {
        case .dns: "DNS & Ad-blocking"
        case .media: "Media"
        case .storage: "Storage"
        case .automation: "Home Automation"
        case .monitoring: "Monitoring"
        case .network: "Network"
        case .containers: "Containers"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .dns: "shield.lefthalf.filled"
        case .media: "play.rectangle.on.rectangle"
        case .storage: "externaldrive"
        case .automation: "house"
        case .monitoring: "waveform.path.ecg"
        case .network: "network"
        case .containers: "shippingbox"
        case .other: "square.grid.2x2"
        }
    }
}

/// An icon for a service type, an SF Symbol for now.
public struct ServiceIcon: Sendable, Hashable {
    public var systemName: String
    public init(systemName: String) { self.systemName = systemName }
    public static func symbol(_ name: String) -> ServiceIcon { ServiceIcon(systemName: name) }
}

/// How an integration authenticates. Declared as data so most integrations need
/// no auth code, a helper applies it to the request.
public enum AuthMethod: Sendable, Codable, Hashable {
    case none
    case bearer
    case basic(usernameField: String)
    case header(name: String)
    case queryItem(name: String)
    case sessionToken
    case custom

    /// Whether the Add form should show a secret (password/token/key) field.
    public var needsSecret: Bool {
        switch self {
        case .none: false
        default: true
        }
    }

    public var secretLabel: String {
        switch self {
        case .basic: "Password"
        case .bearer: "Token"
        case .header, .queryItem: "API key"
        default: "Secret"
        }
    }
}

/// A data-driven config field. The generic Add/Edit form is generated from these.
public struct ConfigField: Identifiable, Codable, Sendable, Hashable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var kind: Kind
    public var placeholder: String?
    public var defaultValue: String?
    public var isRequired: Bool

    public enum Kind: String, Codable, Sendable {
        case text, url, number, port, toggle, secret
    }

    public init(
        key: String, label: String, kind: Kind = .text,
        placeholder: String? = nil, defaultValue: String? = nil, isRequired: Bool = false
    ) {
        self.key = key; self.label = label; self.kind = kind
        self.placeholder = placeholder; self.defaultValue = defaultValue
        self.isRequired = isRequired
    }
}
