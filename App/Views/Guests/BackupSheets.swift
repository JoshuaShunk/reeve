import ReeveModels
import ReevePersistence
import SwiftUI

// MARK: - Back up now

struct BackupNowSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let guest: ClusterResource
    let profile: ServerProfile
    var onComplete: () -> Void

    @State private var storages: [String] = []
    @State private var storage = ""
    @State private var mode = "snapshot"
    @State private var compress = "zstd"
    @State private var removeOld = true
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Guest") { Text(guest.displayName).foregroundStyle(.secondary) }
                    Picker("Storage", selection: $storage) {
                        ForEach(storages, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Snapshot").tag("snapshot")
                        Text("Suspend").tag("suspend")
                        Text("Stop").tag("stop")
                    }
                    Picker("Compression", selection: $compress) {
                        Text("ZSTD").tag("zstd")
                        Text("LZO").tag("lzo")
                        Text("GZIP").tag("gzip")
                        Text("None").tag("0")
                    }
                    Toggle("Prune old backups", isOn: $removeOld)
                } footer: {
                    Text("Snapshot mode backs up a running guest with minimal downtime.")
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Back Up Now")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() }
                    else { Button("Back Up") { backup() }.disabled(storage.isEmpty) }
                }
            }
            .task {
                guard let conn = app.profiles.connection(for: profile), let node = guest.node else { return }
                storages = ((try? await app.api.nodeStorages(conn, node: node, content: "backup")) ?? [])
                    .map(\.storage)
                storage = storages.first ?? ""
            }
        }
    }

    private func backup() {
        guard let conn = app.profiles.connection(for: profile),
              let node = guest.node, let vmid = guest.vmid else { return }
        working = true
        Task {
            do {
                try await app.api.createBackup(
                    conn, node: node, vmid: vmid, storage: storage,
                    mode: mode, compress: compress, removeOld: removeOld
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}

// MARK: - Restore

struct RestoreBackupSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let backup: BackupFile
    let profile: ServerProfile
    let node: String
    var onComplete: () -> Void

    @State private var vmid = ""
    @State private var force = false
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Archive") { Text(backup.filename).foregroundStyle(.secondary).lineLimit(1) }
                    TextField("Target VMID", text: $vmid)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } footer: {
                    Text("Restores a \(backup.guestKind?.label ?? "guest") from this backup.")
                }
                Section {
                    Toggle("Overwrite existing guest", isOn: $force)
                } footer: {
                    if force {
                        Text("⚠️ If a guest with this VMID exists, it and its disks will be replaced.")
                            .foregroundStyle(.red)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Restore Backup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() }
                    else {
                        Button("Restore", role: force ? .destructive : nil) { restore() }
                            .disabled(Int(vmid) == nil || backup.guestKind == nil)
                    }
                }
            }
            .onAppear { if vmid.isEmpty, let v = backup.vmid { vmid = String(v) } }
        }
    }

    private func restore() {
        guard let conn = app.profiles.connection(for: profile),
              let id = Int(vmid), let kind = backup.guestKind else { return }
        working = true
        Task {
            do {
                try await app.api.restoreBackup(
                    conn, node: node, kind: kind, vmid: id,
                    archive: backup.volid, storage: nil, force: force
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}
