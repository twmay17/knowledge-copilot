import Foundation

/// One question the listener spotted and the orchestrator answered from the
/// corpus, ready to land on the whiteboard.
///
/// Swift port of the bench's `AnsweredNote` (`tools/sidecast-debug/src/listener.ts`).
/// `timestamp` is an absolute wall-clock `Date` (matching the live `Utterance`
/// seam — see `.superpowers/sdd/wb0-seam-report.md`), not the bench's
/// session-relative `number`.
struct SidecastAnsweredNote: Equatable, Sendable {
    let question: String
    let answer: String
    let timestamp: Date
}

// MARK: - Structured LLM call seam

/// The one structured-output call both the listener and the orchestrator
/// need: a static system prompt, a user prompt (already redacted by the
/// caller), and a JSON schema the response must conform to. Swift port of
/// the bench's `structuredCall` (`tools/sidecast-debug/src/sidecast.ts`).
///
/// Production conformance (`OpenRouterSidecastLLM` below) wraps
/// `OpenRouterClient.complete(...)`, which already owns the schema-rejection
/// fallback for this request shape — that logic is not reimplemented here.
/// WB-2 proves the adapter compiles and passes prompt/schema through
/// untouched; wiring a live, settings-backed instance into
/// `LiveSessionController` is WB-4.
protocol SidecastLLM: Sendable {
    func call(system: String, user: String, schema: OpenRouterClient.JSONSchemaSpec) async throws -> String
}

/// Wraps `OpenRouterClient.complete(...)` behind the `SidecastLLM` seam.
/// `OpenRouterClient` is itself an actor (hence `Sendable`), so this struct
/// is a plain value wrapper with no concurrency concerns of its own.
struct OpenRouterSidecastLLM: SidecastLLM {
    let client: OpenRouterClient
    let apiKey: String?
    let model: String
    let baseURL: URL?
    let transport: OpenRouterClient.CompletionTransport
    let maxTokens: Int
    let temperature: Double?
    let requestTimeout: TimeInterval

    init(
        client: OpenRouterClient,
        apiKey: String?,
        model: String,
        baseURL: URL? = nil,
        transport: OpenRouterClient.CompletionTransport = .chatCompletions,
        maxTokens: Int = 512,
        temperature: Double? = nil,
        requestTimeout: TimeInterval = 300
    ) {
        self.client = client
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.requestTimeout = requestTimeout
    }

    /// Pure — pulled out of `call(system:user:schema:)` so the pass-through
    /// shape (system/user become the two chat messages, verbatim) can be
    /// unit-tested at the mock level without a network round trip.
    static func buildMessages(system: String, user: String) -> [OpenRouterClient.Message] {
        [
            OpenRouterClient.Message(role: "system", content: system),
            OpenRouterClient.Message(role: "user", content: user),
        ]
    }

    func call(system: String, user: String, schema: OpenRouterClient.JSONSchemaSpec) async throws -> String {
        try await client.complete(
            apiKey: apiKey,
            model: model,
            messages: Self.buildMessages(system: system, user: user),
            maxTokens: maxTokens,
            temperature: temperature,
            baseURL: baseURL,
            transport: transport,
            requestTimeout: requestTimeout,
            jsonSchema: schema
        )
    }
}

// MARK: - Prompts (ported verbatim from listener.ts)

enum SidecastPrompts {
    /// Verbatim port of `LISTENER_SYSTEM` (`listener.ts`), including the
    /// "already covered" clause.
    static let listenerSystem = """
        You monitor a live conversation transcript for a quiet reference assistant backed by a document corpus.

        From the transcript window, extract the items worth looking up: direct questions someone asked aloud, or specific checkable claims (figures, named facts, dates). Rephrase each as ONE standalone question, resolving pronouns and vague references from the context. In dense stretches, extract EVERY distinct checkable claim — up to 4 — not just the most prominent one; two claims in the same sentence are two items.

        Only include items whose answer would plausibly live in a reference corpus. Skip chit-chat, opinions, rhetorical questions, and forecasts. If an "already covered" list is provided, do not re-ask those questions or paraphrases of them — but a genuinely different fact or aspect of the same topic is a new item, not a duplicate. An empty list is the common, correct output.
        """

    /// Verbatim port of `ANSWER_SYSTEM` (`listener.ts`), including the
    /// grounded/value contract.
    static let answerSystem = """
        You answer one question for a live meeting whiteboard.

        Use ONLY the provided evidence. If the evidence does not answer the question, set grounded=false and leave the answer empty. One or two sentences, readable aloud, numbers verbatim with units. No preamble, no hedging boilerplate. Set value to how useful this answer is to someone mid-call (0 to 1).
        """

    /// Verbatim port of the answer-prompt's no-corpus fallback text
    /// (`listener.ts`'s `evidence ?? "..."` default).
    static let noCorpusFallback =
        "None — no corpus is loaded. Answer only if this is settled factual ground you are confident about; otherwise grounded=false."

    /// Verbatim port of the covered-list header line (`listener.ts`'s
    /// `covered` template).
    static let alreadyCoveredHeader = "Already covered — do not re-ask these or paraphrases of them:"
}

// MARK: - JSON schemas (ported verbatim from listener.ts)

enum SidecastSchemas {
    /// Port of `LISTEN_SCHEMA`. `strict` isn't a field here — OpenRouterClient
    /// applies it itself (see `OpenRouterClient.responseFormat(for:url:)`).
    static let listen = OpenRouterClient.JSONSchemaSpec(
        name: "listen_items",
        schema: .object([
            "type": .string("object"),
            "properties": .object([
                "items": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "question": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("question")]),
                        "additionalProperties": .bool(false),
                    ]),
                ])
            ]),
            "required": .array([.string("items")]),
            "additionalProperties": .bool(false),
        ])
    )

    /// Port of `ANSWER_SCHEMA`.
    static let answer = OpenRouterClient.JSONSchemaSpec(
        name: "corpus_answer",
        schema: .object([
            "type": .string("object"),
            "properties": .object([
                "answer": .object(["type": .string("string")]),
                "grounded": .object(["type": .string("boolean")]),
                "value": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("answer"), .string("grounded"), .string("value")]),
            "additionalProperties": .bool(false),
        ])
    )
}

// MARK: - Shared parsing helpers

/// Response shape for `SidecastSchemas.listen`.
struct SidecastListenResponse: Decodable {
    struct Item: Decodable {
        let question: String?
    }
    let items: [Item]?
}

/// Response shape for `SidecastSchemas.answer`.
struct SidecastAnswerResponse: Decodable {
    let answer: String?
    let grounded: Bool?
    let value: Double?
}

enum SidecastJSON {
    /// Strips a leading/trailing ```json or ``` fence, if present. Structured
    /// output shouldn't need this, but the schema-rejection fallback path in
    /// `OpenRouterClient` degrades to prompt-only JSON, which can come back
    /// fenced — matches the bench's `extractJSON` (`sidecast.ts`).
    static func extract(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json") {
            text = String(text.dropFirst(7))
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst(3))
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let json = extract(raw)
        let data = Data(json.utf8)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Question/answer similarity (ported verbatim from listener.ts)

/// Near-verbatim dedup backstop, distinct from `SidecastCorpusService`'s
/// retrieval tokenizer (which lowercases to `[a-z0-9.$%]` and drops tokens of
/// length <= 2). This one is a direct port of listener.ts's `tokenSet`/
/// `jaccard`: lowercase, split on runs outside `[a-z0-9]`, keep every
/// non-empty piece (no length filter).
enum SidecastQuestionSimilarity {
    private static let tokenScalars: Set<Unicode.Scalar> = Set("abcdefghijklmnopqrstuvwxyz0123456789".unicodeScalars)

    static func tokenize(_ text: String) -> Set<String> {
        var tokens: Set<String> = []
        var current = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if tokenScalars.contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                tokens.insert(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty {
            tokens.insert(String(current))
        }
        return tokens
    }

    static func jaccard(_ a: String, _ b: String) -> Double {
        let setA = tokenize(a)
        let setB = tokenize(b)
        if setA.isEmpty && setB.isEmpty { return 1.0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }
}
