import ReeveFeatures
import ReeveModels
import ReevePersistence
import SwiftUI

struct SnapshotsView: View {
    @Environment(AppModel.self) private var app
    let guest: ClusterResource
    let profile: ServerProfile

    @State private var model: SnapshotsModel?
    @State private var showingCreate = false
    @State private var pendingRollback: Snapshot?
    @State private var pendingDelete: Snapshot?

    var body: some View {
        List {
            if let model {
                ForEach(model.listed) { snapshot in
                    SnapshotRow(snapshot: snapshot)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = snapshot } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { pendingRollback = snapshot } label: {
                                Label("Roll Back", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        }
                }
            }
        }
        .overlay {
            if let message = model?.busyMessage {
                busyOverlay(message)
            } else if model?.listed.isEmpty == true, model?.isLoading == false {
                ContentUnavailableView(
                    "No Snapshots", systemImage: "camera.viewfinder",
                    description: Text("Capture the current state with a snapshot.")
                )
            }
        }
        .navigationTitle("Snapshots")
        .toolbar {
            ToolbarItem {
                Button("New Snapshot", systemImage: "plus") { showingCreate = true }
                    .disabled(model?.busyMessage != nil)
            }
        }
        .task {
            let created = app.makeSnapshots(for: guest, profile: profile)
            model = created
            await created?.load()
        }
        .refreshable { await model?.load() }
        .sheet(isPresented: $showingCreate) {
            CreateSnapshotSheet(isVM: guest.type == .qemu) { name, description, includeRAM in
                Task { await model?.create(name: name, description: description, includeRAM: includeRAM) }
            }
        }
        .confirmationDialog(
            "Roll back to “\(pendingRollback?.name ?? "")”?",
            isPresented: binding($pendingRollback), titleVisibility: .visible
        ) {
            Button("Roll Back", role: .destructive) {
                if let snapshot = pendingRollback {
                    Task { await model?.rollback(snapshot) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The guest will be restored to this snapshot. Unsaved changes since then are lost.")
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: binding($pendingDelete), titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let snapshot = pendingDelete {
                    Task { await model?.delete(snapshot) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Snapshot Error",
            isPresented: Binding(
                get: { model?.errorMessage != nil },
                set: { if !$0 { model?.errorMessage = nil } }
            )
        ) {
            Button("OK") { model?.errorMessage = nil }
        } message: {
            Text(model?.errorMessage ?? "")
        }
    }

    private func binding(_ source: Binding<Snapshot?>) -> Binding<Bool> {
        Binding(get: { source.wrappedValue != nil }, set: { if !$0 { source.wrappedValue = nil } })
    }

    private func busyOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(message).font(.callout)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "camera.viewfinder").foregroundStyle(.secondary)
                Text(snapshot.name).font(.body.weight(.medium))
                if snapshot.includesRAM {
                    Image(systemName: "memorychip").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let date = snapshot.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let description = snapshot.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CreateSnapshotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isVM: Bool
    let onCreate: (String, String, Bool) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var includeRAM = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    TextField("Description (optional)", text: $description)
                } footer: {
                    Text("Letters, digits, - and _; must start with a letter.")
                }
                if isVM {
                    Section {
                        Toggle("Include RAM", isOn: $includeRAM)
                    } footer: {
                        Text("Saves the running memory state (larger, slower).")
                    }
                }
            }
            .navigationTitle("New Snapshot")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, description, includeRAM)
                        dismiss()
                    }
                    .disabled(!Snapshot.isValidName(name))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
