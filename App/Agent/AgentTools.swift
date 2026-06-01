import Foundation

/// The functions the agent may call. Schemas are sent to the model; names in
/// `writeTools` change state and require explicit user approval before running.
enum AgentTools {
    static let writeTools: Set<String> = [
        "guest_power", "create_snapshot", "delete_snapshot", "rollback_snapshot",
        "clone_guest", "delete_guest", "migrate_guest", "set_guest_resources",
        "resize_disk", "set_guest_tags", "set_guest_notes", "create_backup",
        "node_power", "wake_on_lan", "service_action",
        "create_guest", "restore_backup", "convert_to_template", "set_cloud_init",
        "create_firewall_rule", "delete_firewall_rule", "set_firewall_rule",
        "create_backup_job", "delete_backup_job", "set_backup_job", "delete_volume",
        "run_in_guest", "run_on_node",
    ]

    static func isWrite(_ name: String) -> Bool { writeTools.contains(name) }

    private static let vmidProp: [String: Any] = ["type": "integer", "description": "The guest VMID."]

    static var schemas: [[String: Any]] {
        [
            // MARK: reads
            fn(
                "web_search",
                "Search the public web for current information (news, docs, prices, facts) beyond the homelab. Read-only.",
                [
                    "query": ["type": "string", "description": "The search query."],
                    "max_results": ["type": "integer",
                                    "description": "Maximum results to return (default 5, max 10)."],
                ],
                ["query"]
            ),
            fn("list_guests", "List all VMs and containers with VMID, type, and running state.", [:], []),
            fn("list_nodes", "List the cluster's nodes and whether each is online.", [:], []),
            fn("node_status", "CPU %, memory, and uptime for a node (defaults to the first node).",
               ["node": ["type": "string"]], []),
            fn("guest_status", "Live CPU/memory/uptime for one guest.", ["vmid": vmidProp], ["vmid"]),
            fn("guest_config", "Full configuration (cores, memory, disks, network, notes) of a guest.",
               ["vmid": vmidProp], ["vmid"]),
            fn("list_snapshots", "List snapshots of a guest.", ["vmid": vmidProp], ["vmid"]),
            fn("list_backups", "List vzdump backups across backup storages.", [:], []),
            fn("list_storage", "List storages with usage on a node.", ["node": ["type": "string"]], []),
            fn("list_disks", "List physical disks with SMART health and SSD wear on a node.",
               ["node": ["type": "string"]], []),
            fn("list_services", "List node services and whether each is running.",
               ["node": ["type": "string"]], []),
            fn("list_tasks", "Recent Proxmox tasks and their status.", ["node": ["type": "string"]], []),
            fn("list_updates", "Available apt package updates on a node.", ["node": ["type": "string"]], []),
            fn("list_firewall_rules",
               "List firewall rules at a scope: datacenter, node, or guest.",
               ["scope": ["type": "string", "enum": ["datacenter", "node", "guest"]],
                "vmid": vmidProp, "node": ["type": "string"]], ["scope"]),

            // MARK: writes (require approval)
            fn("guest_power", "Start, stop, shut down, or reboot a guest. Changes state.",
               ["vmid": vmidProp, "action": ["type": "string", "enum": ["start", "stop", "shutdown", "reboot"]]],
               ["vmid", "action"]),
            fn("create_snapshot", "Create a snapshot of a guest. Changes state.",
               ["vmid": vmidProp, "name": ["type": "string", "description": "Snapshot name, no spaces."]],
               ["vmid", "name"]),
            fn("delete_snapshot", "Delete a named snapshot of a guest. Changes state.",
               ["vmid": vmidProp, "name": ["type": "string"]], ["vmid", "name"]),
            fn("rollback_snapshot", "Roll a guest back to a snapshot. Destructive.",
               ["vmid": vmidProp, "name": ["type": "string"]], ["vmid", "name"]),
            fn("clone_guest", "Clone a guest/template to a new VMID. Changes state.",
               ["vmid": vmidProp, "newid": ["type": "integer"], "name": ["type": "string"],
                "full": ["type": "boolean"]], ["vmid", "newid"]),
            fn("delete_guest", "Permanently destroy a guest and its disks. Destructive.",
               ["vmid": vmidProp, "purge": ["type": "boolean"]], ["vmid"]),
            fn("migrate_guest", "Migrate a guest to another node. Changes state.",
               ["vmid": vmidProp, "target": ["type": "string"], "online": ["type": "boolean"]],
               ["vmid", "target"]),
            fn("set_guest_resources", "Change a guest's vCPU cores and/or memory (MB). Changes state.",
               ["vmid": vmidProp, "cores": ["type": "integer"], "memory": ["type": "integer"]], ["vmid"]),
            fn("resize_disk", "Grow a guest disk by N gigabytes. Changes state.",
               ["vmid": vmidProp, "disk": ["type": "string", "description": "e.g. scsi0, rootfs"],
                "gb": ["type": "integer"]], ["vmid", "disk", "gb"]),
            fn("set_guest_tags", "Set a guest's tags (space/comma separated). Changes state.",
               ["vmid": vmidProp, "tags": ["type": "string"]], ["vmid", "tags"]),
            fn("set_guest_notes", "Set a guest's notes/description. Changes state.",
               ["vmid": vmidProp, "notes": ["type": "string"]], ["vmid", "notes"]),
            fn("create_backup", "Back up a guest now to a storage. Changes state.",
               ["vmid": vmidProp, "storage": ["type": "string"],
                "mode": ["type": "string", "enum": ["snapshot", "suspend", "stop"]]], ["vmid"]),
            fn("node_power", "Reboot or shut down a node. Affects all its guests. Destructive.",
               ["node": ["type": "string"], "command": ["type": "string", "enum": ["reboot", "shutdown"]]],
               ["command"]),
            fn("wake_on_lan", "Send a Wake-on-LAN packet to power a node on.",
               ["node": ["type": "string"]], []),
            fn("service_action", "Start, stop, or restart a node service. Changes state.",
               ["service": ["type": "string"], "action": ["type": "string", "enum": ["start", "stop", "restart"]],
                "node": ["type": "string"]], ["service", "action"]),

            // MARK: more reads
            fn("list_backup_jobs", "List scheduled backup jobs (id, schedule, storage, selection).", [:], []),
            fn("list_users", "List Proxmox users and whether each is enabled.", [:], []),
            fn("list_templates", "List installable templates: container (vztmpl) and ISO volume ids.",
               ["node": ["type": "string"]], []),
            fn("list_replication", "List ZFS replication jobs.", [:], []),
            fn("list_sdn", "List software-defined networking zones and VNets.", [:], []),
            fn("list_network", "List a node's network interfaces (bridges, etc.).",
               ["node": ["type": "string"]], []),
            fn("cluster_status", "Cluster nodes, quorum, and HA resources.", [:], []),
            fn("next_vmid", "Get a free VMID to use for a new guest or clone.", [:], []),

            // MARK: more writes (require approval)
            fn("create_guest",
               "Create a new container or VM. For lxc provide template (vztmpl volid) and password; for qemu optionally provide iso and ostype.",
               ["type": ["type": "string", "enum": ["lxc", "qemu"]],
                "vmid": ["type": "integer", "description": "Optional; a free id is used if omitted."],
                "name": ["type": "string"], "cores": ["type": "integer"], "memory": ["type": "integer"],
                "disk_gb": ["type": "integer"], "storage": ["type": "string"], "bridge": ["type": "string"],
                "template": ["type": "string", "description": "lxc ostemplate volid"],
                "password": ["type": "string", "description": "lxc root password"],
                "iso": ["type": "string", "description": "qemu install ISO volid"],
                "ostype": ["type": "string"], "start": ["type": "boolean"]],
               ["type", "storage"]),
            fn("restore_backup", "Restore a guest from a backup archive (volid). Destructive if overwriting.",
               ["archive": ["type": "string", "description": "Backup volid from list_backups."],
                "vmid": vmidProp, "force": ["type": "boolean", "description": "Overwrite existing guest."]],
               ["archive", "vmid"]),
            fn("convert_to_template", "Convert a guest into a template. Irreversible.",
               ["vmid": vmidProp], ["vmid"]),
            fn("set_cloud_init", "Set cloud-init fields on a VM (user/password/ssh keys/ip).",
               ["vmid": vmidProp, "ciuser": ["type": "string"], "cipassword": ["type": "string"],
                "sshkeys": ["type": "string"], "ipconfig0": ["type": "string"]], ["vmid"]),
            fn("create_firewall_rule", "Add a firewall rule at a scope (datacenter/node/guest).",
               ["scope": ["type": "string", "enum": ["datacenter", "node", "guest"]],
                "vmid": vmidProp, "node": ["type": "string"],
                "direction": ["type": "string", "enum": ["in", "out"]],
                "action": ["type": "string", "enum": ["ACCEPT", "DROP", "REJECT"]],
                "proto": ["type": "string"], "dport": ["type": "string"],
                "source": ["type": "string"], "comment": ["type": "string"]],
               ["scope", "direction", "action"]),
            fn("delete_firewall_rule", "Delete a firewall rule by position at a scope.",
               ["scope": ["type": "string", "enum": ["datacenter", "node", "guest"]],
                "vmid": vmidProp, "node": ["type": "string"], "pos": ["type": "integer"]],
               ["scope", "pos"]),
            fn("set_firewall_rule", "Enable or disable a firewall rule by position.",
               ["scope": ["type": "string", "enum": ["datacenter", "node", "guest"]],
                "vmid": vmidProp, "node": ["type": "string"], "pos": ["type": "integer"],
                "enabled": ["type": "boolean"]], ["scope", "pos", "enabled"]),
            fn("create_backup_job", "Create a scheduled backup job.",
               ["storage": ["type": "string"], "schedule": ["type": "string", "description": "systemd calendar, e.g. 02:00"],
                "mode": ["type": "string", "enum": ["snapshot", "suspend", "stop"]],
                "all": ["type": "boolean"], "vmid": ["type": "string", "description": "comma-separated VMIDs if not all"],
                "comment": ["type": "string"]], ["storage", "schedule"]),
            fn("delete_backup_job", "Delete a scheduled backup job by id.",
               ["id": ["type": "string"]], ["id"]),
            fn("set_backup_job", "Enable or disable a backup job by id.",
               ["id": ["type": "string"], "enabled": ["type": "boolean"]], ["id", "enabled"]),
            fn("delete_volume", "Delete a storage volume (ISO/template/backup) by volid. Destructive.",
               ["node": ["type": "string"], "storage": ["type": "string"], "volid": ["type": "string"]],
               ["storage", "volid"]),
            fn("run_in_guest",
               """
               Run a shell command as root INSIDE a guest and return its combined output \
               plus the exit status. This is how you install and configure software \
               (apt/dnf, downloads, writing config files, enabling systemd services, etc.). \
               Runs via `pct exec` for containers or the QEMU guest agent for VMs, so the \
               guest must be running. Requires SSH credentials for the server (set up once \
               in a node's Terminal). \
               Work step by step: run ONE command, read its output and exit status, then \
               decide the next. Rules that keep commands from hanging (each call has a time \
               limit and is killed if exceeded): \
               (1) Always use non-interactive flags, `apt-get -y`, `DEBIAN_FRONTEND=noninteractive`, \
               `curl -fsSL`; never run a command that waits for input or opens a pager/editor. \
               (2) NEVER start a long-running/foreground process directly (e.g. `java -jar …`, \
               `./server`, `npm start`), it will hit the time limit. Instead install it as a \
               `systemd` service and `systemctl enable --now` it, which returns immediately. \
               (3) Make steps idempotent where possible. \
               (4) For a slow download/build, pass a larger `timeout_seconds`. \
               After setup, verify the service is actually listening (e.g. `ss -tlnp`, `systemctl status`) \
               before telling the user it's ready.
               """,
               ["vmid": vmidProp,
                "command": ["type": "string", "description": "Shell command (run with bash -lc)."],
                "timeout_seconds": ["type": "integer",
                    "description": "Max seconds before the command is killed. Default 120, max 900."]],
               ["vmid", "command"]),
            fn("run_on_node",
               """
               Run a shell command as root directly on a Proxmox NODE host (not inside a \
               guest) and return its combined output plus exit status. Use this for node \
               maintenance the API can't do, e.g. updating the host: \
               `apt update && DEBIAN_FRONTEND=noninteractive apt full-upgrade -y`, checking \
               `[ -f /var/run/reboot-required ]`, or inspecting `journalctl`. Runs over the \
               server's SSH credentials (set up once in a node's Terminal). Same rules as \
               run_in_guest: non-interactive flags only, never start a foreground process, \
               run one command at a time and check its exit status. For a Proxmox-version or \
               kernel upgrade, tell the user a reboot may be needed afterward (use node_power \
               to reboot, with approval).
               """,
               ["node": ["type": "string", "description": "Node name; defaults to the first node."],
                "command": ["type": "string", "description": "Shell command (run with bash -lc)."],
                "timeout_seconds": ["type": "integer",
                    "description": "Max seconds before the command is killed. Default 120, max 900."]],
               ["command"]),
        ]
    }

    private static func fn(
        _ name: String, _ description: String, _ properties: [String: Any], _ required: [String]
    ) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name, "description": description,
                "parameters": ["type": "object", "properties": properties, "required": required],
            ],
        ]
    }
}
