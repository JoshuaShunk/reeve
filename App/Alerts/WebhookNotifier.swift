import Foundation
import ReevePersistence

/// An outbound notification destination the user configures (so alerts reach them
/// even when the app isn't open).
struct NotificationChannel: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case discord, slack, telegram, webhook
        var id: String { rawValue }
        var label: String {
            switch self {
            case .discord: "Discord"
            case .slack: "Slack"
            case .telegram: "Telegram"
            case .webhook: "Webhook"
            }
        }
        var symbol: String {
            switch self {
            case .discord: "bubble.left.and.bubble.right"
            case .slack: "number.square"
            case .telegram: "paperplane"
            case .webhook: "link"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var url: String = ""        // Discord/Slack/generic webhook URL
    var botToken: String = ""   // Telegram
    var chatID: String = ""     // Telegram
    var enabled = true
}

/// Persists channels in the Keychain (webhook URLs and bot tokens are secrets).
struct ChannelStore {
    private let keychain = KeychainStore(service: "com.reeveapp.webhooks")
    private let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000FE")!

    func load() -> [NotificationChannel] {
        guard let json = keychain.secret(for: id), let data = json.data(using: .utf8),
              let channels = try? JSONDecoder().decode([NotificationChannel].self, from: data)
        else { return [] }
        return channels
    }

    func save(_ channels: [NotificationChannel]) {
        guard let data = try? JSONEncoder().encode(channels),
              let json = String(data: data, encoding: .utf8) else { return }
        try? keychain.setSecret(json, for: id)
    }
}

/// Fans an alert out to every enabled channel. Off the main actor; fire-and-forget.
final class WebhookNotifier: @unchecked Sendable {
    static let shared = WebhookNotifier()
    private let store = ChannelStore()

    func broadcast(title: String, body: String) {
        let channels = store.load().filter(\.enabled)
        guard !channels.isEmpty else { return }
        for channel in channels {
            Task.detached { try? await Self.send(channel, title: title, body: body) }
        }
    }

    /// Used by the "Send test" button; surfaces errors to the caller.
    static func test(_ channel: NotificationChannel) async throws {
        try await send(channel, title: "Reeve",
                       body: "Test notification, your \(channel.kind.label) channel works. ✅")
    }

    private static func send(_ channel: NotificationChannel, title: String, body: String) async throws {
        let (url, payload): (URL?, [String: Any])
        switch channel.kind {
        case .discord:
            url = URL(string: channel.url)
            payload = ["content": "**\(title)**\n\(body)"]
        case .slack:
            url = URL(string: channel.url)
            payload = ["text": "*\(title)*\n\(body)"]
        case .telegram:
            url = URL(string: "https://api.telegram.org/bot\(channel.botToken)/sendMessage")
            payload = ["chat_id": channel.chatID, "text": "\(title)\n\(body)"]
        case .webhook:
            url = URL(string: channel.url)
            payload = ["title": title, "body": body]
        }
        guard let url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.init(rawValue: http.statusCode))
        }
    }
}
