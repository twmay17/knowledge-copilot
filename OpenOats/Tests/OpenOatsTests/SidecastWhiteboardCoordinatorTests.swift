import Foundation
import XCTest
import os
@testable import OpenOatsKit

// MARK: - Test doubles

/// Scriptable `SidecastLLM` double — records every call (so tests can prove
/// "zero llm calls"), returns canned listen/answer JSON keyed off the
/// schema name (`SidecastSchemas.listen`/`.answer`), and can suspend answer
/// calls on demand so a test can land its own coordinator calls
/// (`sessionEnded()`/`sessionStarted()`) precisely while an answer is in
/// flight — the same shape of control WB-2's own `SidecastListenerOrchestratorTests`
/// uses for its epoch/end-of-session behaviors, trimmed to what this
/// coordinator-level suite needs.
private actor MockLLM: SidecastLLM {
    struct Call: Sendable {
        let system: String
        let user: String
        let schemaName: String
    }

    private(set) var calls: [Call] = []
    private var listenResponse: Result<String, Error> = .success("{\"items\":[]}")
    private var answerResponse: Result<String, Error> = .success("{\"answer\":\"\",\"grounded\":false,\"value\":0}")

    private var suspendAnswers = false
    private var suspendedAnswerContinuations: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func setListenResponse(_ json: String) { listenResponse = .success(json) }
    func setAnswerResponse(_ json: String) { answerResponse = .success(json) }
    func setSuspendAnswers(_ value: Bool) { suspendAnswers = value }

    /// Resumes the single oldest suspended answer call, if any.
    func resumeOneAnswer() {
        guard !suspendedAnswerContinuations.isEmpty else { return }
        suspendedAnswerContinuations.removeFirst().resume()
    }

    func callCount() -> Int { calls.count }

    /// True happens-before wait, resolved the moment the target call
    /// *starts* (recorded below) — even if that call then suspends waiting
    /// for `resumeOneAnswer()`. Checked-and-registered atomically: no
    /// `await` happens between the count check and appending to
    /// `callWaiters`, so a concurrent `call(...)` can't slip in between.
    func waitForCallCount(_ target: Int) async {
        if calls.count >= target { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((target, continuation))
        }
    }

    func call(system: String, user: String, schema: OpenRouterClient.JSONSchemaSpec) async throws -> String {
        let isAnswer = schema.name == SidecastSchemas.answer.name

        calls.append(Call(system: system, user: user, schemaName: schema.name))
        let ready = callWaiters.filter { calls.count >= $0.target }
        callWaiters.removeAll { calls.count >= $0.target }
        for waiter in ready { waiter.continuation.resume() }

        if isAnswer && suspendAnswers {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                suspendedAnswerContinuations.append(continuation)
            }
        }

        let result = isAnswer ? answerResponse : listenResponse
        switch result {
        case .success(let json): return json
        case .failure(let error): throw error
        }
    }
}

/// Manually-advanced clock handed to the coordinator as `now: @Sendable () -> Date`.
private final class TestClock: @unchecked Sendable {
    private let box: OSAllocatedUnfairLock<Date>

    init(_ start: Date) {
        box = OSAllocatedUnfairLock(initialState: start)
    }

    func now() -> Date { box.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { box.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

// MARK: - Tests

@MainActor
final class SidecastWhiteboardCoordinatorTests: XCTestCase {

    // MARK: Fixture helpers

    private func makeSettings(
        whiteboardEnabled: Bool = true,
        llmProvider: LLMProvider = .openRouter,
        openRouterApiKey: String = "test-key-123"
    ) -> AppSettings {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecast-whiteboard-coordinator-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let suiteName = "com.openoats.tests.whiteboardcoordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: .ephemeral,
            defaultNotesDirectory: root,
            runMigrations: false
        )
        let settings = AppSettings(storage: storage)
        settings.sidecastWhiteboardEnabled = whiteboardEnabled
        settings.llmProvider = llmProvider
        settings.openRouterApiKey = openRouterApiKey
        return settings
    }

    private func makeCoordinator(
        settings: AppSettings,
        llm: MockLLM,
        clock: TestClock,
        model: SidecastWhiteboardModel = SidecastWhiteboardModel(),
        resolveCorpusBookmark: @escaping @Sendable () -> URL? = { nil }
    ) -> SidecastWhiteboardCoordinator {
        SidecastWhiteboardCoordinator(
            model: model,
            llm: llm,
            settings: settings,
            now: { clock.now() },
            resolveCorpusBookmark: resolveCorpusBookmark
        )
    }

    private func jsonStringLiteral(_ text: String) -> String {
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder().encode(text)
        return String(data: data, encoding: .utf8)!
    }

    private func listenJSON(_ questions: [String]) -> String {
        let items = questions.map { "{\"question\":\(jsonStringLiteral($0))}" }.joined(separator: ",")
        return "{\"items\":[\(items)]}"
    }

    private func answerJSON(answer: String, grounded: Bool = true, value: Double = 0.9) -> String {
        "{\"answer\":\(jsonStringLiteral(answer)),\"grounded\":\(grounded),\"value\":\(value)}"
    }

    /// A handful of yields — cheap extra margin before a check that's
    /// already otherwise justified by a hard wait just before it.
    private func settle(_ iterations: Int = 20) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    /// Retries `action` with a short real sleep between tries — for
    /// conditions with no exposed signal to await directly (MainActor
    /// view-model state mutated from inside an unstructured `Task` this
    /// test has no continuation into). Same idiom as
    /// `SidecastListenerOrchestratorTests`'s own `eventually(_:)`.
    @discardableResult
    private func eventually(attempts: Int = 100, _ action: () async -> Bool) async -> Bool {
        for attempt in 0..<attempts {
            if await action() { return true }
            if attempt < attempts - 1 {
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
        return false
    }

    /// For asserting a negative within a bounded window — mirrors
    /// `SidecastListenerOrchestratorTests`'s `NoteRecorder.exceededCount`.
    private func callCountStaysAtMost(_ maxAllowed: Int, llm: MockLLM, within duration: Duration = .milliseconds(200)) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            if await llm.callCount() > maxAllowed { return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return await llm.callCount() <= maxAllowed
    }

    // MARK: - a. Flag OFF

    func testFlagOffProducesZeroLLMCallsAndZeroViewModelMutation() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let llm = MockLLM()
        let model = SidecastWhiteboardModel()
        let settings = makeSettings(whiteboardEnabled: false)
        let coordinator = makeCoordinator(settings: settings, llm: llm, clock: clock, model: model)

        coordinator.sessionStarted(at: clock.now())
        coordinator.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())
        clock.advance(9)
        coordinator.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())
        coordinator.sessionEnded()

        let stayedQuiet = await callCountStaysAtMost(0, llm: llm)
        XCTAssertTrue(stayedQuiet, "flag off: the pipeline must never reach the llm")

        XCTAssertEqual(model.status, .ready, "flag off: sessionStarted/sessionEnded must not touch the view model")
        XCTAssertNil(model.sessionStart)
        XCTAssertEqual(model.heardCount, 0, "flag off: receive must not bump the heard counter")
        XCTAssertTrue(model.notes.isEmpty)
    }

    // MARK: - b. Flag ON: session start, utterances feed listener, note lands

    func testFlagOnSessionStartFeedsListenerAndLandedNoteUpdatesViewModel() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let llm = MockLLM()
        let model = SidecastWhiteboardModel()
        let settings = makeSettings()
        let coordinator = makeCoordinator(settings: settings, llm: llm, clock: clock, model: model)

        let sessionStart = clock.now()
        coordinator.sessionStarted(at: sessionStart)
        XCTAssertEqual(model.status, .live)
        XCTAssertEqual(model.sessionStart, sessionStart)

        await llm.setListenResponse(listenJSON(["What is the pricing?"]))
        await llm.setAnswerResponse(answerJSON(answer: "It's $10 per month."))

        coordinator.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())
        await settle()
        coordinator.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())

        // Listen call, then answer call: two calls total once the pass and
        // the enqueued question have both gone through.
        await llm.waitForCallCount(2)
        let landed = await eventually { model.notes.count == 1 }
        XCTAssertTrue(landed, "an answered question should land on the board")

        XCTAssertEqual(model.notes.first?.question, "What is the pricing?")
        XCTAssertEqual(model.notes.first?.answer, "It's $10 per month.")
        XCTAssertEqual(model.answersCount, 1)
        XCTAssertEqual(model.heardCount, 2, "bumped once per utterance received, independent of listen/answer outcome")
        XCTAssertTrue(model.diagText.contains("answers 1"))
    }

    // MARK: - c. Session end: status ended, board retained, in-flight answer still lands

    func testSessionEndKeepsBoardAndLetsInFlightAnswerLandWithoutRevivingStatus() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let llm = MockLLM()
        let model = SidecastWhiteboardModel()
        let settings = makeSettings()
        let coordinator = makeCoordinator(settings: settings, llm: llm, clock: clock, model: model)

        coordinator.sessionStarted(at: clock.now())
        await llm.setListenResponse(listenJSON(["What is the pricing?"]))
        await llm.setAnswerResponse(answerJSON(answer: "It's $10 per month."))
        await llm.setSuspendAnswers(true)

        coordinator.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())
        await settle()
        coordinator.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())

        // Wait until the answer call has actually started (and is now
        // suspended) before ending the session, so this genuinely proves
        // "already in flight when the session ends", not "enqueued after".
        await llm.waitForCallCount(2)
        await settle()

        coordinator.sessionEnded()
        XCTAssertEqual(model.status, .ended)
        XCTAssertTrue(model.notes.isEmpty, "the answer has not landed yet")

        await llm.resumeOneAnswer()
        let landed = await eventually { model.notes.count == 1 }
        XCTAssertTrue(landed, "an answer already in flight at end time must still land — end is not clear/new-session")

        XCTAssertEqual(model.notes.first?.answer, "It's $10 per month.")
        XCTAssertEqual(
            model.status, .ended,
            "the note landing (onNote) must not resurrect Live/Answering (onActivity) once ended"
        )
    }

    // MARK: - d. New session start after a previous one: epoch bumped, stale in-flight discarded

    func testNewSessionStartBumpsEpochAndDiscardsStaleInFlightAnswer() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let llm = MockLLM()
        let model = SidecastWhiteboardModel()
        let settings = makeSettings()
        let coordinator = makeCoordinator(settings: settings, llm: llm, clock: clock, model: model)

        coordinator.sessionStarted(at: clock.now())
        await llm.setListenResponse(listenJSON(["What is the pricing?"]))
        await llm.setAnswerResponse(answerJSON(answer: "It's $10 per month."))
        await llm.setSuspendAnswers(true)

        coordinator.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())
        await settle()
        coordinator.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())
        await llm.waitForCallCount(2)
        await settle()

        // A brand-new session starts while the first session's answer is
        // still in flight — this is the WB-2 epoch pattern invoked at the
        // coordinator level: sessionStarted -> orchestrator.clear() bumps
        // the epoch, so the stale item's eventual completion discards
        // itself (SidecastQuestionOrchestrator.answer(_:)'s own epoch
        // check), not anything this coordinator re-implements.
        clock.advance(120)
        let secondSessionStart = clock.now()
        coordinator.sessionStarted(at: secondSessionStart)
        XCTAssertEqual(model.sessionStart, secondSessionStart)

        await llm.resumeOneAnswer()
        await settle(200)

        XCTAssertTrue(model.notes.isEmpty, "the stale first-session answer must be discarded, not appear in the new session")
    }

    // MARK: - e. Corpus refresh failure surfaces on VM corpus line, session continues

    func testCorpusRefreshFailureSurfacesOnViewModelAndSessionContinues() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let llm = MockLLM()
        let model = SidecastWhiteboardModel()
        let settings = makeSettings()
        // A path that is guaranteed not to be a real directory — the exact
        // failure `SidecastCorpusService.read(folder:)` reports.
        let brokenFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecast-whiteboard-coordinator-missing-\(UUID().uuidString)", isDirectory: true)
        let coordinator = makeCoordinator(
            settings: settings, llm: llm, clock: clock, model: model,
            resolveCorpusBookmark: { brokenFolder }
        )

        coordinator.sessionStarted(at: clock.now())
        coordinator.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())

        let surfaced = await eventually { model.corpusStatusLine != nil }
        XCTAssertTrue(surfaced, "a corpus refresh failure must surface on the view model, not disappear silently")
        XCTAssertEqual(model.status, .live, "never fatal — the session keeps running")

        // Session continues: a second utterance still reaches the listener
        // (heard count keeps counting) rather than the coordinator wedging.
        clock.advance(1)
        coordinator.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())
        XCTAssertEqual(model.heardCount, 2)
    }

    // MARK: - f. Egress gate: gate closed, flag ON produces zero llm calls

    func testEgressGateClosedProducesZeroLLMCallsEvenWithFlagOn() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let llm = MockLLM()
        let model = SidecastWhiteboardModel()
        // Flag ON, but no OpenRouter key configured — the same
        // "presence of credentials" gate the legacy realtime path checks.
        let settings = makeSettings(whiteboardEnabled: true, openRouterApiKey: "")
        let coordinator = makeCoordinator(settings: settings, llm: llm, clock: clock, model: model)

        coordinator.sessionStarted(at: clock.now())
        coordinator.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())
        await settle()
        coordinator.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())

        let stayedQuiet = await callCountStaysAtMost(0, llm: llm)
        XCTAssertTrue(stayedQuiet, "with the egress gate closed, the wrapped llm must never be reached")

        // The gate closing a provider mismatch (right settings, wrong
        // provider selected) must behave identically.
        let wrongProviderSettings = makeSettings(whiteboardEnabled: true, llmProvider: .anthropic, openRouterApiKey: "present-but-unselected")
        let llm2 = MockLLM()
        let coordinator2 = makeCoordinator(settings: wrongProviderSettings, llm: llm2, clock: clock, model: SidecastWhiteboardModel())
        coordinator2.sessionStarted(at: clock.now())
        coordinator2.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())
        await settle()
        coordinator2.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())
        let stayedQuiet2 = await callCountStaysAtMost(0, llm: llm2)
        XCTAssertTrue(stayedQuiet2, "an OpenRouter key alone must not open egress when a different provider is active")
    }

    // MARK: - g. Diag guard: answers-only nonzero -> diagText visible

    func testDiagTextIsVisibleOnceAnAnswerLandsThroughTheFullPipeline() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let llm = MockLLM()
        let model = SidecastWhiteboardModel()
        let settings = makeSettings()
        let coordinator = makeCoordinator(settings: settings, llm: llm, clock: clock, model: model)

        XCTAssertEqual(model.diagText, "", "nothing has happened yet")

        coordinator.sessionStarted(at: clock.now())
        await llm.setListenResponse(listenJSON(["What is the pricing?"]))
        await llm.setAnswerResponse(answerJSON(answer: "It's $10 per month."))

        coordinator.receive(utteranceText: "What is the pricing?", speaker: .them, at: clock.now())
        await settle()
        coordinator.receive(utteranceText: "Let me check that.", speaker: .you, at: clock.now())
        await llm.waitForCallCount(2)

        let visible = await eventually { !model.diagText.isEmpty && model.diagText.contains("answers 1") }
        XCTAssertTrue(visible, "an answers-only-nonzero board must show the diag line, not stay blank")
    }
}
