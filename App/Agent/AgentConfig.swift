import Foundation
import ReevePersistence

/// How the agent talks to its model backend.
enum AgentMode: String, Codable, CaseIterable, Identifiable {
    case ollama            // local, native /api/chat (streaming + tools)
    case openAICompatible  // OpenAI-style /v1/chat/completions (BYOK)
    var id: String { rawValue }
    var label: String { self == .ollama ? "Ollama (local)" : "OpenAI-compatible" }
}

/// Non-secret agent settings (the API key lives in the Keychain).
struct AgentConfig: Codable, Equatable {
    var mode: AgentMode = .ollama
    var baseURL: String = "http://10.0.0.1:11434"   // Ollama default port
    var model: String = ""
    /// Let the agent call tools to act on the homelab (writes need approval).
    var allowActions: Bool = true
    /// Run guest shell commands (`run_in_guest`) without confirming each one.
    /// Off by default, running a root shell in a guest is powerful, so the
    /// command is shown for approval unless the user opts into autonomy.
    var autoApproveShell: Bool = false
    /// Backend for the agent's `web_search` tool. The default needs no API key.
    var searchProvider: SearchProvider = .duckDuckGo
    /// Base URL of a self-hosted SearXNG instance (used when `searchProvider == .searxng`).
    var searxngURL: String = ""

    init() {}

    /// Decode tolerantly so configs written by older builds keep their settings
    /// when new fields are added (a missing key falls back to its default).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(AgentMode.self, forKey: .mode) ?? .ollama
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "http://10.0.0.1:11434"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        allowActions = try c.decodeIfPresent(Bool.self, forKey: .allowActions) ?? true
        autoApproveShell = try c.decodeIfPresent(Bool.self, forKey: .autoApproveShell) ?? false
        searchProvider = try c.decodeIfPresent(SearchProvider.self, forKey: .searchProvider) ?? .duckDuckGo
        searxngURL = try c.decodeIfPresent(String.self, forKey: .searxngURL) ?? ""
    }

    /// Endpoint for a chat completion, per dialect.
    var chatURL: URL? {
        switch mode {
        case .ollama: URL(string: trimmedBase + "/api/chat")
        case .openAICompatible: URL(string: trimmedBase + "/chat/completions")
        }
    }
    /// Endpoint that lists available models.
    var modelsURL: URL? {
        switch mode {
        case .ollama: URL(string: trimmedBase + "/api/tags")
        case .openAICompatible: URL(string: trimmedBase + "/models")
        }
    }
    private var trimmedBase: String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }
}

/// Persists the config (UserDefaults) and the API key (Keychain, best practice).
struct AgentConfigStore {
    private let defaults = UserDefaults.standard
    private let key = "agent.config"
    private let keychain = KeychainStore(service: "com.reeveapp.agent")
    private let keyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private let searchKeyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!

    var config: AgentConfig {
        get {
            guard let data = defaults.data(forKey: key),
                  let c = try? JSONDecoder().decode(AgentConfig.self, from: data) else { return AgentConfig() }
            return c
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: key) }
        }
    }

    var apiKey: String? { keychain.secret(for: keyID) }
    func setAPIKey(_ value: String) { try? keychain.setSecret(value, for: keyID) }

    var searchAPIKey: String? { keychain.secret(for: searchKeyID) }
    func setSearchAPIKey(_ value: String) { try? keychain.setSecret(value, for: searchKeyID) }

    var isConfigured: Bool {
        let c = config
        guard !c.model.isEmpty, c.chatURL != nil else { return false }
        return c.mode == .ollama || (apiKey?.isEmpty == false)
    }
}
