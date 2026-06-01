#if os(iOS)
import ReeveModels
import ReevePersistence
import ReeveTerminal
import SwiftUI

/// An interactive in-guest console: opens a PTY to the node over SSH and runs
/// `pct enter <vmid>` (containers) or `qm terminal <vmid>` (VM serial console),
/// rendered with a full terminal emulator.
struct GuestConsoleView: View {
    let guest: ClusterResource
    let profile: ServerProfile

    @State private var session: PTYTerminalSession?
    @State private var showingSetup = false
    @State private var needsSetup = false
    private let store = SSHCredentialStore()

    var body: some View {
        Group {
            if let session {
                SSHTerminalView(session: session)
                    .background(Color.black)
                    .ignoresSafeArea(.container, edges: .bottom)
            } else if needsSetup {
                ContentUnavailableView {
                    Label("SSH Required", systemImage: "terminal")
                } description: {
                    Text("The console connects over SSH to \(guest.node ?? "the node") and runs \(command). Add SSH credentials to continue.")
                } actions: {
                    Button("Set Up SSH") { showingSetup = true }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSetup) {
            SSHSetupView(profile: profile) { start() }
        }
        .task { start() }
        .onDisappear { session?.stop() }
    }

    private var command: String {
        guard let vmid = guest.vmid else { return "" }
        return guest.type.guestKind == .lxc ? "pct enter \(vmid)" : "qm terminal \(vmid)"
    }

    private func start() {
        session?.stop()
        guard let credential = store.credential(for: profile.id),
              let password = store.password(for: profile.id),
              guest.vmid != nil else {
            needsSetup = true
            session = nil
            return
        }
        needsSetup = false
        session = PTYTerminalSession(
            host: credential.host, port: credential.port,
            username: credential.username, password: password,
            initialCommand: command
        )
    }
}
#endif
