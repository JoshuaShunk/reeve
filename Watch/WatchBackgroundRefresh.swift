import Foundation
import ReeveNetworking
import ReevePersistence
import WatchKit

/// Keeps the complication cache fresh while the app is closed. watchOS grants a
/// best-effort background-refresh budget (roughly every 15-30 min, and only when
/// a complication is on the active face); we re-arm after each run and always
/// complete the task so the system keeps scheduling us.
enum WatchBackgroundRefresh {
    /// ~15 minutes: the floor watchOS will realistically honour for app refresh.
    private static let interval: TimeInterval = 15 * 60

    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(interval),
            userInfo: nil
        ) { _ in }
    }

    /// Hard ceiling for a background pass. watchOS gives a background task only a
    /// few seconds of wall time before the watchdog kills it (which also reduces
    /// future budget), so we abandon slow servers rather than risk overrunning.
    private static let deadline: Duration = .seconds(10)

    /// Fetch every synced server once and write its complication snapshot. Races
    /// the work against `deadline`: whichever finishes first cancels the other, so
    /// an unreachable server can't keep the task alive past the budget.
    @MainActor
    static func run() async {
        let profiles = ProfileStore()
        let api: ProxmoxAPI = DemoProxmoxAPI(live: LiveProxmoxAPI())
        WatchWidgetSync.refreshDirectory(profiles.profiles)
        let servers: [WatchServer] = profiles.profiles.compactMap { profile in
            profiles.connection(for: profile).map {
                WatchServer(profile: profile, api: api, connection: $0)
            }
        }
        guard !servers.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await Task.sleep(for: deadline) }
            group.addTask {
                await withTaskGroup(of: Void.self) { inner in
                    for server in servers { inner.addTask { await server.refresh() } }
                }
            }
            await group.next()   // first of (deadline, all-refreshes-done)
            group.cancelAll()    // cancel whichever is still running
        }
    }
}

/// watchOS app delegate: arms background refresh at launch and services the
/// background task when it fires.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchBackgroundRefresh.schedule()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let refreshTask = task as? WKApplicationRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            Task { @MainActor in
                await WatchBackgroundRefresh.run()
                // Re-arm the next refresh before completing this one.
                WatchBackgroundRefresh.schedule()
                refreshTask.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
