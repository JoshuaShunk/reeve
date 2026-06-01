#if os(iOS)
import ActivityKit
import ReeveModels

/// Starts/updates/ends the Live Activity for a long-running agent task. Driven
/// from the foreground agent loop (no push server). Only `Sendable` values
/// (the content-state fields) cross into the async work; the non-Sendable
/// `Activity` handles are created and consumed inside one nonisolated context,
/// which keeps Swift 6 region checking happy (same approach as
/// `LiveActivityController`).
enum AgentActivityController {
    static func start(title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = AgentActivityAttributes.ContentState(
            detail: "Starting…", step: 0, finished: false, succeeded: false
        )
        _ = try? Activity.request(
            attributes: AgentActivityAttributes(title: title),
            content: .init(state: state, staleDate: nil)
        )
    }

    static func update(detail: String, step: Int) {
        let state = AgentActivityAttributes.ContentState(
            detail: detail, step: step, finished: false, succeeded: false
        )
        Task { await apply(state, end: false) }
    }

    static func end(detail: String, succeeded: Bool) {
        let state = AgentActivityAttributes.ContentState(
            detail: detail, step: 0, finished: true, succeeded: succeeded
        )
        Task { await apply(state, end: true) }
    }

    private static func apply(_ state: AgentActivityAttributes.ContentState, end: Bool) async {
        for activity in Activity<AgentActivityAttributes>.activities {
            if end {
                await activity.end(.init(state: state, staleDate: nil),
                                   dismissalPolicy: .after(.now.addingTimeInterval(8)))
            } else {
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }
}
#endif
