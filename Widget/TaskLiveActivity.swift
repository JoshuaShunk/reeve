#if os(iOS)
import ActivityKit
import AppIntents
import ReeveModels
import SwiftUI
import WidgetKit

/// Lock Screen banner + Dynamic Island presentation for a running Proxmox task.
struct TaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: icon(context.state))
                    .font(.title2)
                    .foregroundStyle(tint(context.state))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(context.attributes)).font(.headline)
                    Text(context.state.statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.35))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "server.rack").foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: icon(context.state)).foregroundStyle(tint(context.state))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(headline(context.attributes)).font(.caption.weight(.semibold))
                        Text(context.state.statusText).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(context.state)).foregroundStyle(tint(context.state))
            } compactTrailing: {
                Text(context.attributes.title).font(.caption2)
            } minimal: {
                Image(systemName: icon(context.state)).foregroundStyle(tint(context.state))
            }
        }
    }

    private func headline(_ attributes: TaskActivityAttributes) -> String {
        attributes.target.isEmpty ? attributes.title : "\(attributes.title) · \(attributes.target)"
    }

    private func icon(_ state: TaskActivityAttributes.ContentState) -> String {
        if !state.finished { return "arrow.triangle.2.circlepath" }
        return state.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }

    private func tint(_ state: TaskActivityAttributes.ContentState) -> Color {
        if !state.finished { return .blue }
        return state.succeeded ? .green : .red
    }
}

// MARK: - iOS 18 Control Center control

@available(iOS 18.0, *)
struct OpenReeveControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.reeveapp.control.open") {
            ControlWidgetButton(action: OpenReeveIntent()) {
                Label("Reeve", systemImage: "server.rack")
            }
        }
        .displayName("Open Reeve")
        .description("Jump straight to your homelab dashboard.")
    }
}

@available(iOS 18.0, *)
struct OpenReeveIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Reeve"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
#endif
