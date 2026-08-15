import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeStudyImportApplierTests: XCTestCase {
  func testPlanIsReadyAndDoesNotModifyPackFiles() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let approvedImport = try makeApprovedImport(packDirectory: directory)
    let before = try mutableFileData(in: directory)

    let plan = try makeApplier().plan(
      approvedImport: approvedImport,
      packDirectory: directory
    )

    XCTAssertEqual(plan.state, .ready)
    XCTAssertEqual(plan.activePackContentHash, approvedImport.basePackContentHash)
    XCTAssertEqual(plan.approvedQuestionFamilyIDs, ["question-revpar-reconciliation-2020"])
    XCTAssertEqual(plan.approvedResponseCardIDs, ["card-revpar-reconciliation-2020"])
    XCTAssertEqual(try mutableFileData(in: directory), before)
  }

  func testApplyInstallsOnlyReviewedApprovedRecordsAndReturnsReceipt() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let approvedImport = try makeApprovedImport(packDirectory: directory)
    let appliedAt = Date(timeIntervalSince1970: 1_787_072_400)
    let applier = makeApplier(now: { appliedAt })

    let receipt = try applier.apply(approvedImport: approvedImport, to: directory)
    let pack = try loadPack(from: directory)
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)

    XCTAssertEqual(receipt.outcome, .applied)
    XCTAssertEqual(receipt.appliedAt, appliedAt)
    XCTAssertFalse(receipt.recoveredInterruptedTransaction)
    XCTAssertEqual(bundle.packContentHash, approvedImport.resultingPackContentHash)
    XCTAssertEqual(
      pack.questionFamilies.first { $0.id == "question-revpar-reconciliation-2020" },
      approvedImport.approvedQuestionFamilies.first
    )
    XCTAssertEqual(
      pack.responseCards.first { $0.id == "card-revpar-reconciliation-2020" }?.reviewStatus,
      .reviewed
    )
    XCTAssertFalse(transactionArtifactsExist(in: directory))
  }

  func testApplyingSameArtifactTwiceIsIdempotent() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let approvedImport = try makeApprovedImport(packDirectory: directory)
    let applier = makeApplier()
    _ = try applier.apply(approvedImport: approvedImport, to: directory)
    let afterFirstApply = try mutableFileData(in: directory)

    let secondReceipt = try applier.apply(approvedImport: approvedImport, to: directory)
    let pack = try loadPack(from: directory)

    XCTAssertEqual(secondReceipt.outcome, .alreadyApplied)
    XCTAssertEqual(
      secondReceipt.previousPackContentHash,
      approvedImport.resultingPackContentHash
    )
    XCTAssertEqual(try mutableFileData(in: directory), afterFirstApply)
    XCTAssertEqual(
      pack.questionFamilies.filter { $0.id == "question-revpar-reconciliation-2020" }.count,
      1
    )
    XCTAssertEqual(
      pack.responseCards.filter { $0.id == "card-revpar-reconciliation-2020" }.count,
      1
    )
  }

  func testStalePackFailsBeforeMutation() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let approvedImport = try makeApprovedImport(packDirectory: directory)
    try appendJSONLine(
      KnowledgeQuestionFamily(
        id: "question-added-after-approval",
        canonicalQuestion: "Was this question added after approval?",
        variants: []
      ),
      to: directory.appendingPathComponent("question-families.jsonl")
    )
    let beforeAttempt = try mutableFileData(in: directory)

    XCTAssertThrowsError(try makeApplier().apply(approvedImport: approvedImport, to: directory)) {
      error in
      guard case KnowledgeStudyImportApplicationError.stalePack = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try mutableFileData(in: directory), beforeAttempt)
    XCTAssertFalse(transactionArtifactsExist(in: directory))
  }

  func testTamperedResultHashFailsBeforeMutation() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try makeApprovedImport(packDirectory: directory)
    let tampered = copy(
      original,
      resultingPackContentHash: String(repeating: "0", count: 64)
    )
    let before = try mutableFileData(in: directory)

    XCTAssertThrowsError(try makeApplier().apply(approvedImport: tampered, to: directory)) {
      error in
      guard case KnowledgeStudyImportApplicationError.resultingHashMismatch = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try mutableFileData(in: directory), before)
    XCTAssertFalse(transactionArtifactsExist(in: directory))
  }

  func testApprovedCardMustStillBeMarkedReviewed() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try makeApprovedImport(packDirectory: directory)
    let card = try XCTUnwrap(original.approvedResponseCards.first)
    let generatedCard = KnowledgeResponseCard(
      id: card.id,
      title: card.title,
      answer: card.answer,
      evidenceState: card.evidenceState,
      questionFamilyIDs: card.questionFamilyIDs,
      assertionIDs: card.assertionIDs,
      citationPassageIDs: card.citationPassageIDs,
      calculationIDs: card.calculationIDs,
      reviewStatus: .generated
    )
    let tampered = copy(original, approvedResponseCards: [generatedCard])

    XCTAssertThrowsError(try makeApplier().apply(approvedImport: tampered, to: directory)) {
      error in
      guard case KnowledgeStudyImportApplicationError.responseCardNotReviewed(let id) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(id, card.id)
    }
  }

  func testApprovedRecordsMustExactlyMatchApprovalDecisions() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try makeApprovedImport(packDirectory: directory)
    let missingApprovedCard = copy(original, approvedResponseCards: [])

    XCTAssertThrowsError(
      try makeApplier().apply(approvedImport: missingApprovedCard, to: directory)
    ) { error in
      guard
        case KnowledgeStudyImportApplicationError.approvedRecordsDoNotMatchDecisions(let kind) =
          error
      else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(kind, .responseCard)
    }
  }

  func testFailureAfterFirstInstallRollsBackBothFiles() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let approvedImport = try makeApprovedImport(packDirectory: directory)
    let before = try mutableFileData(in: directory)
    let applier = makeApplier(mutationHook: { step in
      if step == .questionFamiliesInstalled {
        throw SyntheticMutationError.interrupted
      }
    })

    XCTAssertThrowsError(try applier.apply(approvedImport: approvedImport, to: directory)) {
      error in
      guard case KnowledgeStudyImportApplicationError.transactionFailed = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try mutableFileData(in: directory), before)
    XCTAssertEqual(
      try KnowledgeStudyBundleBuilder().build(from: loadPack(from: directory)).packContentHash,
      approvedImport.basePackContentHash
    )
    XCTAssertFalse(transactionArtifactsExist(in: directory))
  }

  func testNextApplyRecoversInterruptedMixedStateBeforeInstalling() throws {
    let directory = try makeTemporaryPack()
    let donorDirectory = try makeTemporaryPack()
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: donorDirectory)
    }
    let approvedImport = try makeApprovedImport(packDirectory: directory)
    _ = try makeApplier().apply(approvedImport: approvedImport, to: donorDirectory)

    let questionURL = directory.appendingPathComponent("question-families.jsonl")
    let questionBackupName = ".knowledge-copilot-recovery-questions.backup"
    let questionBackupURL = directory.appendingPathComponent(questionBackupName)
    try FileManager.default.moveItem(at: questionURL, to: questionBackupURL)
    try Data(
      contentsOf: donorDirectory.appendingPathComponent("question-families.jsonl")
    ).write(to: questionURL)

    let responseStagedName = ".knowledge-copilot-recovery-cards.staged"
    try Data(
      contentsOf: donorDirectory.appendingPathComponent("response-cards.jsonl")
    ).write(to: directory.appendingPathComponent(responseStagedName))
    let journal: [String: Any] = [
      "schemaVersion": 1,
      "importID": approvedImport.importID,
      "basePackContentHash": approvedImport.basePackContentHash,
      "resultingPackContentHash": approvedImport.resultingPackContentHash,
      "questionStagedFileName": ".knowledge-copilot-recovery-questions.staged",
      "questionBackupFileName": questionBackupName,
      "responseStagedFileName": responseStagedName,
      "responseBackupFileName": ".knowledge-copilot-recovery-cards.backup",
    ]
    try JSONSerialization.data(withJSONObject: journal).write(
      to: directory.appendingPathComponent(
        ".knowledge-copilot-study-import-transaction.json"
      )
    )

    let receipt = try makeApplier().apply(approvedImport: approvedImport, to: directory)
    let finalHash = try KnowledgeStudyBundleBuilder().build(
      from: loadPack(from: directory)
    ).packContentHash

    XCTAssertEqual(receipt.outcome, .applied)
    XCTAssertTrue(receipt.recoveredInterruptedTransaction)
    XCTAssertEqual(finalHash, approvedImport.resultingPackContentHash)
    XCTAssertFalse(transactionArtifactsExist(in: directory))
  }

  func testRejectOnlyImportIsAValidatedNoOp() throws {
    let directory = try makeTemporaryPack()
    defer { try? FileManager.default.removeItem(at: directory) }
    let approvedImport = try makeApprovedImport(
      packDirectory: directory,
      questionDisposition: .reject,
      cardDisposition: .reject
    )
    let before = try mutableFileData(in: directory)

    let receipt = try makeApplier().apply(approvedImport: approvedImport, to: directory)

    XCTAssertEqual(receipt.outcome, .noChanges)
    XCTAssertEqual(approvedImport.basePackContentHash, approvedImport.resultingPackContentHash)
    XCTAssertEqual(try mutableFileData(in: directory), before)
    XCTAssertFalse(transactionArtifactsExist(in: directory))
  }

  private enum SyntheticMutationError: Error {
    case interrupted
  }

  private var reviewDate: Date {
    Date(timeIntervalSince1970: 1_776_441_600)
  }

  private func makeApplier(
    now: @escaping @Sendable () -> Date = Date.init,
    mutationHook: @escaping @Sendable (KnowledgeStudyImportMutationStep) throws -> Void = { _ in }
  ) -> KnowledgeStudyImportApplier {
    KnowledgeStudyImportApplier(
      profileRegistry: registry,
      now: now,
      mutationHook: mutationHook
    )
  }

  private var registry: KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func makeApprovedImport(
    packDirectory: URL,
    questionDisposition: KnowledgeStudyReviewDisposition = .approve,
    cardDisposition: KnowledgeStudyReviewDisposition = .approve
  ) throws -> KnowledgeStudyApprovedImport {
    let pack = try loadPack(from: packDirectory)
    let analysis = try JSONDecoder().decode(
      KnowledgeStudyAnalysis.self,
      from: Data(contentsOf: analysisURL())
    )
    let queue = try KnowledgeStudyAnalysisValidator().makeReviewQueue(
      analysis: analysis,
      bundle: KnowledgeStudyBundleBuilder().build(from: pack)
    )
    let decisions = KnowledgeStudyReviewDecisionSet(
      schemaVersion: 1,
      queueID: queue.queueID,
      analysisID: queue.analysis.analysisID,
      bundleID: queue.analysis.bundleID,
      reviewer: "Synthetic Fixture Reviewer",
      reviewedAt: reviewDate,
      decisions: [
        KnowledgeStudyReviewDecision(
          proposalKind: .questionFamily,
          proposalID: "question-revpar-reconciliation-2020",
          disposition: questionDisposition,
          note: "Human question-family decision."
        ),
        KnowledgeStudyReviewDecision(
          proposalKind: .responseCard,
          proposalID: "card-revpar-reconciliation-2020",
          disposition: cardDisposition,
          note: "Human response-card decision."
        ),
      ]
    )
    return try KnowledgeStudyReviewGate(profileRegistry: registry).approve(
      queue: queue,
      decisions: decisions,
      pack: pack
    )
  }

  private func copy(
    _ approvedImport: KnowledgeStudyApprovedImport,
    resultingPackContentHash: String? = nil,
    approvedResponseCards: [KnowledgeResponseCard]? = nil
  ) -> KnowledgeStudyApprovedImport {
    KnowledgeStudyApprovedImport(
      schemaVersion: approvedImport.schemaVersion,
      importID: approvedImport.importID,
      packID: approvedImport.packID,
      basePackContentHash: approvedImport.basePackContentHash,
      resultingPackContentHash: resultingPackContentHash
        ?? approvedImport.resultingPackContentHash,
      sourceBundleID: approvedImport.sourceBundleID,
      sourceAnalysisID: approvedImport.sourceAnalysisID,
      sourceQueueID: approvedImport.sourceQueueID,
      reviewer: approvedImport.reviewer,
      reviewedAt: approvedImport.reviewedAt,
      approvedQuestionFamilies: approvedImport.approvedQuestionFamilies,
      approvedResponseCards: approvedResponseCards ?? approvedImport.approvedResponseCards,
      reviewDecisions: approvedImport.reviewDecisions,
      rejectedDecisions: approvedImport.rejectedDecisions
    )
  }

  private func loadPack(from directory: URL) throws -> KnowledgePack {
    try KnowledgePackLoader(profileRegistry: registry).load(from: directory)
  }

  private func makeTemporaryPack() throws -> URL {
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
      "knowledge-study-import-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.copyItem(at: packURL(), to: destination)
    return destination
  }

  private func mutableFileData(in directory: URL) throws -> [String: Data] {
    [
      "questions": try Data(
        contentsOf: directory.appendingPathComponent("question-families.jsonl")
      ),
      "cards": try Data(contentsOf: directory.appendingPathComponent("response-cards.jsonl")),
    ]
  }

  private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: encoder.encode(value))
    try handle.write(contentsOf: Data("\n".utf8))
  }

  private func transactionArtifactsExist(in directory: URL) -> Bool {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.contains { name in
      name == ".knowledge-copilot-study-import-transaction.json"
        || name.hasSuffix(".staged")
        || name.hasSuffix(".backup")
    }
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func packURL() -> URL {
    repositoryRoot().appendingPathComponent(
      "fixtures/knowledge-packs/minimal-hospitality",
      isDirectory: true
    )
  }

  private func analysisURL() -> URL {
    repositoryRoot().appendingPathComponent(
      "fixtures/study-analysis/synthetic-hospitality-analysis.json"
    )
  }
}
