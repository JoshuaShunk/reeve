import ReeveFeatures
import ReeveModels
import ReevePersistence
import SwiftUI

struct TasksView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String

    @State private var model: TasksModel?

    var body: some View {
        List {
            if let model {
                ForEach(model.tasks) { task in
                    NavigationLink {
                        TaskLogView(model: model, task: task)
                    } label: {
                        TaskRow(task: task)
                    }
                }
            }
        }
        .overlay {
            if let model, model.tasks.isEmpty, !model.isLoading {
                ContentUnavailableView(
                    "No Tasks", systemImage: "list.bullet.rectangle",
                    description: Text(model.errorMessage ?? "No recent tasks on this node.")
                )
            }
        }
        .navigationTitle("Activity")
        .task {
            let created = app.makeTasks(profile: profile, node: node)
            model = created
            await created?.load()
        }
        .refreshable { await model?.load() }
    }
}

private struct TaskRow: View {
    let task: ProxmoxTaskInfo

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(task.type).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let id = task.workerID, !id.isEmpty {
                        Text("#\(id)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let date = task.startDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(task.displayStatus)
                .font(.caption)
                .foregroundStyle(task.isRunning ? Color.secondary : (task.succeeded ? Color.green : Color.red))
                .lineLimit(1)
        }
    }

    @ViewBuilder private var statusIcon: some View {
        if task.isRunning {
            ProgressView().controlSize(.small)
        } else if task.succeeded {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}

private struct TaskLogView: View {
    let model: TasksModel
    let task: ProxmoxTaskInfo

    @State private var lines: [TaskLogLine] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding()
            } else if let error {
                ContentUnavailableView("Couldn't load log", systemImage: "doc.text", description: Text(error))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        Text(line.t)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(task.type)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            do { lines = try await model.log(for: task) }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            loading = false
        }
    }
}
