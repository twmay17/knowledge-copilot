import Foundation

/// Streaming OpenAI-compatible client for OpenRouter API (and Ollama via OpenAI-compatible endpoint).
actor OpenRouterClient {
    private static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let anthropicVersion = "2023-06-01"

    enum CompletionTransport: Equatable, Sendable {
        case chatCompletions
        case anthropicMessages
    }

    /// Builds a chat completions URL from a user-provided base URL, stripping
    /// any trailing `/v1` or `/v1/chat/completions` to avoid double-pathing.
    static func chatCompletionsURL(from rawBase: String) -> URL? {
        let trimmed = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }

        for suffix in ["/v1/chat/completions", "/v1"] {
            if path.hasSuffix(suffix) {
                path.removeLast(suffix.count)
                break
            }
        }

        if path.isEmpty {
            components.path = "/v1/chat/completions"
        } else {
            components.path = path + "/v1/chat/completions"
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Builds an Anthropic Messages URL from a user-provided base URL, stripping
    /// trailing `/v1` or `/v1/messages` before appending the canonical path.
    static func anthropicMessagesURL(from rawBase: String) -> URL? {
        let trimmed = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }

        for suffix in ["/v1/messages", "/v1"] {
            if path.hasSuffix(suffix) {
                path.removeLast(suffix.count)
                break
            }
        }

        components.path = path.isEmpty ? "/v1/messages" : path + "/v1/messages"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func isLocalHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "0.0.0.0"
    }

    struct Message: Codable, Sendable {
        let role: String
        let content: String
    }

    struct WebSearchPlugin: Codable, Sendable {
        let id: String
        let max_results: Int

        static let `default` = WebSearchPlugin(id: "web", max_results: 5)
    }

    struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let max_tokens: Int?
        let max_completion_tokens: Int?
        let temperature: Double?
        let plugins: [WebSearchPlugin]?
        let response_format: ResponseFormat?
    }

    // MARK: - Structured Output

    /// Minimal JSON tree for embedding a hand-written JSON Schema in a Codable
    /// request body. Encoded with `.sortedKeys` so the same schema always
    /// serializes to the same bytes.
    enum JSONValue: Encodable {
        case string(String)
        case bool(Bool)
        case array([JSONValue])
        case object([String: JSONValue])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }

        /// Nullable scalar. Expressed as `anyOf` rather than a `["number","null"]`
        /// type union because Anthropic's schema subset accepts `anyOf` but not
        /// type arrays; OpenAI-compatible providers accept both.
        static func nullable(_ type: String) -> JSONValue {
            .object(["anyOf": .array([
                .object(["type": .string(type)]),
                .object(["type": .string("null")]),
            ])])
        }
    }

    /// A schema the caller wants the model's response constrained to.
    /// `name` is required by the OpenAI-compatible shape and ignored by Anthropic.
    struct JSONSchemaSpec: Sendable {
        let name: String
        let schema: JSONValue

        init(name: String, schema: JSONValue) {
            self.name = name
            self.schema = schema
        }
    }

    /// OpenAI-compatible shape: `response_format.json_schema`.
    struct ResponseFormat: Encodable {
        let type: String
        let json_schema: Payload

        struct Payload: Encodable {
            let name: String
            let strict: Bool?
            let schema: JSONValue
        }
    }

    /// Anthropic Messages shape: `output_config.format`. Carries no `name` and no
    /// `strict` — that is the OpenAI spelling, and sending it here is rejected.
    /// (The older top-level `output_format` parameter is deprecated; this is the
    /// current one.)
    struct OutputConfig: Encodable {
        let format: Format

        struct Format: Encodable {
            let type: String
            let schema: JSONValue
        }
    }

    /// Ollama's OpenAI-compat layer accepts `json_schema` but rejects `strict`.
    private static func responseFormat(for spec: JSONSchemaSpec, url: URL) -> ResponseFormat {
        let acceptsStrict = !Self.isLocalHost(url)
        return ResponseFormat(
            type: "json_schema",
            json_schema: .init(
                name: spec.name,
                strict: acceptsStrict ? true : nil,
                schema: spec.schema
            )
        )
    }

    /// A 4xx naming the schema field means this model/provider can't constrain
    /// decoding — Anthropic supports it only on newer models, and not every
    /// OpenRouter model does either.
    static func isSchemaRejection(_ statusCode: Int, body: String) -> Bool {
        guard [400, 404, 422].contains(statusCode) else { return false }
        let markers = ["response_format", "json_schema", "output_config", "schema", "structured"]
        let lowered = body.lowercased()
        return markers.contains { lowered.contains($0) }
    }

    /// Delay before the single retry on a 429 from the structured-output path.
    static let rateLimitRetryDelay: TimeInterval = 2.5

    /// Retries once after `delay` when a schema-enforced request (`hasSchema`) comes
    /// back HTTP 429 — shared-quota models 429 transiently in live use, and a single
    /// quiet retry converts that into a normal success rather than a failed turn.
    /// Scoped to the structured-output path only: when `hasSchema` is false the first
    /// response is returned as-is, so plain callers (SuggestionEngine, NotesEngine,
    /// etc.) keep today's exact behavior — no retry.
    ///
    /// If the retry also comes back 429, that response is likewise returned as-is —
    /// no second retry, no infinite loop — and the caller's existing status-code guard
    /// surfaces the same `OpenRouterError.httpError` it always has.
    static func sendRetryingRateLimit(
        hasSchema: Bool,
        delay: TimeInterval,
        send: () async throws -> (Data, HTTPURLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        let response = try await send()
        guard hasSchema, response.1.statusCode == 429 else { return response }
        try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
        return try await send()
    }

    private static func schemaAwareEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Whether a URL points to a host that supports the `max_completion_tokens`
    /// parameter (OpenAI, OpenRouter). Other OpenAI-compatible providers such as
    /// Mistral and Ollama only accept `max_tokens`.
    private static func usesMaxCompletionTokens(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return host.contains("openrouter.ai") || host.contains("openai.com")
    }

    static func preflightError(for url: URL, apiKey: String?) -> OpenRouterError? {
        guard let host = url.host?.lowercased(), host.contains("openrouter.ai") else {
            return nil
        }

        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingAPIKey(host: host)
        }

        return nil
    }

    /// Streams the completion response, yielding text chunks.
    func streamCompletion(
        apiKey: String? = nil,
        model: String,
        messages: [Message],
        maxTokens: Int = 1024,
        baseURL: URL? = nil,
        transport: CompletionTransport = .chatCompletions
    ) -> AsyncThrowingStream<String, Error> {
        if transport == .anthropicMessages {
            return streamAnthropicCompletion(
                apiKey: apiKey,
                model: model,
                messages: messages,
                maxTokens: maxTokens,
                baseURL: baseURL
            )
        }

        return AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    let targetURL = baseURL ?? Self.defaultBaseURL
                    if let preflightError = Self.preflightError(for: targetURL, apiKey: apiKey) {
                        continuation.finish(throwing: preflightError)
                        return
                    }
                    let useNewParam = Self.usesMaxCompletionTokens(targetURL)
                    let request = ChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        max_tokens: useNewParam ? nil : maxTokens,
                        max_completion_tokens: useNewParam ? maxTokens : nil,
                        temperature: nil,
                        plugins: nil,
                        response_format: nil
                    )

                    var urlRequest = URLRequest(url: targetURL)
                    urlRequest.httpMethod = "POST"
                    // Idle timeout between streamed bytes. Must cover cold-start of local models
                    // (Ollama/MLX) and first-token latency of reasoning models, which routinely
                    // exceed URLRequest's 60s default.
                    urlRequest.timeoutInterval = 300
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let apiKey, !apiKey.isEmpty {
                        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    if targetURL.host?.contains("openrouter.ai") == true {
                        urlRequest.setValue("OpenOats/2.0", forHTTPHeaderField: "HTTP-Referer")
                    }
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: OpenRouterError.httpError(statusCode, host: targetURL.host))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(SSEChunk.self, from: data) {
                            if let content = chunk.choices.first?.delta.content {
                                continuation.yield(content)
                            } else if chunk.choices.first?.finish_reason == "length" {
                                continuation.yield("…")
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Non-streaming completion for structured JSON tasks (gate decisions, state updates).
    func complete(
        apiKey: String? = nil,
        model: String,
        messages: [Message],
        maxTokens: Int = 512,
        temperature: Double? = nil,
        baseURL: URL? = nil,
        webSearch: Bool = false,
        transport: CompletionTransport = .chatCompletions,
        requestTimeout: TimeInterval = 300,
        jsonSchema: JSONSchemaSpec? = nil
    ) async throws -> String {
        if transport == .anthropicMessages {
            return try await completeAnthropic(
                apiKey: apiKey,
                model: model,
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                baseURL: baseURL,
                requestTimeout: requestTimeout,
                jsonSchema: jsonSchema
            )
        }

        let targetURL = baseURL ?? Self.defaultBaseURL
        if let preflightError = Self.preflightError(for: targetURL, apiKey: apiKey) {
            throw preflightError
        }
        let useNewParam = Self.usesMaxCompletionTokens(targetURL)

        func makeRequest(withSchema: Bool) -> ChatRequest {
            ChatRequest(
                model: model,
                messages: messages,
                stream: false,
                max_tokens: useNewParam ? nil : maxTokens,
                max_completion_tokens: useNewParam ? maxTokens : nil,
                temperature: temperature,
                plugins: webSearch ? [.default] : nil,
                response_format: withSchema
                    ? jsonSchema.map { Self.responseFormat(for: $0, url: targetURL) }
                    : nil
            )
        }

        func send(_ request: ChatRequest) async throws -> (Data, HTTPURLResponse) {
            var urlRequest = URLRequest(url: targetURL)
            urlRequest.httpMethod = "POST"
            // Total request timeout — covers gate / judge / structured-JSON calls that may hit
            // slow local models or reasoning models. Default 60s is too aggressive in practice.
            urlRequest.timeoutInterval = requestTimeout
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey, !apiKey.isEmpty {
                urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            if targetURL.host?.contains("openrouter.ai") == true {
                urlRequest.setValue("OpenOats/2.0", forHTTPHeaderField: "HTTP-Referer")
            }
            urlRequest.httpBody = try Self.schemaAwareEncoder().encode(request)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let httpResponse = response as? HTTPURLResponse
                ?? HTTPURLResponse(url: targetURL, statusCode: -1, httpVersion: nil, headerFields: nil)!
            return (data, httpResponse)
        }

        var (data, httpResponse) = try await Self.sendRetryingRateLimit(
            hasSchema: jsonSchema != nil,
            delay: Self.rateLimitRetryDelay
        ) {
            try await send(makeRequest(withSchema: jsonSchema != nil))
        }

        // Not every model supports constrained decoding. Degrade to prompt-only
        // JSON rather than failing the whole generation.
        if jsonSchema != nil, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            if Self.isSchemaRejection(httpResponse.statusCode, body: body) {
                Log.sidecast.warning(
                    "\(model, privacy: .public) rejected response_format — retrying without schema enforcement"
                )
                (data, httpResponse) = try await send(makeRequest(withSchema: false))
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenRouterError.httpError(httpResponse.statusCode, host: targetURL.host)
        }

        let completionResponse = try JSONDecoder().decode(CompletionResponse.self, from: data)
        return completionResponse.choices.first?.message.content ?? ""
    }

    private func streamAnthropicCompletion(
        apiKey: String?,
        model: String,
        messages: [Message],
        maxTokens: Int,
        baseURL: URL?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    let targetURL = baseURL ?? Self.anthropicMessagesURL(from: "https://api.anthropic.com")!
                    guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continuation.finish(throwing: OpenRouterError.missingAPIKey(host: targetURL.host))
                        return
                    }

                    let request = AnthropicRequest(
                        model: model,
                        max_tokens: maxTokens,
                        messages: Self.anthropicMessages(from: messages),
                        stream: true,
                        temperature: nil,
                        system: Self.anthropicSystemPrompt(from: messages),
                        output_config: nil
                    )

                    var urlRequest = URLRequest(url: targetURL)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = 300
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: OpenRouterError.httpError(statusCode, host: targetURL.host))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data) else {
                            continue
                        }
                        if event.type == "message_stop" { break }
                        if event.type == "content_block_delta",
                           event.delta?.type == "text_delta",
                           let text = event.delta?.text {
                            continuation.yield(text)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func completeAnthropic(
        apiKey: String?,
        model: String,
        messages: [Message],
        maxTokens: Int,
        temperature: Double?,
        baseURL: URL?,
        requestTimeout: TimeInterval,
        jsonSchema: JSONSchemaSpec? = nil
    ) async throws -> String {
        let targetURL = baseURL ?? Self.anthropicMessagesURL(from: "https://api.anthropic.com")!
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.missingAPIKey(host: targetURL.host)
        }

        func makeRequest(withSchema: Bool) -> AnthropicRequest {
            AnthropicRequest(
                model: model,
                max_tokens: maxTokens,
                messages: Self.anthropicMessages(from: messages),
                stream: false,
                temperature: temperature,
                system: Self.anthropicSystemPrompt(from: messages),
                output_config: withSchema
                    ? jsonSchema.map { OutputConfig(format: .init(type: "json_schema", schema: $0.schema)) }
                    : nil
            )
        }

        func send(_ request: AnthropicRequest) async throws -> (Data, HTTPURLResponse) {
            var urlRequest = URLRequest(url: targetURL)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = requestTimeout
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
            urlRequest.httpBody = try Self.schemaAwareEncoder().encode(request)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let httpResponse = response as? HTTPURLResponse
                ?? HTTPURLResponse(url: targetURL, statusCode: -1, httpVersion: nil, headerFields: nil)!
            return (data, httpResponse)
        }

        var (data, httpResponse) = try await Self.sendRetryingRateLimit(
            hasSchema: jsonSchema != nil,
            delay: Self.rateLimitRetryDelay
        ) {
            try await send(makeRequest(withSchema: jsonSchema != nil))
        }

        // Structured outputs are only on newer Claude models — degrade rather than fail.
        if jsonSchema != nil, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            if Self.isSchemaRejection(httpResponse.statusCode, body: body) {
                Log.sidecast.warning(
                    "\(model, privacy: .public) rejected output_config — retrying without schema enforcement"
                )
                (data, httpResponse) = try await send(makeRequest(withSchema: false))
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenRouterError.httpError(httpResponse.statusCode, host: targetURL.host)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.compactMap(\.text).joined()
    }

    private static func anthropicSystemPrompt(from messages: [Message]) -> String? {
        let prompt = messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? nil : prompt
    }

    private static func anthropicMessages(from messages: [Message]) -> [AnthropicMessage] {
        messages.compactMap { message in
            guard message.role != "system" else { return nil }
            let role = message.role == "assistant" ? "assistant" : "user"
            return AnthropicMessage(role: role, content: message.content)
        }
    }

    enum OpenRouterError: Error, LocalizedError {
        case httpError(Int, host: String?)
        case missingAPIKey(host: String?)

        var errorDescription: String? {
            switch self {
            case .httpError(let code, let host):
                let provider = switch host {
                case let h? where h.contains("openrouter.ai"): "OpenRouter"
                case let h? where h.contains("localhost"), let h? where h.contains("127.0.0.1"): "Local LLM"
                case let h?: h
                case nil: "LLM"
                }
                return "\(provider) API error (HTTP \(code))"
            case .missingAPIKey(let host):
                let provider = switch host {
                case let h? where h.contains("openrouter.ai"): "OpenRouter"
                case let h?: h
                case nil: "LLM"
                }
                return "\(provider) API key required"
            }
        }
    }

    // MARK: - SSE Types

    private struct SSEChunk: Codable {
        let choices: [Choice]

        struct Choice: Codable {
            let delta: Delta
            let finish_reason: String?
        }

        struct Delta: Codable {
            let content: String?
        }
    }

    private struct CompletionResponse: Codable {
        let choices: [CompletionChoice]

        struct CompletionChoice: Codable {
            let message: CompletionMessage
        }

        struct CompletionMessage: Codable {
            let content: String
        }
    }

    private struct AnthropicRequest: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [AnthropicMessage]
        let stream: Bool
        let temperature: Double?
        let system: String?
        let output_config: OutputConfig?
    }

    private struct AnthropicMessage: Codable {
        let role: String
        let content: String
    }

    private struct AnthropicStreamEvent: Codable {
        let type: String
        let delta: Delta?

        struct Delta: Codable {
            let type: String
            let text: String?
        }
    }

    private struct AnthropicResponse: Codable {
        let content: [ContentBlock]

        struct ContentBlock: Codable {
            let type: String
            let text: String?
        }
    }
}
