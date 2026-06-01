#if os(iOS)
import ActivityKit
import ReeveModels
import SwiftUI
import WidgetKit

/// Lock Screen banner + Dynamic Island presentation for a long-running agent task.
struct AgentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: icon(context.state))
                    .font(.title2)
                    .foregroundStyle(tint(context.state))
                    .symbolEffect(.pulse, isActive: !context.state.finished)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Text(context.state.detail).font(.caption)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !context.state.finished, context.state.step > 0 {
                    Text("\(context.state.step)").font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.35))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: icon(context.state)).foregroundStyle(tint(context.state))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(context.state.detail).font(.caption2)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(context.state)).foregroundStyle(tint(context.state))
            } compactTrailing: {
                if !context.state.finished, context.state.step > 0 {
                    Text("\(context.state.step)").font(.caption2.monospacedDigit())
                }
            } minimal: {
                Image(systemName: icon(context.state)).foregroundStyle(tint(context.state))
            }
        }
    }

    private func icon(_ state: AgentActivityAttributes.ContentState) -> String {
        if !state.finished { return "gearshape.2" }
        return state.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }

    private func tint(_ state: AgentActivityAttributes.ContentState) -> Color {
        if !state.finished { return .indigo }
        return state.succeeded ? .green : .red
    }
}
#endif
