import ReeveModels
import ReeveNetworking
import ReevePersistence
import Observation
import SwiftUI

/// Shared state for the Add Server flow, kept in one `@Observable` model so the
/// steps stay thin and the logic is testable/UI-agnostic.
@MainActor
@Observable
final class AddServerModel {
    var name = ""
    /// Raw user input: a URL, hostname, or `host:port`. Normalized into the
    /// fields below by `normalizeAddress()`.
    var host = ""
    var port = "8006"
    var useHTTPS = true
    var tokenID = ""
    var secret = ""
    var allowInsecure = true

    var scanning = false
    var discovered: [DiscoveredServer] = []

    var testing = false
    var testResult: String?
    var testOK = false

    func scan() async {
        scanning = true
        defer { scanning = false }
        discovered = (try? await LANScanner().scan()) ?? []
    }

    func select(_ server: DiscoveredServer) {
        host = server.ipAddress
        port = String(server.port)
        useHTTPS = true
        if name.isEmpty { name = server.suggestedName }
    }

    /// Accept a pasted URL or `host:port` in the address field and split it into
    /// scheme/host/port, so adding by hostname (e.g. https://pve.example.com)
    /// works as easily as in Jellyfin/Home Assistant.
    func normalizeAddress() {
        let raw = host.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let hasScheme = raw.contains("://")
        guard let comp = URLComponents(string: hasScheme ? raw : "//\(raw)"),
              let parsedHost = comp.host
        else { return }
        host = parsedHost
        if let scheme = comp.scheme { useHTTPS = scheme.lowercased() != "http" }
        if let parsedPort = comp.port {
            port = String(parsedPort)
        } else if hasScheme {
            port = useHTTPS ? "443" : "80"
        }
    }

    var profile: ServerProfile {
        ServerProfile(
            name: name.isEmpty ? host : name,
            host: host,
            port: Int(port) ?? 8006,
            useHTTPS: useHTTPS,
            tokenID: tokenID,
            tlsPolicy: allowInsecure ? .allowInsecure : .system
        )
    }

    var hostIsValid: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty }
    var canSave: Bool { hostIsValid && !tokenID.isEmpty && !secret.isEmpty }

    func test(api: ProxmoxAPI) async {
        testing = true
        defer { testing = false }
        guard let connection = profile.connection(secret: secret) else { return }
        do {
            let version = try await api.version(connection)
            testResult = "Connected. Proxmox VE \(version.version)"
            testOK = true
        } catch {
            testResult = error.localizedDescription
            testOK = false
        }
    }

    @discardableResult
    func save(into store: ProfileStore) -> Bool {
        let profile = profile
        do {
            try store.save(profile, secret: secret)
            store.selectedID = profile.id
            return true
        } catch {
            testResult = "Couldn't save: \(error.localizedDescription)"
            testOK = false
            return false
        }
    }
}

enum AddServerStep: Hashable {
    case manual
    case token
}

/// Connect-to-server flow modelled on Swiftfin / Home Assistant: a discovery
/// screen with a searching animation, found servers listed as they appear, and an
/// always-available "Add Manually" path → token entry → test & add.
struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = AddServerModel()
    @State private var path: [AddServerStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            DiscoverPage(model: model, path: $path)
                .navigationTitle("Add Server")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(for: AddServerStep.self) { step in
                    switch step {
                    case .manual:
                        ManualPage(model: model, path: $path)
                    case .token:
                        TokenPage(model: model, onComplete: { dismiss() })
                    }
                }
        }
    }
}

// MARK: - Step 1: Discover

private struct DiscoverPage: View {
    @Bindable var model: AddServerModel
    @Binding var path: [AddServerStep]
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RadarView(isActive: model.scanning)
                    .frame(height: 200)
                    .padding(.top, 24)

                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !model.discovered.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(model.discovered) { server in
                            ServerCard(server: server) {
                                model.select(server)
                                path.append(.token)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if !model.scanning {
                    Button {
                        Task { await model.scan() }
                    } label: {
                        Label("Search Again", systemImage: "arrow.clockwise")
                    }
                    .font(.callout)
                }
                Button {
                    path.append(.manual)
                } label: {
                    Text("Add Manually").frame(maxWidth: .infinity)
                }
                .glassProminentButton()
                .controlSize(.large)
            }
            .padding()
            .background(.bar)
        }
        .task {
            guard !started else { return }
            started = true
            await model.scan()
        }
    }

    private var title: String {
        if model.scanning { "Searching…" }
        else if model.discovered.isEmpty { "No Servers Found" }
        else { "Select Your Server" }
    }

    private var subtitle: String {
        if model.scanning { "Looking for Proxmox servers on your network." }
        else if model.discovered.isEmpty { "Add your server manually below." }
        else { "Tap a server to continue, or add one manually." }
    }
}

/// A clean radar-style pulse used while discovering.
private struct RadarView: View {
    var isActive: Bool

    var body: some View {
        ZStack {
            if isActive {
                ForEach(0..<3, id: \.self) { index in
                    PulseRing(delay: Double(index) * 0.7)
                }
            }
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 88, height: 88)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: isActive)
        }
        .frame(width: 200, height: 200)
    }
}

private struct PulseRing: View {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
            .scaleEffect(expanded ? 1 : 0.35)
            .opacity(expanded ? 0 : 0.7)
            .onAppear {
                // Respect Reduce Motion: skip the looping pulse entirely.
                guard !reduceMotion else { return }
                withAnimation(
                    .easeOut(duration: 2).repeatForever(autoreverses: false).delay(delay)
                ) {
                    expanded = true
                }
            }
    }
}

private struct ServerCard: View {
    let server: DiscoveredServer
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.hostname ?? server.ipAddress)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(server.ipAddress):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 2 (optional): Manual entry

private struct ManualPage: View {
    @Bindable var model: AddServerModel
    @Binding var path: [AddServerStep]

    var body: some View {
        Form {
            Section {
                TextField("Name (optional)", text: $model.name)
                TextField("Server URL or IP", text: $model.host)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    #endif
            } footer: {
                Text("e.g. https://pve.example.com or 192.168.1.10. A hostname works anywhere it resolves, including over a VPN.")
            }
        }
        .navigationTitle("Add Manually")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") {
                    model.normalizeAddress()
                    path.append(.token)
                }
                .disabled(!model.hostIsValid)
            }
        }
    }
}

// MARK: - Step 3: Token + test + add

private struct TokenPage: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: AddServerModel
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    "Server", value: model.profile.baseURL?.absoluteString ?? model.host
                )
            }
            Section {
                TextField("Token ID (user@realm!name)", text: $model.tokenID)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                SecureField("Token secret", text: $model.secret)
                Toggle("Allow self-signed certificate", isOn: $model.allowInsecure)
            } header: {
                Text("API Token")
            } footer: {
                Text("Create a token in Proxmox: Datacenter → Permissions → API Tokens. Grant PVEAuditor (add VM.PowerMgmt for power controls).")
            }
            if let result = model.testResult {
                Section {
                    Label(result, systemImage: model.testOK ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(model.testOK ? .green : .red)
                }
            }
            Section {
                Button(model.testing ? "Testing…" : "Test Connection") {
                    Task { await model.test(api: app.api) }
                }
                .disabled(model.testing || !model.canSave)
            }
        }
        .navigationTitle("API Token")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    if model.save(into: app.profiles) { onComplete() }
                }
                .disabled(!model.canSave)
            }
        }
    }
}
