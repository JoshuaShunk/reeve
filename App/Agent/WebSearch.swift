import Foundation

/// Backend for the agent's `web_search` tool.
///
/// The default (`duckDuckGo`) needs no API key, so search works out of the box;
/// `searxng` points at the user's own instance (ideal for self-hosters); `tavily`
/// and `brave` are optional, higher-quality providers that take an API key.
enum SearchProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case duckDuckGo
    case searxng
    case tavily
    case brave

    var id: String { rawValue }

    var label: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo (no key)"
        case .searxng: "SearXNG (self-hosted)"
        case .tavily: "Tavily (API key)"
        case .brave: "Brave Search (API key)"
        }
    }

    var needsInstanceURL: Bool { self == .searxng }
    var needsAPIKey: Bool { self == .tavily || self == .brave }
}

/// One normalized search hit, provider-agnostic.
struct SearchResult: Sendable {
    let title: String
    let url: String
    let snippet: String
}

/// A normalized search response: an optional synthesized answer plus ranked hits.
struct SearchResponse: Sendable {
    var answer: String?
    var results: [SearchResult]
}

enum SearchError: LocalizedError {
    case notConfigured(String)
    case http(Int, String?)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured(let why): why
        case .http(let code, let body):
            "Search request failed (HTTP \(code))." + (body.map { " \($0)" } ?? "")
        case .badResponse: "The search service returned an unexpected response."
        }
    }
}

/// Performs a web search for the agent using the user's configured provider and
/// returns a compact, model-friendly text block.
struct WebSearch {
    let provider: SearchProvider
    let searxngURL: String
    let apiKey: String?

    private static let userAgent = "Reeve/1.0 (+https://github.com)"

    func run(query: String, maxResults: Int) async throws -> String {
        let limit = min(max(maxResults, 1), 10)
        let response: SearchResponse
        switch provider {
        case .duckDuckGo: response = try await duckDuckGo(query, limit: limit)
        case .searxng: response = try await searxng(query, limit: limit)
        case .tavily: response = try await tavily(query, limit: limit)
        case .brave: response = try await brave(query, limit: limit)
        }
        return format(response, query: query, limit: limit)
    }

    // MARK: Formatting

    private func format(_ response: SearchResponse, query: String, limit: Int) -> String {
        var lines: [String] = []
        if let answer = response.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !answer.isEmpty {
            lines.append("Answer: \(answer)")
            lines.append("")
        }
        let hits = response.results.prefix(limit)
        if hits.isEmpty {
            if lines.isEmpty { return "No results for “\(query)”." }
        } else {
            for (i, r) in hits.enumerated() {
                let snippet = r.snippet.isEmpty ? "" : "\n   \(r.snippet)"
                lines.append("\(i + 1). \(r.title)\n   \(r.url)\(snippet)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Networking

    private func get(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SearchError.http(http.statusCode, String(data: data, encoding: .utf8)?.prefix(200).description)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw SearchError.badResponse }
    }

    // MARK: DuckDuckGo (no key). Instant Answers, with a Wikipedia fallback

    private func duckDuckGo(_ query: String, limit: Int) async throws -> SearchResponse {
        var comp = URLComponents(string: "https://api.duckduckgo.com/")!
        comp.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "json"),
            .init(name: "no_html", value: "1"),
            .init(name: "skip_disambig", value: "1"),
        ]
        let data = try await get(comp.url!)
        let ddg = try decode(DDGResponse.self, from: data)

        var results: [SearchResult] = []
        func flatten(_ topics: [DDGTopic]?) {
            for t in topics ?? [] {
                if let text = t.Text, let url = t.FirstURL {
                    results.append(SearchResult(title: text, url: url, snippet: ""))
                }
                flatten(t.Topics)
            }
        }
        flatten(ddg.RelatedTopics)

        let answer = [ddg.Answer, ddg.AbstractText, ddg.Definition]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first
        let abstractURL = ddg.AbstractURL ?? ddg.DefinitionURL
        if let answer, let abstractURL, !abstractURL.isEmpty {
            results.insert(
                SearchResult(title: ddg.Heading ?? "Source", url: abstractURL, snippet: ""),
                at: 0
            )
        }

        // Instant Answers are often empty for general queries, fall back to
        // Wikipedia full-text search so the keyless default is still useful.
        if answer == nil, results.isEmpty {
            return try await wikipedia(query, limit: limit)
        }
        return SearchResponse(answer: answer, results: results)
    }

    private func wikipedia(_ query: String, limit: Int) async throws -> SearchResponse {
        var comp = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        comp.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "list", value: "search"),
            .init(name: "srsearch", value: query),
            .init(name: "srlimit", value: String(limit)),
            .init(name: "format", value: "json"),
        ]
        let data = try await get(comp.url!)
        let wiki = try decode(WikiResponse.self, from: data)
        let results = (wiki.query?.search ?? []).map { hit in
            SearchResult(
                title: hit.title,
                url: "https://en.wikipedia.org/wiki/" +
                    (hit.title.replacingOccurrences(of: " ", with: "_")
                        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? hit.title),
                snippet: hit.snippet.strippingHTML
            )
        }
        return SearchResponse(answer: nil, results: results)
    }

    // MARK: SearXNG (self-hosted, no key)

    private func searxng(_ query: String, limit: Int) async throws -> SearchResponse {
        let trimmed = searxngURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var comp = URLComponents(string: trimmed) else {
            throw SearchError.notConfigured(
                "Set your SearXNG instance URL in Agent settings to use SearXNG search."
            )
        }
        comp.path = (comp.path.hasSuffix("/") ? String(comp.path.dropLast()) : comp.path) + "/search"
        comp.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "json"),
        ]
        guard let url = comp.url else { throw SearchError.notConfigured("Invalid SearXNG URL.") }
        do {
            let data = try await get(url)
            let searx = try decode(SearxResponse.self, from: data)
            let results = (searx.results ?? []).prefix(limit).map {
                SearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.content ?? "")
            }
            return SearchResponse(answer: nil, results: Array(results))
        } catch SearchError.http(403, _) {
            throw SearchError.notConfigured(
                "SearXNG rejected the JSON request (403). Add `json` to `search.formats` in your instance's settings.yml."
            )
        }
    }

    // MARK: Tavily (API key). LLM-native results with a synthesized answer

    private func tavily(_ query: String, limit: Int) async throws -> SearchResponse {
        guard let key = apiKey, !key.isEmpty else {
            throw SearchError.notConfigured("Add a Tavily API key in Agent settings.")
        }
        var request = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "max_results": limit,
            "search_depth": "basic",
            "include_answer": true,
        ])
        let data = try await send(request)
        let tavily = try decode(TavilyResponse.self, from: data)
        let results = (tavily.results ?? []).map {
            SearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.content ?? "")
        }
        return SearchResponse(answer: tavily.answer, results: results)
    }

    // MARK: Brave Search (API key)

    private func brave(_ query: String, limit: Int) async throws -> SearchResponse {
        guard let key = apiKey, !key.isEmpty else {
            throw SearchError.notConfigured("Add a Brave Search API key in Agent settings.")
        }
        var comp = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        comp.queryItems = [
            .init(name: "q", value: query),
            .init(name: "count", value: String(limit)),
        ]
        let data = try await get(comp.url!, headers: ["X-Subscription-Token": key])
        let brave = try decode(BraveResponse.self, from: data)
        let results = (brave.web?.results ?? []).map {
            SearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: $0.description ?? "")
        }
        return SearchResponse(answer: nil, results: results)
    }
}

// MARK: - Decodable wire models

private struct DDGResponse: Decodable {
    let Heading: String?
    let AbstractText: String?
    let AbstractURL: String?
    let Answer: String?
    let Definition: String?
    let DefinitionURL: String?
    let RelatedTopics: [DDGTopic]?
}

private struct DDGTopic: Decodable {
    let Text: String?
    let FirstURL: String?
    let Topics: [DDGTopic]?
}

private struct WikiResponse: Decodable {
    struct Query: Decodable { let search: [Hit]? }
    struct Hit: Decodable { let title: String; let snippet: String }
    let query: Query?
}

private struct SearxResponse: Decodable {
    struct Result: Decodable { let title: String?; let url: String?; let content: String? }
    let results: [Result]?
}

private struct TavilyResponse: Decodable {
    struct Result: Decodable { let title: String?; let url: String?; let content: String? }
    let answer: String?
    let results: [Result]?
}

private struct BraveResponse: Decodable {
    struct Web: Decodable {
        struct Result: Decodable { let title: String?; let url: String?; let description: String? }
        let results: [Result]?
    }
    let web: Web?
}

private extension String {
    /// Strips HTML tags (Wikipedia/SearXNG snippets embed `<span>` highlights).
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
