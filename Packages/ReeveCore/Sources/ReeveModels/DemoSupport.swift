import Foundation

// Demo mode support. The app ships a built-in demonstration dataset (App Store
// Review Guideline 2.1) that anyone can explore without a Proxmox server. It is
// reached by adding a server whose address is `DemoMode.host` — a recognizable but
// unguessable magic host that the networking layer intercepts and answers with
// this canned data instead of making any network request.
public enum DemoMode {
    /// The magic server address that activates the built-in demo dataset.
    /// (Documented in the App Store Review notes; intercepted before any request.)
    public static let host = "demo-3f9a2c7e.reeve.app"

    /// Whether a host string refers to the demo dataset.
    public static func isDemo(host: String?) -> Bool {
        host?.lowercased() == self.host
    }
}

// These two model types declare a custom `init(from:)`, so no memberwise init is
// synthesized — a public one is safe to add (and useful for previews/tests). The
// rest of the models keep their synthesized memberwise init, which `DemoDataset`
// (same module) uses directly.

extension Snapshot {
    public init(
        name: String, description: String? = nil, snaptime: Int? = nil,
        parent: String? = nil, includesRAM: Bool = false
    ) {
        self.name = name; self.description = description; self.snaptime = snaptime
        self.parent = parent; self.includesRAM = includesRAM
    }
}

extension GuestConfig {
    public init(values: [String: String]) { self.values = values }
}

// MARK: - The demonstration dataset
//
// Built here in `ReeveModels` so it can use the models' (internal) memberwise
// initializers. `DemoProxmoxAPI` (in ReeveNetworking) simply forwards to these.

public enum DemoDataset {
    public static let node = "pve"

    struct Guest {
        let vmid: Int; let name: String; let kind: GuestKind; let running: Bool
        let cpu: Double; let memUsed: Double; let memMax: Double; let diskMax: Double
        let tags: String?
    }

    /// GiB → bytes.
    static func gib(_ x: Double) -> Int { Int(x * 1_073_741_824) }

    static let guests: [Guest] = [
        Guest(vmid: 100, name: "nginxproxymanager", kind: .lxc, running: true, cpu: 0.003, memUsed: 0.18, memMax: 0.5, diskMax: 8, tags: "web;proxy"),
        Guest(vmid: 101, name: "uptime-kuma",        kind: .lxc, running: true, cpu: 0.006, memUsed: 0.21, memMax: 0.5, diskMax: 8, tags: "monitoring"),
        Guest(vmid: 102, name: "home-assistant",     kind: .qemu, running: true, cpu: 0.031, memUsed: 2.4, memMax: 4, diskMax: 32, tags: "automation"),
        Guest(vmid: 103, name: "immich",             kind: .lxc, running: true, cpu: 0.018, memUsed: 3.1, memMax: 6, diskMax: 256, tags: "photos"),
        Guest(vmid: 104, name: "jellyfin",           kind: .lxc, running: true, cpu: 0.124, memUsed: 1.8, memMax: 4, diskMax: 32, tags: "media"),
        Guest(vmid: 105, name: "adguard",            kind: .lxc, running: true, cpu: 0.002, memUsed: 0.12, memMax: 0.5, diskMax: 8, tags: "dns"),
        Guest(vmid: 106, name: "postgresql",         kind: .lxc, running: true, cpu: 0.041, memUsed: 1.2, memMax: 2, diskMax: 32, tags: "db"),
        Guest(vmid: 107, name: "vaultwarden",        kind: .lxc, running: true, cpu: 0.001, memUsed: 0.08, memMax: 0.5, diskMax: 8, tags: "security"),
        Guest(vmid: 108, name: "docker",             kind: .qemu, running: true, cpu: 0.219, memUsed: 5.1, memMax: 8, diskMax: 64, tags: "containers"),
        Guest(vmid: 110, name: "windows11",          kind: .qemu, running: false, cpu: 0, memUsed: 0, memMax: 8, diskMax: 128, tags: nil),
    ]

    static func guest(_ vmid: Int) -> Guest? { guests.first { $0.vmid == vmid } }

    public static func version() -> PVEVersion {
        PVEVersion(version: "8.2.4", release: "8.2", repoid: "demo")
    }

    /// Concise `ClusterResource` builder over the full synthesized init.
    private static func resource(
        id: String, type: ResourceType, status: RunStatus? = nil, node: String? = nil,
        name: String? = nil, vmid: Int? = nil, cpu: Double? = nil, maxcpu: Double? = nil,
        mem: Int? = nil, maxmem: Int? = nil, disk: Int? = nil, maxdisk: Int? = nil,
        netin: Int? = nil, netout: Int? = nil, uptime: Int? = nil, tags: String? = nil,
        storage: String? = nil, content: String? = nil
    ) -> ClusterResource {
        ClusterResource(
            id: id, type: type, status: status, node: node, name: name, vmid: vmid,
            cpu: cpu, maxcpu: maxcpu, mem: mem, maxmem: maxmem, disk: disk, maxdisk: maxdisk,
            netin: netin, netout: netout, diskread: nil, diskwrite: nil, uptime: uptime,
            tags: tags, template: nil, storage: storage, plugintype: nil, content: content, shared: 0
        )
    }

    public static func clusterResources() -> [ClusterResource] {
        var rows: [ClusterResource] = [
            resource(id: "node/\(node)", type: .node, status: .online, node: node, name: node,
                     cpu: 0.12, maxcpu: 32, mem: gib(180.9), maxmem: gib(251.6),
                     disk: gib(28), maxdisk: gib(440), uptime: 54 * 86400 + 82_800)
        ]
        for g in guests {
            rows.append(resource(
                id: "\(g.kind.rawValue)/\(g.vmid)", type: g.kind == .qemu ? .qemu : .lxc,
                status: g.running ? .running : .stopped, node: node, name: g.name, vmid: g.vmid,
                cpu: g.cpu, maxcpu: g.kind == .qemu ? 4 : 2, mem: gib(g.memUsed), maxmem: gib(g.memMax),
                disk: gib(g.diskMax * 0.4), maxdisk: gib(g.diskMax),
                netin: g.running ? 84_213_004 : 0, netout: g.running ? 41_882_113 : 0,
                uptime: g.running ? 21 * 86400 : 0, tags: g.tags))
        }
        rows.append(contentsOf: [
            resource(id: "storage/\(node)/local", type: .storage, status: .online, node: node,
                     disk: gib(74), maxdisk: gib(440), storage: "local", content: "backup,iso,vztmpl"),
            resource(id: "storage/\(node)/local-lvm", type: .storage, status: .online, node: node,
                     disk: gib(612), maxdisk: gib(1800), storage: "local-lvm", content: "images,rootdir"),
            resource(id: "storage/\(node)/local-zfs", type: .storage, status: .online, node: node,
                     disk: gib(1340), maxdisk: gib(3600), storage: "local-zfs", content: "images,rootdir"),
        ])
        return rows
    }

    public static func nodeStatus() -> NodeStatus {
        NodeStatus(
            cpu: 0.12,
            memory: NodeStatus.Memory(total: gib(251.6), used: gib(180.9), free: gib(70.7)),
            swap: NodeStatus.Memory(total: gib(8), used: gib(0.3), free: gib(7.7)),
            rootfs: NodeStatus.Memory(total: gib(440), used: gib(74), free: gib(366)),
            cpuinfo: NodeStatus.CPUInfo(model: "AMD Ryzen 9 5950X 16-Core Processor", cpus: 32, cores: 16, sockets: 1, mhz: "3400.000"),
            loadavg: ["0.42", "0.55", "0.61"], uptime: 54 * 86400 + 82_800,
            pveversion: "pve-manager/8.2.4/run", kversion: "Linux 6.8.12-1-pve"
        )
    }

    public static func guestStatus(vmid: Int, kind: GuestKind) -> GuestStatus {
        let g = guest(vmid)
        return GuestStatus(
            status: (g?.running ?? true) ? .running : .stopped, name: g?.name, vmid: vmid,
            cpu: g?.cpu, cpus: kind == .qemu ? 4 : 2, mem: gib(g?.memUsed ?? 1), maxmem: gib(g?.memMax ?? 2),
            disk: gib((g?.diskMax ?? 16) * 0.4), maxdisk: gib(g?.diskMax ?? 16),
            netin: 84_213_004, netout: 41_882_113, diskread: 1_284_213_004, diskwrite: 402_882_113,
            uptime: (g?.running ?? true) ? 21 * 86400 + 14_400 : 0, pid: (g?.running ?? true) ? 1843 : nil
        )
    }

    private static func series(node isNode: Bool, base: Double, amp: Double, memUsed: Double, memMax: Double) -> [RRDPoint] {
        let now = Int(Date().timeIntervalSince1970)
        let count = 60, step = 60
        return (0..<count).map { i in
            let t = now - (count - i) * step
            let phase = Double(i)
            let wave = 0.5 + 0.5 * sin(phase / 7) * 0.6 + 0.3 * sin(phase / 2.3)
            let cpu = max(0.005, min(0.98, base + amp * wave))
            let mem = (memUsed + 0.15 * memMax * sin(phase / 9)) * 1_073_741_824
            let netIn = 200_000 + 1_400_000 * abs(sin(phase / 5))
            let netOut = 120_000 + 900_000 * abs(cos(phase / 6))
            if isNode {
                return RRDPoint(time: t, cpu: cpu, maxcpu: 32, mem: nil, maxmem: nil, disk: nil,
                                maxdisk: nil, netin: netIn, netout: netOut, diskread: nil, diskwrite: nil,
                                memused: mem, memtotal: memMax * 1_073_741_824)
            } else {
                return RRDPoint(time: t, cpu: cpu, maxcpu: 4, mem: mem, maxmem: memMax * 1_073_741_824,
                                disk: nil, maxdisk: nil, netin: netIn, netout: netOut,
                                diskread: 600_000 * abs(sin(phase / 4)), diskwrite: 300_000 * abs(cos(phase / 3)),
                                memused: nil, memtotal: nil)
            }
        }
    }

    public static func guestRRD(vmid: Int) -> [RRDPoint] {
        let g = guest(vmid)
        return series(node: false, base: max(0.02, g?.cpu ?? 0.05), amp: 0.06, memUsed: g?.memUsed ?? 1, memMax: g?.memMax ?? 2)
    }

    public static func nodeRRD() -> [RRDPoint] {
        series(node: true, base: 0.10, amp: 0.08, memUsed: 180.9, memMax: 251.6)
    }

    public static func snapshots() -> [Snapshot] {
        let now = Int(Date().timeIntervalSince1970)
        return [
            Snapshot(name: "clean-install", description: "Fresh install", snaptime: now - 19 * 86400),
            Snapshot(name: "stable-2026-05", description: "Known-good before upgrade", snaptime: now - 3 * 86400, parent: "clean-install", includesRAM: true),
            Snapshot(name: "pre-update", description: "Auto snapshot before update", snaptime: now - 4 * 3600, parent: "stable-2026-05"),
            Snapshot(name: "current", description: "You are here", parent: "pre-update"),
        ]
    }

    public static func backups(storage: String) -> [BackupFile] {
        let now = Int(Date().timeIntervalSince1970)
        func vol(_ id: Int, _ kind: String, _ size: Double, _ ageDays: Int, _ note: String) -> BackupFile {
            BackupFile(volid: "\(storage):backup/vzdump-\(kind)-\(id)-2026_05_\(28 - ageDays)-02_00_03.tar.zst",
                       size: gib(size), ctime: now - ageDays * 86400, format: "tar.zst", notes: note, vmid: id)
        }
        return [
            vol(102, "qemu", 2.1, 0, "home-assistant"), vol(103, "lxc", 18.4, 0, "immich"),
            vol(104, "lxc", 3.2, 1, "jellyfin"), vol(106, "lxc", 1.7, 1, "postgresql"),
            vol(108, "qemu", 22.6, 2, "docker"),
        ]
    }

    public static func nodeServices() -> [NodeService] {
        func svc(_ n: String, _ d: String, _ running: Bool = true) -> NodeService {
            NodeService(name: n, desc: d, state: running ? "running" : "dead",
                        activeState: running ? "active" : "inactive", unitState: "enabled")
        }
        return [
            svc("pveproxy", "PVE API Proxy Server"), svc("pvedaemon", "PVE API Daemon"),
            svc("pve-cluster", "Proxmox VE cluster filesystem"), svc("pvestatd", "PVE Status Daemon"),
            svc("pvescheduler", "Proxmox VE scheduler"), svc("sshd", "OpenBSD Secure Shell server"),
            svc("chrony", "chrony NTP client/server"), svc("zfs-zed", "ZFS Event Daemon"),
        ]
    }

    public static func tasks() -> [ProxmoxTaskInfo] {
        let now = Int(Date().timeIntervalSince1970)
        func task(_ type: String, _ worker: String, _ ago: Int, _ dur: Int, ok: Bool = true) -> ProxmoxTaskInfo {
            ProxmoxTaskInfo(upid: "UPID:\(node):0000\(ago):DEMO:\(type):\(worker):root@pam:",
                            type: type, workerID: worker, user: "root@pam",
                            status: ok ? "OK" : "error", starttime: now - ago, endtime: now - ago + dur,
                            exitstatus: ok ? "OK" : "command failed")
        }
        return [
            task("vzdump", "103", 4 * 3600, 220), task("vzdump", "102", 4 * 3600, 90),
            task("qmsnapshot", "102", 4 * 3600, 6), task("startall", "", 86400, 42),
            task("aptupdate", "", 2 * 86400, 14),
        ]
    }

    public static func taskStatus(upid: String) -> ProxmoxTaskStatus {
        ProxmoxTaskStatus(upid: upid, status: "stopped", exitstatus: "OK", type: "demo")
    }

    public static func guestConfig(vmid: Int, kind: GuestKind) -> GuestConfig {
        let g = guest(vmid)
        return GuestConfig(values: [
            "name": g?.name ?? "guest", "cores": kind == .qemu ? "4" : "2",
            "memory": String(Int((g?.memMax ?? 2) * 1024)), "ostype": kind == .qemu ? "l26" : "debian",
            "onboot": "1", "net0": "virtio,bridge=vmbr0", "scsi0": "local-lvm:vm-\(vmid)-disk-0",
            "description": "Managed by Reeve demo dataset.",
        ])
    }

    public static func emptyAgentInterfaces() -> AgentNetworkInterfaces {
        AgentNetworkInterfaces(result: [])
    }

    /// A believable task UPID returned by demo mutations.
    public static let upid = "UPID:\(node):00000DEM:00000000:00000000:demo:0:root@pam:"
}
