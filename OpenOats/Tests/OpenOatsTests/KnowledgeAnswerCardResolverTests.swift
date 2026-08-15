import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeAnswerCardResolverTests: XCTestCase {
  func testProvisionalCandidateDoesNotSurfaceAnswer() throws {
    let resolver = try makeResolver()

    XCTAssertNil(resolver.resolve(makeCandidate(status: .provisional)))
  }

  func testStableRevPARCandidateResolvesReviewedCalculatedCardAndEvidence() throws {
    let resolver = try makeResolver()

    let answer = try XCTUnwrap(resolver.resolve(makeCandidate()))

    XCTAssertEqual(answer.responseCardID, "card-revpar-2020")
    XCTAssertEqual(answer.evidenceState, .calculated)
    XCTAssertTrue(answer.answer.contains("$89.50"))
    XCTAssertFalse(answer.isFallback)
    XCTAssertEqual(answer.calculations.map(\.id), ["calculation-revpar-v1"])
    XCTAssertEqual(answer.citations.count, 2)
    XCTAssertEqual(
      answer.citations.first?.locatorLabel, "Operating Statement · A3:J3 · 2020 actual")
    for citation in answer.citations {
      XCTAssertTrue(citation.fileURL.isFileURL)
      XCTAssertTrue(FileManager.default.fileExists(atPath: citation.fileURL.path))
    }
  }

  func testRequestedPeriodMustAgreeWithCardAssertions() throws {
    let resolver = try makeResolver()

    let answer = try XCTUnwrap(resolver.resolve(makeCandidate(period: "2021")))

    XCTAssertTrue(answer.isFallback)
    XCTAssertNil(answer.responseCardID)
    XCTAssertEqual(answer.evidenceState, .notFoundInCorpus)
    XCTAssertTrue(answer.answer.contains("does not contain a reviewed answer"))
  }

  func testUnreviewedAnswerFailsClosed() throws {
    let pack = try loadFixture()
    let unreviewedCards = pack.responseCards.map { card in
      KnowledgeResponseCard(
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
    }
    let resolver = KnowledgeAnswerCardResolver(
      pack: copy(pack, responseCards: unreviewedCards),
      rootDirectory: fixtureURL()
    )

    let answer = try XCTUnwrap(resolver.resolve(makeCandidate()))

    XCTAssertTrue(answer.isFallback)
    XCTAssertEqual(answer.evidenceState, .notFoundInCorpus)
    XCTAssertTrue(answer.citations.isEmpty)
  }

  func testAmbiguousReviewedCardsFailClosed() throws {
    let pack = try loadFixture()
    let first = try XCTUnwrap(
      pack.responseCards.first(where: { $0.id == "card-revpar-2020" }))
    let duplicate = KnowledgeResponseCard(
      id: "card-revpar-2020-alternative",
      title: first.title,
      answer: first.answer,
      evidenceState: first.evidenceState,
      questionFamilyIDs: first.questionFamilyIDs,
      assertionIDs: first.assertionIDs,
      citationPassageIDs: first.citationPassageIDs,
      calculationIDs: first.calculationIDs,
      reviewStatus: .reviewed
    )
    let resolver = KnowledgeAnswerCardResolver(
      pack: copy(pack, responseCards: pack.responseCards + [duplicate]),
      rootDirectory: fixtureURL()
    )

    let answer = try XCTUnwrap(resolver.resolve(makeCandidate()))

    XCTAssertTrue(answer.isFallback)
    XCTAssertEqual(answer.evidenceState, .needsClarification)
    XCTAssertTrue(answer.answer.contains("more than one reviewed answer"))
  }

  func testMissingEvidenceFileFailsClosed() throws {
    let pack = try loadFixture()
    let missingRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let resolver = KnowledgeAnswerCardResolver(pack: pack, rootDirectory: missingRoot)

    let answer = try XCTUnwrap(resolver.resolve(makeCandidate()))

    XCTAssertTrue(answer.isFallback)
    XCTAssertEqual(answer.evidenceState, .needsClarification)
    XCTAssertTrue(answer.answer.contains("evidence cannot be opened"))
  }

  @MainActor
  func testStorePromotesStableCandidateIntoAnswerAndRemovesItOnCorrection() async throws {
    let store = KnowledgePackStore(profileRegistry: makeRegistry())
    await store.load(fromPath: fixtureURL().path)

    _ = store.processTranscriptText(
      streamID: "remote",
      text: "What was the rev par",
      stability: .partial
    )
    XCTAssertNil(store.activeAnswerCard(forStreamID: "remote"))

    _ = store.processTranscriptText(
      streamID: "remote",
      text: "What was the rev par for this asset in 2020",
      stability: .partial
    )
    XCTAssertEqual(
      store.activeAnswerCard(forStreamID: "remote")?.responseCardID,
      "card-revpar-2020"
    )

    _ = store.processTranscriptText(
      streamID: "remote",
      text: "What was the rev par for this asset in 2021",
      stability: .partial
    )
    XCTAssertNil(store.activeAnswerCard(forStreamID: "remote"))

    _ = store.processTranscriptText(
      streamID: "remote",
      text: "What was the rev par for this asset in 2021",
      stability: .final
    )
    XCTAssertEqual(
      store.activeAnswerCard(forStreamID: "remote")?.evidenceState,
      .notFoundInCorpus
    )
  }

  private func makeResolver() throws -> KnowledgeAnswerCardResolver {
    KnowledgeAnswerCardResolver(pack: try loadFixture(), rootDirectory: fixtureURL())
  }

  private func makeCandidate(
    status: QuestionCandidateStatus = .stable,
    period: String = "2020"
  ) -> QuestionCandidate {
    QuestionCandidate(
      id: "remote#1",
      streamID: "remote",
      revisionSequence: 2,
      questionFamilyID: "question-revpar-period",
      sourceText: "What was RevPAR for this asset in \(period)?",
      confidence: 1,
      status: status,
      bindings: [
        ResolvedQuestionBinding(
          key: "period",
          value: period,
          surfaceText: period
        ),
        ResolvedQuestionBinding(
          key: "term",
          value: "hospitality.revpar",
          surfaceText: "revpar"
        ),
      ]
    )
  }

  private func loadFixture() throws -> KnowledgePack {
    try KnowledgePackLoader(profileRegistry: makeRegistry()).load(from: fixtureURL())
  }

  private func makeRegistry() -> KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }

  private func copy(
    _ pack: KnowledgePack,
    responseCards: [KnowledgeResponseCard]
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: responseCards,
      questionFamilies: pack.questionFamilies
    )
  }
}
