import Foundation

/// What a configurable widget can point at: one of the user's servers or services.
public enum WidgetTargetKind: String, Codable, Sendable, Hashable {
    case server, service
}

/// A selectable widget target, listed in the widget's configuration picker. Kept
/// tiny and self-describing (incl. an SF Symbol name) so the widget extension can
/// render it without importing the integration catalog.
public struct WidgetTarget: Identifiable, Codable, Sendable, Hashable {
    public var id: String          // server: profile UUID string; service: instance UUID string
    public var name: String
    public var kind: WidgetTargetKind
    public var symbolName: String

    public init(id: String, name: String, kind: WidgetTargetKind, symbolName: String) {
        self.id = id; self.name = name; self.kind = kind; self.symbolName = symbolName
    }
}

/// One labelled metric on a widget (optionally with a 0...1 gauge value).
public struct WidgetMetric: Codable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
    public var fraction: Double?   // 0...1 for a gauge/bar, nil for plain text

    public init(label: String, value: String, fraction: Double? = nil) {
        self.label = label; self.value = value; self.fraction = fraction
    }
}

/// The cached, network-free data a widget renders for a chosen target. The app
/// writes these to the shared App Group; the widget reads the one it's set to.
public struct WidgetItemSnapshot: Codable, Sendable, Hashable {
    public var target: WidgetTarget
    public var date: Date
    public var health: Health
    public var caption: String?        // e.g. "14/15 guests up" or "Online"
    public var metrics: [WidgetMetric] // up to ~3 shown

    public init(
        target: WidgetTarget, date: Date = Date(), health: Health,
        caption: String? = nil, metrics: [WidgetMetric] = []
    ) {
        self.target = target; self.date = date; self.health = health
        self.caption = caption; self.metrics = metrics
    }
}
