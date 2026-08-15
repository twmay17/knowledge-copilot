import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeProofReplayTests: XCTestCase {
  func testSyntheticRevPARReplayPassesFromCleanStateBeforeFinalSpeech() throws {
    let report = try makeRunner().run(loadSpec())

    XCTAssertEqual(report.verdict, .pass)
    XCTAssertEqual(report.answerTriggeredAtMilliseconds, 420)
    let appearedAt = try XCTUnwrap(report.answerAppearedAtMilliseconds)
    XCTAssertGreaterThanOrEqual(appearedAt, 420)
    XCTAssertLessThan(appearedAt, 421)
    XCTAssertEqual(report.finalSpeechAtMilliseconds, 900)
    XCTAssertGreaterThan(try XCTUnwrap(report.deadlineHeadroomMilliseconds), 579)
    XCTAssertGreaterThan(try XCTUnwrap(report.answerLeadBeforeFinalMilliseconds), 479)
    XCTAssertEqual(report.revisions.count, 3)
    XCTAssertEqual(report.revisions[0].activeCandidateStatus, .provisional)
    XCTAssertNil(report.revisions[0].activeResponseCardID)
    XCTAssertEqual(report.revisions[1].activeCandidateStatus, .stable)
    XCTAssertEqual(report.revisions[1].activeResponseCardID, "card-revpar-2020")
    XCTAssertEqual(
      report.citations.map(\.passageID),
      [
        "passage-inventory-2020-actual",
        "passage-operating-2020-actual",
      ])
    XCTAssertTrue(report.citations.allSatisfy { $0.exists && $0.insidePack })
    XCTAssertTrue(report.checks.allSatisfy(\.passed))
    XCTAssertLessThanOrEqual(report.latency.maximumMilliseconds, 50)
  }

  func testReplayRunnerStartsWithFreshCandidateStateOnEveryRun() throws {
    let runner = try makeRunner()
    let spec = try loadSpec()

    let first = try runner.run(spec)
    let second = try runner.run(spec)

    XCTAssertEqual(first.verdict, .pass)
    XCTAssertEqual(second.verdict, .pass)
    XCTAssertEqual(
      first.revisions.map(\.activeCandidateID), second.revisions.map(\.activeCandidateID))
    XCTAssertEqual(first.answerTriggeredAtMilliseconds, second.answerTriggeredAtMilliseconds)
  }

  func testExpectedCardMismatchProducesFailedProofInsteadOfFalseSuccess() throws {
    let original = try loadSpec()
    let mismatched = KnowledgeProofReplaySpec(
      name: original.name,
      streamID: original.streamID,
      responseDeadlineMilliseconds: original.responseDeadlineMilliseconds,
      maximumProcessingLatencyMilliseconds: original.maximumProcessingLatencyMilliseconds,
      requireAnswerBeforeFinal: original.requireAnswerBeforeFinal,
      revisions: original.revisions,
      expected: KnowledgeProofReplayExpectation(
        questionFamilyID: original.expected.questionFamilyID,
        responseCardID: "card-that-does-not-exist",
        evidenceState: original.expected.evidenceState,
        answerContains: original.expected.answerContains,
        citationPassageIDs: original.expected.citationPassageIDs
      )
    )

    let report = try makeRunner().run(mismatched)

    XCTAssertEqual(report.verdict, .fail)
    XCTAssertEqual(
      report.checks.first(where: { $0.name == "reviewed_response_card" })?.passed,
      false
    )
  }

  func testOutOfOrderReplayIsRejectedBeforeRunning() throws {
    let original = try loadSpec()
    let outOfOrder = KnowledgeProofReplaySpec(
      name: original.name,
      streamID: original.streamID,
      responseDeadlineMilliseconds: original.responseDeadlineMilliseconds,
      maximumProcessingLatencyMilliseconds: original.maximumProcessingLatencyMilliseconds,
      requireAnswerBeforeFinal: original.requireAnswerBeforeFinal,
      revisions: [
        KnowledgeProofReplayRevision(
          atMilliseconds: 100,
          text: "What was the rev par",
          stability: .partial
        ),
        KnowledgeProofReplayRevision(
          atMilliseconds: 50,
          text: "What was the RevPAR for this asset in 2020?",
          stability: .final
        ),
      ],
      expected: original.expected
    )

    XCTAssertThrowsError(try makeRunner().run(outOfOrder)) { error in
      XCTAssertEqual(error as? KnowledgeProofReplayValidationError, .outOfOrderRevision(index: 1))
    }
  }

  private func makeRunner() throws -> KnowledgeProofReplayRunner {
    let registry = KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
    let pack = try KnowledgePackLoader(profileRegistry: registry).load(from: fixtureURL())
    return KnowledgeProofReplayRunner(
      pack: pack,
      rootDirectory: fixtureURL(),
      termAliases: registry.termAliases(for: pack.manifest)
    )
  }

  private func loadSpec() throws -> KnowledgeProofReplaySpec {
    let url = fixtureURL().appendingPathComponent("evaluation/live-proof-revpar.json")
    return try JSONDecoder().decode(
      KnowledgeProofReplaySpec.self,
      from: Data(contentsOf: url)
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
