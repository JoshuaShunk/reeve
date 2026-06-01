#if os(iOS)
import ActivityKit
import Foundation

/// Live Activity describing a running Proxmox task (e.g. a backup) so it can be
/// shown on the Lock Screen and in the Dynamic Island. Shared between the app
/// (which starts/updates/ends it) and the widget extension (which renders it).
public struct TaskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var statusText: String
        public var finished: Bool
        public var succeeded: Bool

        public init(statusText: String, finished: Bool, succeeded: Bool) {
            self.statusText = statusText
            self.finished = finished
            self.succeeded = succeeded
        }
    }

    public var title: String     // friendly task type, e.g. "Backup"
    public var target: String    // worker id / vmid, e.g. "104"
    public var node: String

    public init(title: String, target: String, node: String) {
        self.title = title
        self.target = target
        self.node = node
    }
}
#endif
