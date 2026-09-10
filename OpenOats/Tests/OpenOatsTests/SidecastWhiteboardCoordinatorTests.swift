import Foundation
import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

/// End-to-end native whiteboard regressions: actual detector, selected pack,
/// evidence resolver and presentation. No provider, microphone or private data.
@MainActor
final class SidecastWhiteboardCoordinatorTests: XCTestCase {
  private func fixture(_ name: String = "minimal-hospitality") -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/\(name)")
  }

  private func makeSettings(enabled: Bool = true) -> AppSettings {
    let name = "com.openoats.tests.verified-whiteboard.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    addTeardownBlock { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(
      storage: AppSettingsStorage(
        defaults: defaults, secretStore: .ephemeral,
        defaultNotesDirectory: FileManager.default.temporaryDirectory,
        runMigrations: false))
    settings.sidecastWhiteboardEnabled = enabled
    return settings
  }

  private func makeStore(_ name: String = "minimal-hospitality") async -> KnowledgePackStore {
    let store = KnowledgePackStore(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))
    await store.load(fromPath: fixture(name).path)
    return store
  }

  private func drain(
    _ store: KnowledgePackStore, file: StaticString = #filePath, line: UInt = #line
  ) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while store.activeTieredAnswerTaskCount > 0, ContinuousClock.now < deadline {
      await Task.yield()
    }
    XCTAssertEqual(
      store.activeTieredAnswerTaskCount, 0, "Pipeline did not quiesce", file: file, line: line)
  }

  private func ask(_ question: String, on coordinator: SidecastWhiteboardCoordinator) async {
    coordinator.receive(utteranceText: question, speaker: .them, at: Date())
    await drain(coordinator.knowledgePackStore)
  }

  func testDisabledFeatureDoesNotProcessSpeech() async {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(
      knowledgePackStore: store, settings: makeSettings(enabled: false))
    board.sessionStarted(at: Date())
    await ask("What was RevPAR for this asset in 2020?", on: board)
    XCTAssertTrue(board.model.notes.isEmpty)
    XCTAssertEqual(store.tieredAnswerTaskStartCount, 0)
    XCTAssertEqual(board.model.status, .paused)
  }

  func testNoCorpusNeverFallsBackToGeneralKnowledge() async {
    let store = KnowledgePackStore(profileRegistry: .empty)
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    await ask("What did this asset earn?", on: board)
    XCTAssertTrue(board.model.notes.isEmpty)
    XCTAssertTrue(board.model.corpusStatusLineIsError)
    XCTAssertTrue(board.model.corpusStatusLine?.contains("disabled") == true)
  }

  func testSingleQuestionFollowedBySilenceProducesCitedLocalAnswer() async throws {
    let store = await makeStore()
    let settings = makeSettings()
    settings.llmProvider = .ollama
    settings.openRouterApiKey = ""
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: settings)
    board.sessionStarted(at: Date(), sessionID: "session-test")
    await ask("What was RevPAR for this asset in 2020?", on: board)
    let note = try XCTUnwrap(board.model.notes.last)
    XCTAssertTrue(note.answer.contains("$89.50"))
    XCTAssertEqual(note.evidence?.evidenceState, .calculated)
    XCTAssertEqual(note.evidence?.sessionID, "session-test")
    XCTAssertEqual(note.evidence?.packContentHash, store.searchIndex?.packContentHash)
    XCTAssertFalse(note.evidence?.sources.isEmpty ?? true)
    XCTAssertEqual(note.evidence?.engine, "local-knowledge-pack")
    XCTAssertEqual(board.model.status, .live)
  }

  func testMissingPeriodProducesAbstentionInsteadOfWrongYear() async throws {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    await ask("What was RevPAR for this asset in 2020?", on: board)
    await ask("What was RevPAR in 2018?", on: board)
    let note = try XCTUnwrap(board.model.notes.last)
    XCTAssertEqual(note.evidence?.evidenceState, .notFoundInCorpus)
    XCTAssertFalse(note.answer.contains("$89.50"))
    XCTAssertGreaterThanOrEqual(board.model.notes.count, 2)
  }

  func testChangedYearIsNotLexicallyDeduplicated() async {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    await ask("What was the reported RevPAR for this particular asset in 2020?", on: board)
    let count = store.tieredAnswerTaskStartCount
    await ask("What was the reported RevPAR for this particular asset in 2021?", on: board)
    XCTAssertGreaterThan(store.tieredAnswerTaskStartCount, count)
    XCTAssertFalse(board.model.notes.last?.answer.contains("2021 RevPAR was $89.50") == true)
  }

  func testConflictingSourcesRemainContestedWithBothCitations() async throws {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    await ask("Do all sources agree on 2020 RevPAR?", on: board)
    let note = try XCTUnwrap(board.model.notes.last)
    XCTAssertEqual(note.evidence?.evidenceState, .contested)
    XCTAssertGreaterThanOrEqual(note.evidence?.sources.count ?? 0, 2)
    XCTAssertTrue(note.answer.contains("$89.50"))
    XCTAssertTrue(note.answer.contains("$92"))
  }

  func testClearSynchronouslyRetiresQueuedAnswersAndAllowsFreshQuestions() async {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    board.receive(
      utteranceText: "What was RevPAR for this asset in 2020?", speaker: .them, at: Date())
    XCTAssertGreaterThan(store.activeTieredAnswerTaskCount, 0)
    board.clear()
    XCTAssertEqual(store.activeTieredAnswerTaskCount, 0)
    XCTAssertTrue(board.model.notes.isEmpty)
    await ask("What was RevPAR in 2018?", on: board)
    XCTAssertTrue(board.model.notes.allSatisfy { $0.question.contains("2018") })
  }

  func testOldSessionCannotPublishAfterNewSessionStarts() async throws {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date(), sessionID: "old")
    board.receive(
      utteranceText: "What was RevPAR for this asset in 2020?", speaker: .them, at: Date())
    board.sessionEnded()
    board.sessionStarted(at: Date(), sessionID: "new")
    await ask("What was RevPAR in 2018?", on: board)
    XCTAssertFalse(board.model.notes.isEmpty)
    XCTAssertTrue(
      board.model.notes.allSatisfy {
        $0.evidence?.sessionID == "new" && $0.question.contains("2018")
      })
  }

  func testEndStopsQueuedAndSubsequentWorkButPreservesAcceptedNotes() async {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    await ask("What was RevPAR for this asset in 2020?", on: board)
    let accepted = board.model.notes
    board.receive(utteranceText: "What was RevPAR in 2018?", speaker: .them, at: Date())
    board.sessionEnded()
    await ask("What was 2020 occupancy?", on: board)
    XCTAssertEqual(board.model.notes, accepted)
    XCTAssertEqual(store.activeTieredAnswerTaskCount, 0)
    XCTAssertEqual(board.model.status, .ended)
    board.clear()
    XCTAssertEqual(board.model.status, .ended)
  }

  func testDisablementDoesNotNeedAnotherUtteranceToRejectPublication() async {
    let store = await makeStore()
    let settings = makeSettings()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: settings)
    board.sessionStarted(at: Date())
    board.receive(
      utteranceText: "What was RevPAR for this asset in 2020?", speaker: .them, at: Date())
    settings.sidecastWhiteboardEnabled = false
    await drain(store)
    XCTAssertTrue(board.model.notes.isEmpty)
    board.settingsChanged()
    XCTAssertEqual(board.model.status, .paused)
    XCTAssertEqual(store.activeTieredAnswerTaskCount, 0)
  }

  func testProviderChangeCannotStartIndependentCloudAnswer() async throws {
    let store = await makeStore()
    let settings = makeSettings()
    settings.openRouterApiKey = "synthetic-unused-key"
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: settings)
    board.sessionStarted(at: Date())
    board.receive(
      utteranceText: "What was RevPAR for this asset in 2020?", speaker: .them, at: Date())
    settings.llmProvider = .ollama
    await drain(store)
    XCTAssertEqual(try XCTUnwrap(board.model.notes.last).evidence?.engine, "local-knowledge-pack")
    XCTAssertEqual(store.networkMode, .offline)
    // The shipping coordinator has no SidecastLLM/provider dependency.
  }

  func testFailedCorpusSwitchPausesRatherThanAnsweringFromLastGoodPack() async {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    board.receive(
      utteranceText: "What was RevPAR for this asset in 2020?", speaker: .them, at: Date())
    await store.load(fromPath: fixture("nonexistent-synthetic-pack").path)
    await ask("What was 2020 occupancy?", on: board)
    XCTAssertNil(store.selectedPack)
    XCTAssertTrue(board.model.notes.isEmpty)
    XCTAssertTrue(board.model.corpusStatusLineIsError)
    XCTAssertEqual(store.activeTieredAnswerTaskCount, 0)
  }

  func testSuccessfulSwitchPreservesOldNoteIdentityButRetiresIt() async throws {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    await ask("What was RevPAR for this asset in 2020?", on: board)
    let hash = try XCTUnwrap(board.model.notes.last?.evidence?.packContentHash)
    await store.load(fromPath: fixture("nestarc-product-pitch").path)
    XCTAssertEqual(board.model.notes.first?.evidence?.packContentHash, hash)
    XCTAssertTrue(board.model.notes.first?.isSuperseded == true)
    XCTAssertNotEqual(store.searchIndex?.packContentHash, hash)
  }

  func testPartialQuestionIsRevisedRatherThanDuplicated() async {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    board.receivePartial(text: "what was revpar for this asset", speaker: .them, at: Date())
    await drain(store)
    await ask("What was RevPAR for this asset in 2020?", on: board)
    XCTAssertEqual(board.model.notes.count, 1)
    XCTAssertFalse(board.model.notes.last?.evidence?.isProvisional ?? true)
  }

  func testExportsCarryEvidenceAndNeverPretendTheConfiguredCloudModelWasUsed() async throws {
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    await ask("What was RevPAR for this asset in 2020?", on: board)
    let data = try board.model.exportJSON()
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(text.contains("packContentHash"))
    XCTAssertTrue(text.contains("local-knowledge-pack"))
    XCTAssertTrue(text.contains("sources"))
    XCTAssertTrue(board.model.exportText().contains("Source:"))
  }

  func testEnablingDuringAnExistingSessionUsesItsActualIdentity() async {
    let store = await makeStore()
    let settings = makeSettings()
    settings.sidecastWhiteboardEnabled = false
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: settings)
    board.sessionStarted(at: Date(), sessionID: "already-recording")
    settings.sidecastWhiteboardEnabled = true
    board.settingsChanged()
    await ask("What was RevPAR for this asset in 2020?", on: board)
    XCTAssertEqual(board.model.notes.first?.evidence?.sessionID, "already-recording")
  }

  func testHistoricalDiscussionUsesGenericEvidenceStatesAndIgnoresDocumentInstructions()
    async throws
  {
    let store = KnowledgePackStore(profileRegistry: .empty)
    await store.load(fromPath: fixture("aster-history-discussion").path)
    guard case .loaded = store.state else {
      XCTFail("Historical pack failed validation: \(store.state)")
      return
    }
    let readiness = WhiteboardPackReadiness(pack: try XCTUnwrap(store.selectedPack))
    XCTAssertEqual(readiness.totalQuestionFamilies, 4)
    XCTAssertEqual(readiness.reviewedQuestionFamilies, 4)
    XCTAssertEqual(readiness.knownGaps, 1)
    XCTAssertEqual(readiness.disagreements, 1)
    XCTAssertEqual(readiness.cardsAwaitingReview, 0)
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date())
    let cases: [(String, KnowledgeEvidenceState, String, Int)] = [
      ("Where did the Aster council meet?", .directlySourced, "north hall", 1),
      ("Do the accounts agree on the Aster council year?", .contested, "413", 2),
      ("Why might the Aster accounts differ?", .interpretive, "not proof", 1),
      ("Who chaired the Aster council?", .notFoundInCorpus, "does not identify", 0),
    ]
    for (question, state, fragment, sourceCount) in cases {
      board.clear()
      await ask(question, on: board)
      let note = try XCTUnwrap(board.model.notes.last, question)
      XCTAssertEqual(note.evidence?.evidenceState, state, question)
      XCTAssertTrue(note.answer.contains(fragment), question)
      XCTAssertEqual(note.evidence?.sources.count, sourceCount, question)
      XCTAssertFalse(note.answer.contains("SECRET-SENTINEL"))
      XCTAssertEqual(note.evidence?.packID, "aster-history-discussion-v1")
    }
  }

  func testThreeDomainPreparedReplayRecordsLocalLatencyAndNeverCallsAnAnswerModel() async throws {
    let cases = [
      ("minimal-hospitality", "What was RevPAR for this asset in 2020?", "$89.50"),
      ("nestarc-product-pitch", "What is NestArc Go?", "modular organizer insert"),
      ("aster-history-discussion", "Where did the Aster council meet?", "north hall"),
    ]
    var milliseconds: [Double] = []
    for (pack, question, fragment) in cases {
      let store = await makeStore(pack)
      let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
      board.sessionStarted(at: Date())
      for _ in 0..<10 {
        board.clear()
        let started = ContinuousClock.now
        await ask(question, on: board)
        let elapsed = started.duration(to: .now).components
        milliseconds.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        let note = try XCTUnwrap(board.model.notes.last, pack)
        XCTAssertTrue(note.answer.contains(fragment), pack)
        XCTAssertFalse(note.evidence?.sources.isEmpty ?? true, pack)
        XCTAssertEqual(note.evidence?.engine, "local-knowledge-pack")
      }
    }
    milliseconds.sort()
    print(
      "WHITEBOARD_LOCAL_REPLAY samples=\(milliseconds.count) p50_ms=\(milliseconds[14]) p95_ms=\(milliseconds[28]) max_ms=\(milliseconds[29]) answer_model_calls=0"
    )
    // Observational only: a loaded-pack, synthetic, final-question-to-model
    // replay. It excludes capture/STT, cold loading and actual UI rendering.
  }

  func testAcceptedNotesSurviveClearNewSessionAndRepositoryReopen() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "whiteboard-save-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = SessionRepository(rootDirectory: root)
    let first = await repository.startSession()
    let store = await makeStore()
    let settings = makeSettings()
    let board = SidecastWhiteboardCoordinator(
      knowledgePackStore: store, settings: settings, repository: repository)
    board.sessionStarted(at: Date(), sessionID: first.sessionID)
    await ask("What was RevPAR for this asset in 2020?", on: board)
    board.clear()  // Clear the display, not the saved session history.
    await ask("What was RevPAR in 2018?", on: board)
    await board.flushNotes()
    XCTAssertNil(board.model.storageStatusLine)
    board.sessionEnded()
    let second = await repository.startSession()
    XCTAssertNotEqual(first.sessionID, second.sessionID)
    board.sessionStarted(at: Date(), sessionID: second.sessionID)
    await ask("What was 2020 occupancy?", on: board)
    board.sessionEnded()
    await board.flushNotes()

    let reopened = SessionRepository(rootDirectory: root)
    let loadedFirst = try await reopened.loadWhiteboard(sessionID: first.sessionID)
    let loadedSecond = try await reopened.loadWhiteboard(sessionID: second.sessionID)
    XCTAssertEqual(loadedFirst?.notes.count, 2)
    XCTAssertTrue(
      loadedFirst?.notes.allSatisfy { $0.evidence?.sessionID == first.sessionID } == true)
    XCTAssertEqual(loadedSecond?.notes.count, 1)
    XCTAssertTrue(
      loadedSecond?.notes.allSatisfy { $0.evidence?.sessionID == second.sessionID } == true)
    let restored = SidecastWhiteboardModel()
    restored.restore(try XCTUnwrap(loadedFirst))
    XCTAssertEqual(restored.notes.count, 2)
    XCTAssertEqual(restored.status, .ended)
    XCTAssertTrue(restored.exportText().contains("Source:"))
    // Deterministic save ordering even when both sessions start in one second.
    for (offset, handle) in [first, second].enumerated() {
      let path = root.appendingPathComponent("sessions/\(handle.sessionID)/whiteboard.json").path
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: Double(100 + offset))], ofItemAtPath: path)
    }
    await board.openLastSavedBoard()
    XCTAssertEqual(board.model.notes.first?.evidence?.sessionID, second.sessionID)
    await reopened.moveToRecentlyDeleted(sessionID: second.sessionID)
    let deleted = try await reopened.loadWhiteboard(sessionID: second.sessionID)
    XCTAssertNil(deleted)
    let recoverable = root.appendingPathComponent(
      "sessions/.recently-deleted/\(second.sessionID)/whiteboard.json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: recoverable.path))
  }

  func testWriteFailureIsVisibleAndDoesNotDiscardTheInMemoryAnswer() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "whiteboard-missing-session-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = SessionRepository(rootDirectory: root)
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(
      knowledgePackStore: store, settings: makeSettings(), repository: repository)
    board.sessionStarted(at: Date(), sessionID: "session-does-not-exist")
    await ask("What was RevPAR for this asset in 2020?", on: board)
    await board.flushNotes()
    XCTAssertEqual(board.model.notes.count, 1)
    XCTAssertTrue(board.model.storageStatusLine?.contains("could not be saved") == true)
  }

  func testArchiveRejectsTraversalAndMismatchedSessionIdentity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "whiteboard-boundary-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = SessionRepository(rootDirectory: root)
    do {
      _ = try await repository.loadWhiteboard(sessionID: "../outside")
      XCTFail("Traversal must be rejected")
    } catch WhiteboardArchiveError.invalidSession {}
    let handle = await repository.startSession()
    let store = await makeStore()
    let board = SidecastWhiteboardCoordinator(knowledgePackStore: store, settings: makeSettings())
    board.sessionStarted(at: Date(), sessionID: "another-session")
    await ask("What was RevPAR for this asset in 2020?", on: board)
    do {
      try await repository.saveWhiteboardNote(
        try XCTUnwrap(board.model.notes.first), sessionID: handle.sessionID, startedAt: Date())
      XCTFail("Cross-session note must be rejected")
    } catch WhiteboardArchiveError.invalidArchive {}
  }
}
