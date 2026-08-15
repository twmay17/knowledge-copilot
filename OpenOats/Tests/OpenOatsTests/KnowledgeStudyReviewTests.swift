import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeStudyReviewTests: XCTestCase {
  func testValidAnalysisProducesDeterministicPendingReviewQueue() throws {
    let pack = try loadPack()
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    let analysis = try loadAnalysis()
    let validator = KnowledgeStudyAnalysisValidator()

    let first = try validator.makeReviewQueue(analysis: analysis, bundle: bundle)
    let second = try validator.makeReviewQueue(analysis: analysis, bundle: bundle)

    XCTAssertEqual(first, second)
    XCTAssertTrue(first.queueID.hasPrefix("review-"))
    XCTAssertEqual(first.state, .pendingHumanReview)
    XCTAssertEqual(first.responseCardItems.count, 1)
    XCTAssertEqual(first.responseCardItems.first?.reviewStatus, .generated)
    XCTAssertEqual(first.responseCardItems.first?.referencedAssertions.count, 3)
    XCTAssertEqual(first.responseCardItems.first?.citedPassages.count, 3)
    XCTAssertEqual(first.responseCardItems.first?.referencedCalculations.count, 1)
  }

  func testAnalysisMustMatchExactBundleHash() throws {
    let pack = try loadPack()
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    let original = try loadAnalysis()
    let stale = copy(original, packContentHash: String(repeating: "0", count: 64))

    XCTAssertThrowsError(
      try KnowledgeStudyAnalysisValidator().makeReviewQueue(analysis: stale, bundle: bundle)
    ) { error in
      guard case KnowledgeStudyAnalysisError.identityMismatch(let field, _, _) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(field, "packContentHash")
    }
  }

  func testUnknownAssertionReferenceFailsClosed() throws {
    let bundle = try KnowledgeStudyBundleBuilder().build(from: loadPack())
    let original = try loadAnalysis()
    let card = try XCTUnwrap(original.responseCardProposals.first)
    let invalidCard = copy(card, assertionIDs: ["assertion-does-not-exist"])
    let invalid = copy(original, responseCardProposals: [invalidCard])

    XCTAssertThrowsError(
      try KnowledgeStudyAnalysisValidator().makeReviewQueue(analysis: invalid, bundle: bundle)
    ) { error in
      guard case KnowledgeStudyAnalysisError.unknownReference(_, let type, let id) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(type, "assertion")
      XCTAssertEqual(id, "assertion-does-not-exist")
    }
  }

  func testCitationMustBelongToClaimedEvidenceClosure() throws {
    let bundle = try KnowledgeStudyBundleBuilder().build(from: loadPack())
    let original = try loadAnalysis()
    let invalidCard = KnowledgeStudyResponseCardProposal(
      id: "card-bad-evidence",
      title: "Bad evidence",
      answer: "The memo says RevPAR was $92.00.",
      evidenceState: .directlySourced,
      questionFamilyIDs: ["question-revpar-conflict"],
      assertionIDs: ["assertion-revpar-memo-2020"],
      citationPassageIDs: ["passage-inventory-2020-actual"],
      calculationIDs: []
    )
    let invalid = copy(original, responseCardProposals: [invalidCard])

    XCTAssertThrowsError(
      try KnowledgeStudyAnalysisValidator().makeReviewQueue(analysis: invalid, bundle: bundle)
    ) { error in
      guard case KnowledgeStudyAnalysisError.citationOutsideEvidence(let id, let passageID) = error
      else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(id, invalidCard.id)
      XCTAssertEqual(passageID, "passage-inventory-2020-actual")
    }
  }

  func testModelSuppliedReviewStatusCannotBypassQueue() throws {
    let data = try Data(contentsOf: analysisURL())
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var cards = try XCTUnwrap(object["responseCardProposals"] as? [[String: Any]])
    cards[0]["reviewStatus"] = "reviewed"
    object["responseCardProposals"] = cards
    let tamperedData = try JSONSerialization.data(withJSONObject: object)
    let analysis = try JSONDecoder().decode(KnowledgeStudyAnalysis.self, from: tamperedData)
    let bundle = try KnowledgeStudyBundleBuilder().build(from: loadPack())

    let queue = try KnowledgeStudyAnalysisValidator().makeReviewQueue(
      analysis: analysis,
      bundle: bundle
    )

    XCTAssertEqual(queue.responseCardItems.first?.reviewStatus, .generated)
  }

  func testExplicitHumanApprovalProducesReviewedImportArtifact() throws {
    let pack = try loadPack()
    let queue = try makeQueue(pack: pack)
    let decisions = makeDecisions(queue: queue, question: .approve, card: .approve)

    let result = try makeGate().approve(queue: queue, decisions: decisions, pack: pack)

    XCTAssertEqual(result.approvedQuestionFamilies.count, 1)
    XCTAssertEqual(result.approvedResponseCards.count, 1)
    XCTAssertEqual(result.approvedResponseCards.first?.reviewStatus, .reviewed)
    XCTAssertEqual(result.reviewer, "Synthetic Fixture Reviewer")
    XCTAssertEqual(result.reviewDecisions.count, 2)
    XCTAssertNotEqual(result.basePackContentHash, result.resultingPackContentHash)
    XCTAssertTrue(result.rejectedDecisions.isEmpty)
  }

  func testEveryProposalRequiresAnExplicitDecision() throws {
    let pack = try loadPack()
    let queue = try makeQueue(pack: pack)
    let incomplete = KnowledgeStudyReviewDecisionSet(
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
          disposition: .approve
        )
      ]
    )

    XCTAssertThrowsError(try makeGate().approve(queue: queue, decisions: incomplete, pack: pack)) {
      error in
      guard case KnowledgeStudyReviewGateError.missingDecision(let kind, let id) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(kind, .responseCard)
      XCTAssertEqual(id, "card-revpar-reconciliation-2020")
    }
  }

  func testRejectingEveryProposalProducesNoImportableRecords() throws {
    let pack = try loadPack()
    let queue = try makeQueue(pack: pack)
    let decisions = makeDecisions(queue: queue, question: .reject, card: .reject)

    let result = try makeGate().approve(queue: queue, decisions: decisions, pack: pack)

    XCTAssertTrue(result.approvedQuestionFamilies.isEmpty)
    XCTAssertTrue(result.approvedResponseCards.isEmpty)
    XCTAssertEqual(result.rejectedDecisions.count, 2)
    XCTAssertEqual(result.basePackContentHash, result.resultingPackContentHash)
  }

  func testApprovedCardCannotReferenceRejectedProposedQuestion() throws {
    let pack = try loadPack()
    let queue = try makeQueue(pack: pack)
    let decisions = makeDecisions(queue: queue, question: .reject, card: .approve)

    XCTAssertThrowsError(try makeGate().approve(queue: queue, decisions: decisions, pack: pack)) {
      error in
      guard case KnowledgeStudyReviewGateError.mergedPackInvalid(let report) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertTrue(report.errors.contains { $0.code == "card.unknown_question_family" })
    }
  }

  func testTamperedReviewQueueIsRejected() throws {
    let pack = try loadPack()
    let queue = try makeQueue(pack: pack)
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
    let decisions = makeDecisions(queue: queue, question: .approve, card: .approve)

    XCTAssertThrowsError(try makeGate().approve(queue: tampered, decisions: decisions, pack: pack))
    {
      error in
      guard case KnowledgeStudyReviewGateError.queueTampered = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testQueueBecomesStaleWhenPackContentChanges() throws {
    let pack = try loadPack()
    let queue = try makeQueue(pack: pack)
    let changedPack = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies + [
        KnowledgeQuestionFamily(
          id: "question-added-after-review",
          canonicalQuestion: "Was this added after review?",
          variants: []
        )
      ]
    )
    let decisions = makeDecisions(queue: queue, question: .approve, card: .approve)

    XCTAssertThrowsError(
      try makeGate().approve(queue: queue, decisions: decisions, pack: changedPack)
    ) { error in
      guard case KnowledgeStudyReviewGateError.queueDoesNotMatchCurrentBundle = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testDuplicateHumanDecisionIsRejected() throws {
    let pack = try loadPack()
    let queue = try makeQueue(pack: pack)
    let original = makeDecisions(queue: queue, question: .approve, card: .approve)
    let duplicated = KnowledgeStudyReviewDecisionSet(
      schemaVersion: original.schemaVersion,
      queueID: original.queueID,
      analysisID: original.analysisID,
      bundleID: original.bundleID,
      reviewer: original.reviewer,
      reviewedAt: original.reviewedAt,
      decisions: original.decisions + [try XCTUnwrap(original.decisions.first)]
    )

    XCTAssertThrowsError(try makeGate().approve(queue: queue, decisions: duplicated, pack: pack)) {
      error in
      guard case KnowledgeStudyReviewGateError.duplicateDecision(let kind, let id) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(kind, .questionFamily)
      XCTAssertEqual(id, "question-revpar-reconciliation-2020")
    }
  }

  private var reviewDate: Date {
    Date(timeIntervalSince1970: 1_776_441_600)
  }

  private func makeQueue(pack: KnowledgePack) throws -> KnowledgeStudyReviewQueue {
    try KnowledgeStudyAnalysisValidator().makeReviewQueue(
      analysis: loadAnalysis(),
      bundle: KnowledgeStudyBundleBuilder().build(from: pack)
    )
  }

  private func makeDecisions(
    queue: KnowledgeStudyReviewQueue,
    question: KnowledgeStudyReviewDisposition,
    card: KnowledgeStudyReviewDisposition
  ) -> KnowledgeStudyReviewDecisionSet {
    KnowledgeStudyReviewDecisionSet(
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
          disposition: question,
          note: "Human question-family decision."
        ),
        KnowledgeStudyReviewDecision(
          proposalKind: .responseCard,
          proposalID: "card-revpar-reconciliation-2020",
          disposition: card,
          note: "Human response-card decision."
        ),
      ]
    )
  }

  private func makeGate() -> KnowledgeStudyReviewGate {
    KnowledgeStudyReviewGate(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
    )
  }

  private func loadPack() throws -> KnowledgePack {
    try KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
    ).load(from: packURL())
  }

  private func loadAnalysis() throws -> KnowledgeStudyAnalysis {
    try JSONDecoder().decode(
      KnowledgeStudyAnalysis.self,
      from: Data(contentsOf: analysisURL())
    )
  }

  private func copy(
    _ analysis: KnowledgeStudyAnalysis,
    packContentHash: String? = nil,
    responseCardProposals: [KnowledgeStudyResponseCardProposal]? = nil
  ) -> KnowledgeStudyAnalysis {
    KnowledgeStudyAnalysis(
      schemaVersion: analysis.schemaVersion,
      analysisID: analysis.analysisID,
      bundleID: analysis.bundleID,
      packID: analysis.packID,
      packContentHash: packContentHash ?? analysis.packContentHash,
      generator: analysis.generator,
      questionFamilyProposals: analysis.questionFamilyProposals,
      responseCardProposals: responseCardProposals ?? analysis.responseCardProposals,
      contradictions: analysis.contradictions,
      corpusGaps: analysis.corpusGaps
    )
  }

  private func copy(
    _ proposal: KnowledgeStudyResponseCardProposal,
    assertionIDs: [String]
  ) -> KnowledgeStudyResponseCardProposal {
    KnowledgeStudyResponseCardProposal(
      id: proposal.id,
      title: proposal.title,
      answer: proposal.answer,
      evidenceState: proposal.evidenceState,
      questionFamilyIDs: proposal.questionFamilyIDs,
      assertionIDs: assertionIDs,
      citationPassageIDs: proposal.citationPassageIDs,
      calculationIDs: proposal.calculationIDs,
      caveat: proposal.caveat
    )
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
