import Foundation
import ReeveModels
import ReevePersistence
import ReeveTerminal
import Observation

struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case system, user, assistant, tool }
    var id = UUID()
    let role: Role
    var content: String
    /// Collapsed "thinking" output for reasoning models (assistant turns).
    var reasoning: String? = nil
    /// Expandable detail for tool rows (arguments/result).
    var detail: String? = nil
    /// Base64 JPEG attached to a user turn (for vision models).
    var imageBase64: String? = nil
}

/// A pending state-changing tool the agent wants to run, awaiting user approval.
struct ApprovalRequest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

@MainActor
@Observable
final class AgentModel {
    var messages: [ChatMessage] = []
    var input = ""
    var isStreaming = false
    var error: String?
    var pendingApproval: ApprovalRequest?
    var conversations: [Conversation] = []
    /// Base64 JPEG staged in the composer to send with the next message.
    var pendingImage: String?
    /// Per-conversation overrides (empty = use the global agent settings).
    var instructions = ""
    var modelOverride = ""

    /// Live progress for a long-running task (drives the in-app strip + Live
    /// Activity). `taskActive` is true while a multi-step task is under way.
    var taskActive = false
    var taskTitle = ""
    var taskDetail = ""
    var taskSteps = 0
    var taskStartedAt: Date?

    private let client = AgentClient()
    let store = AgentConfigStore()
    private let convStore = ConversationStore()
    private var currentID = UUID()
    private var streamTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    var isConfigured: Bool { store.isConfigured }

    init() {
        conversations = convStore.load()
        if let latest = conversations.first {
            currentID = latest.id
            messages = latest.messages
            instructions = latest.instructions ?? ""
            modelOverride = latest.model ?? ""
        }
    }

    // MARK: - History

    func newChat() {
        persist()
        stop()
        currentID = UUID()
        messages = []
        instructions = ""
        modelOverride = ""
    }

    func select(_ conversation: Conversation) {
        persist()
        stop()
        currentID = conversation.id
        messages = conversation.messages
        instructions = conversation.instructions ?? ""
        modelOverride = conversation.model ?? ""
    }

    func rename(_ conversation: Conversation, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[idx].title = trimmed
        convStore.save(conversations)
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        convStore.save(conversations)
        if conversation.id == currentID {
            currentID = UUID()
            messages = []
        }
    }

    /// Snapshot the live messages into the current conversation and save.
    private func persist() {
        let real = messages.filter { $0.role == .user || $0.role == .assistant }
        guard !real.isEmpty else { return }
        let title = real.first { $0.role == .user }?.content.prefix(50).trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = Conversation(
            id: currentID,
            title: (title?.isEmpty == false ? title! : "New Chat"),
            messages: messages,
            updatedAt: Date(),
            instructions: instructions.isEmpty ? nil : instructions,
            model: modelOverride.isEmpty ? nil : modelOverride
        )
        conversations.removeAll { $0.id == currentID }
        conversations.insert(conversation, at: 0)
        conversations.sort { $0.updatedAt > $1.updatedAt }
        convStore.save(conversations)
    }

    func send(app: AppModel) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImage != nil, !isStreaming else { return }
        guard store.isConfigured else { error = "Set up a model in the Agent settings first."; return }
        input = ""
        messages.append(ChatMessage(role: .user, content: text, imageBase64: pendingImage))
        pendingImage = nil
        persist()
        generate(app: app)
    }

    private func generate(app: AppModel) {
        guard store.isConfigured else { return }
        isStreaming = true
        var config = store.config
        if !modelOverride.isEmpty { config.model = modelOverride }
        streamTask = Task {
            await runAgent(app: app, config: config)
            isStreaming = false
            persist()
        }
    }

    /// Re-run the last user turn (used for "Regenerate" and retry-on-error).
    func regenerate(app: AppModel) {
        guard !isStreaming else { return }
        while let last = messages.last, last.role != .user { messages.removeLast() }
        guard messages.last?.role == .user else { return }
        generate(app: app)
    }

    /// Edit a previous user message and re-run from there.
    func editAndResend(_ message: ChatMessage, text: String, app: AppModel) {
        guard !isStreaming, let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.removeSubrange(idx...)
        messages.append(ChatMessage(role: .user, content: trimmed))
        persist()
        generate(app: app)
    }

    func stop() {
        streamTask?.cancel()
        resolveApproval(false)
        isStreaming = false
    }

    func resolveApproval(_ approved: Bool) {
        pendingApproval = nil
        approvalContinuation?.resume(returning: approved)
        approvalContinuation = nil
    }

    // MARK: - Unified streaming agent loop (streams content + tools every turn)

    private func runAgent(app: AppModel, config: AgentConfig) async {
        defer { endLiveTask() }
        var wire = await buildWire(app: app, mode: config.mode)
        let tools = config.allowActions ? AgentTools.schemas : nil
        var toolsRun = 0
        do {
            for _ in 0..<24 {
                if Task.isCancelled { return }
                let assistant = ChatMessage(role: .assistant, content: "")
                messages.append(assistant)
                var rawContent = "", rawReasoning = ""
                var turn: AgentClient.TurnResult?

                for try await event in client.streamTurn(
                    config: config, apiKey: store.apiKey, messages: wire, tools: tools
                ) {
                    switch event {
                    case .content(let c): rawContent += c; applyStreamed(assistant.id, rawContent, rawReasoning)
                    case .reasoning(let r): rawReasoning += r; applyStreamed(assistant.id, rawContent, rawReasoning)
                    case .completed(let result): turn = result
                    }
                }
                if Task.isCancelled { return }
                guard let turn else { messages.removeAll { $0.id == assistant.id }; return }

                let (visible, embedded) = Self.splitReasoning(rawContent)
                let think = [rawReasoning, embedded ?? ""].filter { !$0.isEmpty }
                    .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if let idx = messages.firstIndex(where: { $0.id == assistant.id }) {
                    messages[idx].content = visible
                    messages[idx].reasoning = think.isEmpty ? nil : think
                }
                let emptyTurn = visible.isEmpty && think.isEmpty

                if turn.toolCalls.isEmpty {
                    if emptyTurn { messages.removeAll { $0.id == assistant.id } }
                    return
                }
                // Tool-using turn: drop an empty placeholder, run tools, then loop;
                // the next turn streams the final answer.
                if emptyTurn { messages.removeAll { $0.id == assistant.id } }

                let calls = turn.toolCalls.enumerated().map { i, stc in
                    (id: stc.id ?? "call_\(i)", name: stc.name, json: stc.argumentsJSON,
                     args: parseArgs(stc.argumentsJSON))
                }
                wire.append(assistantToolMessage(content: rawContent, calls: calls, mode: config.mode))
                for c in calls {
                    let action = humanAction(c.name, c.args)
                    if Self.longTools.contains(c.name) || toolsRun >= 2 {
                        startLiveTaskIfNeeded(detail: action)
                    }
                    if taskActive { updateLiveTask(detail: action, step: toolsRun) }
                    let call = AgentClient.ToolCall(id: c.id, name: c.name, arguments: c.args)
                    let output = await execute(call, app: app, config: config)
                    toolsRun += 1
                    if taskActive { updateLiveTask(detail: action, step: toolsRun) }
                    if let i = messages.lastIndex(where: { $0.role == .tool }) {
                        let argsText = c.args.isEmpty ? "" :
                            "\n\nArguments:\n" + c.args.map { "• \($0.key): \($0.value)" }.joined(separator: "\n")
                        messages[i].detail = "Result:\n\(output)\(argsText)"
                    }
                    wire.append(toolResult(call, output: output, mode: config.mode))
                }
            }
            messages.append(ChatMessage(
                role: .assistant,
                content: "I've reached the step limit for one turn (to avoid runaway loops). I've done the work so far above. Say **continue** and I'll pick up where I left off."))
        } catch {
            if let last = messages.last, last.role == .assistant, last.content.isEmpty {
                messages.removeLast()
            }
            handle(error, assistantID: nil)
        }
    }

    private func applyStreamed(_ id: UUID, _ rawContent: String, _ rawReasoning: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let (visible, embedded) = Self.splitReasoning(rawContent)
        messages[idx].content = visible
        let think = (rawReasoning + (embedded ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        messages[idx].reasoning = think.isEmpty ? nil : think
    }

    private func assistantToolMessage(
        content: String,
        calls: [(id: String, name: String, json: String, args: [String: Any])],
        mode: AgentMode
    ) -> [String: Any] {
        switch mode {
        case .openAICompatible:
            return ["role": "assistant", "content": content,
                    "tool_calls": calls.map {
                        ["id": $0.id, "type": "function",
                         "function": ["name": $0.name, "arguments": $0.json]]
                    }]
        case .ollama:
            return ["role": "assistant", "content": content,
                    "tool_calls": calls.map { ["function": ["name": $0.name, "arguments": $0.args]] }]
        }
    }

    private func parseArgs(_ json: String) -> [String: Any] {
        (json.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    }

    /// Split out `<think>…</think>` blocks (DeepSeek-R1 style) embedded in content.
    /// Returns the visible text and any reasoning found (works mid-stream).
    static func splitReasoning(_ raw: String) -> (visible: String, reasoning: String?) {
        guard let open = raw.range(of: "<think>") else { return (raw, nil) }
        let before = String(raw[..<open.lowerBound])
        if let close = raw.range(of: "</think>") {
            let reasoning = String(raw[open.upperBound..<close.lowerBound])
            let after = String(raw[close.upperBound...])
            return ((before + after).trimmingCharacters(in: .whitespacesAndNewlines), reasoning)
        }
        return (before.trimmingCharacters(in: .whitespacesAndNewlines), String(raw[open.upperBound...]))
    }

    private func toolResult(_ call: AgentClient.ToolCall, output: String, mode: AgentMode) -> [String: Any] {
        switch mode {
        case .openAICompatible:
            return ["role": "tool", "tool_call_id": call.id ?? call.name, "content": output]
        case .ollama:
            return ["role": "tool", "tool_name": call.name, "content": output]
        }
    }

    // MARK: - Tool execution

    private func execute(_ call: AgentClient.ToolCall, app: AppModel, config: AgentConfig) async -> String {
        guard let profile = app.profiles.selectedProfile,
              let conn = app.profiles.connection(for: profile) else {
            return "No server is selected."
        }
        let args = call.arguments
        do {
            switch call.name {

            // MARK: reads
            case "list_guests":
                let guests = try await app.api.clusterResources(conn)
                    .filter { ($0.type == .qemu || $0.type == .lxc) && !$0.isTemplate }
                note("Listed \(guests.count) guests")
                return guests.map {
                    "\($0.vmid.map(String.init) ?? "?") \($0.displayName) [\($0.type.rawValue)] \($0.status?.isUp == true ? "running" : "stopped")"
                }.joined(separator: "\n")

            case "list_nodes":
                let nodes = try await app.api.clusterResources(conn).filter { $0.type == .node }
                note("Listed \(nodes.count) nodes")
                return nodes.map { "\($0.displayName): \($0.status?.isUp == true ? "online" : "offline")" }
                    .joined(separator: "\n")

            case "node_status":
                let node = try await resolveNode(args, conn: conn, app: app)
                let s = try await app.api.nodeStatus(conn, node: node)
                note("Checked node \(node)")
                return "Node \(node): CPU \(Int(s.cpuPercent ?? 0))%, memory \(Int((s.memoryFraction ?? 0) * 100))%, uptime \(s.uptime ?? 0)s."

            case "guest_status":
                guard let vmid = intArg(args["vmid"]), let g = try await guest(for: vmid, conn: conn, app: app),
                      let node = g.node, let kind = g.type.guestKind else { return "Guest not found." }
                let s = try await app.api.guestStatus(conn, node: node, kind: kind, vmid: vmid)
                note("Checked \(g.displayName)")
                return "\(g.displayName): \(s.status.rawValue), CPU \(Int((s.cpuPercent ?? 0)))%, mem \(Int((s.memoryFraction ?? 0) * 100))%."

            case "guest_config":
                guard let vmid = intArg(args["vmid"]), let g = try await guest(for: vmid, conn: conn, app: app),
                      let node = g.node, let kind = g.type.guestKind else { return "Guest not found." }
                let c = try await app.api.guestConfig(conn, node: node, kind: kind, vmid: vmid)
                note("Read config of \(g.displayName)")
                return c.values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")

            case "list_snapshots":
                guard let vmid = intArg(args["vmid"]), let g = try await guest(for: vmid, conn: conn, app: app),
                      let node = g.node, let kind = g.type.guestKind else { return "Guest not found." }
                let snaps = try await app.api.snapshots(conn, node: node, kind: kind, vmid: vmid)
                note("Listed snapshots of \(g.displayName)")
                return snaps.map { $0.name }.joined(separator: "\n")

            case "list_backups":
                let node = try await resolveNode(args, conn: conn, app: app)
                let storages = try await app.api.nodeStorages(conn, node: node, content: "backup").map(\.storage)
                var all: [String] = []
                for s in storages {
                    let b = (try? await app.api.backups(conn, node: node, storage: s)) ?? []
                    all += b.map { "\($0.filename) (\($0.vmid.map { "vmid \($0)" } ?? "?"))" }
                }
                note("Listed \(all.count) backups")
                return all.isEmpty ? "No backups." : all.joined(separator: "\n")

            case "list_storage":
                let node = try await resolveNode(args, conn: conn, app: app)
                let storages = try await app.api.nodeStorages(conn, node: node, content: nil)
                note("Listed storages on \(node)")
                return storages.map {
                    "\($0.storage) [\($0.content ?? "")] \($0.usedFraction.map { "\(Int($0 * 100))% used" } ?? "")"
                }.joined(separator: "\n")

            case "list_disks":
                let node = try await resolveNode(args, conn: conn, app: app)
                let disks = try await app.api.physicalDisks(conn, node: node)
                note("Listed disks on \(node)")
                return disks.map {
                    "\($0.devpath) \($0.model ?? "") \($0.health ?? "?")\($0.wearout.map { " wear \(100 - $0)%" } ?? "")"
                }.joined(separator: "\n")

            case "list_services":
                let node = try await resolveNode(args, conn: conn, app: app)
                let services = try await app.api.nodeServices(conn, node: node)
                note("Listed services on \(node)")
                return services.map { "\($0.name): \($0.isRunning ? "running" : "stopped")" }.joined(separator: "\n")

            case "list_tasks":
                let node = try await resolveNode(args, conn: conn, app: app)
                let tasks = try await app.api.tasks(conn, node: node, limit: 20, vmid: nil)
                note("Listed recent tasks on \(node)")
                return tasks.map { "\($0.type) \($0.workerID ?? ""), \($0.displayStatus)" }.joined(separator: "\n")

            case "list_updates":
                let node = try await resolveNode(args, conn: conn, app: app)
                let updates = try await app.api.aptUpdates(conn, node: node)
                note("\(updates.count) updates on \(node)")
                return updates.isEmpty ? "Up to date." : "\(updates.count) updates: " + updates.prefix(30).map(\.package).joined(separator: ", ")

            case "list_firewall_rules":
                let basePath = try await firewallBasePath(args, conn: conn, app: app)
                let rules = try await app.api.firewallRules(conn, basePath: basePath)
                note("Listed firewall rules (\(args["scope"] as? String ?? "?"))")
                return rules.isEmpty ? "No rules." : rules.map {
                    "[\($0.isEnabled ? "on" : "off")] \($0.type ?? "") \($0.action ?? "") \($0.proto ?? "") \($0.dport ?? "")"
                }.joined(separator: "\n")

            // MARK: writes
            case "guest_power":
                guard let vmid = intArg(args["vmid"]),
                      let action = (args["action"] as? String).flatMap(PowerAction.init(rawValue:)),
                      let g = try await guest(for: vmid, conn: conn, app: app),
                      let node = g.node, let kind = g.type.guestKind else { return "Missing/invalid arguments." }
                guard await approve("\(action.label) \(g.displayName)?", "\(action.label) \(g.type.guestKind?.label ?? "guest") \(vmid)?") else { return "Denied." }
                _ = try await app.api.power(conn, node: node, kind: kind, vmid: vmid, action: action)
                note("\(action.label) \(g.displayName)")
                return "Issued \(action.rawValue) for \(vmid)."

            case "create_snapshot":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app) else { return "Guest not found." }
                let name = (args["name"] as? String) ?? "snap"
                guard await approve("Snapshot \(g.displayName)?", "Create snapshot “\(name)” of \(vmid)?") else { return "Denied." }
                _ = try await app.api.createSnapshot(conn, node: node, kind: kind, vmid: vmid, name: name, description: nil, includeRAM: false)
                note("Snapshot \(name) of \(g.displayName)"); return "Created snapshot \(name)."

            case "delete_snapshot":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app), let name = args["name"] as? String else { return "Need vmid and name." }
                guard await approve("Delete snapshot?", "Delete snapshot “\(name)” of \(vmid)?") else { return "Denied." }
                _ = try await app.api.deleteSnapshot(conn, node: node, kind: kind, vmid: vmid, name: name)
                note("Deleted snapshot \(name) of \(g.displayName)"); return "Deleted snapshot \(name)."

            case "rollback_snapshot":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app), let name = args["name"] as? String else { return "Need vmid and name." }
                guard await approve("Roll back \(g.displayName)?", "Roll \(vmid) back to “\(name)”? Current state is lost.") else { return "Denied." }
                _ = try await app.api.rollbackSnapshot(conn, node: node, kind: kind, vmid: vmid, name: name)
                note("Rolled \(g.displayName) back to \(name)"); return "Rolled back to \(name)."

            case "clone_guest":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app), let newid = intArg(args["newid"]) else { return "Need vmid and newid." }
                guard await approve("Clone \(g.displayName)?", "Clone \(vmid) to new VMID \(newid)?") else { return "Denied." }
                _ = try await app.api.cloneGuest(conn, node: node, kind: kind, vmid: vmid, newID: newid, name: args["name"] as? String, full: (args["full"] as? Bool) ?? false, targetStorage: nil)
                note("Cloned \(g.displayName) → \(newid)"); return "Cloning \(vmid) → \(newid)."

            case "delete_guest":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app) else { return "Guest not found." }
                guard await approve("Delete \(g.displayName)?", "Permanently destroy \(vmid) and its disks?") else { return "Denied." }
                _ = try await app.api.deleteGuest(conn, node: node, kind: kind, vmid: vmid, purge: (args["purge"] as? Bool) ?? true)
                note("Deleted \(g.displayName)"); return "Destroying \(vmid)."

            case "migrate_guest":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app), let target = args["target"] as? String else { return "Need vmid and target." }
                guard await approve("Migrate \(g.displayName)?", "Migrate \(vmid) to \(target)?") else { return "Denied." }
                _ = try await app.api.migrateGuest(conn, node: node, kind: kind, vmid: vmid, target: target, online: (args["online"] as? Bool) ?? true)
                note("Migrating \(g.displayName) → \(target)"); return "Migrating \(vmid) → \(target)."

            case "set_guest_resources":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app) else { return "Guest not found." }
                var params: [String: String] = [:]
                if let c = intArg(args["cores"]) { params["cores"] = String(c) }
                if let m = intArg(args["memory"]) { params["memory"] = String(m) }
                guard !params.isEmpty else { return "Nothing to change." }
                guard await approve("Update \(g.displayName)?", "Set \(params.map { "\($0)=\($1)" }.joined(separator: ", ")) on \(vmid)?") else { return "Denied." }
                try await app.api.updateGuestConfig(conn, node: node, kind: kind, vmid: vmid, parameters: params)
                note("Updated resources of \(g.displayName)"); return "Updated \(vmid)."

            case "resize_disk":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app), let disk = args["disk"] as? String, let gb = intArg(args["gb"]) else { return "Need vmid, disk, gb." }
                guard await approve("Resize disk on \(g.displayName)?", "Grow \(disk) on \(vmid) by \(gb) GB?") else { return "Denied." }
                _ = try await app.api.resizeDisk(conn, node: node, kind: kind, vmid: vmid, disk: disk, size: "+\(gb)G")
                note("Grew \(disk) on \(g.displayName) by \(gb)GB"); return "Resized \(disk)."

            case "set_guest_tags":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app), let tags = args["tags"] as? String else { return "Need vmid and tags." }
                let normalized = tags.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }).joined(separator: ";")
                guard await approve("Set tags on \(g.displayName)?", "Set tags to “\(normalized)” on \(vmid)?") else { return "Denied." }
                try await app.api.updateGuestConfig(conn, node: node, kind: kind, vmid: vmid, parameters: ["tags": normalized])
                note("Set tags on \(g.displayName)"); return "Updated tags."

            case "set_guest_notes":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app), let notes = args["notes"] as? String else { return "Need vmid and notes." }
                guard await approve("Set notes on \(g.displayName)?", "Replace the notes of \(vmid)?") else { return "Denied." }
                try await app.api.updateGuestConfig(conn, node: node, kind: kind, vmid: vmid, parameters: ["description": notes])
                note("Set notes on \(g.displayName)"); return "Updated notes."

            case "create_backup":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app) else { return "Guest not found." }
                _ = kind
                var storage = (args["storage"] as? String) ?? ""
                if storage.isEmpty {
                    storage = try await app.api.nodeStorages(conn, node: node, content: "backup").first?.storage ?? ""
                }
                guard !storage.isEmpty else { return "No backup storage available." }
                guard await approve("Back up \(g.displayName)?", "Back up \(vmid) to \(storage)?") else { return "Denied." }
                _ = try await app.api.createBackup(conn, node: node, vmid: vmid, storage: storage, mode: (args["mode"] as? String) ?? "snapshot", compress: "zstd", removeOld: true)
                note("Backing up \(g.displayName)"); return "Backing up \(vmid) to \(storage)."

            case "node_power":
                let node = try await resolveNode(args, conn: conn, app: app)
                guard let command = args["command"] as? String else { return "Need command." }
                guard await approve("\(command.capitalized) \(node)?", "\(command.capitalized) node \(node)? This affects every guest.") else { return "Denied." }
                _ = try await app.api.nodeCommand(conn, node: node, command: command)
                note("\(command.capitalized) \(node)"); return "Issued \(command) for \(node)."

            case "wake_on_lan":
                let node = try await resolveNode(args, conn: conn, app: app)
                guard await approve("Wake \(node)?", "Send a Wake-on-LAN packet to \(node)?") else { return "Denied." }
                _ = try await app.api.wakeOnLAN(conn, node: node)
                note("Sent WoL to \(node)"); return "Sent WoL to \(node)."

            case "service_action":
                let node = try await resolveNode(args, conn: conn, app: app)
                guard let service = args["service"] as? String, let action = args["action"] as? String else { return "Need service and action." }
                guard await approve("\(action.capitalized) \(service)?", "\(action.capitalized) service \(service) on \(node)?") else { return "Denied." }
                _ = try await app.api.serviceAction(conn, node: node, service: service, action: action)
                note("\(action.capitalized) \(service) on \(node)"); return "Issued \(action) for \(service)."

            // MARK: more reads
            case "list_backup_jobs":
                let jobs = try await app.api.backupJobs(conn)
                note("Listed \(jobs.count) backup jobs")
                return jobs.isEmpty ? "No backup jobs." : jobs.map {
                    "\($0.id): \($0.schedule ?? "?") → \($0.storage ?? "?") [\($0.selection)] \($0.isEnabled ? "" : "(disabled)")"
                }.joined(separator: "\n")

            case "list_users":
                let users = try await app.api.users(conn)
                note("Listed \(users.count) users")
                return users.map { "\($0.userid) \($0.isEnabled ? "" : "(disabled)")" }.joined(separator: "\n")

            case "list_templates":
                let node = try await resolveNode(args, conn: conn, app: app)
                var out: [String] = []
                for s in try await app.api.nodeStorages(conn, node: node, content: nil).map(\.storage) {
                    let content = (try? await app.api.storageContent(conn, node: node, storage: s, content: nil)) ?? []
                    out += content.filter { $0.content == "vztmpl" || $0.content == "iso" }.map { "\($0.content ?? ""): \($0.volid)" }
                }
                note("Listed \(out.count) templates/ISOs")
                return out.isEmpty ? "None found." : out.joined(separator: "\n")

            case "list_replication":
                let jobs = try await app.api.replicationJobs(conn)
                note("Listed replication jobs")
                return jobs.isEmpty ? "No replication jobs." : jobs.map { "\($0.id) → \($0.target ?? "?") \($0.schedule ?? "")" }.joined(separator: "\n")

            case "list_sdn":
                let zones = try await app.api.sdnZones(conn)
                let vnets = try await app.api.sdnVNets(conn)
                note("Listed SDN")
                return "Zones: \(zones.map(\.zone).joined(separator: ", "))\nVNets: \(vnets.map(\.vnet).joined(separator: ", "))"

            case "list_network":
                let node = try await resolveNode(args, conn: conn, app: app)
                let ifaces = try await app.api.nodeNetwork(conn, node: node)
                note("Listed interfaces on \(node)")
                return ifaces.map { "\($0.iface) [\($0.type ?? "")] \($0.cidr ?? $0.address ?? "")" }.joined(separator: "\n")

            case "cluster_status":
                let status = try await app.api.clusterStatus(conn)
                let ha = (try? await app.api.haResources(conn)) ?? []
                note("Checked cluster status")
                let nodeLines = status.filter { $0.type == "node" }.map { "\($0.name): \($0.isOnline ? "online" : "offline")" }
                return (nodeLines + ["HA resources: \(ha.count)"]).joined(separator: "\n")

            case "next_vmid":
                let id = try await app.api.nextID(conn)
                note("Next free VMID: \(id)")
                return "\(id)"

            // MARK: more writes
            case "create_guest":
                let kind: GuestKind = (args["type"] as? String) == "qemu" ? .qemu : .lxc
                let node = try await resolveNode(args, conn: conn, app: app)
                let storage = args["storage"] as? String ?? ""
                guard !storage.isEmpty else { return "Need a storage." }
                let vmid: Int
                if let provided = intArg(args["vmid"]) { vmid = provided }
                else { vmid = try await app.api.nextID(conn) }
                let diskGB = intArg(args["disk_gb"]) ?? 8
                let bridge = args["bridge"] as? String ?? "vmbr0"
                var params: [String: String] = [
                    "vmid": String(vmid), "cores": String(intArg(args["cores"]) ?? 1),
                    "memory": String(intArg(args["memory"]) ?? 1024),
                    "start": (args["start"] as? Bool) == true ? "1" : "0",
                ]
                if kind == .lxc {
                    guard let template = args["template"] as? String, !template.isEmpty else {
                        return "Container needs a template volid; call list_templates first."
                    }
                    params["ostemplate"] = template
                    params["rootfs"] = "\(storage):\(diskGB)"
                    if let pw = args["password"] as? String { params["password"] = pw }
                    if let name = args["name"] as? String { params["hostname"] = name }
                    params["net0"] = "name=eth0,bridge=\(bridge),ip=dhcp"
                } else {
                    if let name = args["name"] as? String { params["name"] = name }
                    params["ostype"] = (args["ostype"] as? String) ?? "l26"
                    params["scsihw"] = "virtio-scsi-pci"
                    params["scsi0"] = "\(storage):\(diskGB)"
                    if let iso = args["iso"] as? String, !iso.isEmpty {
                        params["ide2"] = "\(iso),media=cdrom"; params["boot"] = "order=scsi0;ide2"
                    }
                    params["net0"] = "virtio,bridge=\(bridge)"
                }
                guard await approve("Create \(kind.label) \(vmid)?", "Create a new \(kind.label) (VMID \(vmid)) on \(node)?") else { return "Denied." }
                _ = try await app.api.createGuest(conn, node: node, kind: kind, parameters: params)
                note("Created \(kind.label) \(vmid)"); return "Creating \(kind.label) \(vmid)."

            case "restore_backup":
                guard let archive = args["archive"] as? String, let vmid = intArg(args["vmid"]) else { return "Need archive and vmid." }
                let node = try await resolveNode(args, conn: conn, app: app)
                let kind: GuestKind = archive.contains("lxc") ? .lxc : .qemu
                let force = (args["force"] as? Bool) ?? false
                guard await approve("Restore to \(vmid)?", "Restore \(archive) to VMID \(vmid)\(force ? ", overwriting any existing guest" : "")?") else { return "Denied." }
                _ = try await app.api.restoreBackup(conn, node: node, kind: kind, vmid: vmid, archive: archive, storage: nil, force: force)
                note("Restoring \(vmid)"); return "Restoring \(vmid) from backup."

            case "convert_to_template":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app) else { return "Guest not found." }
                guard await approve("Templatize \(g.displayName)?", "Convert \(vmid) into a template? Irreversible.") else { return "Denied." }
                _ = try await app.api.convertToTemplate(conn, node: node, kind: kind, vmid: vmid)
                note("Converted \(g.displayName) to template"); return "Converted \(vmid) to a template."

            case "set_cloud_init":
                guard let (g, node, kind, vmid) = try await locate(args, conn, app) else { return "Guest not found." }
                var params: [String: String] = [:]
                for key in ["ciuser", "cipassword", "sshkeys", "ipconfig0"] {
                    if let v = args[key] as? String, !v.isEmpty { params[key] = v }
                }
                guard !params.isEmpty else { return "Nothing to set." }
                guard await approve("Set cloud-init on \(g.displayName)?", "Update cloud-init (\(params.keys.sorted().joined(separator: ", "))) on \(vmid)?") else { return "Denied." }
                try await app.api.updateGuestConfig(conn, node: node, kind: kind, vmid: vmid, parameters: params)
                note("Set cloud-init on \(g.displayName)"); return "Updated cloud-init."

            case "create_firewall_rule":
                let basePath = try await firewallBasePath(args, conn: conn, app: app)
                var params: [String: String] = [
                    "type": (args["direction"] as? String) ?? "in",
                    "action": (args["action"] as? String) ?? "ACCEPT", "enable": "1",
                ]
                for key in ["proto", "dport", "source", "comment"] {
                    if let v = args[key] as? String, !v.isEmpty { params[key] = v }
                }
                guard await approve("Add firewall rule?", "Add \(params["type"]!) \(params["action"]!) rule (\(args["scope"] as? String ?? "?"))?") else { return "Denied." }
                try await app.api.createFirewallRule(conn, basePath: basePath, parameters: params)
                note("Added firewall rule"); return "Added rule."

            case "delete_firewall_rule":
                guard let pos = intArg(args["pos"]) else { return "Need pos." }
                let basePath = try await firewallBasePath(args, conn: conn, app: app)
                guard await approve("Delete firewall rule \(pos)?", "Delete rule #\(pos) (\(args["scope"] as? String ?? "?"))?") else { return "Denied." }
                try await app.api.deleteFirewallRule(conn, basePath: basePath, pos: pos)
                note("Deleted firewall rule \(pos)"); return "Deleted rule \(pos)."

            case "set_firewall_rule":
                guard let pos = intArg(args["pos"]), let enabled = args["enabled"] as? Bool else { return "Need pos and enabled." }
                let basePath = try await firewallBasePath(args, conn: conn, app: app)
                guard await approve("\(enabled ? "Enable" : "Disable") rule \(pos)?", "\(enabled ? "Enable" : "Disable") firewall rule #\(pos)?") else { return "Denied." }
                try await app.api.updateFirewallRule(conn, basePath: basePath, pos: pos, parameters: ["enable": enabled ? "1" : "0"])
                note("\(enabled ? "Enabled" : "Disabled") firewall rule \(pos)"); return "Updated rule \(pos)."

            case "create_backup_job":
                guard let storage = args["storage"] as? String, let schedule = args["schedule"] as? String else { return "Need storage and schedule." }
                var params: [String: String] = ["storage": storage, "schedule": schedule, "enabled": "1", "mode": (args["mode"] as? String) ?? "snapshot"]
                if (args["all"] as? Bool) == true { params["all"] = "1" }
                else if let vmid = args["vmid"] as? String { params["vmid"] = vmid }
                if let comment = args["comment"] as? String { params["comment"] = comment }
                guard await approve("Create backup job?", "Schedule backups (\(schedule)) to \(storage)?") else { return "Denied." }
                try await app.api.createBackupJob(conn, parameters: params)
                note("Created backup job"); return "Created backup job."

            case "delete_backup_job":
                guard let id = args["id"] as? String else { return "Need id." }
                guard await approve("Delete backup job?", "Delete backup job \(id)?") else { return "Denied." }
                try await app.api.deleteBackupJob(conn, id: id)
                note("Deleted backup job \(id)"); return "Deleted job \(id)."

            case "set_backup_job":
                guard let id = args["id"] as? String, let enabled = args["enabled"] as? Bool else { return "Need id and enabled." }
                guard await approve("\(enabled ? "Enable" : "Disable") backup job?", "\(enabled ? "Enable" : "Disable") job \(id)?") else { return "Denied." }
                try await app.api.updateBackupJob(conn, id: id, parameters: ["enabled": enabled ? "1" : "0"])
                note("Updated backup job \(id)"); return "Updated job \(id)."

            case "delete_volume":
                guard let storage = args["storage"] as? String, let volid = args["volid"] as? String else { return "Need storage and volid." }
                let node = try await resolveNode(args, conn: conn, app: app)
                guard await approve("Delete volume?", "Delete \(volid) from \(storage)? This cannot be undone.") else { return "Denied." }
                _ = try await app.api.deleteVolume(conn, node: node, storage: storage, volid: volid)
                note("Deleted \(volid)"); return "Deleted \(volid)."

            case "run_in_guest":
                guard let (g, _, kind, vmid) = try await locate(args, conn, app) else { return "Guest not found." }
                guard let command = (args["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !command.isEmpty else { return "Need a command." }
                guard let (cred, password) = sshCredentials(for: profile) else { return sshMissingMessage(profile) }
                guard g.status?.isUp == true else { return "\(g.displayName) is not running; start it first." }
                if !config.autoApproveShell {
                    guard await approve("Run in \(g.displayName)?", "Run inside \(vmid) as root:\n\n\(command)") else { return "Denied." }
                }
                let timeoutSecs = min(max(intArg(args["timeout_seconds"]) ?? 120, 5), 900)
                // pct exec for containers; qm guest exec (needs the guest agent) for VMs.
                let bounded = Self.boundedShell(command, timeoutSecs: timeoutSecs)
                let hostCommand = kind == .lxc
                    ? "pct exec \(vmid) -- bash -lc \(Self.shellQuote(bounded))"
                    : "qm guest exec \(vmid) -- bash -lc \(Self.shellQuote(bounded))"
                note("Ran in \(g.displayName): \(command.prefix(70))")
                return await runRemoteShell(cred: cred, password: password, remoteCommand: hostCommand,
                                            displayCommand: command, timeoutSecs: timeoutSecs)

            case "run_on_node":
                guard let command = (args["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !command.isEmpty else { return "Need a command." }
                guard let (cred, password) = sshCredentials(for: profile) else { return sshMissingMessage(profile) }
                let node = try await resolveNode(args, conn: conn, app: app)
                if !config.autoApproveShell {
                    guard await approve("Run on node \(node)?", "Run on the Proxmox host as root:\n\n\(command)") else { return "Denied." }
                }
                let timeoutSecs = min(max(intArg(args["timeout_seconds"]) ?? 120, 5), 900)
                // Runs directly on the node host (no pct/qm wrapper), used for node
                // maintenance like apt updates.
                let bounded = Self.boundedShell(command, timeoutSecs: timeoutSecs)
                note("Ran on \(node): \(command.prefix(70))")
                return await runRemoteShell(cred: cred, password: password,
                                            remoteCommand: "bash -lc \(Self.shellQuote(bounded))",
                                            displayCommand: command, timeoutSecs: timeoutSecs)

            case "web_search":
                guard let query = args["query"] as? String, !query.isEmpty else {
                    return "Provide a non-empty search query."
                }
                let maxResults = intArg(args["max_results"]) ?? 5
                let search = WebSearch(
                    provider: config.searchProvider,
                    searxngURL: config.searxngURL,
                    apiKey: store.searchAPIKey
                )
                let output = try await search.run(query: query, maxResults: maxResults)
                note("Searched the web: \(query)")
                return output

            default:
                return "Unknown tool \(call.name)."
            }
        } catch {
            return "Tool error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// Find a guest and unpack node/kind/vmid in one go.
    private func locate(
        _ args: [String: Any], _ conn: ServerConnection, _ app: AppModel
    ) async throws -> (ClusterResource, String, GuestKind, Int)? {
        guard let vmid = intArg(args["vmid"]), let g = try await guest(for: vmid, conn: conn, app: app),
              let node = g.node, let kind = g.type.guestKind else { return nil }
        return (g, node, kind, vmid)
    }

    private func resolveNode(_ args: [String: Any], conn: ServerConnection, app: AppModel) async throws -> String {
        if let n = args["node"] as? String, !n.isEmpty { return n }
        guard let n = try await app.api.clusterResources(conn).first(where: { $0.type == .node })?.node else {
            throw AgentClient.AgentError.badURL
        }
        return n
    }

    private func firewallBasePath(_ args: [String: Any], conn: ServerConnection, app: AppModel) async throws -> String {
        switch args["scope"] as? String {
        case "guest":
            guard let (_, node, kind, vmid) = try await locate(args, conn, app) else { return "cluster/firewall" }
            return "nodes/\(node)/\(kind.pathSegment)/\(vmid)/firewall"
        case "node":
            return "nodes/\(try await resolveNode(args, conn: conn, app: app))/firewall"
        default:
            return "cluster/firewall"
        }
    }

    private func approve(_ title: String, _ detail: String) async -> Bool {
        await requestApproval(title: title, detail: detail)
    }

    private func guest(for vmid: Int, conn: ServerConnection, app: AppModel) async throws -> ClusterResource? {
        try await app.api.clusterResources(conn).first { $0.vmid == vmid && ($0.type == .qemu || $0.type == .lxc) }
    }

    /// Wrap a string in single quotes for safe use as one shell argument,
    /// escaping any embedded single quotes (`'` → `'\''`).
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// SSH host/user + Keychain password for a server, or nil if not configured.
    private func sshCredentials(for profile: ServerProfile) -> (SSHCredential, String)? {
        let store = SSHCredentialStore()
        guard let cred = store.credential(for: profile.id), let password = store.password(for: profile.id) else { return nil }
        return (cred, password)
    }

    private func sshMissingMessage(_ profile: ServerProfile) -> String {
        "No SSH credentials are configured for \(profile.name). Ask the user to add them on a node's Terminal screen, then retry."
    }

    /// Wrap a command so it's bounded by coreutils `timeout` (SIGTERM, then SIGKILL
    /// after 5s, to the process tree) and emits its exit status via an `__rc=`
    /// marker that survives the SSH layer's non-zero-exit handling.
    static func boundedShell(_ command: String, timeoutSecs: Int) -> String {
        "timeout -k 5 \(timeoutSecs) bash -lc \(shellQuote(command)); printf '\\n__rc=%d\\n' \"$?\""
    }

    /// Run a prepared remote command over SSH, parse the exit marker, record the
    /// tool-row detail, and return a model-facing result (with timeout/exit-status
    /// banners). Shared by `run_in_guest` and `run_on_node`.
    private func runRemoteShell(
        cred: SSHCredential, password: String, remoteCommand: String,
        displayCommand: String, timeoutSecs: Int
    ) async -> String {
        do {
            let output = try await runSSHCommand(
                host: cred.host, port: cred.port, username: cred.username,
                password: password, command: remoteCommand,
                timeoutSeconds: timeoutSecs + 30   // client-side net beyond the remote bound
            )
            let (body, exitCode) = Self.parseExitMarker(output)
            let clipped = body.count > 6000 ? "…(truncated)\n" + String(body.suffix(6000)) : body
            let status: String
            switch exitCode {
            case 0, nil: status = ""
            case 124, 137:
                status = "⏱️ TIMED OUT after \(timeoutSecs)s and was killed. If this was a long download/build, retry with a larger timeout_seconds. If it starts a foreground service, run it via systemd instead.\n\n"
            case let code?: status = "⚠️ Command exited with status \(code).\n\n"
            }
            if let i = messages.lastIndex(where: { $0.role == .tool }) {
                messages[i].detail = "$ \(displayCommand)\n\n\(status)\(clipped.isEmpty ? "(no output)" : clipped)"
            }
            return status + (clipped.isEmpty ? "(command finished, no output)" : clipped)
        } catch {
            if case SSHSessionError.timedOut = error {
                return "⏱️ No response after \(timeoutSecs)s. The command appears stuck (waiting for input, or the host is unreachable). Use non-interactive flags and don't run foreground processes."
            }
            return "SSH error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// Split the trailing `__rc=<n>` marker (appended by the bounded shell) off the
    /// command output, returning the cleaned body and the parsed exit code (nil if
    /// the marker is absent, e.g. a VM's guest-agent JSON wrapper).
    static func parseExitMarker(_ output: String) -> (body: String, exitCode: Int?) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = trimmed.range(of: "__rc=", options: .backwards) else { return (trimmed, nil) }
        let digits = trimmed[r.upperBound...].prefix { $0.isNumber }
        let body = String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (body, Int(digits))
    }

    private func intArg(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func note(_ text: String) { messages.append(ChatMessage(role: .tool, content: text)) }

    // MARK: - Long-running task progress (in-app strip + Live Activity + iOS 26 BG)

    /// Tools that mark genuinely long/multi-step work, seeing one starts the
    /// live progress task even on the first call.
    private static let longTools: Set<String> = [
        "run_in_guest", "run_on_node", "create_guest", "restore_backup", "clone_guest",
        "migrate_guest", "create_backup",
    ]

    /// A short, human label for what a tool call is doing (shown in the strip /
    /// Live Activity).
    private func humanAction(_ name: String, _ args: [String: Any]) -> String {
        switch name {
        case "run_in_guest", "run_on_node":
            let cmd = (args["command"] as? String) ?? ""
            return "Running: " + (cmd.count > 44 ? String(cmd.prefix(44)) + "…" : cmd)
        case "create_guest": return "Creating \(args["type"] as? String == "qemu" ? "VM" : "container")"
        case "guest_power": return "\((args["action"] as? String)?.capitalized ?? "Power") guest"
        case "create_backup", "restore_backup": return name == "create_backup" ? "Backing up" : "Restoring"
        case "create_firewall_rule": return "Opening firewall port"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func startLiveTaskIfNeeded(detail: String) {
        guard !taskActive else { return }
        taskActive = true
        taskSteps = 0
        taskStartedAt = Date()
        let lastUser = messages.last { $0.role == .user && !$0.content.isEmpty }?.content
        taskTitle = lastUser.map { String($0.prefix(48)) } ?? "Working on your homelab"
        taskDetail = detail
        #if os(iOS)
        AgentActivityController.start(title: taskTitle)
        if #available(iOS 26.0, *) {
            AgentBackgroundTask.shared.cancelHandler = { [weak self] in
                Task { @MainActor in self?.stop() }
            }
            AgentBackgroundTask.shared.begin(title: taskTitle)
        }
        #endif
    }

    private func updateLiveTask(detail: String, step: Int) {
        guard taskActive else { return }
        taskDetail = detail
        taskSteps = step
        #if os(iOS)
        AgentActivityController.update(detail: detail, step: step)
        if #available(iOS 26.0, *) { AgentBackgroundTask.shared.update(subtitle: detail, step: step) }
        #endif
    }

    private func endLiveTask() {
        guard taskActive else { return }
        let succeeded = error == nil && !Task.isCancelled
        let summary = Task.isCancelled ? "Stopped" : (succeeded ? "Done, \(taskSteps) steps" : "Failed")
        taskActive = false
        taskDetail = summary
        #if os(iOS)
        AgentActivityController.end(detail: summary, succeeded: succeeded)
        if #available(iOS 26.0, *) { AgentBackgroundTask.shared.end() }
        #endif
    }

    private func requestApproval(title: String, detail: String) async -> Bool {
        await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            pendingApproval = ApprovalRequest(title: title, detail: detail)
        }
    }

    private func handle(_ error: Error, assistantID: UUID?) {
        self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let assistantID, let idx = messages.firstIndex(where: { $0.id == assistantID }),
           messages[idx].content.isEmpty {
            messages.remove(at: idx)
        }
    }

    // MARK: - Wire building

    /// Keep the system prompt + the most recent turns so small local context
    /// windows don't overflow (older turns are dropped).
    private static let maxTurns = 16

    private func buildWire(app: AppModel, mode: AgentMode) async -> [[String: Any]] {
        var system = await Self.systemPrompt(app: app)
        if !instructions.isEmpty { system += "\n\nAdditional instructions:\n\(instructions)" }
        var wire: [[String: Any]] = [["role": "system", "content": system]]
        let turns = messages.filter {
            ($0.role == .user || $0.role == .assistant) && (!$0.content.isEmpty || $0.imageBase64 != nil)
        }
        for message in turns.suffix(Self.maxTurns) {
            if let image = message.imageBase64, message.role == .user {
                switch mode {
                case .openAICompatible:
                    wire.append(["role": "user", "content": [
                        ["type": "text", "text": message.content],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image)"]],
                    ]])
                case .ollama:
                    wire.append(["role": "user", "content": message.content, "images": [image]])
                }
            } else {
                wire.append(["role": message.role.rawValue, "content": message.content])
            }
        }
        return wire
    }

    private static func systemPrompt(app: AppModel) async -> String {
        var lines = [
            "You are an assistant embedded in Reeve, an app for managing Proxmox VE.",
            "Be concise and practical. Use the provided tools to read state or perform actions.",
            "State-changing actions require user approval, which the app handles.",
            "",
            "Be persistent and autonomous. When the user gives you a goal, especially "
                + "\"keep going until it works\" or \"continue until it's online\", keep working "
                + "through tool calls until the goal is actually achieved or you hit a genuine "
                + "blocker. Do NOT stop to ask permission to continue when you've already been "
                + "told to continue, and do NOT end your turn by listing what you *could* do "
                + "next, just do it. If you need information (logs, config, status, error "
                + "messages), get it yourself with tools, e.g. run_on_node `journalctl -xe`, "
                + "`pct start <id> --debug`, `lxc-start -n <id> -F -l DEBUG`, read the guest "
                + "config, rather than asking the user to paste it. Only stop early when you "
                + "truly need something only the user can give: a decision between real "
                + "alternatives, a secret/credential, or sign-off on a risky irreversible action. "
                + "When debugging, form a hypothesis, run a command to test it, read the result, "
                + "and iterate until you find and fix the root cause; then verify the fix. If you "
                + "run out of steps in a turn, the app lets the user resume by saying \"continue\".",
            "",
            "You can act like a hands-on home IT admin: to set up a service (e.g. AdGuard "
                + "Home, a Minecraft server, Pi-hole), plan the steps, then carry them out "
                + "end to end. A typical flow: pick a free VMID (next_vmid) and a template "
                + "(list_templates) + storage (list_storage); create the guest (create_guest); "
                + "start it; then use run_in_guest to install and configure software inside it. "
                + "run_in_guest executes a root shell command in the guest, install packages, "
                + "download and configure the app, write config files, enable a systemd service, "
                + "verify it's listening, running ONE command at a time and checking each result "
                + "(and its exit status) before the next; never assume a step succeeded. Finally "
                + "open any needed port with a firewall rule and tell the "
                + "user the address to reach the service. Use non-interactive flags so commands "
                + "don't hang. If run_in_guest reports missing SSH credentials, tell the user to "
                + "add them on a node's Terminal screen.",
            "",
            "You can also maintain the Proxmox host itself with run_on_node (a root shell on "
                + "the node, not inside a guest). Use it for things the API can't do, most "
                + "importantly installing node updates: `apt update && DEBIAN_FRONTEND="
                + "noninteractive apt full-upgrade -y`. Don't tell the user to open a terminal "
                + "and run it themselves, run it for them (it asks for approval), then check "
                + "whether a reboot is needed (`test -f /var/run/reboot-required`) and offer to "
                + "reboot with node_power.",
            "",
            "You can search the public web with web_search for anything beyond the homelab, "
                + "current events, software versions and release notes, documentation, error "
                + "messages, prices. Use it instead of guessing whenever a question depends on "
                + "up-to-date or external facts, and cite the sources (titles/links) you used.",
        ]
        if let profile = app.profiles.selectedProfile,
           let conn = app.profiles.connection(for: profile),
           let resources = try? await app.api.clusterResources(conn) {
            let nodes = resources.filter { $0.type == .node }
            let guests = resources.filter { ($0.type == .qemu || $0.type == .lxc) && !$0.isTemplate }
            let up = guests.filter { $0.status?.isUp == true }.count
            lines.append("\nCurrent server: \(profile.name). Nodes: \(nodes.map { $0.displayName }.joined(separator: ", ")). Guests: \(up)/\(guests.count) running.")
        }
        return lines.joined(separator: "\n")
    }
}
