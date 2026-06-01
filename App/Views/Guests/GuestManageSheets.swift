import ReeveModels
import ReevePersistence
import SwiftUI

/// Which management sheet is open for a guest.
enum GuestManageSheet: String, Identifiable {
    case clone, editResources, resizeDisk, migrate, backup, tagsNotes, cloudInit
    var id: String { rawValue }
}

private struct GuestTarget {
    let connection: ServerConnection
    let node: String
    let vmid: Int
    let kind: GuestKind
}

private func target(_ app: AppModel, _ profile: ServerProfile, _ guest: ClusterResource) -> GuestTarget? {
    guard let connection = app.profiles.connection(for: profile),
          let node = guest.node, let vmid = guest.vmid,
          let kind = guest.type.guestKind else { return nil }
    return GuestTarget(connection: connection, node: node, vmid: vmid, kind: kind)
}

// MARK: - Clone

struct CloneGuestSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let guest: ClusterResource
    let profile: ServerProfile
    var onComplete: () -> Void

    @State private var newID = ""
    @State private var name = ""
    @State private var fullClone = false
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Source") { Text(guest.displayName).foregroundStyle(.secondary) }
                    TextField("New VMID", text: $newID)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField(guest.type.guestKind == .qemu ? "Name" : "Hostname", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                } footer: {
                    Text("A linked clone shares the template's disks; a full clone copies them.")
                }
                Section {
                    Toggle("Full clone", isOn: $fullClone)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Clone")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() }
                    else { Button("Clone") { clone() }.disabled(Int(newID) == nil) }
                }
            }
            .task {
                guard let t = target(app, profile, guest) else { return }
                if let id = try? await app.api.nextID(t.connection) { newID = String(id) }
                if name.isEmpty { name = "\(guest.displayName)-clone" }
            }
        }
    }

    private func clone() {
        guard let t = target(app, profile, guest), let id = Int(newID) else { return }
        working = true
        Task {
            do {
                try await app.api.cloneGuest(
                    t.connection, node: t.node, kind: t.kind, vmid: t.vmid,
                    newID: id, name: name, full: fullClone, targetStorage: nil
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}

// MARK: - Edit resources

struct EditResourcesSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let guest: ClusterResource
    let profile: ServerProfile
    let config: GuestConfig?
    var onComplete: () -> Void

    @State private var cores = "1"
    @State private var memory = "512"
    @State private var swap = "512"
    @State private var error: String?
    @State private var working = false

    private var isLXC: Bool { guest.type.guestKind == .lxc }

    var body: some View {
        NavigationStack {
            Form {
                Section("CPU") {
                    Stepper(value: bindingInt($cores), in: 1...256) {
                        LabeledContent("Cores", value: cores)
                    }
                }
                Section("Memory") {
                    TextField("Memory (MB)", text: $memory)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    if isLXC {
                        TextField("Swap (MB)", text: $swap)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Edit Resources")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Save") { save() } }
                }
            }
            .onAppear {
                cores = config?.cores ?? "1"
                memory = String(config?.memoryMB ?? 512)
                swap = config?.values["swap"] ?? "512"
            }
        }
    }

    private func bindingInt(_ text: Binding<String>) -> Binding<Int> {
        Binding(get: { Int(text.wrappedValue) ?? 1 }, set: { text.wrappedValue = String($0) })
    }

    private func save() {
        guard let t = target(app, profile, guest) else { return }
        var params = ["cores": cores, "memory": memory]
        if isLXC { params["swap"] = swap }
        working = true
        Task {
            do {
                try await app.api.updateGuestConfig(
                    t.connection, node: t.node, kind: t.kind, vmid: t.vmid, parameters: params
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}

// MARK: - Resize disk

struct ResizeDiskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let guest: ClusterResource
    let profile: ServerProfile
    let config: GuestConfig?
    var onComplete: () -> Void

    @State private var disk = ""
    @State private var growBy = "8"
    @State private var error: String?
    @State private var working = false

    private var disks: [String] {
        (config?.disks ?? []).map(\.id).filter { !$0.hasPrefix("unused") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Disk", selection: $disk) {
                        ForEach(disks, id: \.self) { Text($0).tag($0) }
                    }
                    HStack {
                        Text("Grow by")
                        Spacer()
                        TextField("8", text: $growBy)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("GB").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Disks can only be grown, never shrunk.")
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Resize Disk")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() }
                    else { Button("Resize") { resize() }.disabled(disk.isEmpty || Int(growBy) == nil) }
                }
            }
            .onAppear { if disk.isEmpty { disk = disks.first ?? "" } }
        }
    }

    private func resize() {
        guard let t = target(app, profile, guest), let gb = Int(growBy) else { return }
        working = true
        Task {
            do {
                try await app.api.resizeDisk(
                    t.connection, node: t.node, kind: t.kind, vmid: t.vmid,
                    disk: disk, size: "+\(gb)G"
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}

// MARK: - Tags & notes

struct TagsNotesSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let guest: ClusterResource
    let profile: ServerProfile
    let config: GuestConfig?
    var onComplete: () -> Void

    @State private var tags = ""
    @State private var notes = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tags (space or comma separated)", text: $tags)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                } header: { Text("Tags") }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Tags & Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Save") { save() } }
                }
            }
            .onAppear {
                tags = config?.values["tags"] ?? ""
                notes = config?.notes ?? ""
            }
        }
    }

    private func save() {
        guard let t = target(app, profile, guest) else { return }
        // Normalise tag separators to semicolons (Proxmox's canonical form).
        let normalisedTags = tags
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .joined(separator: ";")
        working = true
        Task {
            do {
                try await app.api.updateGuestConfig(
                    t.connection, node: t.node, kind: t.kind, vmid: t.vmid,
                    parameters: ["tags": normalisedTags, "description": notes]
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}

// MARK: - Cloud-Init

struct CloudInitSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let guest: ClusterResource
    let profile: ServerProfile
    let config: GuestConfig?
    var onComplete: () -> Void

    @State private var user = ""
    @State private var password = ""
    @State private var sshKeys = ""
    @State private var ipConfig = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section("User") {
                    TextField("Username", text: $user)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    SecureField("Password (leave blank to keep)", text: $password)
                }
                Section("SSH Keys") {
                    TextField("Public keys (one per line)", text: $sshKeys, axis: .vertical)
                        .lineLimit(2...8)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                }
                Section {
                    TextField("ipconfig0", text: $ipConfig)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                } header: { Text("Network") } footer: {
                    Text("e.g. ip=dhcp or ip=10.0.0.50/24,gw=10.0.0.1")
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Cloud-Init")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Save") { save() } }
                }
            }
            .onAppear {
                user = config?.values["ciuser"] ?? ""
                ipConfig = config?.values["ipconfig0"] ?? ""
            }
        }
    }

    private func save() {
        guard let t = target(app, profile, guest) else { return }
        var params: [String: String] = [:]
        if !user.isEmpty { params["ciuser"] = user }
        if !password.isEmpty { params["cipassword"] = password }
        if !sshKeys.isEmpty { params["sshkeys"] = sshKeys }
        if !ipConfig.isEmpty { params["ipconfig0"] = ipConfig }
        guard !params.isEmpty else { dismiss(); return }
        working = true
        Task {
            do {
                try await app.api.updateGuestConfig(
                    t.connection, node: t.node, kind: t.kind, vmid: t.vmid, parameters: params
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}

// MARK: - Migrate

struct MigrateGuestSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let guest: ClusterResource
    let profile: ServerProfile
    var onComplete: () -> Void

    @State private var nodes: [String] = []
    @State private var targetNode = ""
    @State private var online = true
    @State private var error: String?
    @State private var working = false

    private var isLXC: Bool { guest.type.guestKind == .lxc }

    var body: some View {
        NavigationStack {
            Form {
                if nodes.isEmpty {
                    Section { Text("No other nodes available to migrate to.").foregroundStyle(.secondary) }
                } else {
                    Section {
                        Picker("Target node", selection: $targetNode) {
                            ForEach(nodes, id: \.self) { Text($0).tag($0) }
                        }
                        Toggle(isLXC ? "Restart migrate" : "Live migrate", isOn: $online)
                    } footer: {
                        Text(isLXC
                             ? "A running container is briefly stopped and restarted on the target."
                             : "A running VM is migrated live with minimal downtime.")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Migrate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() }
                    else { Button("Migrate") { migrate() }.disabled(targetNode.isEmpty) }
                }
            }
            .task {
                guard let t = target(app, profile, guest),
                      let resources = try? await app.api.clusterResources(t.connection) else { return }
                nodes = resources
                    .filter { $0.type == .node && $0.node != guest.node && $0.status?.isUp == true }
                    .compactMap(\.node)
                targetNode = nodes.first ?? ""
            }
        }
    }

    private func migrate() {
        guard let t = target(app, profile, guest) else { return }
        working = true
        Task {
            do {
                try await app.api.migrateGuest(
                    t.connection, node: t.node, kind: t.kind, vmid: t.vmid,
                    target: targetNode, online: online
                )
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}
