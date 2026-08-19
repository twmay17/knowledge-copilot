import Foundation
import os

/// Wires the WB-1..3 whiteboard pipeline (corpus service, listener,
/// orchestrator, view-model) into the live session lifecycle. Owner of the
/// listener + orchestrator + corpus-refresh cadence + view-model updates;
/// `LiveSessionController` only ever calls the three methods below, at the
/// same three touchpoints it already has (session start/stop, the
/// utterance seam) — everything else (actor wiring, egress gating, corpus
/// refresh) is internal.
///
/// **Feature flag** (`AppSettings.sidecastWhiteboardEnabled`, default ON):
/// every entry point below no-ops entirely when it reads false — zero
/// listener/orchestrator activity, zero view-model mutation. This is the
/// prime-directive seam: with the flag OFF, this type does nothing
/// observable at all, and `LiveSessionController`'s legacy `SidecastEngine`
/// dispatch runs exactly as it did before WB-4.
///
/// **Egress gate**: the `llm` handed to `init` is never called directly —
/// it is wrapped once, here, in `GatedSidecastLLM`, so the listener and
/// orchestrator (both WB-2 actors, unmodified) only ever hold the gated
/// wrapper. The gate mirrors the same credential-presence check the legacy
/// realtime path already makes independently in both `SidecastEngine` and
/// `SuggestionEngine` (`onUtterance`'s per-provider "do we have a key"
/// switch) — narrowed to the one provider this pipeline's production `llm`
/// (WB-2's `OpenRouterSidecastLLM`) can ever actually reach: OpenRouter.
/// Requiring `llmProvider == .openRouter` too (not just a non-empty key)
/// keeps a user who has switched their active assistant provider elsewhere
/// (Ollama, Anthropic, ...) from getting a surprise cloud call out of a
/// leftover OpenRouter key — this pipeline opens no egress path the legacy
/// one wouldn't have taken with OpenRouter selected.
@MainActor
final class SidecastWhiteboardCoordinator {
    /// Thread-safe, `@unchecked Sendable` snapshot of the current egress
    /// gate state — refreshed on the MainActor (see `isEgressAllowed`)
    /// every time an utterance is received, then read synchronously from
    /// inside `GatedSidecastLLM.call`, which runs on the listener/
    /// orchestrator actors' own executors, not the MainActor. A plain
    /// `AppSettings` reference can't be read from there without crossing
    /// actor isolation live; this box is the Sendable-safe snapshot instead
    /// — same lock-backed-box idiom `SidecastListenerOrchestratorTests`
    /// already uses for its own cross-actor test doubles.
    private final class GateSnapshot: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock<Bool>(initialState: false)
        var isOpen: Bool {
            get { lock.withLock { $0 } }
            set { lock.withLock { $0 = newValue } }
        }
    }

    private struct GatedSidecastLLM: SidecastLLM {
        struct EgressGateClosed: Error {}
        let wrapped: any SidecastLLM
        let gate: GateSnapshot

        func call(system: String, user: String, schema: OpenRouterClient.JSONSchemaSpec) async throws -> String {
            guard gate.isOpen else { throw EgressGateClosed() }
            return try await wrapped.call(system: system, user: user, schema: schema)
        }
    }

    /// How often (at most) `receive` attempts a corpus re-read, an
    /// approximation of "before each listen pass" — the listener's own
    /// cadence gate (`SidecastQuestionListener`'s ≥2 unlistened / ≥8s) is
    /// private actor state with no exposed hook, so this coordinator can't
    /// observe "a pass is about to start" precisely without WB-2 changes
    /// this phase doesn't make. Reusing the same 8s order of magnitude
    /// keeps the corpus reasonably fresh for whenever the listener does
    /// fire, without re-scanning the folder on every single utterance.
    private static let corpusRefreshMinInterval: TimeInterval = 8

    let model: SidecastWhiteboardModel
    let corpusService: SidecastCorpusService

    private let settings: AppSettings
    private let now: @Sendable () -> Date
    private let resolveCorpusBookmark: @Sendable () -> URL?
    private let gate: GateSnapshot
    private let gatedLLM: any SidecastLLM
    private let orchestrator: SidecastQuestionOrchestrator
    private var listener: SidecastQuestionListener
    private var lastCorpusRefreshAt: Date = .distantPast

    init(
        model: SidecastWhiteboardModel = SidecastWhiteboardModel(),
        corpusService: SidecastCorpusService = SidecastCorpusService(),
        llm: any SidecastLLM,
        settings: AppSettings,
        now: @escaping @Sendable () -> Date = { Date() },
        resolveCorpusBookmark: @escaping @Sendable () -> URL? = { SidecastCorpusBookmark.resolve() }
    ) {
        self.model = model
        self.corpusService = corpusService
        self.settings = settings
        self.now = now
        self.resolveCorpusBookmark = resolveCorpusBookmark

        let gate = GateSnapshot()
        self.gate = gate
        let gatedLLM = GatedSidecastLLM(wrapped: llm, gate: gate)
        self.gatedLLM = gatedLLM

        let orchestrator = SidecastQuestionOrchestrator(
            llm: gatedLLM,
            corpusService: corpusService,
            onNote: { note in
                Task { @MainActor in
                    model.receive(note: note)
                }
            },
            onActivity: { inFlight, _ in
                Task { @MainActor in
                    // Once a session has ended, later activity from
                    // work already in flight at end time must not
                    // resurrect a "Live"/"Answering" status — only the
                    // note itself (via onNote above) still lands. See
                    // sessionEnded()'s doc comment.
                    guard model.status != .ended else { return }
                    model.status = inFlight > 0 ? .answering(count: inFlight) : .live
                }
            }
        )
        self.orchestrator = orchestrator
        self.listener = SidecastQuestionListener(orchestrator: orchestrator, llm: gatedLLM, now: now)
    }

    // MARK: - Session lifecycle

    /// Call once a session has actually started (not merely requested —
    /// `LiveSessionController.startTranscription`, after services are
    /// ensured initialized). No-ops entirely when the flag is off.
    ///
    /// A fresh `SidecastQuestionListener` is built for every session: the
    /// listener has no `clear()` of its own (its recent-text window and
    /// cadence timers are private actor state, WB-2 exposed no reset hook,
    /// and this phase doesn't modify WB-2 files) — starting from a new
    /// instance is the simplest way to guarantee a new session's first
    /// listen pass isn't primed with the previous session's trailing
    /// transcript. The orchestrator is long-lived across sessions instead:
    /// `clear()` bumps its epoch and drops its queue, which is the exact
    /// "WB-2 epoch test pattern" a fresh instance would otherwise have had
    /// to reinvent — any stale in-flight answer from the previous session
    /// discards itself via the epoch check already built into
    /// `SidecastQuestionOrchestrator.finish(_:)`/`answer(_:)`.
    func sessionStarted(at date: Date) {
        guard settings.sidecastWhiteboardEnabled else { return }
        gate.isOpen = isEgressAllowed
        lastCorpusRefreshAt = .distantPast
        model.sessionStart = date
        model.status = .live
        listener = SidecastQuestionListener(orchestrator: orchestrator, llm: gatedLLM, now: now)
        Task { [orchestrator] in await orchestrator.clear() }
    }

    /// Call once a session has actually ended (`LiveSessionController.
    /// finalizeCurrentSession`, before its own teardown work). Board
    /// content is deliberately left untouched (kept for export) and the
    /// orchestrator's epoch is deliberately NOT bumped — an answer already
    /// in flight when the session ends still lands on the board when it
    /// completes (WB-2 semantics: end is not the same event as clear/new-
    /// session-start). Only the status strip changes, and — see the
    /// `onActivity` callback above — it will not un-flip to "Live"/
    /// "Answering" once ended, no matter what stale activity follows.
    func sessionEnded() {
        guard settings.sidecastWhiteboardEnabled else { return }
        model.status = .ended
    }

    /// Feed one utterance from the live seam — called for EVERY utterance
    /// that reaches `LiveSessionController.handleNewUtterance`, both `.you`
    /// and system-audio speakers alike (the board hears the whole call).
    /// No-ops entirely when the flag is off: zero listener activity, zero
    /// view-model mutation, matching `sessionStarted`/`sessionEnded`.
    func receive(utteranceText: String, speaker: Speaker, at date: Date) {
        guard settings.sidecastWhiteboardEnabled else { return }
        gate.isOpen = isEgressAllowed
        model.noteDiagHeard()
        maybeRefreshCorpus()

        let text = "\(speaker.displayLabel): \(utteranceText)"
        let currentListener = listener
        Task { await currentListener.noteUtterance(text: text, at: date) }
    }

    // MARK: - Egress gate

    /// Mirrors the legacy realtime path's own per-utterance credential
    /// check (`SidecastEngine`/`SuggestionEngine`'s provider switch in
    /// `onUtterance`), narrowed to the one provider this pipeline's
    /// production `llm` can reach. See the type's doc comment.
    private var isEgressAllowed: Bool {
        settings.llmProvider == .openRouter && !settings.openRouterApiKey.isEmpty
    }

    // MARK: - Corpus refresh

    /// Re-reads the corpus folder from the saved bookmark, throttled to
    /// `corpusRefreshMinInterval`. Actor-safe (hops onto `corpusService`,
    /// an actor, for the read itself) and never fatal: a failure lands on
    /// `model.corpusStatusLine` for the board to show, and the session
    /// keeps running exactly as before — this is best-effort freshness, not
    /// a precondition for anything else here.
    private func maybeRefreshCorpus() {
        let nowValue = now()
        guard nowValue.timeIntervalSince(lastCorpusRefreshAt) >= Self.corpusRefreshMinInterval else { return }
        lastCorpusRefreshAt = nowValue
        guard let folder = resolveCorpusBookmark() else { return }

        let corpusService = corpusService
        Task { [weak self] in
            do {
                _ = try await corpusService.read(folder: folder)
                await MainActor.run { self?.model.corpusStatusLine = nil }
            } catch {
                let message = "Corpus refresh failed: \(error.localizedDescription)"
                Log.sidecast.error("[whiteboard-coordinator] \(message, privacy: .public)")
                await MainActor.run { self?.model.corpusStatusLine = message }
            }
        }
    }
}
