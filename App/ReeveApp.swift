import AppIntents
import SwiftUI

@main
struct ReeveApp: App {
    @State private var model = AppModel()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Larger shared cache so service logos (AsyncImage) stay resident and don't
        // flicker/re-fetch while scrolling the Services list.
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
        // App Intents (Siri/Shortcuts/Spotlight) reach the Proxmox client through
        // this dependency; registered here so it resolves even on a background launch.
        AppDependencyManager.shared.add(dependency: ProxmoxIntentProvider())
        // Register the agent's continued-processing task during launch (iOS 26+),
        // so a long-running setup keeps going after the user leaves the app.
        #if os(iOS)
        if #available(iOS 26.0, *) { AgentBackgroundTask.shared.registerOnce() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environment(model)
                if lock.isLocked {
                    LockView(lock: lock)
                }
            }
            .task {
                lock.lockIfEnabled()
                await lock.authenticate()
                WidgetSync.refreshDirectory(
                    profiles: model.profiles, services: model.serviceStore
                )
                #if os(iOS)
                WatchConnectivityProvider.shared.start()
                WatchConnectivityProvider.shared.sync(from: model.profiles)
                #endif
                // Refresh the Spotlight index of individual guests in the background.
                if #available(iOS 18.0, macOS 15.0, *) {
                    Task.detached(priority: .utility) {
                        await GuestSpotlightIndexer.reindex()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    lock.lockIfEnabled()
                case .active:
                    Task { await lock.authenticate() }
                    #if os(iOS)
                    WatchConnectivityProvider.shared.sync(from: model.profiles)
                    #endif
                default:
                    break
                }
            }
        }

        #if os(macOS)
        // Always-available homelab status in the menu bar.
        MenuBarExtra("Reeve", systemImage: "server.rack") {
            MenuBarView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .frame(width: 460, height: 420)
        }
        #endif
    }
}
