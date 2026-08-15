import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

@MainActor
final class KnowledgeStudyReviewWorkspaceModelTests: XCTestCase {
  func testLoadRevalidatesQueueAndStartsOnEvidenceRichResponseCard() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let model = makeModel()

    let didLoad = await model.load(queueURL: fixture.queue, packDirectory: fixture.pack)

    XCTAssertTrue(didLoad)

    XCTAssertTrue(model.isLoaded)
    XCTAssertEqual(model.packTitle, "Synthetic Hotel 2020 Reference Pack")
    XCTAssertEqual(model.proposalCount, 2)
    XCTAssertEqual(model.pendingCount, 2)
    XCTAssertEqual(model.responseCardSelections.count, 1)
    XCTAssertEqual(model.contradictionSelections.count, 1)
    XCTAssertEqual(model.corpusGapSelections.count, 1)
    XCTAssertEqual(model.selection, model.responseCardSelections.first)
    XCTAssertEqual(model.bundle?.assertions.count, 18)
  }

  func testTamperedQueueIsRejectedBeforeReview() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let queue = try decodeQueue(from: fixture.queue)
    let item = try XCTUnwrap(queue.responseCardItems.first)
    let tamperedItem = KnowledgeStudyResponseCardReviewItem(
      proposal: item.proposal,
      referencedAssertions: item.referencedAssertions,
      citedPassages: item.citedPassages,
      referencedCalculations: item.referencedCalculations,
      reviewStatus: .reviewed
    )
    let tampered = KnowledgeStudyReviewQueue(
      schemaVersion: queue.schemaVersion,
      queueID: queue.queueID,
      state: queue.state,
      analysis: queue.analysis,
      responseCardItems: [tamperedItem]
    )
    try encode(tampered, to: fixture.queue)
    let model = makeModel()

    let didLoad = await model.load(queueURL: fixture.queue, packDirectory: fixture.pack)

    XCTAssertFalse(didLoad)
    XCTAssertFalse(model.isLoaded)
    XCTAssertTrue(model.errorMessage?.contains("does not exactly match") == true)
  }

  func testEveryProposalAndNamedReviewerAreRequiredBeforePreview() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let model = makeModel(reviewer: "")
    let didLoad = await model.load(queueURL: fixture.queue, packDirectory: fixture.pack)
    XCTAssertTrue(didLoad)
    let question = try XCTUnwrap(model.questionSelections.first)
    let card = try XCTUnwrap(model.responseCardSelections.first)

    XCTAssertFalse(model.canPrepareImport)
    model.updateReviewer("Synthetic UI Reviewer")
    model.setDisposition(.approve, for: question)
    XCTAssertEqual(model.pendingCount, 1)
    XCTAssertFalse(model.canPrepareImport)
    model.setDisposition(.approve, for: card)

    XCTAssertTrue(model.canPrepareImport)
    let didPrepare = await model.prepareImport()

    XCTAssertTrue(didPrepare)
    XCTAssertEqual(model.importPlan?.state, .ready)
    XCTAssertEqual(model.approvedImport?.reviewer, "Synthetic UI Reviewer")
    XCTAssertEqual(model.approvedImport?.approvedQuestionFamilies.count, 1)
    XCTAssertEqual(model.approvedImport?.approvedResponseCards.first?.reviewStatus, .reviewed)
  }

  func testEditingDecisionAfterPreviewInvalidatesPreparedArtifact() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let model = makeModel()
    let didLoad = await model.load(queueURL: fixture.queue, packDirectory: fixture.pack)
    XCTAssertTrue(didLoad)
    approveEveryProposal(in: model)
    let didPrepare = await model.prepareImport()
    XCTAssertTrue(didPrepare)
    XCTAssertNotNil(model.importPlan)

    model.setNote(
      "Reviewer changed the rationale.", for: try XCTUnwrap(model.responseCardSelections.first))

    XCTAssertNil(model.importPlan)
    XCTAssertNil(model.approvedImport)
    XCTAssertTrue(model.canPrepareImport)
  }

  func testApplyUsesPreparedArtifactAndUpdatesWritablePack() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let model = makeModel()
    let didLoad = await model.load(queueURL: fixture.queue, packDirectory: fixture.pack)
    XCTAssertTrue(didLoad)
    approveEveryProposal(in: model)
    let didPrepare = await model.prepareImport()
    XCTAssertTrue(didPrepare)

    let didApply = await model.applyImport()

    XCTAssertTrue(didApply)

    let pack = try loadPack(from: fixture.pack)
    XCTAssertEqual(model.receipt?.outcome, .applied)
    XCTAssertEqual(pack.responseCards.count, 10)
    XCTAssertEqual(
      pack.responseCards.first { $0.id == "card-revpar-reconciliation-2020" }?.reviewStatus,
      .reviewed
    )
    XCTAssertFalse(model.canApplyImport)
  }

  func testRejectingAllProposalsPreviewsAndRecordsNoChanges() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let model = makeModel()
    let didLoad = await model.load(queueURL: fixture.queue, packDirectory: fixture.pack)
    XCTAssertTrue(didLoad)
    for selection in model.questionSelections + model.responseCardSelections {
      model.setDisposition(.reject, for: selection)
    }

    let didPrepare = await model.prepareImport()
    XCTAssertTrue(didPrepare)
    XCTAssertEqual(model.importPlan?.state, .noChanges)
    let didApply = await model.applyImport()
    XCTAssertTrue(didApply)
    XCTAssertEqual(model.receipt?.outcome, .noChanges)
    XCTAssertEqual(try loadPack(from: fixture.pack).responseCards.count, 9)
  }

  func testPackChangeAfterQueueLoadFailsClosedDuringPreview() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let model = makeModel()
    let didLoad = await model.load(queueURL: fixture.queue, packDirectory: fixture.pack)
    XCTAssertTrue(didLoad)
    approveEveryProposal(in: model)
    try appendJSONLine(
      KnowledgeQuestionFamily(
        id: "question-added-after-ui-load",
        canonicalQuestion: "Did the corpus change after UI load?",
        variants: []
      ),
      to: fixture.pack.appendingPathComponent("question-families.jsonl")
    )

    let didPrepare = await model.prepareImport()

    XCTAssertFalse(didPrepare)
    XCTAssertNil(model.importPlan)
    XCTAssertTrue(model.errorMessage?.contains("does not match the active KnowledgePack") == true)
  }

  private struct Fixture {
    let root: URL
    let pack: URL
    let queue: URL
  }

  private var registry: KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func makeModel(
    reviewer: String = "Synthetic UI Reviewer"
  ) -> KnowledgeStudyReviewWorkspaceModel {
    KnowledgeStudyReviewWorkspaceModel(
      profileRegistry: registry,
      reviewer: reviewer,
      now: { Date(timeIntervalSince1970: 1_787_072_400) }
    )
  }

  private func approveEveryProposal(
    in model: KnowledgeStudyReviewWorkspaceModel
  ) {
    for selection in model.questionSelections + model.responseCardSelections {
      model.setDisposition(.approve, for: selection)
    }
    XCTAssertEqual(model.pendingCount, 0)
  }

  private func makeFixture() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "knowledge-study-review-workspace-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let pack = root.appendingPathComponent("pack", isDirectory: true)
    try FileManager.default.copyItem(at: packFixtureURL(), to: pack)
    let loadedPack = try loadPack(from: pack)
    let analysis = try JSONDecoder().decode(
      KnowledgeStudyAnalysis.self,
      from: Data(contentsOf: analysisFixtureURL())
    )
    let queue = try KnowledgeStudyAnalysisValidator().makeReviewQueue(
      analysis: analysis,
      bundle: KnowledgeStudyBundleBuilder().build(from: loadedPack)
    )
    let queueURL = root.appendingPathComponent("review-queue.json")
    try encode(queue, to: queueURL)
    return Fixture(root: root, pack: pack, queue: queueURL)
  }

  private func loadPack(from directory: URL) throws -> KnowledgePack {
    try KnowledgePackLoader(profileRegistry: registry).load(from: directory)
  }

  private func decodeQueue(from url: URL) throws -> KnowledgeStudyReviewQueue {
    try JSONDecoder().decode(KnowledgeStudyReviewQueue.self, from: Data(contentsOf: url))
  }

  private func encode<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
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

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func packFixtureURL() -> URL {
    repositoryRoot().appendingPathComponent(
      "fixtures/knowledge-packs/minimal-hospitality",
      isDirectory: true
    )
  }

  private func analysisFixtureURL() -> URL {
    repositoryRoot().appendingPathComponent(
      "fixtures/study-analysis/synthetic-hospitality-analysis.json"
    )
  }
}
