import ReeveModels
import ReevePersistence
import SwiftUI

/// Create a new LXC container or QEMU VM from scratch. LXC can use a downloaded
/// template or (PVE 9.1) an OCI image referenced as a template.
struct CreateGuestView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let profile: ServerProfile
    let node: String
    var onComplete: () -> Void

    @State private var kind: GuestKind = .lxc
    @State private var vmid = ""
    @State private var name = ""
    @State private var cores = "1"
    @State private var memory = "1024"
    @State private var diskGB = "8"
    @State private var bridge = "vmbr0"
    @State private var start = false

    // LXC
    @State private var template = ""
    @State private var rootfsStorage = ""
    @State private var swap = "512"
    @State private var password = ""
    @State private var unprivileged = true

    // VM
    @State private var iso = ""
    @State private var diskStorage = ""
    @State private var osType = "l26"

    @State private var templates: [String] = []
    @State private var isos: [String] = []
    @State private var storages: [String] = []
    @State private var bridges: [String] = []
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Container").tag(GuestKind.lxc)
                    Text("Virtual Machine").tag(GuestKind.qemu)
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("VMID", text: $vmid)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField(kind == .lxc ? "Hostname" : "Name", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                }

                if kind == .lxc {
                    Section("Template") {
                        Picker("Template", selection: $template) {
                            Text("Choose…").tag("")
                            ForEach(templates, id: \.self) { Text(short($0)).tag($0) }
                        }
                        TextField("…or OCI image / template volid", text: $template)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                            .font(.caption)
                    }
                } else {
                    Section("Installation media") {
                        Picker("ISO", selection: $iso) {
                            Text("None").tag("")
                            ForEach(isos, id: \.self) { Text(short($0)).tag($0) }
                        }
                        Picker("OS type", selection: $osType) {
                            Text("Linux").tag("l26"); Text("Windows 11/2022").tag("win11")
                            Text("Windows 10").tag("win10"); Text("Other").tag("other")
                        }
                    }
                }

                Section("Resources") {
                    Stepper(value: intBinding($cores), in: 1...64) {
                        LabeledContent("Cores", value: cores)
                    }
                    TextField("Memory (MB)", text: $memory)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    if kind == .lxc {
                        TextField("Swap (MB)", text: $swap)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    HStack {
                        Text("Disk")
                        Spacer()
                        TextField("8", text: $diskGB)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing).frame(width: 60)
                        Text("GB").foregroundStyle(.secondary)
                    }
                    Picker("Storage", selection: kind == .lxc ? $rootfsStorage : $diskStorage) {
                        ForEach(storages, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Network") {
                    Picker("Bridge", selection: $bridge) {
                        ForEach(bridges, id: \.self) { Text($0).tag($0) }
                    }
                }

                if kind == .lxc {
                    Section("Container options") {
                        SecureField("Root password", text: $password)
                        Toggle("Unprivileged", isOn: $unprivileged)
                    }
                }

                Section { Toggle("Start after creation", isOn: $start) }

                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("New Guest")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() }
                    else { Button("Create") { create() }.disabled(!canCreate) }
                }
            }
            .task { await loadOptions() }
        }
    }

    private var canCreate: Bool {
        guard Int(vmid) != nil, !storageSelection.isEmpty else { return false }
        if kind == .lxc { return !template.isEmpty && !password.isEmpty }
        return true
    }

    private var storageSelection: String { kind == .lxc ? rootfsStorage : diskStorage }

    private func intBinding(_ text: Binding<String>) -> Binding<Int> {
        Binding(get: { Int(text.wrappedValue) ?? 1 }, set: { text.wrappedValue = String($0) })
    }

    private func short(_ volid: String) -> String {
        if let slash = volid.lastIndex(of: "/") { return String(volid[volid.index(after: slash)...]) }
        return volid
    }

    private func loadOptions() async {
        guard let conn = app.profiles.connection(for: profile) else { return }
        if let id = try? await app.api.nextID(conn) { vmid = String(id) }
        let allStorages = (try? await app.api.nodeStorages(conn, node: node, content: nil)) ?? []
        storages = allStorages.filter { ($0.content ?? "").contains("images") || ($0.content ?? "").contains("rootdir") }
            .map(\.storage)
        if storages.isEmpty { storages = allStorages.map(\.storage) }
        rootfsStorage = storages.first ?? ""
        diskStorage = storages.first ?? ""

        var tmpl: [String] = [], isoList: [String] = []
        for s in allStorages.map(\.storage) {
            let content = (try? await app.api.storageContent(conn, node: node, storage: s, content: nil)) ?? []
            tmpl += content.filter { $0.content == "vztmpl" }.map(\.volid)
            isoList += content.filter { $0.content == "iso" }.map(\.volid)
        }
        templates = tmpl; isos = isoList

        bridges = ((try? await app.api.nodeNetwork(conn, node: node)) ?? [])
            .filter { $0.type == "bridge" }.map(\.iface)
        if bridges.isEmpty { bridges = ["vmbr0"] }
        bridge = bridges.first ?? "vmbr0"
    }

    private func create() {
        guard let conn = app.profiles.connection(for: profile), let id = Int(vmid) else { return }
        var params: [String: String] = ["vmid": String(id), "cores": cores, "memory": memory, "start": start ? "1" : "0"]
        if kind == .lxc {
            params["ostemplate"] = template
            params["rootfs"] = "\(rootfsStorage):\(diskGB)"
            params["swap"] = swap
            params["unprivileged"] = unprivileged ? "1" : "0"
            params["password"] = password
            if !name.isEmpty { params["hostname"] = name }
            params["net0"] = "name=eth0,bridge=\(bridge),ip=dhcp"
        } else {
            if !name.isEmpty { params["name"] = name }
            params["ostype"] = osType
            params["scsihw"] = "virtio-scsi-pci"
            params["scsi0"] = "\(diskStorage):\(diskGB)"
            if !iso.isEmpty {
                params["ide2"] = "\(iso),media=cdrom"
                params["boot"] = "order=scsi0;ide2"
            }
            params["net0"] = "virtio,bridge=\(bridge)"
        }
        working = true
        Task {
            do {
                try await app.api.createGuest(conn, node: node, kind: kind, parameters: params)
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}
