import Foundation
import XCTest

@testable import OpenOatsKit

final class SidecastWhiteboardModelTests: XCTestCase {

    // MARK: - Fixture helpers

    private func note(_ question: String, _ answer: String, at date: Date) -> SidecastAnsweredNote {
        SidecastAnsweredNote(question: question, answer: answer, timestamp: date)
    }

    // MARK: - 1. Note append, ordering, and session-relative mm:ss formatting

    @MainActor
    func testReceiveAppendsNotesInOrderWithSessionRelativeTimeFormatting() {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let model = SidecastWhiteboardModel()
        model.sessionStart = sessionStart

        model.receive(note: note("First question", "First answer", at: sessionStart.addingTimeInterval(5)))
        model.receive(note: note("Second question", "Second answer", at: sessionStart.addingTimeInterval(65)))
        model.receive(note: note("Third question", "Third answer", at: sessionStart.addingTimeInterval(3_725)))

        XCTAssertEqual(model.notes.map(\.question), ["First question", "Second question", "Third question"])
        XCTAssertEqual(model.notes.map(\.answer), ["First answer", "Second answer", "Third answer"])

        XCTAssertEqual(model.sessionRelativeTime(for: sessionStart.addingTimeInterval(5)), "0:05")
        XCTAssertEqual(model.sessionRelativeTime(for: sessionStart.addingTimeInterval(65)), "1:05")
        XCTAssertEqual(model.sessionRelativeTime(for: sessionStart.addingTimeInterval(3_725)), "62:05")
        // A timestamp before sessionStart (clock skew, or no session yet)
        // floors at zero rather than going negative.
        XCTAssertEqual(model.sessionRelativeTime(for: sessionStart.addingTimeInterval(-10)), "0:00")
    }

    @MainActor
    func testSessionRelativeTimeWithNoSessionStartReadsAsZero() {
        let model = SidecastWhiteboardModel()
        XCTAssertNil(model.sessionStart)
        XCTAssertEqual(model.sessionRelativeTime(for: Date(timeIntervalSince1970: 1_700_000_500)), "0:00")
    }

    // MARK: - 2. Status transitions, including answering counts

    @MainActor
    func testStatusTransitionsDriveTextDotColorAndPulsing() {
        let model = SidecastWhiteboardModel()

        XCTAssertEqual(model.status, .ready)
        XCTAssertEqual(model.statusText, "Ready")
        XCTAssertEqual(model.statusDotColor, .gray)
        XCTAssertFalse(model.isStatusPulsing)

        model.status = .live
        XCTAssertEqual(model.statusText, "Live — listening")
        XCTAssertEqual(model.statusDotColor, .green)
        XCTAssertTrue(model.isStatusPulsing, "only .live pulses")

        model.status = .answering(count: 1)
        XCTAssertEqual(model.statusText, "Answering 1 question…", "singular phrasing for exactly one")
        XCTAssertEqual(model.statusDotColor, .amber)
        XCTAssertFalse(model.isStatusPulsing)

        model.status = .answering(count: 3)
        XCTAssertEqual(model.statusText, "Answering 3 questions…", "plural phrasing for more than one")
        XCTAssertEqual(model.statusDotColor, .amber)

        model.status = .paused
        XCTAssertEqual(model.statusText, "Paused")
        XCTAssertEqual(model.statusDotColor, .green)
        XCTAssertFalse(model.isStatusPulsing)

        model.status = .error("Corpus unreadable — permission denied")
        XCTAssertEqual(model.statusText, "Corpus unreadable — permission denied", "error text passes the message through verbatim")
        XCTAssertEqual(model.statusDotColor, .red)
        XCTAssertFalse(model.isStatusPulsing)

        model.status = .ended
        XCTAssertEqual(model.statusText, "Ended")
        XCTAssertEqual(model.statusDotColor, .gray)
        XCTAssertFalse(model.isStatusPulsing, "a stopped session's board is not receiving anything new")
    }

    // MARK: - 3. Diagnostic line content

    @MainActor
    func testDiagLineContentTracksCountersAndStaysEmptyWhenNothingHasHappened() {
        let model = SidecastWhiteboardModel()

        XCTAssertEqual(model.diagText, "", "nothing heard/listened and not live — the strip stays blank, matching the bench")

        model.noteDiagHeard()
        XCTAssertEqual(model.diagText, "heard 1 · listens 0 · questions 0 · answers 0")

        model.noteDiagHeard()
        model.noteDiagListen()
        model.noteDiagQuestions(2)
        model.noteDiagAnswer()
        XCTAssertEqual(model.diagText, "heard 2 · listens 1 · questions 2 · answers 1")

        model.noteDiagQuestions(3)
        XCTAssertEqual(model.diagText, "heard 2 · listens 1 · questions 5 · answers 1", "noteDiagQuestions accumulates by the given count")
    }

    /// WB-4 guard fix: `questionsCount`/`answersCount` moving independently
    /// of `heardCount`/`listensCount` (as they can once a live coordinator —
    /// rather than this model's own lockstep test helpers — drives them)
    /// must still flip the strip visible, not just stay silently blank.
    @MainActor
    func testDiagLineIsVisibleWhenOnlyQuestionsOrAnswersCounterIsNonzero() {
        let questionsOnly = SidecastWhiteboardModel()
        questionsOnly.noteDiagQuestions(1)
        XCTAssertEqual(questionsOnly.diagText, "heard 0 · listens 0 · questions 1 · answers 0")

        let answersOnly = SidecastWhiteboardModel()
        answersOnly.receive(note: note("Q", "A", at: Date()))
        XCTAssertEqual(answersOnly.diagText, "heard 0 · listens 0 · questions 0 · answers 1")
    }

    @MainActor
    func testDiagLineIsVisibleWhenLiveEvenBeforeAnythingIsHeard() {
        let model = SidecastWhiteboardModel()
        model.status = .live
        XCTAssertEqual(model.diagText, "heard 0 · listens 0 · questions 0 · answers 0")
    }

    @MainActor
    func testReceiveIncrementsAnswersDiagCounter() {
        let model = SidecastWhiteboardModel()
        // Realistic causality: an answer only ever lands after something was
        // heard (matches the bench's segments-accumulate -> listen -> answer
        // chain) — `diagText`'s own visibility gate keys off heard/listens/
        // live, same as the bench's `renderDiag`, so heard must be nonzero
        // here for the assertion below to be meaningful.
        model.noteDiagHeard()
        model.receive(note: note("Q", "A", at: Date()))
        XCTAssertEqual(model.answersCount, 1)
        XCTAssertTrue(model.diagText.contains("answers 1"))
    }

    // MARK: - 4. Export — exact text format

    @MainActor
    func testExportTextExactStringWithoutConfiguredModel() {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let model = SidecastWhiteboardModel()
        model.sessionStart = sessionStart
        model.receive(note: note("What year did the acquisition close", "2019.", at: sessionStart.addingTimeInterval(5)))
        model.receive(note: note("Who is the general manager", "Jordan Alvarez.", at: sessionStart.addingTimeInterval(70)))

        let now = Date(timeIntervalSince1970: 1_700_010_000)
        let expectedPreamble = "Whiteboard notes — \(ISO8601DateFormatter().string(from: now))"
        let expected = [
            expectedPreamble,
            "",
            "[0:05] What year did the acquisition close",
            "2019.",
            "",
            "[1:10] Who is the general manager",
            "Jordan Alvarez.",
            "",
        ].joined(separator: "\n")

        XCTAssertEqual(model.exportText(now: now), expected)
    }

    @MainActor
    func testExportTextIncludesModelLineWhenConfigured() {
        let model = SidecastWhiteboardModel(configuredModel: "anthropic/claude-sonnet")
        let now = Date(timeIntervalSince1970: 1_700_010_000)

        let expected = [
            "Whiteboard notes — \(ISO8601DateFormatter().string(from: now))",
            "Model: anthropic/claude-sonnet",
            "",
        ].joined(separator: "\n")

        XCTAssertEqual(model.exportText(now: now), expected)
    }

    // MARK: - 5. Export — JSON decode-and-assert

    private struct DecodedExportNote: Decodable, Equatable {
        let timestamp: String
        let question: String
        let text: String
    }

    private struct DecodedExportPayload: Decodable, Equatable {
        let exportedAt: String
        let model: String?
        let notes: [DecodedExportNote]
        let totalNotes: Int
    }

    @MainActor
    func testExportJSONDecodesToExpectedShapeWithConfiguredModel() throws {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let model = SidecastWhiteboardModel(configuredModel: "anthropic/claude-sonnet")
        model.sessionStart = sessionStart
        model.receive(note: note("What year did the acquisition close", "2019.", at: sessionStart.addingTimeInterval(5)))

        let now = Date(timeIntervalSince1970: 1_700_010_000)
        let data = try model.exportJSON(now: now)
        let decoded = try JSONDecoder().decode(DecodedExportPayload.self, from: data)

        XCTAssertEqual(decoded.exportedAt, ISO8601DateFormatter().string(from: now))
        XCTAssertEqual(decoded.model, "anthropic/claude-sonnet")
        XCTAssertEqual(decoded.totalNotes, 1)
        XCTAssertEqual(
            decoded.notes,
            [DecodedExportNote(timestamp: "0:05", question: "What year did the acquisition close", text: "2019.")]
        )
    }

    @MainActor
    func testExportJSONOmitsModelKeyEntirelyWhenNotConfigured() throws {
        let model = SidecastWhiteboardModel()
        let data = try model.exportJSON(now: Date())

        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertFalse(raw.keys.contains("model"), "model must be omitted entirely, not encoded as null, when unconfigured")

        let decoded = try JSONDecoder().decode(DecodedExportPayload.self, from: data)
        XCTAssertNil(decoded.model)
        XCTAssertEqual(decoded.totalNotes, 0)
        XCTAssertEqual(decoded.notes, [])
    }

    // MARK: - 5b. WB-5/I4: write failures propagate instead of vanishing silently
    //
    // `SidecastWhiteboardView`'s export actions drive a modal `NSSavePanel`
    // with no test harness in this codebase (same as `SidecastCorpusBookmark
    // .pick()` — maintainer-verified only, per that type's own doc comment).
    // These two tests exercise the identical throwing write path
    // (`writeExportText(to:)`/`writeExportJSON(to:)`, which the view now
    // calls) one level down, at the model, with a URL guaranteed to fail to
    // write (a parent directory that does not exist) — the level this repo
    // achieves for a save-panel-gated action.

    @MainActor
    func testWriteExportTextThrowsWhenTheDestinationIsUnwritable() {
        let model = SidecastWhiteboardModel()
        model.receive(note: note("Q", "A", at: Date()))
        let unwritableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecast-whiteboard-model-missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("whiteboard.txt")
        XCTAssertThrowsError(try model.writeExportText(to: unwritableURL))
    }

    @MainActor
    func testWriteExportJSONThrowsWhenTheDestinationIsUnwritable() {
        let model = SidecastWhiteboardModel()
        model.receive(note: note("Q", "A", at: Date()))
        let unwritableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecast-whiteboard-model-missing-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("whiteboard.json")
        XCTAssertThrowsError(try model.writeExportJSON(to: unwritableURL))
    }

    // MARK: - 6. Auto-scroll flag transitions

    @MainActor
    func testAutoScrollFlagTransitions() {
        let model = SidecastWhiteboardModel()
        XCTAssertTrue(model.isAutoScroll, "starts following the newest note")

        model.userScrolledUp()
        XCTAssertFalse(model.isAutoScroll)

        model.scrolledToBottom()
        XCTAssertTrue(model.isAutoScroll)
    }

    // MARK: - 7. clear() resets everything

    @MainActor
    func testClearResetsEverything() {
        let model = SidecastWhiteboardModel()
        model.sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        model.status = .live
        model.userScrolledUp()
        model.noteDiagHeard()
        model.noteDiagListen()
        model.noteDiagQuestions(2)
        model.receive(note: note("Q", "A", at: Date(timeIntervalSince1970: 1_700_000_100)))

        model.clear()

        XCTAssertEqual(model.notes, [])
        XCTAssertNil(model.sessionStart)
        XCTAssertEqual(model.status, .ready)
        XCTAssertTrue(model.isAutoScroll)
        XCTAssertEqual(model.heardCount, 0)
        XCTAssertEqual(model.listensCount, 0)
        XCTAssertEqual(model.questionsCount, 0)
        XCTAssertEqual(model.answersCount, 0)
        XCTAssertEqual(model.diagText, "")
    }

    @MainActor
    func testClearPreservesConfiguredModel() {
        let model = SidecastWhiteboardModel(configuredModel: "anthropic/claude-sonnet")
        model.clear()
        XCTAssertEqual(model.configuredModel, "anthropic/claude-sonnet", "clearing the board is not a settings change")
    }
}
