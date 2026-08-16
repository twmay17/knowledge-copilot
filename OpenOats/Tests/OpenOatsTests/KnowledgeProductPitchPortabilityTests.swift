import XCTest

@testable import OpenOatsKit

final class KnowledgeProductPitchPortabilityTests: XCTestCase {
  func testPackLoadsWithGenericCoreAndNoDomainProfile() throws {
    let pack = try loadPack()

    XCTAssertEqual(pack.manifest.packID, "nestarc-go-product-pitch-v1")
    XCTAssertTrue(pack.manifest.domainProfiles.isEmpty)
    XCTAssertEqual(pack.sources.count, 4)
    XCTAssertEqual(pack.passages.count, 10)
    XCTAssertEqual(pack.assertions.count, 23)
    XCTAssertTrue(pack.calculations.isEmpty)
    XCTAssertEqual(pack.responseCards.count, 17)
    XCTAssertEqual(pack.questionFamilies.count, 17)
    XCTAssertFalse(pack.assertions.contains { $0.predicate.hasPrefix("hospitality.") })

    for source in pack.sources {
      let sourceText = try String(
        contentsOf: fixtureURL().appendingPathComponent(source.relativePath),
        encoding: .utf8
      ).lowercased()
      XCTAssertTrue(
        sourceText.contains("fictional") || sourceText.contains("synthetic"),
        "\(source.id) must identify its public-safe synthetic status"
      )
    }
  }

  func testAllSeventeenGoldenQuestionsDetectAndResolveExpectedReviewedCards() throws {
    let pack = try loadPack()
    let resolver = KnowledgeAnswerCardResolver(pack: pack, rootDirectory: fixtureURL())
    let goldenCases = try loadGoldenCases()

    XCTAssertGreaterThanOrEqual(goldenCases.count, 10)
    for (index, golden) in goldenCases.enumerated() {
      var detector = QuestionCandidateDetector(questionFamilies: pack.questionFamilies)
      let events = detector.process(
        TranscriptRevision(
          streamID: "golden-\(index)",
          sequence: 1,
          text: golden.utterance,
          stability: .final
        )
      )
      let candidate = try XCTUnwrap(
        events.compactMap { event -> QuestionCandidate? in
          guard case .upsert(let candidate) = event else { return nil }
          return candidate
        }.first,
        golden.id
      )
      let answer = try XCTUnwrap(resolver.resolve(candidate), golden.id)

      XCTAssertEqual(answer.responseCardID, golden.expectedCardID, golden.id)
      XCTAssertEqual(answer.evidenceState, golden.expectedEvidenceState, golden.id)
      XCTAssertFalse(answer.isFallback, golden.id)
      for fragment in golden.expectedAnswerContains {
        XCTAssertTrue(answer.answer.contains(fragment), "\(golden.id) missing '\(fragment)'")
      }
      switch answer.evidenceState {
      case .notFoundInCorpus, .needsClarification:
        XCTAssertTrue(answer.citations.isEmpty, golden.id)
      default:
        XCTAssertFalse(answer.citations.isEmpty, golden.id)
        XCTAssertTrue(
          answer.citations.allSatisfy {
            $0.fileURL.path.hasPrefix(fixtureURL().path)
              && FileManager.default.fileExists(atPath: $0.fileURL.path)
          },
          golden.id
        )
      }
    }
  }

  func testUnsafeAndUnsupportedClaimsFailClosedWhileDisagreementsStayVisible() throws {
    let cards = Dictionary(
      uniqueKeysWithValues: try loadPack().responseCards.map { ($0.id, $0) }
    )

    XCTAssertEqual(cards["card-contamination-missing"]?.evidenceState, .notFoundInCorpus)
    XCTAssertEqual(cards["card-sleep-safety-missing"]?.evidenceState, .notFoundInCorpus)
    XCTAssertEqual(cards["card-version-clarification"]?.evidenceState, .needsClarification)
    XCTAssertEqual(cards["card-wash-conflict"]?.evidenceState, .contested)
    XCTAssertEqual(cards["card-market-size"]?.evidenceState, .contested)
    XCTAssertEqual(cards["card-price-objection"]?.evidenceState, .interpretive)
    XCTAssertEqual(cards["card-modular-rationale"]?.evidenceState, .interpretive)
  }

  func testPartialSpeechReplayAnswersBeforeFinalWithPackBoundCitation() throws {
    let pack = try loadPack()
    let replayURL = fixtureURL().appendingPathComponent(
      "evaluation/live-proof-materials.json"
    )
    let spec = try JSONDecoder().decode(
      KnowledgeProofReplaySpec.self,
      from: Data(contentsOf: replayURL)
    )
    let report = try KnowledgeProofReplayRunner(
      pack: pack,
      rootDirectory: fixtureURL()
    ).run(spec)

    XCTAssertEqual(report.verdict, .pass)
    XCTAssertEqual(report.answerTriggeredAtMilliseconds, 420)
    XCTAssertLessThan(try XCTUnwrap(report.answerAppearedAtMilliseconds), 900)
    XCTAssertLessThanOrEqual(report.latency.maximumMilliseconds, 50)
    XCTAssertEqual(report.citations.map(\.passageID), ["passage-product-overview"])
    XCTAssertTrue(report.citations.allSatisfy { $0.exists && $0.insidePack })
    XCTAssertTrue(report.checks.allSatisfy(\.passed))
  }

  private func loadPack() throws -> KnowledgePack {
    try KnowledgePackLoader().load(from: fixtureURL())
  }

  private func loadGoldenCases() throws -> [GoldenCase] {
    let contents = try String(
      contentsOf: fixtureURL().appendingPathComponent("evaluation/golden-cases.jsonl"),
      encoding: .utf8
    )
    return try contents.split(whereSeparator: \.isNewline).map {
      try JSONDecoder().decode(GoldenCase.self, from: Data($0.utf8))
    }
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/nestarc-product-pitch", isDirectory: true)
  }

  private struct GoldenCase: Decodable {
    let id: String
    let utterance: String
    let expectedCardID: String
    let expectedEvidenceState: KnowledgeEvidenceState
    let expectedAnswerContains: [String]
  }
}
