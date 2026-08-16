import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeReplayBenchmarkTests: XCTestCase {
  func testVersionedTwoDomainBenchmarkPassesAllOneHundredOneScenarios() throws {
    let spec = try loadSpec()

    let report = try makeRunner(for: spec).run(spec)

    XCTAssertEqual(report.verdict, .pass)
    XCTAssertEqual(report.scenarioCount, 101)
    XCTAssertEqual(report.passedScenarioCount, 101)
    XCTAssertEqual(
      report.scenariosByPack,
      [
        "nestarc-go-product-pitch-v1": 63,
        "synthetic-hotel-2020-v1": 38,
      ]
    )
    XCTAssertEqual(report.negativeScenarioCount, 4)
    XCTAssertEqual(report.falseCardCount, 0)
    XCTAssertEqual(report.falseCardRate, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["conflicting"] ?? 0, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["interpretive"] ?? 0, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["partial"] ?? 0, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["corrected"] ?? 0, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["ambiguous"] ?? 0, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["missing"] ?? 0, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["rhetorical"] ?? 0, 0)
    XCTAssertGreaterThan(report.scenariosByCategory["rapid_follow_up"] ?? 0, 0)
    XCTAssertTrue(report.scenarios.allSatisfy { $0.verdict == .pass })
    XCTAssertLessThanOrEqual(
      report.latency.p95Milliseconds,
      spec.maximumP95ProcessingLatencyMilliseconds
    )
  }

  func testEveryRunStartsFromCleanDetectorState() throws {
    let spec = try loadSpec()
    let runner = try makeRunner(for: spec)

    let first = try runner.run(spec)
    let second = try runner.run(spec)

    XCTAssertEqual(first.verdict, .pass)
    XCTAssertEqual(second.verdict, .pass)
    XCTAssertEqual(first.scenarios.map(\.id), second.scenarios.map(\.id))
    XCTAssertEqual(
      first.scenarios.map { $0.traces.map(\.actualKinds) },
      second.scenarios.map { $0.traces.map(\.actualKinds) }
    )
    XCTAssertEqual(
      first.scenarios.map(\.finalResponseCardID),
      second.scenarios.map(\.finalResponseCardID)
    )
  }

  func testIncorrectExpectedCardFailsTheScenarioAndOverallBenchmark() throws {
    let original = try loadSpec()
    let first = try XCTUnwrap(original.expandedScenarios.first)
    let altered = KnowledgeReplayBenchmarkScenario(
      id: first.id,
      packID: first.packID,
      categories: first.categories,
      revisions: first.revisions,
      expected: KnowledgeReplayBenchmarkExpectation(
        answerMode: .reviewed,
        questionFamilyID: first.expected.questionFamilyID,
        responseCardID: "card-that-does-not-exist",
        evidenceState: first.expected.evidenceState,
        answerContains: first.expected.answerContains,
        citationPassageIDs: first.expected.citationPassageIDs
      )
    )
    let spec = KnowledgeReplayBenchmarkSpec(
      name: "Deliberate expected-card mismatch",
      minimumScenarioCount: 1,
      maximumFalseCardRate: 0,
      maximumP95ProcessingLatencyMilliseconds: 50,
      redistributable: true,
      packs: original.packs,
      scenarioTemplates: [],
      scenarios: [altered]
    )

    let report = try makeRunner(for: spec).run(spec)

    XCTAssertEqual(report.verdict, .fail)
    XCTAssertEqual(report.passedScenarioCount, 0)
    XCTAssertEqual(report.scenarios.first?.verdict, .fail)
    XCTAssertEqual(
      report.scenarios.first?.checks.first(where: { $0.name == "response_card" })?.passed,
      false
    )
  }

  func testCorpusBelowDeclaredMinimumIsRejectedBeforeReplay() throws {
    let original = try loadSpec()
    let spec = KnowledgeReplayBenchmarkSpec(
      name: original.name,
      minimumScenarioCount: 100,
      maximumFalseCardRate: original.maximumFalseCardRate,
      maximumP95ProcessingLatencyMilliseconds: original.maximumP95ProcessingLatencyMilliseconds,
      redistributable: true,
      packs: original.packs,
      scenarioTemplates: [],
      scenarios: Array(original.expandedScenarios.prefix(99))
    )

    XCTAssertThrowsError(try makeRunner(for: spec).run(spec)) { error in
      XCTAssertEqual(
        error as? KnowledgeReplayBenchmarkValidationError,
        .belowMinimumScenarioCount(actual: 99, minimum: 100)
      )
    }
  }

  private func loadSpec() throws -> KnowledgeReplayBenchmarkSpec {
    try JSONDecoder().decode(
      KnowledgeReplayBenchmarkSpec.self,
      from: Data(contentsOf: fixtureRoot().appendingPathComponent("replay-benchmark-v1.json"))
    )
  }

  private func makeRunner(
    for spec: KnowledgeReplayBenchmarkSpec
  ) throws -> KnowledgeReplayBenchmarkRunner {
    let registry = KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
    var packs: [String: KnowledgeReplayBenchmarkPack] = [:]
    for reference in spec.packs {
      let directory = fixtureRoot().appendingPathComponent(
        reference.relativePath, isDirectory: true)
      let pack = try KnowledgePackLoader(profileRegistry: registry).load(from: directory)
      packs[reference.packID] = KnowledgeReplayBenchmarkPack(
        pack: pack,
        rootDirectory: directory,
        termAliases: registry.termAliases(for: pack.manifest)
      )
    }
    return KnowledgeReplayBenchmarkRunner(packs: packs)
  }

  private func fixtureRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures", isDirectory: true)
  }
}
