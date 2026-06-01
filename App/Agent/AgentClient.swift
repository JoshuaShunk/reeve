import Foundation

/// Talks to either a local Ollama server (native `/api/chat`, NDJSON stream) or
/// an OpenAI-compatible endpoint (`/v1/chat/completions`, SSE stream). Streams
/// content + reasoning live while assembling any tool calls, so the tool loop
/// streams just like a plain chat.
struct AgentClient {
    enum AgentError: LocalizedError {
        case badURL, http(Int, String?)
        var errorDescription: String? {
            switch self {
            case .badURL: "Invalid server URL."
            case .http(let code, let body): "Server returned \(code).\(body.map { " \($0)" } ?? "")"
            }
        }
    }

    /// Parsed tool call (arguments decoded) used by the executor.
    struct ToolCall {
        let id: String?
        let name: String
        let arguments: [String: Any]
    }

    /// A tool call assembled from a stream (arguments kept as JSON for Sendability).
    struct StreamedToolCall: Sendable {
        let id: String?
        let name: String
        let argumentsJSON: String
    }

    /// The assembled outcome of one streamed turn.
    struct TurnResult: Sendable {
        let content: String
        let reasoning: String
        let toolCalls: [StreamedToolCall]
    }

    /// Events emitted while streaming a turn.
    enum StreamEvent: Sendable {
        case content(String)
        case reasoning(String)
        case completed(TurnResult)
    }

    /// Stream one turn: yields content/reasoning deltas, then a `.completed`
    /// event carrying the full text + any assembled tool calls.
    func streamTurn(
        config: AgentConfig, apiKey: String?,
        messages: [[String: Any]], tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = config.chatURL else { throw AgentError.badURL }
                    var body: [String: Any] = [
                        "model": config.model, "messages": messages, "stream": true, "temperature": 0.2,
                    ]
                    if let tools, !tools.isEmpty { body["tools"] = tools }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if config.mode == .openAICompatible, let apiKey, !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw AgentError.http(http.statusCode, nil)
                    }

                    var content = "", reasoning = ""
                    var openAITools: [Int: (id: String?, name: String, args: String)] = [:]
                    var ollamaTools: [StreamedToolCall] = []

                    func finish() {
                        let calls: [StreamedToolCall]
                        if config.mode == .openAICompatible {
                            calls = openAITools.sorted { $0.key < $1.key }.map {
                                StreamedToolCall(id: $0.value.id, name: $0.value.name,
                                                 argumentsJSON: $0.value.args.isEmpty ? "{}" : $0.value.args)
                            }
                        } else {
                            calls = ollamaTools
                        }
                        continuation.yield(.completed(
                            TurnResult(content: content, reasoning: reasoning, toolCalls: calls)))
                        continuation.finish()
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        switch config.mode {
                        case .openAICompatible:
                            guard line.hasPrefix("data:") else { continue }
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { finish(); return }
                            guard let data = payload.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  let delta = (json["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any]
                            else { continue }
                            if let r = (delta["reasoning_content"] ?? delta["reasoning"]) as? String, !r.isEmpty {
                                reasoning += r; continuation.yield(.reasoning(r))
                            }
                            if let c = delta["content"] as? String, !c.isEmpty {
                                content += c; continuation.yield(.content(c))
                            }
                            if let tcs = delta["tool_calls"] as? [[String: Any]] {
                                for tc in tcs {
                                    let idx = tc["index"] as? Int ?? 0
                                    var slot = openAITools[idx] ?? (id: nil, name: "", args: "")
                                    if let id = tc["id"] as? String { slot.id = id }
                                    if let fn = tc["function"] as? [String: Any] {
                                        if let n = fn["name"] as? String { slot.name = n }
                                        if let a = fn["arguments"] as? String { slot.args += a }
                                    }
                                    openAITools[idx] = slot
                                }
                            }
                        case .ollama:
                            guard let data = line.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }
                            if let message = json["message"] as? [String: Any] {
                                if let r = message["thinking"] as? String, !r.isEmpty {
                                    reasoning += r; continuation.yield(.reasoning(r))
                                }
                                if let c = message["content"] as? String, !c.isEmpty {
                                    content += c; continuation.yield(.content(c))
                                }
                                if let tcs = message["tool_calls"] as? [[String: Any]] {
                                    for tc in tcs {
                                        guard let fn = tc["function"] as? [String: Any],
                                              let name = fn["name"] as? String else { continue }
                                        let argsObj = fn["arguments"] ?? [String: Any]()
                                        let argsJSON = (try? JSONSerialization.data(withJSONObject: argsObj))
                                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                                        ollamaTools.append(StreamedToolCall(id: nil, name: name, argumentsJSON: argsJSON))
                                    }
                                }
                            }
                            if (json["done"] as? Bool) == true { finish(); return }
                        }
                    }
                    finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Fetch the list of available model names.
    func listModels(config: AgentConfig, apiKey: String?) async throws -> [String] {
        guard let url = config.modelsURL else { throw AgentError.badURL }
        var request = URLRequest(url: url)
        if config.mode == .openAICompatible, let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AgentError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch config.mode {
        case .ollama:
            let models = json?["models"] as? [[String: Any]] ?? []
            return models.compactMap { $0["name"] as? String }
        case .openAICompatible:
            let models = json?["data"] as? [[String: Any]] ?? []
            return models.compactMap { $0["id"] as? String }
        }
    }
}
