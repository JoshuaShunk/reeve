# Implementation Brief. Widgets, Background Refresh/Alerts, and App Intents

Target: SwiftUI app for iOS 17+ / macOS 14+, Xcode 26, Swift 6 (strict concurrency).
Shared code lives in the local SPM package **ReeveCore** with products
`ReeveModels`, `ReeveNetworking`, `ReevePersistence`, `ReeveFeatures`.
`KeychainStore` already accepts an `accessGroup`; `ProfileStore` holds server profiles.

This brief covers three features and is written so each part can be picked up
independently. Code is illustrative (correct API names, abbreviated error handling).

---

## Shared groundwork (do this once, used by all three parts)

These IDs are referenced throughout. Pick real reverse-DNS strings and keep them in
one constants file inside `ReeveModels` (so app, widget, and any helper target share them).

```swift
// ReeveModels/SharedIdentifiers.swift
public enum Shared {
    // App Group: container + UserDefaults suite shared by app + widget + extensions.
    public static let appGroup = "group.com.homelabmonitor.shared"

    // Keychain access group. NOTE: the real value the system uses is
    // "<TeamID/AppIdentifierPrefix>.com.homelabmonitor.keychain".
    // In the Keychain query you pass the bare suffix; the prefix is implicit.
    public static let keychainAccessGroup = "com.homelabmonitor.keychain"

    // BackgroundTasks identifiers (must also be listed in Info.plist).
    public static let bgRefreshTaskID  = "com.homelabmonitor.refresh"
    public static let bgProcessingID   = "com.homelabmonitor.maintenance"

    // Widget kind strings.
    public static let statusWidgetKind = "HomelabStatusWidget"
}
```

### App Group setup (Signing & Capabilities)
Add the **App Groups** capability to BOTH the main app target and the widget
extension target (and the macOS app target). Select the same group
`group.com.homelabmonitor.shared`. This produces the
`com.apple.security.application-groups` entitlement (an array) in each target's
`.entitlements` file. ([App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups))

This gives you two shared resources:
- A **shared `UserDefaults` suite**: `UserDefaults(suiteName: Shared.appGroup)`, use for
  small cached status snapshots (codable → JSON `Data`).
- A **shared container directory**:
  `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroup)`;
  use this if a snapshot grows beyond a few KB.

### Keychain Sharing setup
Add the **Keychain Sharing** capability to the app target AND the widget target with
the SAME keychain group `com.homelabmonitor.keychain`. This writes
`keychain-access-groups` into each target's entitlements. ([Keychain Access Groups](https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups),
[Sharing keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps))

Then construct the existing wrapper with the group so the widget reads the same token:

```swift
let keychain = KeychainStore(accessGroup: Shared.keychainAccessGroup)
```

Two important details that already match the current code:
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (already used in `KeychainStore`)
  is the correct accessibility class. Widgets and background tasks run while the device
  is locked-after-first-unlock, so `WhenUnlocked` would fail; `ThisDeviceOnly` keeps the
  secret off iCloud Keychain backups. ([kSecAttrAccessible](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly))
- Items must be (re)written with the access group set, or the widget cannot see them.

---

## PART A. Home Screen / Lock Screen Widgets (WidgetKit)

### A.1 Adding the Widget Extension target that reuses ReeveCore
1. **File ▸ New ▸ Target ▸ Widget Extension** (uncheck "Include Configuration Intent"
   unless you want a configurable widget; for a homelab status widget you can start
   static and add an `AppIntentConfiguration` later). This creates a new app-extension
   target with its own bundle ID, Info.plist, and entitlements.
2. **Reuse the package:** in the widget target's **General ▸ Frameworks and Libraries**
   (or **Build Phases ▸ Link Binary With Libraries**), add the ReeveCore products you
   need, for a widget that's `ReeveModels`, `ReevePersistence`, and (only if the
   widget fetches) `ReeveNetworking`. Because ReeveCore is a *local* package already
   referenced by the project, the widget target just links the same products; no
   duplication. Keep widget-linked code lightweight, don't pull `ReeveFeatures`
   (UI/observable models) into the widget.
3. Add **App Groups** + **Keychain Sharing** capabilities to the widget target (above).
4. Confirm the widget's **Deployment Target** is iOS 17 to match the package.

> Widgets are app extensions: no long-running work, tight memory limit (~30 MB for the
> rendering process is the practical ceiling), and the view must be pure SwiftUI that
> WidgetKit can archive. ([WidgetKit](https://developer.apple.com/documentation/widgetkit))

### A.2 TimelineProvider design and realistic refresh budget
The provider supplies `TimelineEntry`s and a `TimelineReloadPolicy`. The reload policy
options are `.atEnd`, `.after(Date)`, and `.never`. ([TimelineReloadPolicy](https://developer.apple.com/documentation/widgetkit/timelinereloadpolicy),
[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date))

**Realistic cadence (this is the honest part):**
- WidgetKit does **not** guarantee your requested times. The system gives each widget a
  **daily refresh budget**; in practice this works out to roughly **40–70 timeline
  reloads per day**, i.e. an effective floor of about **one update every 15–60 minutes**
  for a frequently-visible widget, less for one that's rarely on screen.
- Timeline entries should be **spaced at least ~5 minutes apart**; finer spacing is
  ignored.
- The system **learns** over a few days when the widget is visible and biases refreshes
  toward those times. A widget on a rarely-viewed page gets refreshed far less.
- Budget is shared across all of an app's widgets, and `WidgetCenter.reloadTimelines`
  calls also draw against it (with throttling). Treat ~15 minutes as a sane minimum
  design cadence and never promise "real-time."

Design: request `.after(Date)` ~15 min out as a soft cadence, plus have the app proactively
push fresh timelines via `WidgetCenter` whenever it has new data (see A.4).

### A.3 Families: Home Screen, Lock Screen accessory, StandBy
Declare families in `.supportedFamilies`:

```swift
.supportedFamilies([
    .systemSmall, .systemMedium,          // Home Screen (iOS) + Notification Center/Desktop (macOS)
    .accessoryCircular, .accessoryRectangular, .accessoryInline   // Lock Screen (iOS 16+)
])
```
- `accessoryCircular` (gauge/ring), `accessoryRectangular` (a few lines / mini graph),
  `accessoryInline` (one line next to the clock). ([accessoryCircular](https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycircular),
  [accessoryRectangular](https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular))
- **StandBy** (iPhone charging in landscape, iOS 17+): the system reuses your
  `.systemSmall` widget and **removes the background**. From iOS 17 every widget must use
  `.containerBackground(...for: .widget)` so the system can strip/replace the background
  in StandBy and on the Lock Screen. Use `widgetRenderingMode` and avoid baked-in
  backgrounds. ([Container background API / iOS 17 widget requirements](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date))
- Lock Screen accessory widgets render in a **vibrant, tinted, mostly-monochrome** mode;
  design for that (`AccessoryWidgetBackground()` for the circular family).
- **macOS:** Home Screen widgets appear in Notification Center and on the desktop
  (macOS 14+). There are no Lock Screen accessory families on macOS; guard those with the
  same `supportedFamilies` (the system simply ignores unsupported families per platform).

### A.4 Fetch-in-widget vs read-cached, recommendation
**Recommended pattern: widget reads cached data the app wrote to the App Group; the app
(foreground + background task) owns fetching.** Reasons:
- Widget extensions have a tiny memory/time budget and an unreliable network window;
  a self-hosted Proxmox box may be on a VPN/LAN the widget can't reach.
- Self-signed Proxmox TLS: your `ProxmoxTrustDelegate` trust handling is easier to keep
  correct in one place (the app) than duplicated in the extension.
- It keeps the token-use surface small.

So: the app writes a small `StatusSnapshot` to the shared `UserDefaults`/container after
every successful poll (foreground refresh and background task), then calls
`WidgetCenter.shared.reloadTimelines(ofKind: Shared.statusWidgetKind)` (or
`reloadAllTimelines()`). The widget's `TimelineProvider` only **reads** the snapshot.

If you do want the widget to opportunistically refresh on its own (e.g. on home Wi-Fi),
it *can* call `URLSession` inside `getTimeline` using `async/await` with a **short
timeout (~10 s)** and a graceful fallback to the cached snapshot, but make this a
best-effort top-up, not the primary path. ([Fetching remote data in a widget](https://swiftsenpai.com/development/widget-load-remote-data/))

### A.5 Swift snippets

Shared snapshot model + store (in `ReeveModels`, so app and widget share it):

```swift
public struct StatusSnapshot: Codable, Sendable {
    public let generatedAt: Date
    public let nodeName: String
    public let isOnline: Bool
    public let cpuFraction: Double        // 0...1
    public let memoryFraction: Double     // 0...1
    public let runningGuests: Int
    public let totalGuests: Int
}

public enum SnapshotStore {
    private static let key = "status.snapshot.v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: Shared.appGroup) }

    public static func write(_ snapshot: StatusSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }
    public static func read() -> StatusSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StatusSnapshot.self, from: data)
    }
}
```

TimelineEntry + Provider (cache-reading):

```swift
import WidgetKit
import SwiftUI
import ReeveModels

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: StatusSnapshot?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, snapshot: SnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: .now, snapshot: SnapshotStore.read())
        // Soft cadence; app will push reloads when it has fresher data.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
```

Widget + view (iOS 17 container background, multi-family):

```swift
struct HomelabStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.statusWidgetKind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)   // required since iOS 17
        }
        .configurationDisplayName("Homelab Status")
        .description("Node health and running guests.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.snapshot?.isOnline == true ? "Homelab up" : "Homelab ?")
        case .accessoryCircular:
            Gauge(value: entry.snapshot?.cpuFraction ?? 0) { Text("CPU") }
                .gaugeStyle(.accessoryCircular)
        default:
            VStack(alignment: .leading) {
                Text(entry.snapshot?.nodeName ?? "Homelab").font(.headline)
                if let s = entry.snapshot {
                    Text("\(s.runningGuests)/\(s.totalGuests) running")
                    Text(s.generatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No data yet")
                }
            }
        }
    }
}
```

App side, push reloads after every successful poll:

```swift
import WidgetKit
func publish(_ snapshot: StatusSnapshot) {
    SnapshotStore.write(snapshot)
    WidgetCenter.shared.reloadTimelines(ofKind: Shared.statusWidgetKind)
}
```
([WidgetCenter.reloadTimelines / reloadAllTimelines](https://developer.apple.com/documentation/widgetkit/widgetcenter))

---

## PART B. Background refresh + local notifications (alerts)

### B.1 BGAppRefreshTask vs BGProcessingTask
([BackgroundTasks](https://developer.apple.com/documentation/backgroundtasks),
[BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler))

| | `BGAppRefreshTaskRequest` | `BGProcessingTaskRequest` |
|---|---|---|
| Purpose | Keep content fresh ("is my homelab up?") | Long/heavy maintenance (history compaction, log sync) |
| Budget | ~**30 s** wall time per run | **minutes** of run time |
| Scheduling | `earliestBeginDate` only | + `requiresNetworkConnectivity`, `requiresExternalPower` |
| Typical cadence | system-decided, opportunistic (often a few times/day, biased to overnight charging) | runs when device idle/charging |

For Proxmox polling-and-alerting use **`BGAppRefreshTask`** as the primary path; reserve
`BGProcessingTask` for anything heavy you might add later.

### B.2 Info.plist + registration
Add to the **app's** Info.plist:
- `UIBackgroundModes` → array including `fetch` (and `processing` if you use the
  processing task).
- `BGTaskSchedulerPermittedIdentifiers` → array of your identifiers, e.g.
  `com.homelabmonitor.refresh`, `com.homelabmonitor.maintenance`. These MUST exactly
  match the IDs you register, or registration throws and tasks never run.
  ([BGTaskSchedulerPermittedIdentifiers](https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers))

Register **once, before launch finishes** (in `application(_:didFinishLaunchingWithOptions:)`
for UIKit, or an `init`/`.backgroundTask` setup for SwiftUI App lifecycle). Registering
the same identifier twice can cause the system to terminate the app.

```swift
import BackgroundTasks

func registerBackgroundTasks() {
    BGTaskScheduler.shared.register(
        forTaskWithIdentifier: Shared.bgRefreshTaskID, using: nil
    ) { task in
        handleAppRefresh(task as! BGAppRefreshTask)
    }
}

func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Shared.bgRefreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // hint only
    try? BGTaskScheduler.shared.submit(request)
}

func handleAppRefresh(_ task: BGAppRefreshTask) {
    scheduleAppRefresh() // always re-schedule the next one first

    let work = Task {
        do {
            let snapshot = try await PollService.shared.pollOnce()   // uses ReeveNetworking
            SnapshotStore.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()                  // Part A interplay
            await AlertEngine.shared.evaluate(snapshot)               // Part B.4
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }
    task.expirationHandler = { work.cancel() }   // 30 s cap, clean up promptly
}
```

SwiftUI App-lifecycle alternative (iOS 17): use the
[`.backgroundTask(.appRefresh(_:))`](https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:))
scene modifier instead of manual `register`, plus
`.onChange(of: scenePhase)` → `scheduleAppRefresh()` when entering `.background`.

### B.3 macOS differences
- **`BGTaskScheduler` is now available on macOS 13+** (declared on macOS in recent SDKs),
  and SwiftUI's `.backgroundTask(.appRefresh:)` works on macOS 13+. So on macOS 14 you can
  use the same code path. Note the Info.plist `BGTaskSchedulerPermittedIdentifiers`
  requirement applies the same way. (Historically the API was iOS-only, so older guides
  say it's unavailable, verify against the current SDK's availability annotation.)
- The classic, always-reliable macOS option is
  [`NSBackgroundActivityScheduler`](https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler)
  (Foundation), good for low-priority repeating maintenance with QoS/interval/tolerance.
  If you ship a **menu-bar / LSUIElement** Mac app, that process can also simply poll on a
  `Timer` while running, which is far more permissive than iOS.
- macOS has no Lock Screen accessory widgets; otherwise Parts A/B apply.

### B.4 Network poll → thresholds → local notification, without spam
Request authorization once (early, or at the point the user enables alerts):

```swift
import UserNotifications
let center = UNUserNotificationCenter.current()
let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
```
([requestAuthorization](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:)))

Post a notification when a threshold is crossed:

```swift
func notify(title: String, body: String, id: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    // nil trigger = deliver immediately
    let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}
```
([UNNotificationRequest](https://developer.apple.com/documentation/usernotifications/unnotificationrequest),
[UNMutableNotificationContent](https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent))

**Anti-spam / de-dup, track alert state in the shared App Group.** Use edge-triggering
(only notify on transition into a bad state) plus a cooldown, and a **stable request
identifier per alert kind** so re-posting *replaces* rather than stacks:

```swift
struct AlertState: Codable { var firingKinds: Set<String> = []; var lastFired: [String: Date] = [:] }

actor AlertEngine {
    static let shared = AlertEngine()
    private let cooldown: TimeInterval = 30 * 60

    func evaluate(_ s: StatusSnapshot) {
        var state = AlertStateStore.read()
        check("node.down", isBad: !s.isOnline,
              title: "Homelab offline", body: "\(s.nodeName) is not responding.", &state)
        check("cpu.high", isBad: s.cpuFraction > 0.9,
              title: "High CPU", body: "\(Int(s.cpuFraction*100))% on \(s.nodeName).", &state)
        AlertStateStore.write(state)
    }

    private func check(_ kind: String, isBad: Bool, title: String, body: String, _ state: inout AlertState) {
        if isBad {
            let last = state.lastFired[kind] ?? .distantPast
            let isNewEdge = !state.firingKinds.contains(kind)
            if isNewEdge || Date().timeIntervalSince(last) > cooldown {
                notify(title: title, body: body, id: kind)  // same id => replaces
                state.lastFired[kind] = .now
            }
            state.firingKinds.insert(kind)
        } else {
            state.firingKinds.remove(kind)   // recovered: allow next edge to fire
        }
    }
}
```
Key points: edge-trigger on entering the bad state, cooldown to suppress repeats while it
stays bad, clear on recovery so the next failure alerts again, and reuse the identifier so
notifications don't pile up. Persist `AlertState` in the App Group so foreground polls,
background tasks, and (optionally) the widget all share one view of what's already firing.

### B.5 Background ↔ widget interplay
The single background poll does triple duty: write the `StatusSnapshot` to the App Group,
call `WidgetCenter.shared.reloadAllTimelines()`, and run `AlertEngine.evaluate`. That keeps
widget data, alerts, and any in-app cache consistent from one network round-trip. (Shown in
B.2 `handleAppRefresh`.)

### B.6 Honest limits
- iOS background execution is **opportunistic**: the system decides if/when
  `BGAppRefreshTask` runs based on charging, battery, network, usage patterns, and Low
  Power Mode. It can be hours between runs, or never if the user force-quits the app.
  **Do not market this as real-time monitoring**; it's "checked periodically."
- The only true push path is **APNs**, which requires a server to send pushes. A
  self-hosted Proxmox box can't send APNs directly without (a) an Apple Developer account
  for the push certificate/key and (b) a small server-side relay holding device tokens.
  Realistic options if you need timely alerts:
  - Run a tiny relay/bridge (e.g., your own service, or a self-hosted push tool like
    **ntp/ntfy/Gotify** with their iOS apps) that turns Proxmox webhooks into pushes.
  - Accept periodic `BGAppRefreshTask` polling as "good enough" for a hobby homelab.
  - On macOS (menu-bar app left running) you get near-real-time polling for free.

---

## PART C. App Intents / Siri / Control Center (brief)

Use the **App Intents** framework (no SiriKit intents file, pure Swift) to expose actions
to Siri, Shortcuts, Spotlight, the Action button, and Control Center.
([App Intents](https://developer.apple.com/documentation/appintents),
[Integrating actions with Siri and Apple Intelligence](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence))

Put intents in a target both the app and the widget/control extension can link (a thin
`HomelabIntents` SPM target, or directly in ReeveFeatures), so the same `AppIntent`
backs in-app, Shortcuts, and Control Center.

A query/value intent ("is my homelab up"):

```swift
import AppIntents

struct HomelabStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Homelab Status"
    static let openAppWhenRun = false   // run in the background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = try await PollService.shared.pollOnce()
        let line = snapshot.isOnline
            ? "\(snapshot.nodeName) is up: \(snapshot.runningGuests) guests running."
            : "\(snapshot.nodeName) is not responding."
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}
```

A parameterized action ("start a VM") with a dynamic entity for VM selection:

```swift
struct StartGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Guest"
    @Parameter(title: "Guest") var guest: GuestEntity
    func perform() async throws -> some IntentResult {
        try await PollService.shared.power(.start, guestID: guest.id)  // PowerAction already exists
        return .result()
    }
}
// GuestEntity: AppEntity + an AppEntityQuery so Siri/Shortcuts can list guests.
```

Expose discoverability via an `AppShortcutsProvider` so the phrases work without manual
Shortcuts setup.

**Control Center control (iOS 18+ only):** a `ControlWidget` whose button runs an intent.
This is the modern interactive-widget surface; it lives in the (or a) Widget Extension.
([ControlWidget / Control Center controls. WWDC25 "Get to know App Intents"](https://developer.apple.com/videos/play/wwdc2025/244/),
[Integrating App Intents with a control action](https://www.createwithswift.com/integrating-app-intents-with-control-action/))

```swift
import WidgetKit
import AppIntents

@available(iOS 18.0, *)
struct HomelabControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.homelabmonitor.control.status") {
            ControlWidgetButton(action: HomelabStatusIntent()) {
                Label("Homelab", systemImage: "server.rack")
            }
        }
        .displayName("Homelab Status")
    }
}
```
Notes / platform flags:
- Control Center controls and interactive Home Screen widget buttons require **iOS 18+**;
  guard with `@available`. Not available on macOS.
- App Intents themselves work on iOS 17 and macOS 14; Control widgets do not.
- Intents that perform power actions should set `openAppWhenRun = false` only if they can
  finish quickly; otherwise let them open the app.

---

## Build/entitlement checklist
- [ ] App Group `group.com.homelabmonitor.shared` on app + widget (+ macOS) targets.
- [ ] Keychain Sharing group `com.homelabmonitor.keychain` on app + widget; construct
      `KeychainStore(accessGroup:)`; token written with `...AfterFirstUnlockThisDeviceOnly`.
- [ ] Widget target links `ReeveModels` + `ReevePersistence` (+ `ReeveNetworking` only if it fetches).
- [ ] `StatusSnapshot` / `SnapshotStore` / `AlertState` live in `ReeveModels` (shared).
- [ ] Info.plist: `UIBackgroundModes` (`fetch`[/`processing`]) + `BGTaskSchedulerPermittedIdentifiers`.
- [ ] Register BG tasks before end of launch; always re-schedule inside the handler; set `expirationHandler`.
- [ ] Notification authorization requested; alerts edge-triggered with cooldown + stable IDs.
- [ ] iOS 17 widgets use `.containerBackground(_:for: .widget)`.
- [ ] Control Center control guarded `@available(iOS 18, *)`; App Intents available iOS 17 / macOS 14.

## Sources
- WidgetKit, https://developer.apple.com/documentation/widgetkit
- Keeping a widget up to date, https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- TimelineProvider, https://developer.apple.com/documentation/widgetkit/timelineprovider
- TimelineReloadPolicy, https://developer.apple.com/documentation/widgetkit/timelinereloadpolicy
- WidgetCenter, https://developer.apple.com/documentation/widgetkit/widgetcenter
- WidgetFamily.accessoryCircular, https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycircular
- App Groups entitlement, https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups
- Keychain Access Groups entitlement, https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups
- Sharing keychain items among apps, https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
- BackgroundTasks, https://developer.apple.com/documentation/backgroundtasks
- BGTaskScheduler, https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
- BGTaskSchedulerPermittedIdentifiers, https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers
- NSBackgroundActivityScheduler (macOS), https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler
- SwiftUI .backgroundTask, https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:)
- UserNotifications / requestAuthorization, https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:)
- UNNotificationRequest, https://developer.apple.com/documentation/usernotifications/unnotificationrequest
- App Intents, https://developer.apple.com/documentation/appintents
- Integrating actions with Siri and Apple Intelligence, https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence
- WWDC25 "Get to know App Intents", https://developer.apple.com/videos/play/wwdc2025/244/
- Fetching remote data in a widget (Swift Senpai), https://swiftsenpai.com/development/widget-load-remote-data/
