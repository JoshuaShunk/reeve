import ReeveModels
import ReevePersistence
import SwiftUI

// MARK: - Datacenter overview

struct DatacenterView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile

    @State private var nodes: [ClusterStatusEntry] = []
    @State private var ha: [HAResource] = []
    @State private var users: [PVEUser] = []
    @State private var loaded = false

    private var clusterEntry: ClusterStatusEntry? { nodes.first { $0.type == "cluster" } }

    var body: some View {
        List {
            Section("Cluster") {
                if let cluster = clusterEntry {
                    LabeledContent(cluster.name) {
                        Text(cluster.quorate == 1 ? "Quorate" : "No quorum")
                            .foregroundStyle(cluster.quorate == 1 ? .green : .red)
                    }
                }
                ForEach(nodes.filter { $0.type == "node" }) { node in
                    HStack(spacing: 10) {
                        Circle().fill(node.isOnline ? .green : .red).frame(width: 9, height: 9)
                        Text(node.name)
                        if node.isLocal { Text("local").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        if let ip = node.ip { Text(ip).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }

            Section("High Availability") {
                if ha.isEmpty {
                    Text("No HA resources configured.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(ha) { resource in
                        LabeledContent(resource.sid) {
                            Text(resource.state ?? "-").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Users") {
                ForEach(users) { user in
                    NavigationLink {
                        UserTokensView(profile: profile, userid: user.userid)
                    } label: {
                        HStack {
                            Circle().fill(user.isEnabled ? .green : .secondary)
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.userid)
                                if let email = user.email, !email.isEmpty {
                                    Text(email).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    FirewallView(title: "Datacenter Firewall",
                                 basePath: "cluster/firewall", profile: profile)
                } label: { Label("Firewall", systemImage: "shield.lefthalf.filled") }
                NavigationLink {
                    SDNView(profile: profile)
                } label: { Label("SDN", systemImage: "network") }
                NavigationLink {
                    ReplicationView(profile: profile)
                } label: { Label("Replication", systemImage: "arrow.triangle.2.circlepath") }
                NavigationLink {
                    BackupJobsView(profile: profile, node: nodes.first { $0.type == "node" }?.name ?? "")
                } label: { Label("Backup Jobs", systemImage: "calendar.badge.clock") }
            }
        }
        .navigationTitle("Datacenter")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let conn = app.profiles.connection(for: profile) else { return }
        async let s = app.api.clusterStatus(conn)
        async let h = app.api.haResources(conn)
        async let u = app.api.users(conn)
        nodes = (try? await s) ?? []
        ha = (try? await h) ?? []
        users = ((try? await u) ?? []).sorted { $0.userid < $1.userid }
        loaded = true
    }
}

// MARK: - User tokens

struct UserTokensView: View {
    @Environment(AppModel.self) private var app
    let profile: ServerProfile
    let userid: String

    @State private var tokens: [PVEToken] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && tokens.isEmpty {
                ContentUnavailableView("No API Tokens", systemImage: "key",
                                       description: Text("\(userid) has no API tokens."))
            }
            ForEach(tokens) { token in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(userid)!\(token.tokenid)").font(.callout.weight(.medium))
                    if let comment = token.comment, !comment.isEmpty {
                        Text(comment).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(token.privsep == 1 ? "Privilege separated" : "Full privileges")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("API Tokens")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .task {
            guard let conn = app.profiles.connection(for: profile) else { return }
            tokens = ((try? await app.api.userTokens(conn, userid: userid)) ?? [])
                .sorted { $0.tokenid < $1.tokenid }
            loaded = true
        }
    }
}

// MARK: - Firewall

struct FirewallView: View {
    @Environment(AppModel.self) private var app
    let title: String
    let basePath: String
    let profile: ServerProfile

    @State private var rules: [FirewallRule] = []
    @State private var loaded = false
    @State private var showingAdd = false
    @State private var error: String?

    var body: some View {
        List {
            if loaded && rules.isEmpty {
                ContentUnavailableView("No Rules", systemImage: "shield",
                                       description: Text("No firewall rules at this level."))
            }
            ForEach(rules) { rule in
                FirewallRuleRow(rule: rule, toggle: { setEnabled(rule, $0) })
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(rule) }
                    }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if !loaded { ProgressView() } }
        .toolbar { ToolbarItem { Button("Add", systemImage: "plus") { showingAdd = true } } }
        .alert("Failed", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $showingAdd) {
            AddFirewallRuleSheet(basePath: basePath, profile: profile) { Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let conn = app.profiles.connection(for: profile) else { return }
        do { rules = try await app.api.firewallRules(conn, basePath: basePath).sorted { $0.pos < $1.pos } }
        catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func setEnabled(_ rule: FirewallRule, _ on: Bool) {
        guard let conn = app.profiles.connection(for: profile) else { return }
        Task {
            do {
                try await app.api.updateFirewallRule(
                    conn, basePath: basePath, pos: rule.pos, parameters: ["enable": on ? "1" : "0"]
                )
                await load()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func delete(_ rule: FirewallRule) {
        guard let conn = app.profiles.connection(for: profile) else { return }
        Task {
            do { try await app.api.deleteFirewallRule(conn, basePath: basePath, pos: rule.pos); await load() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct FirewallRuleRow: View {
    let rule: FirewallRule
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text((rule.type ?? "in").uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    Text(rule.macro ?? rule.action ?? "-")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(actionColor)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { toggle($0) }))
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var actionColor: Color {
        switch (rule.action ?? "").uppercased() {
        case "ACCEPT": .green
        case "DROP", "REJECT": .red
        default: .primary
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let proto = rule.proto { parts.append(proto.uppercased()) }
        if let dport = rule.dport { parts.append("dport \(dport)") }
        if let source = rule.source { parts.append("from \(source)") }
        if let dest = rule.dest { parts.append("to \(dest)") }
        if let comment = rule.comment, !comment.isEmpty { parts.append("· \(comment)") }
        return parts.isEmpty ? "any" : parts.joined(separator: "  ")
    }
}

private struct AddFirewallRuleSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let basePath: String
    let profile: ServerProfile
    var onComplete: () -> Void

    @State private var direction = "in"
    @State private var action = "ACCEPT"
    @State private var proto = ""
    @State private var dport = ""
    @State private var source = ""
    @State private var comment = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direction", selection: $direction) {
                        Text("In").tag("in"); Text("Out").tag("out")
                    }
                    Picker("Action", selection: $action) {
                        Text("ACCEPT").tag("ACCEPT"); Text("DROP").tag("DROP"); Text("REJECT").tag("REJECT")
                    }
                }
                Section("Match (optional)") {
                    TextField("Protocol (tcp/udp)", text: $proto)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    TextField("Dest. port", text: $dport)
                    TextField("Source (IP/CIDR)", text: $source)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    TextField("Comment", text: $comment)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Add Rule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Add") { add() } }
                }
            }
        }
    }

    private func add() {
        guard let conn = app.profiles.connection(for: profile) else { return }
        var params = ["type": direction, "action": action, "enable": "1"]
        if !proto.isEmpty { params["proto"] = proto }
        if !dport.isEmpty { params["dport"] = dport }
        if !source.isEmpty { params["source"] = source }
        if !comment.isEmpty { params["comment"] = comment }
        working = true
        Task {
            do {
                try await app.api.createFirewallRule(conn, basePath: basePath, parameters: params)
                onComplete(); dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                working = false
            }
        }
    }
}
