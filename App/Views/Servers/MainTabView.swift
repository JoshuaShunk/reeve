import SwiftUI

/// Top-level tabs: Proxmox servers and self-hosted services.
struct MainTabView: View {
    var body: some View {
        TabView {
            RootView()
                .tabItem { Label("Servers", systemImage: "server.rack") }
            ServicesRootView()
                .tabItem { Label("Services", systemImage: "square.grid.2x2") }
            AgentView()
                .tabItem { Label("Agent", systemImage: "sparkles") }
        }
    }
}
