import ReeveFeatures
import ReeveModels
import ReevePersistence
import SwiftUI

struct BackupsView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String
    let storages: [String]

    @State private var model: BackupsModel?
    @State private var restoring: BackupFile?

    var body: some View {
        List {
            if let model {
                ForEach(model.backups) { backup in
                    BackupRow(backup: backup)
                        .swipeActions(edge: .leading) {
                            Button("Restore", systemImage: "arrow.uturn.backward.circle") {
                                restoring = backup
                            }.tint(.blue)
                        }
                        .contextMenu {
                            Button("Restore…", systemImage: "arrow.uturn.backward.circle") {
                                restoring = backup
                            }
                        }
                }
            }
        }
        .sheet(item: $restoring) { backup in
            RestoreBackupSheet(backup: backup, profile: profile, node: node) {
                Task { await model?.load() }
            }
        }
        .overlay {
            if let model, model.backups.isEmpty, !model.isLoading {
                ContentUnavailableView(
                    "No Backups", systemImage: "archivebox",
                    description: Text(model.errorMessage ?? "No vzdump backups found on this node.")
                )
            }
        }
        .navigationTitle("Backups")
        .task {
            let created = app.makeBackups(profile: profile, node: node, storages: storages)
            model = created
            await created?.load()
        }
        .refreshable { await model?.load() }
    }
}

private struct BackupRow: View {
    let backup: BackupFile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: backup.guestKind == .qemu ? "desktopcomputer" : "shippingbox")
                    .foregroundStyle(.secondary)
                Text(backup.vmid.map { "VMID \($0)" } ?? backup.filename)
                    .font(.body.weight(.medium))
                Spacer()
                Text(Format.bytes(backup.size))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(backup.filename).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if let date = backup.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
