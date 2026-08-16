import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeLiveEventDetectorTests: XCTestCase {
  func testPreparedQuestionEmitsCandidateBeforeFinalThenStableWithoutDuplicate() throws {
    var detector = try makeDetector()

    let candidate = detector.process(
      revision(1, "What was the rev par", stability: .partial)
    )
    let stable = detector.process(
      revision(2, "What was the rev par for this asset in 2020", stability: .partial)
    )
    let final = detector.process(
      revision(3, "What was the RevPAR for this asset in 2020?", stability: .final)
    )

    XCTAssertEqual(candidate.map(\.kind), [.questionCandidate])
    XCTAssertEqual(stable.map(\.kind), [.questionStable])
    XCTAssertEqual(final.map(\.kind), [.noAction])
    guard case .noAction(let noAction) = final[0] else {
      return XCTFail("Expected an explicit no-action event")
    }
    XCTAssertEqual(noAction.reason, .unchangedRevision)
  }

  func testCorrectionSupersedesOldAnswerAndEmitsDeterministicTopicShift() throws {
    var detector = try makeDetector()
    let first = detector.process(
      revision(1, "What was RevPAR for this asset in 2020?", stability: .final)
    )

    let correction = detector.process(
      revision(2, "Actually, what was occupancy in 2020?", stability: .final)
    )

    XCTAssertEqual(first.map(\.kind), [.questionStable])
    XCTAssertEqual(
      correction.map(\.kind),
      [.answerSuperseded, .topicShift, .questionStable]
    )
    guard case .answerSuperseded(let supersession) = correction[0] else {
      return XCTFail("Expected supersession first")
    }
    XCTAssertEqual(supersession.previousEventID, "remote#1")
    XCTAssertEqual(supersession.replacementEventID, "remote#2")
    XCTAssertEqual(supersession.reason, .followUp)
    guard case .topicShift(let shift) = correction[1] else {
      return XCTFail("Expected topic shift second")
    }
    XCTAssertEqual(shift.fromTopicIDs, ["hospitality.revpar"])
    XCTAssertEqual(shift.toTopicIDs, ["hospitality.occupancy"])
  }

  func testGenericProductClaimPromotesWithoutHospitalityTypes() {
    var detector = KnowledgeLiveEventDetector(
      questionFamilies: [
        KnowledgeQuestionFamily(
          id: "question-product-safety",
          canonicalQuestion: "What is the product safety rating?",
          variants: ["How safe is the product?"],
          partialPrefixes: ["what is the product safety"],
          aliases: ["product safety rating", "safety score"]
        )
      ]
    )

    let candidate = detector.process(
      TranscriptRevision(
        streamID: "product",
        sequence: 1,
        text: "The product safety rating was 4.8 in 2025",
        stability: .partial
      ))
    let stable = detector.process(
      TranscriptRevision(
        streamID: "product",
        sequence: 2,
        text: "The product safety rating was 4.8 in 2025.",
        stability: .final
      ))

    XCTAssertEqual(candidate.map(\.kind), [.claimCandidate])
    XCTAssertEqual(stable.map(\.kind), [.claimStable])
    guard case .claimStable(let claim) = stable[0] else {
      return XCTFail("Expected a stable product claim")
    }
    XCTAssertEqual(
      claim.bindings.first(where: { $0.key == "term" })?.value,
      "question_family:question-product-safety"
    )
    XCTAssertEqual(claim.bindings.first(where: { $0.key == "period" })?.value, "2025")
    XCTAssertEqual(claim.bindings.first(where: { $0.key == "literal" })?.value, "4.8")
  }

  func testRapidDuplicateQuestionDoesNotCreateAnotherCard() throws {
    var detector = try makeDetector()
    _ = detector.process(
      revision(1, "What was RevPAR for this asset in 2020?", stability: .final, streamID: "first")
    )

    let duplicate = detector.process(
      revision(
        1, "What was the rev par for this asset in 2020?", stability: .final, streamID: "follow-up")
    )

    XCTAssertEqual(duplicate.map(\.kind), [.noAction])
    guard case .noAction(let noAction) = duplicate[0] else {
      return XCTFail("Expected a duplicate no-action event")
    }
    XCTAssertEqual(noAction.reason, .duplicateSignal)
  }

  func testRapidDuplicateClaimDoesNotEmitSecondFactCheck() {
    let aliases = [
      KnowledgeTermAlias(
        id: "product.safety_rating",
        canonicalText: "Product safety rating",
        aliases: ["safety score"]
      )
    ]
    var detector = KnowledgeLiveEventDetector(
      questionFamilies: [],
      termAliases: aliases,
      stableRevisionCount: 1
    )
    _ = detector.process(
      revision(
        1,
        "The product safety rating was 4.8.",
        stability: .final,
        streamID: "first-claim"
      ))

    let duplicate = detector.process(
      revision(
        1,
        "The product safety rating was 4.8.",
        stability: .final,
        streamID: "duplicate-claim"
      ))

    XCTAssertEqual(duplicate.map(\.kind), [.noAction])
    guard case .noAction(let noAction) = duplicate[0] else {
      return XCTFail("Expected a duplicate no-action event")
    }
    XCTAssertEqual(noAction.reason, .duplicateSignal)
  }

  func testInterruptedQuestionSupersedesOnceAndStaleRevisionIsNoAction() throws {
    var detector = try makeDetector()
    _ = detector.process(
      revision(1, "What was RevPAR for this asset in 2020?", stability: .final, streamID: "first")
    )

    let interrupted = detector.process(
      revision(1, "What was occupancy", stability: .partial, streamID: "interruption")
    )
    let stable = detector.process(
      revision(2, "What was occupancy in 2020?", stability: .final, streamID: "interruption")
    )
    let stale = detector.process(
      revision(1, "What was ADR?", stability: .final, streamID: "interruption")
    )

    XCTAssertEqual(interrupted.map(\.kind), [.answerSuperseded, .questionCandidate])
    XCTAssertEqual(stable.map(\.kind), [.topicShift, .questionStable])
    XCTAssertEqual(stale.map(\.kind), [.noAction])
    guard case .noAction(let noAction) = stale[0] else {
      return XCTFail("Expected stale revision no action")
    }
    XCTAssertEqual(noAction.reason, .staleRevision)
  }

  func testLateFinalFromInterruptedStreamCannotResurfaceSupersededQuestion() throws {
    var detector = try makeDetector()
    _ = detector.process(
      revision(1, "What was the rev par", stability: .partial, streamID: "old-stream")
    )
    let interruption = detector.process(
      revision(1, "What was occupancy in 2020?", stability: .final, streamID: "new-stream")
    )

    let lateFinal = detector.process(
      revision(
        2,
        "What was the RevPAR for this asset in 2020?",
        stability: .final,
        streamID: "old-stream"
      ))

    XCTAssertEqual(interruption.map(\.kind), [.answerSuperseded, .questionStable])
    XCTAssertEqual(lateFinal.map(\.kind), [.noAction])
  }

  @MainActor
  func testPackStoreExposesRichEventsAndPreservesLegacyAnswerPath() async throws {
    let registry = makeRegistry()
    let store = KnowledgePackStore(profileRegistry: registry)
    await store.load(fromPath: fixtureURL().path)

    let liveEvents = store.processLiveTranscriptRevision(
      revision(1, "What was RevPAR for this asset in 2020?", stability: .final)
    )

    XCTAssertEqual(liveEvents.map(\.kind), [.questionStable])
    XCTAssertEqual(store.latestLiveKnowledgeEvents, liveEvents)
    XCTAssertEqual(
      store.activeAnswerCard(forStreamID: "remote")?.responseCardID,
      "card-revpar-2020"
    )

    let claimEvents = store.processLiveTranscriptRevision(
      revision(1, "RevPAR was $89.50 in 2020.", stability: .final, streamID: "claim")
    )
    XCTAssertEqual(claimEvents.map(\.kind), [.answerSuperseded, .claimStable])
    XCTAssertNil(store.activeAnswerCard(forStreamID: "remote"))
  }

  func testReplayFixturesProduceExactTracesAndZeroFalsePositives() throws {
    let runner = try makeReplayRunner()
    let transitionReport = try runner.run(loadReplay("live-events-transitions.json"))
    let negativeReport = try runner.run(loadReplay("live-events-negative.json"))

    let mismatches = transitionReport.traces.filter { !$0.passed }
    XCTAssertEqual(transitionReport.verdict, .pass, "\(mismatches)")
    XCTAssertEqual(
      transitionReport.exactTraceMatchCount,
      transitionReport.traces.count,
      "\(mismatches)"
    )
    XCTAssertEqual(transitionReport.falsePositiveRate, 0)
    XCTAssertEqual(negativeReport.verdict, .pass)
    XCTAssertGreaterThan(negativeReport.negativeRevisionCount, 0)
    XCTAssertEqual(negativeReport.falsePositiveRevisionCount, 0)
    XCTAssertEqual(negativeReport.falsePositiveRate, 0)
  }

  func testReplayReportExposesFalsePositiveInsteadOfHidingMismatch() throws {
    let original = try loadReplay("live-events-negative.json")
    let first = try XCTUnwrap(original.revisions.first)
    let alteredFirst = KnowledgeLiveEventReplayRevision(
      streamID: first.streamID,
      sequence: first.sequence,
      text: "What was RevPAR for this asset in 2020?",
      stability: .final,
      expectedKinds: [.noAction]
    )
    let altered = KnowledgeLiveEventReplaySpec(
      name: "Deliberate false-positive audit",
      maximumFalsePositiveRate: 0,
      revisions: [alteredFirst] + Array(original.revisions.dropFirst())
    )

    let report = try makeReplayRunner().run(altered)

    XCTAssertEqual(report.verdict, .fail)
    XCTAssertEqual(report.falsePositiveRevisionCount, 1)
    XCTAssertGreaterThan(report.falsePositiveRate, 0)
    XCTAssertFalse(report.traces[0].passed)
  }

  private func makeDetector() throws -> KnowledgeLiveEventDetector {
    let registry = makeRegistry()
    let pack = try KnowledgePackLoader(profileRegistry: registry).load(from: fixtureURL())
    return KnowledgeLiveEventDetector(
      questionFamilies: pack.questionFamilies,
      termAliases: registry.termAliases(for: pack.manifest)
    )
  }

  private func makeReplayRunner() throws -> KnowledgeLiveEventReplayRunner {
    let registry = makeRegistry()
    let pack = try KnowledgePackLoader(profileRegistry: registry).load(from: fixtureURL())
    return KnowledgeLiveEventReplayRunner(
      questionFamilies: pack.questionFamilies,
      termAliases: registry.termAliases(for: pack.manifest)
    )
  }

  private func loadReplay(_ name: String) throws -> KnowledgeLiveEventReplaySpec {
    try JSONDecoder().decode(
      KnowledgeLiveEventReplaySpec.self,
      from: Data(contentsOf: fixtureURL().appendingPathComponent("evaluation/\(name)"))
    )
  }

  private func makeRegistry() -> KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func revision(
    _ sequence: Int,
    _ text: String,
    stability: TranscriptRevision.Stability,
    streamID: String = "remote"
  ) -> TranscriptRevision {
    TranscriptRevision(
      streamID: streamID,
      sequence: sequence,
      text: text,
      stability: stability
    )
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }
}
