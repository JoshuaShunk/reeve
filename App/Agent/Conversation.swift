import Foundation

/// A saved agent conversation.
struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date
    /// Optional per-conversation overrides.
    var instructions: String? = nil
    var model: String? = nil
}

/// Persists conversations as JSON in Application Support.
struct ConversationStore {
    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agent-conversations.json")
    }

    func load() -> [Conversation] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Conversation].self, from: data)
        else { return [] }
        return list.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ conversations: [Conversation]) {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
