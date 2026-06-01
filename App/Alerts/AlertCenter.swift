import Foundation
import ReeveModels
import UserNotifications

/// Evaluates dashboard data against the user's alert thresholds and posts local
/// notifications, with per-alert cooldown and edge-triggered guest-down detection
/// to avoid spam. Runs while the app is active/refreshing (iOS background polling
/// is opportunistic; true push would require a server).
@MainActor
final class AlertCenter {
    static let shared = AlertCenter()

    private var lastGuestUp: [Int: Bool] = [:]
    private var lastFired: [String: Date] = [:]
    private var runningTasks: Set<String> = []   // task UPIDs seen running
    private let cooldown: TimeInterval = 600
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func evaluate(_ resources: [ClusterResource]) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: PreferenceKey.alertsEnabled) else { return }
        let cpuThreshold = defaults.double(forKey: PreferenceKey.cpuThreshold)
        let memThreshold = defaults.double(forKey: PreferenceKey.memThreshold)
        let notifyGuestDown = defaults.bool(forKey: PreferenceKey.notifyGuestDown)

        if let node = resources.first(where: { $0.type == .node }) {
            if cpuThreshold > 0, let cpu = node.cpuPercent, cpu >= cpuThreshold {
                fire("node-cpu", "High CPU on \(node.displayName)", "CPU at \(Int(cpu))%.")
            }
            if memThreshold > 0, let fraction = node.memoryFraction, fraction * 100 >= memThreshold {
                fire("node-mem", "High memory on \(node.displayName)",
                     "Memory at \(Int(fraction * 100))%.")
            }
        }

        guard notifyGuestDown else { return }
        for guest in resources where guest.type == .qemu || guest.type == .lxc {
            guard let vmid = guest.vmid, !guest.isTemplate else { continue }
            let isUp = guest.status?.isUp == true
            if lastGuestUp[vmid] == true, !isUp {
                // Edge-triggered: a guest that was up is now down.
                fire("guest-\(vmid)", "Guest down", "\(guest.displayName) is no longer running.",
                     ignoreCooldown: true)
            }
            lastGuestUp[vmid] = isUp
        }
    }

    /// Fires when any node temperature crosses the user's threshold. The hottest
    /// channel drives the alert (with per-channel cooldown via the stable id).
    func evaluateTemperature(_ sensors: NodeSensors, nodeName: String) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: PreferenceKey.alertsEnabled) else { return }
        let threshold = defaults.double(forKey: PreferenceKey.tempThreshold)
        guard threshold > 0, let hottest = sensors.hottest, hottest.celsius >= threshold else { return }
        fire("node-temp", "High temperature on \(nodeName)",
             "\(hottest.label) at \(Int(hottest.celsius.rounded()))°C.")
    }

    /// Edge-triggered task notifications: only fires when a task we previously
    /// saw *running* has now finished, so we never notify for tasks that
    /// completed before the app was watching.
    func evaluateTasks(_ tasks: [ProxmoxTaskInfo]) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: PreferenceKey.alertsEnabled),
              defaults.bool(forKey: PreferenceKey.notifyTaskComplete) else { return }

        for task in tasks {
            if task.isRunning {
                runningTasks.insert(task.upid)
            } else if runningTasks.contains(task.upid) {
                runningTasks.remove(task.upid)
                fireTaskDone(task)
            }
        }
        // Drop UPIDs that have aged out of the recent window to bound memory.
        runningTasks.formIntersection(Set(tasks.map(\.upid)))
    }

    private func fireTaskDone(_ task: ProxmoxTaskInfo) {
        let name = Self.taskTypeLabel(task.type)
        let target = task.workerID.map { " (\($0))" } ?? ""
        if task.succeeded {
            fire("task-\(task.upid)", "\(name) finished", "\(name)\(target) completed successfully.",
                 ignoreCooldown: true)
        } else {
            fire("task-\(task.upid)", "\(name) failed", "\(name)\(target): \(task.displayStatus)",
                 ignoreCooldown: true)
        }
    }

    /// Map Proxmox task type codes to friendly names.
    nonisolated static func taskTypeLabel(_ type: String) -> String {
        switch type {
        case "vzdump": "Backup"
        case "qmstart", "vzstart": "Start"
        case "qmstop", "vzstop": "Stop"
        case "qmshutdown", "vzshutdown": "Shutdown"
        case "qmreboot", "vzreboot": "Reboot"
        case "qmsnapshot", "vzsnapshot": "Snapshot"
        case "qmrollback", "vzrollback": "Rollback"
        case "qmigrate": "Migration"
        case "qmclone", "imgcopy": "Clone"
        case "qmrestore", "vzrestore": "Restore"
        case "aptupdate": "Updates"
        case "spiceshell", "vncshell", "termproxy": "Console"
        default: type.capitalized
        }
    }

    private func fire(_ id: String, _ title: String, _ body: String, ignoreCooldown: Bool = false) {
        if !ignoreCooldown, let last = lastFired[id], now().timeIntervalSince(last) < cooldown {
            return
        }
        lastFired[id] = now()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Stable id → a re-fired alert replaces the previous one instead of stacking.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        // Also fan out to any configured webhook/chat channels.
        WebhookNotifier.shared.broadcast(title: title, body: body)
    }
}
