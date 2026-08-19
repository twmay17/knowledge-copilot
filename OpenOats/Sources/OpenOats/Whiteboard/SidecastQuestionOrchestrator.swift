import Foundation

/// `SidecastCorpusService` (WB-1) is a plain, non-actor class: `read`/`clear`
/// mutate its state, `retrieveEvidence` only reads it. The orchestrator below
/// only ever calls `retrieveEvidence`/`state` concurrently with itself, never
/// with a concurrent `read`/`clear` — mutation and the orchestrator's
/// concurrent read-only lookups don't overlap in the actor's own usage
/// pattern, so a retroactive `@unchecked Sendable` here is safe in practice
/// even though the compiler can't prove it. This keeps the corpus dependency
/// as the concrete WB-1 type (no protocol) — the orchestrator is the sole
/// consumer, and using the real class lets tests exercise a real corpus via
/// `read(folder:)` against a temp fixture, exactly like `SidecastCorpusServiceTests`,
/// rather than hand-rolling a fake that could drift from the real semantics.
extension SidecastCorpusService: @unchecked Sendable {}

/// Answers questions the listener spots, one async task per question, so
/// listening never blocks on answering — answers land whenever they finish.
///
/// Swift port of the bench's `QuestionOrchestrator` (`listener.ts`). The
/// control-flow shape differs from the single-threaded JS original in one
/// place: JS's `try/finally` always runs its cleanup, and that cleanup
/// itself checks `item.epoch === this.epoch` to decide whether to touch
/// shared state; here every exit path calls `finish(_:)`, which performs
/// that same epoch check. Because JS is single-threaded, its epoch can only
/// go stale *during* the awaited LLM call; because this is an actor, a
/// concurrent `clear()` could in principle also land before `answer(_:)`'s
/// first synchronous statement runs. `finish(_:)` no-ops correctly either
/// way, so the observable behavior — including epoch discard — matches.
actor SidecastQuestionOrchestrator {
    struct PendingItem: Sendable {
        let question: String
        let timestamp: Date
        let epoch: Int
        let retrievalHint: String?
    }

    private static let maxInFlight = 3
    private static let queueCap = 6
    private static let recentQuestionCap = 20
    private static let recentQuestionListCap = 8
    private static let recentAnswerCap = 12
    // Questions: semantic dedup happens in the listener (it sees the asked
    // list), so this Jaccard is only a near-verbatim backstop. Answers:
    // tighter, since the same fact rephrased is exactly the repeat the board
    // must not show.
    private static let questionDedupThreshold = 0.8
    private static let answerDedupThreshold = 0.5
    private static let minValue = 0.5

    private var inFlight = 0
    private var queue: [PendingItem] = []
    private var recentQuestions: [String] = []
    private var recentAnswers: [String] = []
    private var epoch = 0

    private let llm: any SidecastLLM
    private let corpusService: SidecastCorpusService
    private let now: @Sendable () -> Date
    private let onNote: @Sendable (SidecastAnsweredNote) -> Void
    private let onActivity: @Sendable (_ inFlight: Int, _ queued: Int) -> Void

    init(
        llm: any SidecastLLM,
        corpusService: SidecastCorpusService,
        now: @escaping @Sendable () -> Date = { Date() },
        onNote: @escaping @Sendable (SidecastAnsweredNote) -> Void,
        onActivity: @escaping @Sendable (_ inFlight: Int, _ queued: Int) -> Void
    ) {
        self.llm = llm
        self.corpusService = corpusService
        self.now = now
        self.onNote = onNote
        self.onActivity = onActivity
    }

    /// New source / seek / clear: outstanding work from the old world is
    /// discarded on completion (see `finish(_:)`).
    func clear() {
        epoch += 1
        queue = []
        inFlight = 0
        recentQuestions = []
        recentAnswers = []
        onActivity(0, 0)
    }

    /// Recent questions, newest last — fed back to the listener so it
    /// self-dedups semantically.
    func recentQuestionList() -> [String] {
        Array(recentQuestions.suffix(Self.recentQuestionListCap))
    }

    func enqueue(question: String, timestamp: Date, retrievalHint: String?) {
        if recentQuestions.contains(where: { SidecastQuestionSimilarity.jaccard($0, question) > Self.questionDedupThreshold }) {
            Log.sidecast.debug("[orchestrator] duplicate question dropped: \(question, privacy: .public)")
            return
        }
        recentQuestions.append(question)
        if recentQuestions.count > Self.recentQuestionCap {
            recentQuestions.removeFirst(recentQuestions.count - Self.recentQuestionCap)
        }
        if queue.count >= Self.queueCap {
            queue.removeFirst()
        }
        queue.append(PendingItem(question: question, timestamp: timestamp, epoch: epoch, retrievalHint: retrievalHint))
        pump()
    }

    private func pump() {
        while inFlight < Self.maxInFlight && !queue.isEmpty {
            let item = queue.removeFirst()
            inFlight += 1
            onActivity(inFlight, queue.count)
            Task { await self.answer(item) }
        }
    }

    private func answer(_ item: PendingItem) async {
        let hasCorpus = corpusService.state != nil
        // The raw speech rides along so ASR-garbled names ("DART" for Decart)
        // still land near the right corpus vocabulary.
        let query = item.retrievalHint.map { "\(item.question)\n\($0)" } ?? item.question
        let evidence = corpusService.retrieveEvidence(query: query)

        if hasCorpus && evidence == nil {
            Log.sidecast.debug("[orchestrator] no corpus match, dropped: \(item.question, privacy: .public)")
            finish(item)
            return
        }

        let evidenceText = evidence ?? SidecastPrompts.noCorpusFallback
        let userPrompt = "Question:\n\(item.question)\n\nEvidence:\n\(evidenceText)"
        let redactedPrompt = SensitiveDataGuard.redacted(userPrompt)

        do {
            let raw = try await llm.call(system: SidecastPrompts.answerSystem, user: redactedPrompt, schema: SidecastSchemas.answer)

            // World changed while we worked — old epoch's bookkeeping is
            // dead; `clear()` already reset it. Do not touch shared state.
            guard item.epoch == epoch else { return }

            let parsed = try SidecastJSON.decode(SidecastAnswerResponse.self, from: raw)
            let answer = (parsed.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let grounded = parsed.grounded == true
            let value = parsed.value ?? 0

            guard !answer.isEmpty else {
                finish(item)
                return
            }
            if hasCorpus && !grounded {
                Log.sidecast.debug("[orchestrator] ungrounded with corpus present, dropped: \(item.question, privacy: .public)")
                finish(item)
                return
            }
            if value < Self.minValue {
                Log.sidecast.debug("[orchestrator] below value threshold (\(value)), dropped: \(item.question, privacy: .public)")
                finish(item)
                return
            }
            if recentAnswers.contains(where: { SidecastQuestionSimilarity.jaccard($0, answer) > Self.answerDedupThreshold }) {
                Log.sidecast.debug("[orchestrator] duplicate answer dropped: \(item.question, privacy: .public)")
                finish(item)
                return
            }

            recentAnswers.append(answer)
            if recentAnswers.count > Self.recentAnswerCap {
                recentAnswers.removeFirst(recentAnswers.count - Self.recentAnswerCap)
            }

            onNote(SidecastAnsweredNote(question: item.question, answer: answer, timestamp: item.timestamp))
            finish(item)
        } catch {
            Log.sidecast.error("[orchestrator] answer failed for \"\(item.question, privacy: .public)\": \(String(describing: error), privacy: .public)")
            finish(item)
        }
    }

    /// Shared cleanup for every exit path except the stale-epoch return right
    /// after the LLM call: decrement in-flight, report activity, pump the
    /// queue. No-ops if the world moved on (`clear()` bumped the epoch) —
    /// mirrors JS's `finally { if (item.epoch === this.epoch) { ... } }`.
    private func finish(_ item: PendingItem) {
        guard item.epoch == epoch else { return }
        inFlight = max(0, inFlight - 1)
        onActivity(inFlight, queue.count)
        pump()
    }
}
