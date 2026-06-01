#if os(iOS)
import ActivityKit
import Foundation
import ReeveModels

/// Starts/updates/ends a Live Activity for a running Proxmox task so it appears
/// on the Lock Screen and in the Dynamic Island. Tracks one task at a time and is
/// driven from the foreground refresh loop (no push server needed).
///
/// We deliberately store only the tracked UPID (a `Sendable` String), never the
/// non-Sendable `Activity` handle, and end via the static `Activity.activities`
/// list, this keeps Swift 6 region checking happy without main-actor hops.
final class LiveActivityController: @unchecked Sendable {
    static let shared = LiveActivityController()

    private var trackedUPID: String?

    func sync(tasks: [ProxmoxTaskInfo], enabled: Bool) {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            if trackedUPID != nil { Task { await endAll(status: "Stopped", succeeded: true) } }
            return
        }

        if let tracked = trackedUPID {
            if let finished = tasks.first(where: { $0.upid == tracked && !$0.isRunning }) {
                Task {
                    await endAll(status: finished.succeeded ? "Completed" : "Failed",
                                 succeeded: finished.succeeded)
                }
            } else if !tasks.contains(where: { $0.upid == tracked }) {
                Task { await endAll(status: "Finished", succeeded: true) }
            }
            return
        }

        let running = tasks.filter(\.isRunning).sorted { ($0.starttime ?? 0) > ($1.starttime ?? 0) }
        if let task = running.first { start(task) }
    }

    private func start(_ task: ProxmoxTaskInfo) {
        let attributes = TaskActivityAttributes(
            title: AlertCenter.taskTypeLabel(task.type),
            target: task.workerID ?? "",
            node: ""
        )
        let state = TaskActivityAttributes.ContentState(
            statusText: "Running…", finished: false, succeeded: false
        )
        if (try? Activity.request(
            attributes: attributes, content: .init(state: state, staleDate: nil)
        )) != nil {
            trackedUPID = task.upid
        }
    }

    private func endAll(status: String, succeeded: Bool) async {
        trackedUPID = nil
        let final = TaskActivityAttributes.ContentState(
            statusText: status, finished: true, succeeded: succeeded
        )
        for activity in Activity<TaskActivityAttributes>.activities {
            await activity.end(.init(state: final, staleDate: nil),
                               dismissalPolicy: .after(.now.addingTimeInterval(5)))
        }
    }
}
#endif
