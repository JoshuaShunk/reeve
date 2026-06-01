import ReevePersistence
import ReeveTerminal
import LocalAuthentication
import SwiftUI

/// An SSH command console for a server. Runs commands over a persistent
/// connection and shows their output. Gated behind biometrics when the app lock
/// is enabled, since this is typically a root shell.
struct SSHConsoleView: View {
    let profile: ServerProfile

    @AppStorage(PreferenceKey.biometricLock) private var biometricLock = false
    @State private var session: SSHSession?
    @State private var command = ""
    @State private var showingSetup = false
    @State private var unlocked = false
    @State private var gateMessage: String?
    private let store = SSHCredentialStore()

    var body: some View {
        Group {
            if !unlocked {
                lockedView
            } else if let session {
                console(session)
            } else {
                setupPrompt
            }
        }
        .navigationTitle("Terminal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if unlocked, let session {
                ToolbarItem {
                    Menu {
                        Button("Clear", systemImage: "trash") { session.clear() }
                        Button("Edit Connection", systemImage: "gearshape") { showingSetup = true }
                        Button("Disconnect", systemImage: "bolt.horizontal.circle", role: .destructive) {
                            Task { await session.disconnect() }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            SSHSetupView(profile: profile) { Task { await startSession() } }
        }
        .task { await gateThenStart() }
    }

    // MARK: Gate

    private var lockedView: some View {
        ContentUnavailableView {
            Label("Terminal Locked", systemImage: "lock.fill")
        } description: {
            Text(gateMessage ?? "Authenticate to open a shell on \(profile.name).")
        } actions: {
            Button("Unlock") { Task { await gateThenStart() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func gateThenStart() async {
        if biometricLock {
            let context = LAContext()
            var error: NSError?
            let policy: LAPolicy = .deviceOwnerAuthentication
            guard context.canEvaluatePolicy(policy, error: &error) else {
                gateMessage = "Biometric authentication isn't available."
                unlocked = true   // fall back to app-lock protection rather than locking out
                await startSession()
                return
            }
            do {
                let ok = try await context.evaluatePolicy(
                    policy, localizedReason: "Open a terminal on \(profile.name)"
                )
                unlocked = ok
            } catch {
                gateMessage = "Authentication failed. Tap Unlock to try again."
                return
            }
        } else {
            unlocked = true
        }
        await startSession()
    }

    // MARK: Session lifecycle

    private func startSession() async {
        guard let credential = store.credential(for: profile.id),
              let password = store.password(for: profile.id) else {
            session = nil
            return
        }
        let new = SSHSession(
            host: credential.host, port: credential.port,
            username: credential.username, password: password
        )
        session = new
        await new.connect()
    }

    // MARK: Setup prompt

    private var setupPrompt: some View {
        ContentUnavailableView {
            Label("No SSH Connection", systemImage: "terminal")
        } description: {
            Text("Add SSH credentials to open a shell on \(profile.name).")
        } actions: {
            Button("Set Up SSH") { showingSetup = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Console

    private func console(_ session: SSHSession) -> some View {
        VStack(spacing: 0) {
            statusBar(session)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(session.transcript.isEmpty ? " " : session.transcript)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: session.transcript) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            inputBar(session)
        }
    }

    @ViewBuilder private func statusBar(_ session: SSHSession) -> some View {
        if case .connecting = session.status {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        } else if case .failed(let message) = session.status {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Retry") { Task { await session.connect() } }.font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private func inputBar(_ session: SSHSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.green)
            TextField("command", text: $command)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .onSubmit { send(session) }
                .disabled(session.isBusy)
            if session.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button("Run", systemImage: "return") { send(session) }
                    .labelStyle(.iconOnly)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func send(_ session: SSHSession) {
        let cmd = command
        command = ""
        Task { await session.run(cmd) }
    }
}

// MARK: - Setup sheet

struct SSHSetupView: View {
    let profile: ServerProfile
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host: String
    @State private var port: String
    @State private var username: String = "root"
    @State private var password: String = ""
    @State private var existing = false
    private let store = SSHCredentialStore()

    init(profile: ServerProfile, onSaved: @escaping () -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _host = State(initialValue: profile.host)
        _port = State(initialValue: "22")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host", text: $host)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    TextField("Port", text: $port)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("Username", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    SecureField("Password", text: $password)
                } footer: {
                    Text("Credentials are stored in the Keychain. This usually opens a root shell; handle with care.")
                }
                if existing {
                    Section {
                        Button("Remove SSH Credentials", role: .destructive) {
                            store.delete(for: profile.id)
                            onSaved()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("SSH Connection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                if let credential = store.credential(for: profile.id) {
                    host = credential.host
                    port = String(credential.port)
                    username = credential.username
                    existing = true
                }
            }
        }
    }

    private var canSave: Bool {
        !host.isEmpty && !username.isEmpty && !password.isEmpty && Int(port) != nil
    }

    private func save() {
        let credential = SSHCredential(
            host: host, port: Int(port) ?? 22, username: username
        )
        try? store.save(credential, password: password, for: profile.id)
        onSaved()
        dismiss()
    }
}
