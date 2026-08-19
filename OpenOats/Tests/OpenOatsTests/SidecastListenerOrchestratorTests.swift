import Foundation
import XCTest
import os
@testable import OpenOatsKit

// MARK: - Test doubles

/// Scriptable, continuation-suspendable `SidecastLLM` double. Every call is
/// recorded verbatim (system/user/schema name) so tests can inspect exactly
/// what the listener/orchestrator sent outbound. `setSuspend(true)` makes
/// every subsequent call block on a `CheckedContinuation` until the test
/// releases it with `resumeOne()`/`resumeAll()` — this is how the
/// concurrency-shaped behaviors (single pass in flight, ≤3 concurrent
/// answers, queue-cap drop, epoch discard) are driven deterministically
/// without sleeps.
private actor MockLLM: SidecastLLM {
    struct Call: Sendable {
        let system: String
        let user: String
        let schemaName: String
    }

    private(set) var calls: [Call] = []
    private(set) var startedCount = 0
    private(set) var finishedCount = 0

    private var shouldSuspend = false
    private var suspended: [CheckedContinuation<Void, Never>] = []
    private var responses: [Result<String, Error>] = []
    private var defaultResponse: Result<String, Error> = .success("{}")

    private var startWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var finishWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func setSuspend(_ value: Bool) {
        shouldSuspend = value
    }

    /// Queues one scripted success response (FIFO). Calls beyond the queued
    /// responses fall back to the neutral `"{}"` default, which decodes to
    /// an empty listen/answer response either way — harmless for tests that
    /// don't care about a particular call's output.
    func enqueueResponse(_ json: String) {
        responses.append(.success(json))
    }

    /// Resumes the single oldest suspended call, if any.
    func resumeOne() {
        guard !suspended.isEmpty else { return }
        suspended.removeFirst().resume()
    }

    /// Resumes every call suspended right now (not ones that suspend later).
    func resumeAll() {
        let waiting = suspended
        suspended.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Suspends the caller until `startedCount` (a call has begun, whether
    /// or not it has gone on to suspend) reaches `target`.
    func waitForStarted(_ target: Int) async {
        if startedCount >= target { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((target, continuation))
        }
    }

    /// Suspends the caller until `finishedCount` (a call has returned or
    /// thrown) reaches `target`.
    func waitForFinished(_ target: Int) async {
        if finishedCount >= target { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append((target, continuation))
        }
    }

    func call(system: String, user: String, schema: OpenRouterClient.JSONSchemaSpec) async throws -> String {
        calls.append(Call(system: system, user: user, schemaName: schema.name))
        startedCount += 1
        resolveStartWaiters()

        defer {
            finishedCount += 1
            resolveFinishWaiters()
        }

        if shouldSuspend {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                suspended.append(continuation)
            }
        }

        let result = responses.isEmpty ? defaultResponse : responses.removeFirst()
        switch result {
        case .success(let json): return json
        case .failure(let error): throw error
        }
    }

    private func resolveStartWaiters() {
        guard !startWaiters.isEmpty else { return }
        let ready = startWaiters.filter { startedCount >= $0.target }
        startWaiters.removeAll { startedCount >= $0.target }
        for waiter in ready { waiter.continuation.resume() }
    }

    private func resolveFinishWaiters() {
        guard !finishWaiters.isEmpty else { return }
        let ready = finishWaiters.filter { finishedCount >= $0.target }
        finishWaiters.removeAll { finishedCount >= $0.target }
        for waiter in ready { waiter.continuation.resume() }
    }
}

/// Thread-safe activity log fed by `onActivity`, which the orchestrator
/// calls synchronously (not `async`) — a lock-backed `@unchecked Sendable`
/// class, not an actor, so the closure itself can stay a plain sync
/// `@Sendable` function matching the orchestrator's own call sites verbatim.
private struct ActivityRecord: Sendable, Equatable {
    let inFlight: Int
    let queued: Int
}

private final class ActivityRecorder: @unchecked Sendable {
    private let box = OSAllocatedUnfairLock<[ActivityRecord]>(initialState: [])

    func record(_ inFlight: Int, _ queued: Int) {
        box.withLock { $0.append(ActivityRecord(inFlight: inFlight, queued: queued)) }
    }

    func snapshot() -> [ActivityRecord] {
        box.withLock { $0 }
    }
}

/// Thread-safe note log fed by `onNote` — see `ActivityRecorder` for why
/// this is a lock-backed class rather than an actor.
///
/// Also the synchronization point for tests: `record(_:)` runs on whichever
/// task calls the orchestrator's `onNote` closure, and that task is *not*
/// the same one a test is `await`ing on (`enqueue`/mock `waitFor...` calls
/// resume their own, separately-scheduled continuations) — so "wait for the
/// mock to finish, then yield a few times" is not actually a proof that
/// `record(_:)` has run. `waitForCount`/`exceededCount` below wait on the
/// real event instead of inferring it from a fixed yield budget.
private final class NoteRecorder: @unchecked Sendable {
    private struct State {
        var notes: [SidecastAnsweredNote] = []
        var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let box = OSAllocatedUnfairLock<State>(initialState: State())

    func record(_ note: SidecastAnsweredNote) {
        let ready: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = box.withLock { state in
            state.notes.append(note)
            let count = state.notes.count
            let ready = state.waiters.filter { count >= $0.target }
            state.waiters.removeAll { count >= $0.target }
            return ready
        }
        for waiter in ready { waiter.continuation.resume() }
    }

    func snapshot() -> [SidecastAnsweredNote] {
        box.withLock { $0.notes }
    }

    /// True happens-before wait: resumes only once `record(_:)` has actually
    /// been called for the `target`th time (or immediately, if it already
    /// has) — checked and registered atomically under the same lock so a
    /// concurrent `record(_:)` can't slip in between the check and the
    /// registration.
    func waitForCount(_ target: Int) async {
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = box.withLock { state in
                if state.notes.count >= target { return true }
                state.waiters.append((target, continuation))
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    /// For asserting a negative: true if the count exceeds `maxAllowed`
    /// within `duration`, false if `duration` elapses first. A pure
    /// continuation can prove "it happened" but never "it didn't" without
    /// either hanging forever or racing a timeout. Deliberately plain
    /// polling rather than a `withTaskGroup`/`cancelAll()` race: cancelling
    /// a task group's child does not resume a plain `CheckedContinuation`
    /// it's suspended on (that needs an explicit cancellation handler), so
    /// racing `waitForCount` that way leaves a task permanently suspended —
    /// which `withTaskGroup` then waits on forever before returning. Polling
    /// has no such trap, and the bound here is short enough that it only
    /// ever costs the full `duration` when the assertion is correctly false.
    func exceededCount(_ maxAllowed: Int, within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            if box.withLock({ $0.notes.count }) > maxAllowed {
                return true
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return box.withLock { $0.notes.count } > maxAllowed
    }
}

/// Manually-advanced clock handed to both actors as `now: @Sendable () -> Date`.
private final class TestClock: @unchecked Sendable {
    private let box: OSAllocatedUnfairLock<Date>

    init(_ start: Date) {
        box = OSAllocatedUnfairLock(initialState: start)
    }

    func now() -> Date {
        box.withLock { $0 }
    }

    func advance(_ seconds: TimeInterval) {
        box.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

// MARK: - Tests

final class SidecastListenerOrchestratorTests: XCTestCase {

    // MARK: Fixture helpers

    /// Small enough to stay under `SidecastCorpusService`'s whole-corpus
    /// (10k char) threshold, so `retrieveEvidence(query:)` deterministically
    /// returns the same non-nil evidence for every query regardless of its
    /// content — lets answer-gate tests focus purely on the mock's response
    /// (grounded/value/answer) rather than on corpus matching.
    private func makeCorpusService() async throws -> SidecastCorpusService {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecast-listener-orchestrator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "Fixture corpus content for WB-2 tests.".write(
            to: root.appendingPathComponent("fixture.md"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let service = SidecastCorpusService()
        _ = try await service.read(folder: root)
        return service
    }

    private func makeOrchestrator(
        llm: MockLLM,
        corpusService: SidecastCorpusService,
        clock: TestClock,
        notes: NoteRecorder = NoteRecorder(),
        activity: ActivityRecorder = ActivityRecorder()
    ) -> SidecastQuestionOrchestrator {
        SidecastQuestionOrchestrator(
            llm: llm,
            corpusService: corpusService,
            onNote: { note in notes.record(note) },
            onActivity: { inFlight, queued in activity.record(inFlight, queued) }
        )
    }

    /// Token-disjoint per index (every word is index-suffixed), so no two
    /// distinct indices can accidentally cross the 0.8/0.5 Jaccard dedup
    /// thresholds — tests that need many simultaneously-live, clearly-
    /// distinct questions can lean on this without hand-verifying overlap.
    private func question(_ index: Int) -> String {
        "alpha\(index) beta\(index) gamma\(index) delta\(index) epsilon\(index)"
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

    private func answerJSON(answer: String, grounded: Bool, value: Double) -> String {
        "{\"answer\":\(jsonStringLiteral(answer)),\"grounded\":\(grounded),\"value\":\(value)}"
    }

    /// A handful of yields, not a sleep: cheap extra margin before a check
    /// that is already otherwise justified (see the note on `NoteRecorder`
    /// and `eventually(_:)` below for the cases that need a *real*
    /// happens-before guarantee rather than this).
    private func settle(_ iterations: Int = 20) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    /// Retries `action` (which performs one attempt and reports whether it
    /// succeeded) with a short real sleep between tries. Used specifically
    /// where the condition being waited on is internal actor state with no
    /// exposed signal to await directly — e.g. `SidecastQuestionListener`'s
    /// `passInFlight` resetting once a listen pass's trailing synchronous
    /// work (after its mock call returns) has actually run. That reset and
    /// this test are on two independently-scheduled continuations with no
    /// ordering guarantee between them, so a fixed yield budget is a guess;
    /// retrying with real wall-clock gaps gives the scheduler room to run
    /// the pending continuation regardless of how many rounds it takes.
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

    // MARK: - 1. Cadence: ≥2 unlistened AND ≥8s since last pass started AND no pass in flight

    func test01_CadenceGateOnUtteranceCountAndInterval() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let listenerMock = MockLLM()
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)
        let listener = SidecastQuestionListener(orchestrator: orchestrator, llm: listenerMock, now: { clock.now() })

        await listener.noteUtterance(text: "hello there", at: clock.now())
        var started = await listenerMock.startedCount
        XCTAssertEqual(started, 0, "must not fire before 2 un-listened utterances")

        await listener.noteUtterance(text: "second line", at: clock.now())
        await listenerMock.waitForStarted(1)
        await settle()
        started = await listenerMock.startedCount
        XCTAssertEqual(started, 1, "fires once 2 un-listened utterances have arrived")

        // Two more utterances, no clock movement: the 8s interval blocks a second pass.
        await listener.noteUtterance(text: "third line", at: clock.now())
        await listener.noteUtterance(text: "fourth line", at: clock.now())
        started = await listenerMock.startedCount
        XCTAssertEqual(started, 1, "second pass must wait for the 8s interval")

        // Firing pass 2 also requires pass 1's `passInFlight` flag to have
        // reset, which happens on pass 1's own trailing continuation (after
        // its mock call already returned) — a separately-scheduled unit of
        // work from this test's, with no direct signal to await. Retrying
        // the utterance feed converges on it regardless of how many
        // scheduler rounds that reset takes.
        clock.advance(8)
        let firedAgain = await eventually {
            await listener.noteUtterance(text: "fifth line", at: clock.now())
            return await listenerMock.startedCount >= 2
        }
        XCTAssertTrue(firedAgain, "fires again once the interval has elapsed")
    }

    // MARK: - 2. Single listen pass in flight

    func test02_SingleListenPassInFlight() async throws {
        let clock = TestClock(Date())
        let listenerMock = MockLLM()
        await listenerMock.setSuspend(true)
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)
        let listener = SidecastQuestionListener(orchestrator: orchestrator, llm: listenerMock, now: { clock.now() })

        await listener.noteUtterance(text: "line one", at: clock.now())
        await listener.noteUtterance(text: "line two", at: clock.now())
        await listenerMock.waitForStarted(1)

        // Satisfy the interval gate up front so it can't independently
        // explain a blocked second pass — with the mock still suspended,
        // only `passInFlight` stands between this test and a second
        // concurrent call. (Without this advance, the ≥8s interval gate
        // alone blocks a second pass and this test is vacuous — it would
        // still pass with the `passInFlight` guard deleted.)
        clock.advance(8)

        // Keep feeding utterances while the first pass sits suspended.
        for index in 3...6 {
            await listener.noteUtterance(text: "line \(index)", at: clock.now())
        }
        await settle()
        let started = await listenerMock.startedCount
        XCTAssertEqual(started, 1, "no second listen pass may start while one is in flight")

        await listenerMock.resumeAll()
        await listenerMock.waitForFinished(1)
    }

    // MARK: - 3. Listener caps parsed items at 4

    func test03_ListenerCapsParsedItemsAtFour() async throws {
        let clock = TestClock(Date())
        let listenerMock = MockLLM()
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)
        let listener = SidecastQuestionListener(orchestrator: orchestrator, llm: listenerMock, now: { clock.now() })

        let sixQuestions = (0..<6).map { question($0) }
        await listenerMock.enqueueResponse(listenJSON(sixQuestions))

        await listener.noteUtterance(text: "line one", at: clock.now())
        await listener.noteUtterance(text: "line two", at: clock.now())
        await listenerMock.waitForStarted(1)

        await answerMock.waitForStarted(4)
        await settle()

        let answerCalls = await answerMock.calls
        XCTAssertEqual(answerCalls.count, 4, "only the first 4 parsed items should reach the orchestrator")
        for index in 0..<4 {
            XCTAssertTrue(answerCalls.contains { $0.user.contains(question(index)) }, "item \(index) should have been enqueued")
        }
        for index in 4..<6 {
            XCTAssertFalse(answerCalls.contains { $0.user.contains(question(index)) }, "item \(index) is beyond the cap of 4")
        }
    }

    // MARK: - 4. Covered-list flows from the orchestrator into the next listener prompt

    func test04_CoveredListIncludedInNextListenerPrompt() async throws {
        let clock = TestClock(Date())
        let listenerMock = MockLLM()
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)
        let listener = SidecastQuestionListener(orchestrator: orchestrator, llm: listenerMock, now: { clock.now() })

        let firstQuestions = ["what year did the acquisition close", "who is the general manager"]
        await listenerMock.enqueueResponse(listenJSON(firstQuestions))

        await listener.noteUtterance(text: "line one", at: clock.now())
        await listener.noteUtterance(text: "line two", at: clock.now())
        await listenerMock.waitForStarted(1)
        // Both questions land in the orchestrator's recentQuestions as soon as
        // they've been enqueued; both immediately fit under the in-flight cap,
        // so waiting for both answer calls to start is a solid proxy for "the
        // first listen pass has fully handed off its parsed items."
        await answerMock.waitForStarted(2)
        await settle()

        // See test01's matching comment: firing pass 2 needs pass 1's
        // `passInFlight` to have reset on its own, separately-scheduled
        // trailing continuation, so retry rather than assume one settle is enough.
        clock.advance(8)
        let firedSecondPass = await eventually {
            await listener.noteUtterance(text: "line three", at: clock.now())
            await listener.noteUtterance(text: "line four", at: clock.now())
            return await listenerMock.startedCount >= 2
        }
        XCTAssertTrue(firedSecondPass, "expected a second listen pass to fire")

        let calls = await listenerMock.calls
        XCTAssertEqual(calls.count, 2)
        let secondUserPrompt = calls[1].user
        XCTAssertTrue(secondUserPrompt.contains(SidecastPrompts.alreadyCoveredHeader))
        for asked in firstQuestions {
            XCTAssertTrue(secondUserPrompt.contains(asked), "expected the covered list to include: \(asked)")
        }
    }

    // MARK: - 5. Question dedup: identical dropped, clearly different admitted

    func test05_QuestionDedupDropsIdenticalAdmitsDifferent() async throws {
        let clock = TestClock(Date())
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)

        let original = "What was total revenue for the hotel last year"
        await orchestrator.enqueue(question: original, timestamp: clock.now(), retrievalHint: nil)
        await answerMock.waitForStarted(1)
        var started = await answerMock.startedCount
        XCTAssertEqual(started, 1)

        await orchestrator.enqueue(question: original, timestamp: clock.now(), retrievalHint: nil)
        started = await answerMock.startedCount
        XCTAssertEqual(started, 1, "an identical question must be deduped, not re-answered")

        let different = "Who manages the property day to day"
        await orchestrator.enqueue(question: different, timestamp: clock.now(), retrievalHint: nil)
        await answerMock.waitForStarted(2)
        started = await answerMock.startedCount
        XCTAssertEqual(started, 2, "a clearly different question must be admitted")
    }

    // MARK: - 6. Queue cap 6, drop-oldest

    func test06_QueueCapDropsOldestOnceExceeded() async throws {
        let clock = TestClock(Date())
        let answerMock = MockLLM()
        await answerMock.setSuspend(true)
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)

        // 3 immediately go in flight and stay suspended, holding inFlight at 3.
        for index in 0..<3 {
            await orchestrator.enqueue(question: question(index), timestamp: clock.now(), retrievalHint: nil)
        }
        await answerMock.waitForStarted(3)

        // 7 more arrive while inFlight is pinned: all queue up behind the cap
        // of 6, so the 7th arrival (index 9) forces index 3 — the oldest
        // queued item — out.
        for index in 3..<10 {
            await orchestrator.enqueue(question: question(index), timestamp: clock.now(), retrievalHint: nil)
        }

        // Let everything drain: resume the original 3, and let every item
        // pump() dispatches afterward complete immediately.
        await answerMock.setSuspend(false)
        await answerMock.resumeAll()
        await answerMock.waitForStarted(9)
        await settle()

        let calls = await answerMock.calls
        XCTAssertEqual(calls.count, 9, "3 initial in-flight + 6 that survived the queue cap")
        XCTAssertFalse(
            calls.contains { $0.user.contains(question(3)) },
            "question 3 was the oldest queued item once the 6-slot cap was exceeded")
        for index in [0, 1, 2, 4, 5, 6, 7, 8, 9] {
            XCTAssertTrue(calls.contains { $0.user.contains(question(index)) }, "question \(index) should have been dispatched")
        }
    }

    // MARK: - 7. At most 3 concurrent answer calls

    func test07_MaxThreeConcurrentAnswerCalls() async throws {
        let clock = TestClock(Date())
        let answerMock = MockLLM()
        await answerMock.setSuspend(true)
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)

        for index in 0..<4 {
            await orchestrator.enqueue(question: question(index), timestamp: clock.now(), retrievalHint: nil)
        }
        await answerMock.waitForStarted(3)
        await settle()
        var started = await answerMock.startedCount
        XCTAssertEqual(started, 3, "a 4th concurrent call must not start while 3 are in flight")

        await answerMock.resumeOne()
        await answerMock.waitForStarted(4)
        started = await answerMock.startedCount
        XCTAssertEqual(started, 4, "the 4th call starts once a slot frees up")

        await answerMock.resumeAll()
        await answerMock.waitForFinished(4)
    }

    // MARK: - 8. Epoch discard: clear() while an answer is in flight

    func test08_EpochDiscardsStaleCompletionAfterClear() async throws {
        let clock = TestClock(Date())
        let answerMock = MockLLM()
        await answerMock.setSuspend(true)
        let corpus = try await makeCorpusService()
        let notes = NoteRecorder()
        let activity = ActivityRecorder()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock, notes: notes, activity: activity)

        await answerMock.enqueueResponse(answerJSON(answer: "a stale answer that must never land", grounded: true, value: 0.9))
        await orchestrator.enqueue(question: question(0), timestamp: clock.now(), retrievalHint: nil)
        await answerMock.waitForStarted(1)

        await orchestrator.clear()
        XCTAssertEqual(activity.snapshot().last, ActivityRecord(inFlight: 0, queued: 0))

        // Resume the now-stale call and let it complete.
        await answerMock.setSuspend(false)
        await answerMock.resumeOne()
        await answerMock.waitForFinished(1)

        let staleNoteLanded = await notes.exceededCount(0, within: .milliseconds(300))
        XCTAssertFalse(staleNoteLanded, "a completion from a cleared epoch must never emit a note")
        XCTAssertEqual(activity.snapshot().last, ActivityRecord(inFlight: 0, queued: 0), "counters must stay clean — the stale completion must not touch them")

        // The orchestrator itself must still be healthy post-clear: a fresh item goes through normally.
        await answerMock.enqueueResponse(answerJSON(answer: "a fresh answer", grounded: true, value: 0.9))
        await orchestrator.enqueue(question: question(1), timestamp: clock.now(), retrievalHint: nil)
        await notes.waitForCount(1)

        let finalNotes = notes.snapshot()
        XCTAssertEqual(finalNotes.count, 1, "only the post-clear item should have produced a note")
        XCTAssertEqual(finalNotes.first?.question, question(1))
    }

    // MARK: - 9. Grounded gate (corpus present)

    func test09_GroundedGateWithCorpusPresent() async throws {
        let clock = TestClock(Date())
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let notes = NoteRecorder()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock, notes: notes)

        await answerMock.enqueueResponse(answerJSON(answer: "an ungrounded answer", grounded: false, value: 0.9))
        await orchestrator.enqueue(question: question(0), timestamp: clock.now(), retrievalHint: nil)
        await answerMock.waitForFinished(1)
        let ungroundedNoteLanded = await notes.exceededCount(0, within: .milliseconds(300))
        XCTAssertFalse(ungroundedNoteLanded, "ungrounded answer with corpus present must be dropped")

        // Also covers the orchestrator-path half of outbound redaction (the
        // listener path is covered separately by test12): the question text
        // is the one piece of `answer(_:)`'s user prompt that can carry
        // arbitrary outside content, so planting a credential in it and
        // checking the mock-captured prompt exercises the same
        // `SensitiveDataGuard.redacted(_:)` call the listener path does.
        let secretQuestion = "\(question(1)) — my access key is AKIAIOSFODNN7EXAMPLE"
        await answerMock.enqueueResponse(answerJSON(answer: "a grounded answer", grounded: true, value: 0.9))
        await orchestrator.enqueue(question: secretQuestion, timestamp: clock.now(), retrievalHint: nil)
        await notes.waitForCount(1)
        let snapshot = notes.snapshot()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.first?.question, secretQuestion)
        XCTAssertEqual(snapshot.first?.answer, "a grounded answer")

        let calls = await answerMock.calls
        let secretCall = try XCTUnwrap(calls.last)
        XCTAssertTrue(secretCall.user.contains("<redacted:"), "expected the orchestrator's outbound answer prompt to redact the credential")
        XCTAssertFalse(secretCall.user.contains("AKIAIOSFODNN7EXAMPLE"), "raw credential must never reach the llm closure via the answer path")
    }

    // MARK: - 10. Value gate

    func test10_ValueGateDropsBelowThresholdEmitsAtOrAboveIt() async throws {
        let clock = TestClock(Date())
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let notes = NoteRecorder()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock, notes: notes)

        await answerMock.enqueueResponse(answerJSON(answer: "low value answer", grounded: true, value: 0.4))
        await orchestrator.enqueue(question: question(0), timestamp: clock.now(), retrievalHint: nil)
        await answerMock.waitForFinished(1)
        let lowValueNoteLanded = await notes.exceededCount(0, within: .milliseconds(300))
        XCTAssertFalse(lowValueNoteLanded, "value 0.4 is below the 0.5 threshold and must be dropped")

        await answerMock.enqueueResponse(answerJSON(answer: "high value answer", grounded: true, value: 0.6))
        await orchestrator.enqueue(question: question(1), timestamp: clock.now(), retrievalHint: nil)
        await notes.waitForCount(1)
        let snapshot = notes.snapshot()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.first?.answer, "high value answer")
    }

    // MARK: - 11. Answer dedup (0.5) across different questions

    func test11_AnswerDedupDropsNearIdenticalAnswerToDifferentQuestion() async throws {
        let clock = TestClock(Date())
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let notes = NoteRecorder()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock, notes: notes)

        let firstAnswer = "The meeting starts at nine in the morning tomorrow"
        let nearDuplicateAnswer = "The meeting starts at nine tomorrow morning"

        await answerMock.enqueueResponse(answerJSON(answer: firstAnswer, grounded: true, value: 0.9))
        await orchestrator.enqueue(question: question(0), timestamp: clock.now(), retrievalHint: nil)
        await notes.waitForCount(1)
        XCTAssertEqual(notes.snapshot().count, 1)

        await answerMock.enqueueResponse(answerJSON(answer: nearDuplicateAnswer, grounded: true, value: 0.9))
        await orchestrator.enqueue(question: question(1), timestamp: clock.now(), retrievalHint: nil)
        await answerMock.waitForFinished(2)
        let secondNoteLanded = await notes.exceededCount(1, within: .milliseconds(300))
        XCTAssertFalse(secondNoteLanded, "a near-identical answer to a different question must be dropped")
        XCTAssertEqual(notes.snapshot().count, 1)
    }

    // MARK: - 12. Outbound redaction

    func test12_RedactsSensitiveDataFromOutboundUserPrompt() async throws {
        let clock = TestClock(Date())
        let listenerMock = MockLLM()
        let answerMock = MockLLM()
        let corpus = try await makeCorpusService()
        let orchestrator = makeOrchestrator(llm: answerMock, corpusService: corpus, clock: clock)
        let listener = SidecastQuestionListener(orchestrator: orchestrator, llm: listenerMock, now: { clock.now() })

        let secretKey = "AKIAIOSFODNN7EXAMPLE"
        await listener.noteUtterance(text: "my access key is \(secretKey)", at: clock.now())
        await listener.noteUtterance(text: "please do not share it with anyone", at: clock.now())
        await listenerMock.waitForStarted(1)

        let calls = await listenerMock.calls
        XCTAssertEqual(calls.count, 1)
        let outboundUser = calls[0].user
        XCTAssertTrue(outboundUser.contains("<redacted:"), "expected a redaction marker in the outbound prompt")
        XCTAssertFalse(outboundUser.contains(secretKey), "the raw credential must never reach the llm closure")
    }
}

// MARK: - Production SidecastLLM conformance: prompt/schema pass-through

final class OpenRouterSidecastLLMTests: XCTestCase {
    /// Pulled out of `OpenRouterSidecastLLM.call` specifically so the
    /// pass-through shape can be checked without a network round trip —
    /// `OpenRouterClient.complete(...)` itself is exercised only at the
    /// static/pure-function level elsewhere (`OpenRouterClientTests`), never
    /// against a live or stubbed endpoint; this test stays consistent with
    /// that and checks the adapter's own contribution: it forwards system
    /// and user text verbatim into the two chat messages.
    func testBuildMessagesForwardsSystemAndUserVerbatim() {
        let messages = OpenRouterSidecastLLM.buildMessages(system: "SYSTEM PROMPT", user: "USER PROMPT")

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[0].content, "SYSTEM PROMPT")
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[1].content, "USER PROMPT")
    }

    /// Compiles only if `OpenRouterSidecastLLM` genuinely satisfies
    /// `SidecastLLM` and forwards its construction parameters untouched —
    /// the production conformance the brief asks for, proven without a
    /// network call.
    func testAdapterConformsToSidecastLLMAndRetainsConstructionParameters() {
        let adapter = OpenRouterSidecastLLM(
            client: OpenRouterClient(),
            apiKey: "sk-or-v1-test",
            model: "test-model",
            maxTokens: 256,
            temperature: 0.2
        )

        let llm: any SidecastLLM = adapter
        XCTAssertTrue(llm is OpenRouterSidecastLLM)
        XCTAssertEqual(adapter.apiKey, "sk-or-v1-test")
        XCTAssertEqual(adapter.model, "test-model")
        XCTAssertEqual(adapter.maxTokens, 256)
        XCTAssertEqual(adapter.temperature, 0.2)
    }
}
