#if os(iOS)
import ActivityKit
import Foundation

/// Live Activity describing a long-running AI-agent task (e.g. setting up a
/// service) so its progress shows on the Lock Screen and in the Dynamic Island.
/// Shared between the app (which starts/updates/ends it from the foreground) and
/// the widget extension (which renders it).
public struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// What the agent is doing right now (e.g. "Installing Java").
        public var detail: String
        /// Number of steps (tool calls) completed so far.
        public var step: Int
        public var finished: Bool
        public var succeeded: Bool

        public init(detail: String, step: Int, finished: Bool, succeeded: Bool) {
            self.detail = detail
            self.step = step
            self.finished = finished
            self.succeeded = succeeded
        }
    }

    /// The task headline, derived from the user's request (e.g. "Set up AdGuard").
    public var title: String

    public init(title: String) {
        self.title = title
    }
}
#endif
