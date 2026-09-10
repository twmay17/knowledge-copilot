import Foundation

/// Watches the live utterance stream for question-shaped moments and hands
/// them to a `SidecastQuestionOrchestrator` to answer from the corpus.
///
/// Swift port of the driving loop in the bench's `main.ts` (`runListener`/
/// `onTimeUpdate`, around `LISTEN_MIN_INTERVAL_MS`/`LISTEN_MIN_NEW_SEGMENTS`)
/// combined with `listener.ts`'s stateless `listenForQuestions`. In the
/// bench, the cadence gate and utterance bookkeeping live loosely in the
/// UI-driving loop; here they're folded into the actor itself, since that
/// loop has no equivalent on the native side (wiring a live utterance source
/// to this actor is WB-4).
///
/// v1 reduction: the bench's user prompt also carries a "Conversation
/// summary" block (`transcript.ts`'s `ensureSummary`/running summary). There
/// is no native summary service yet, so that block is omitted entirely
/// (not even a "(none yet)" placeholder) rather than ported.
actor SidecastQuestionListener {
    // ≥2 un-listened utterances AND ≥8s since the last pass STARTED AND no
    // pass in flight — matches the bench's `LISTEN_MIN_NEW_SEGMENTS` (2) and
    // `LISTEN_MIN_INTERVAL_MS` (8_000).
    private static let minUnlistened = 2
    private static let minIntervalSeconds: TimeInterval = 8
    // Window size for "Recent exchange" — the WB-2 brief specifies ~20
    // directly; this is NOT listener.ts's RECENT_CAP (that constant caps the
    // orchestrator's recentQuestions/recentAnswers dedup lists, unrelated to
    // the prompt window). The bench's actual prompt window was smaller — up
    // to 5 segments, computed in transcript.ts's buildContextWindow — which
    // doesn't translate here: it depends on a separately-computed
    // `widerContext`/running-summary this port has no equivalent source for.
    private static let recentCap = 20
    private static let maxItems = 4
    // Matches main.ts's `context.recentExchange.slice(-300)` retrieval hint
    // tail, approximated on Character boundaries rather than JS's exact
    // UTF-16 slice — immaterial here since the hint is a fuzzy-match aid,
    // not something any test pins byte-exact.
    private static let retrievalHintTailChars = 300

    private var recentTexts: [String] = []
    private var unlistenedCount = 0
    private var latestText = ""
    private var latestAt: Date = .distantPast
    private var lastPassStartedAt: Date = .distantPast
    private var passInFlight = false

    private let orchestrator: SidecastQuestionOrchestrator
    private let llm: any SidecastLLM
    private let now: @Sendable () -> Date
    // Post-review addition (additive, default nil — no other listener
    // behavior changes): fired once at the end of every completed pass,
    // with however many questions that pass turned up (0 on an empty
    // result or a caught error). WB-4's coordinator has no other way to
    // observe "a pass ran" — this is private actor state with no signal
    // out otherwise — and needed it to wire the listens/questions diag
    // counters it previously left at zero.
    private let onPassCompleted: (@Sendable (Int) -> Void)?

    init(
        orchestrator: SidecastQuestionOrchestrator,
        llm: any SidecastLLM,
        now: @escaping @Sendable () -> Date = { Date() },
        onPassCompleted: (@Sendable (Int) -> Void)? = nil
    ) {
        self.orchestrator = orchestrator
        self.llm = llm
        self.now = now
        self.onPassCompleted = onPassCompleted
    }

    /// Records one utterance's text and triggers a listen pass if the
    /// cadence gate allows it. Non-blocking: firing a pass only schedules
    /// the LLM round trip in the background, it never awaits it inline —
    /// callers can keep feeding utterances while a pass is in flight.
    func noteUtterance(text: String, at: Date) async {
        recentTexts.append(text)
        if recentTexts.count > Self.recentCap {
            recentTexts.removeFirst(recentTexts.count - Self.recentCap)
        }
        latestText = text
        latestAt = at
        unlistenedCount += 1
        startPassIfNeeded()
    }

    /// Synchronous by design: every check and the resulting state mutation
    /// (`passInFlight = true`, clock/counter reset, snapshotting the window)
    /// happen in one actor turn with no `await` in between, so two rapid
    /// `noteUtterance` calls can never both decide to fire.
    private func startPassIfNeeded() {
        guard !passInFlight else { return }
        guard unlistenedCount >= Self.minUnlistened else { return }
        guard now().timeIntervalSince(lastPassStartedAt) >= Self.minIntervalSeconds else { return }

        passInFlight = true
        lastPassStartedAt = now()
        unlistenedCount = 0

        let windowTexts = recentTexts
        let snapshotLatestText = latestText
        let snapshotLatestAt = latestAt

        Task { await self.runPass(windowTexts: windowTexts, latestText: snapshotLatestText, latestAt: snapshotLatestAt) }
    }

    private func runPass(windowTexts: [String], latestText: String, latestAt: Date) async {
        var questionCount = 0
        defer {
            passInFlight = false
            onPassCompleted?(questionCount)
        }
        do {
            let covered = await orchestrator.recentQuestionList()

            let recentExchangeText = windowTexts.joined(separator: "\n")
            var user = "Recent exchange:\n\(recentExchangeText)\n\nLatest line:\n\(latestText)"
            if !covered.isEmpty {
                let lines = covered.map { "- \($0)" }.joined(separator: "\n")
                user += "\n\n\(SidecastPrompts.alreadyCoveredHeader)\n\(lines)"
            }
            let redacted = SensitiveDataGuard.redacted(user)

            let raw = try await llm.call(system: SidecastPrompts.listenerSystem, user: redacted, schema: SidecastSchemas.listen)
            let response = try SidecastJSON.decode(SidecastListenResponse.self, from: raw)
            let items = (response.items ?? [])
                .map { ($0.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(Self.maxItems)
            questionCount = items.count

            guard !items.isEmpty else { return }

            // The raw recent speech rides along as a retrieval hint so
            // ASR-garbled names still land near the right corpus vocabulary
            // (see the orchestrator's `answer(_:)`).
            let hint = "\(latestText)\n\(recentExchangeText.suffix(Self.retrievalHintTailChars))"
            for question in items {
                await orchestrator.enqueue(question: question, timestamp: latestAt, retrievalHint: hint)
            }
        } catch {
            Log.sidecast.error("[listener] failed; response and transcript omitted")
        }
    }
}
