import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class QuestionCandidateDetectorTests: XCTestCase {
  func testPartialRevPARQuestionProducesProvisionalCandidate() throws {
    var detector = try makeDetector()

    let events = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was the rev par",
        stability: .partial
      ))

    let candidate = try XCTUnwrap(upsert(from: events))
    XCTAssertEqual(candidate.questionFamilyID, "question-revpar-period")
    XCTAssertEqual(candidate.status, .provisional)
    XCTAssertEqual(
      candidate.bindings.first(where: { $0.key == "term" })?.value, "hospitality.revpar")
    XCTAssertNil(candidate.bindings.first(where: { $0.key == "period" }))
  }

  func testStableSpeechPromotesSameCandidateWithoutDuplicateFinalEvent() throws {
    var detector = try makeDetector()
    let first = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was the rev par",
        stability: .partial
      ))
    let initial = try XCTUnwrap(upsert(from: first))

    let promotion = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 2,
        text: "What was the rev par for this asset in 2020",
        stability: .partial
      ))
    let stable = try XCTUnwrap(upsert(from: promotion))

    XCTAssertEqual(stable.id, initial.id)
    XCTAssertEqual(stable.status, .stable)
    XCTAssertEqual(stable.bindings.first(where: { $0.key == "period" })?.value, "2020")

    let duplicateFinal = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 3,
        text: "What was the RevPAR for this asset in 2020?",
        stability: .final
      ))
    XCTAssertTrue(duplicateFinal.isEmpty)
  }

  func testCorrectionCancelsStaleCandidateBeforeCreatingReplacement() throws {
    var detector = try makeDetector()
    let first = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was RevPAR for this asset",
        stability: .partial
      ))
    let initial = try XCTUnwrap(upsert(from: first))

    let corrected = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 2,
        text: "Actually, what was occupancy in 2020?",
        stability: .partial
      ))

    XCTAssertEqual(corrected.count, 2)
    let cancellation = try XCTUnwrap(cancellation(from: corrected))
    let replacement = try XCTUnwrap(upsert(from: corrected))
    XCTAssertEqual(cancellation.candidateID, initial.id)
    XCTAssertEqual(cancellation.reason, .superseded)
    XCTAssertEqual(replacement.questionFamilyID, "question-occupancy-2020")
    XCTAssertNotEqual(replacement.id, initial.id)
  }

  func testClearingPartialCancelsCandidate() throws {
    var detector = try makeDetector()
    let first = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was RevPAR",
        stability: .partial
      ))
    let initial = try XCTUnwrap(upsert(from: first))

    let cleared = detector.process(
      TranscriptRevision(streamID: "remote", sequence: 2, text: "", stability: .partial))
    let cancellation = try XCTUnwrap(cancellation(from: cleared))

    XCTAssertEqual(cancellation.candidateID, initial.id)
    XCTAssertEqual(cancellation.reason, .cleared)
  }

  func testRevPARJoinedAndSpokenAliasesResolveToSameOpaqueTerm() throws {
    var detector = try makeDetector(stableRevisionCount: 1)

    let joined = detector.process(
      TranscriptRevision(
        streamID: "joined",
        sequence: 1,
        text: "Can you give me the RevPAR for 2020?",
        stability: .partial
      ))
    let spoken = detector.process(
      TranscriptRevision(
        streamID: "spoken",
        sequence: 1,
        text: "Can you give me the rev par for 2020?",
        stability: .partial
      ))

    let joinedCandidate = try XCTUnwrap(upsert(from: joined))
    let spokenCandidate = try XCTUnwrap(upsert(from: spoken))
    XCTAssertEqual(joinedCandidate.questionFamilyID, "question-revpar-period")
    XCTAssertEqual(spokenCandidate.questionFamilyID, "question-revpar-period")
    XCTAssertEqual(
      joinedCandidate.bindings.first(where: { $0.key == "term" })?.value,
      "hospitality.revpar"
    )
    XCTAssertEqual(
      spokenCandidate.bindings.first(where: { $0.key == "term" })?.value,
      "hospitality.revpar"
    )
  }

  func testMaterialPeriodCorrectionCancelsAndRestartsSameFamily() throws {
    var detector = try makeDetector()
    let first = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was RevPAR for this asset in 2020?",
        stability: .partial
      ))
    let initial = try XCTUnwrap(upsert(from: first))

    let correction = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 2,
        text: "What was RevPAR for this asset in 2021?",
        stability: .partial
      ))

    let cancellation = try XCTUnwrap(cancellation(from: correction))
    let replacement = try XCTUnwrap(upsert(from: correction))
    XCTAssertEqual(cancellation.reason, .corrected)
    XCTAssertEqual(cancellation.candidateID, initial.id)
    XCTAssertEqual(replacement.questionFamilyID, initial.questionFamilyID)
    XCTAssertNotEqual(replacement.id, initial.id)
    XCTAssertEqual(replacement.bindings.first(where: { $0.key == "period" })?.value, "2021")
  }

  func testOutOfOrderRevisionIsIgnored() throws {
    var detector = try makeDetector()
    _ = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 2,
        text: "What was RevPAR?",
        stability: .partial
      ))

    let stale = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was occupancy?",
        stability: .partial
      ))

    XCTAssertTrue(stale.isEmpty)
  }

  func testCoreUsesOpaqueIDsForAnUnrelatedProductDomain() throws {
    var detector = QuestionCandidateDetector(
      questionFamilies: [
        KnowledgeQuestionFamily(
          id: "question-product-safety",
          canonicalQuestion: "What is the product safety rating?",
          variants: ["How safe is the product?"],
          partialPrefixes: ["what is the product safety"],
          aliases: ["safety rating"]
        )
      ],
      termAliases: [
        KnowledgeTermAlias(
          id: "product.safety_rating",
          canonicalText: "Product safety rating",
          aliases: ["safety rating"]
        )
      ],
      stableRevisionCount: 1
    )

    let events = detector.process(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What is the product safety rating?",
        stability: .partial
      ))

    let candidate = try XCTUnwrap(upsert(from: events))
    XCTAssertEqual(candidate.questionFamilyID, "question-product-safety")
    XCTAssertEqual(candidate.status, .stable)
    XCTAssertEqual(
      candidate.bindings,
      [
        ResolvedQuestionBinding(
          key: "term",
          value: "product.safety_rating",
          surfaceText: "product safety rating"
        )
      ])

    let variantEvents = detector.process(
      TranscriptRevision(
        streamID: "variant",
        sequence: 1,
        text: "How safe is the product?",
        stability: .final
      ))
    let variantCandidate = try XCTUnwrap(upsert(from: variantEvents))
    XCTAssertEqual(variantCandidate.questionFamilyID, "question-product-safety")
    XCTAssertEqual(variantCandidate.status, .stable)
  }

  @MainActor
  func testAppStoreProcessesFixtureRevisionThroughGenericPipeline() async throws {
    let registry = makeRegistry()
    let store = KnowledgePackStore(profileRegistry: registry)
    await store.load(fromPath: fixtureURL().path)

    let events = store.processTranscriptRevision(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was the rev par",
        stability: .partial
      ))

    let candidate = try XCTUnwrap(upsert(from: events))
    XCTAssertEqual(store.activeQuestionCandidate(forStreamID: "remote"), candidate)
    XCTAssertEqual(candidate.questionFamilyID, "question-revpar-period")
  }

  private func makeDetector(stableRevisionCount: Int = 2) throws -> QuestionCandidateDetector {
    let registry = makeRegistry()
    let pack = try KnowledgePackLoader(profileRegistry: registry).load(from: fixtureURL())
    return QuestionCandidateDetector(
      questionFamilies: pack.questionFamilies,
      termAliases: registry.termAliases(for: pack.manifest),
      stableRevisionCount: stableRevisionCount
    )
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

  private func upsert(from events: [QuestionCandidateEvent]) -> QuestionCandidate? {
    events.compactMap { event -> QuestionCandidate? in
      guard case .upsert(let candidate) = event else { return nil }
      return candidate
    }.first
  }

  private func cancellation(
    from events: [QuestionCandidateEvent]
  ) -> QuestionCandidateCancellation? {
    events.compactMap { event -> QuestionCandidateCancellation? in
      guard case .cancel(let cancellation) = event else { return nil }
      return cancellation
    }.first
  }
}
