import ReeveModels
import ReevePersistence
import SwiftUI

struct BackupJobsView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let node: String

    @State private var jobs: [BackupJob] = []
    @State private var loaded = false
    @State private var showingAdd = false
    @State private var error: String?

    var body: some View {
        List {
            if loaded && jobs.isEmpty {
                ContentUnavailableView("No Backup Jobs", systemImage: "calendar.badge.clock",
                                       description: Text("No scheduled backups configured."))
            }
            ForEach(jobs) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.comment?.isEmpty == false ? job.comment! : job.selection)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { job.isEnabled }, set: { setEnabled(job, $0) }
                        )).labelsHidden()
                    }
                    HStack(spacing: 10) {
                        if let schedule = job.schedule {
                            Label(schedule, systemImage: "clock").font(.caption)
                        }
                        if let storage = job.storage {
                            Label(storage, systemImage: "externaldrive").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    Text("\(job.selection) · \(job.mode ?? "snapshot")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(job) }
                }
            }
        }
        .navigationTitle("Backup Jobs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .toolbar { ToolbarItem { Button("Add", systemImage: "plus") { showingAdd = true } } }
        .alert("Failed", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $showingAdd) {
            AddBackupJobSheet(profile: profile, node: node) { Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let conn = app.profiles.connection(for: profile) else { return }
        jobs = ((try? await app.api.backupJobs(conn)) ?? []).sorted { $0.id < $1.id }
        loaded = true
    }

    private func setEnabled(_ job: BackupJob, _ on: Bool) {
        guard let conn = app.profiles.connection(for: profile) else { return }
        Task {
            do {
                try await app.api.updateBackupJob(conn, id: job.id, parameters: ["enabled": on ? "1" : "0"])
                await load()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func delete(_ job: BackupJob) {
        guard let conn = app.profiles.connection(for: profile) else { return }
        Task {
            do { try await app.api.deleteBackupJob(conn, id: job.id); await load() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct AddBackupJobSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let profile: ServerProfile
    let node: String
    var onComplete: () -> Void

    @State private var storages: [String] = []
    @State private var storage = ""
    @State private var schedule = "02:00"
    @State private var mode = "snapshot"
    @State private var allGuests = true
    @State private var vmids = ""
    @State private var comment = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Storage", selection: $storage) {
                        ForEach(storages, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Schedule", text: $schedule)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    Picker("Mode", selection: $mode) {
                        Text("Snapshot").tag("snapshot")
                        Text("Suspend").tag("suspend")
                        Text("Stop").tag("stop")
                    }
                } footer: {
                    Text("Schedule is a systemd calendar event, e.g. 02:00 (daily), mon..fri 22:30, or *-*-* 03:00.")
                }
                Section {
                    Toggle("All guests", isOn: $allGuests)
                    if !allGuests {
                        TextField("VMIDs (comma separated)", text: $vmids)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                    }
                    TextField("Comment", text: $comment)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("New Backup Job")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() }
                    else { Button("Create") { create() }.disabled(storage.isEmpty || schedule.isEmpty) }
                }
            }
            .task {
                guard let conn = app.profiles.connection(for: profile) else { return }
                storages = ((try? await app.api.nodeStorages(conn, node: node, content: "backup")) ?? [])
                    .map(\.storage)
                storage = storages.first ?? ""
            }
        }
    }

    private func create() {
        guard let conn = app.profiles.connection(for: profile) else { return }
        var params = ["storage": storage, "schedule": schedule, "mode": mode, "enabled": "1"]
        if allGuests { params["all"] = "1" }
        else { params["vmid"] = vmids.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",") }
        if !comment.isEmpty { params["comment"] = comment }
        working = true
        Task {
            do {
                try await app.api.createBackupJob(conn, parameters: params)
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}
