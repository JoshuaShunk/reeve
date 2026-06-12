import SwiftUI

@main
struct ReeveWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            ServersListView()
                .environment(model)
        }
    }
}
