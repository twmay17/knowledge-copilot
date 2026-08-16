import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeCorrectnessGateTests: XCTestCase {
  func testGoldenCorrectnessGatePassesEveryReleaseCheck() throws {
    let report = try run(with: try loadPacks())

    XCTAssertEqual(report.verdict, .pass)
    XCTAssertTrue(report.checks.allSatisfy(\.passed))
    XCTAssertEqual(report.packAudits.count, 2)
    XCTAssertTrue(report.packAudits.allSatisfy { $0.verdict == .pass })
    XCTAssertEqual(report.outcomeAudits.count, 8)
    XCTAssertTrue(report.outcomeAudits.allSatisfy(\.passed))
    XCTAssertEqual(
      Set(report.outcomeAudits.compactMap(\.actualState)), Set(KnowledgeEvidenceState.allCases))
    XCTAssertEqual(report.replayAudit?.scenarioCount, 101)
    XCTAssertEqual(report.replayAudit?.passedScenarioCount, 101)
    XCTAssertEqual(report.replayAudit?.crossPackScenarioCount, 2)
    XCTAssertEqual(report.replayAudit?.passedCrossPackScenarioCount, 2)
  }

  func testStructurallyValidQualifierDriftFailsGoldenAssertionFingerprint() throws {
    var packs = try loadPacks()
    let configured = try XCTUnwrap(packs[productPackID])
    let alteredAssertions = configured.pack.assertions.map { assertion in
      guard assertion.id == "assertion-product-category" else { return assertion }
      return replacing(assertion, qualifiers: ["version": "pilot"])
    }
    packs[productPackID] = replacing(
      configured,
      pack: replacing(configured.pack, assertions: alteredAssertions)
    )

    let report = try run(with: packs)

    XCTAssertEqual(report.verdict, .fail)
    let audit = try XCTUnwrap(report.packAudits.first { $0.packID == productPackID })
    XCTAssertTrue(audit.findings.contains { $0.code == "fingerprint.assertions" })
    XCTAssertTrue(
      audit.findings.allSatisfy { $0.code != "loader.profile.invalid_qualifier_value" },
      "The immutable golden assertion fingerprint must catch drift even when generic structure is valid."
    )
  }

  func testCorruptedCalculationOutputFailsArithmeticBeforeReplay() throws {
    var packs = try loadPacks()
    let configured = try XCTUnwrap(packs[hospitalityPackID])
    let alteredAssertions = configured.pack.assertions.map { assertion in
      guard assertion.id == "assertion-occupancy-2020" else { return assertion }
      return replacing(
        assertion,
        value: KnowledgeValue(type: .number, number: 0.71, unit: "ratio", scale: 1)
      )
    }
    packs[hospitalityPackID] = replacing(
      configured,
      pack: replacing(configured.pack, assertions: alteredAssertions)
    )

    let report = try run(with: packs)

    XCTAssertEqual(report.verdict, .fail)
    XCTAssertNil(report.replayAudit)
    let audit = try XCTUnwrap(report.packAudits.first { $0.packID == hospitalityPackID })
    XCTAssertTrue(
      audit.findings.contains { $0.code == "loader.profile.calculation_result_mismatch" })
    XCTAssertEqual(
      report.checks.first { $0.name == "calculation_accuracy" }?.passed,
      false
    )
  }

  func testMislabeledEvidenceStateFailsFingerprintAndReplayGroundTruth() throws {
    var packs = try loadPacks()
    let configured = try XCTUnwrap(packs[productPackID])
    let alteredCards = configured.pack.responseCards.map { card in
      guard card.id == "card-materials" else { return card }
      return replacing(card, evidenceState: .supportedByCorpus)
    }
    packs[productPackID] = replacing(
      configured,
      pack: replacing(configured.pack, responseCards: alteredCards)
    )

    let report = try run(with: packs)

    XCTAssertEqual(report.verdict, .fail)
    let audit = try XCTUnwrap(report.packAudits.first { $0.packID == productPackID })
    XCTAssertTrue(audit.findings.contains { $0.code == "fingerprint.response_cards" })
    XCTAssertEqual(report.replayAudit?.verdict, .fail)
    XCTAssertFalse(report.replayAudit?.failedScenarioIDs.isEmpty ?? true)
  }

  func testCitationSwapToExistingPackPassageFailsClaimProvenanceAndReplay() throws {
    var packs = try loadPacks()
    let configured = try XCTUnwrap(packs[productPackID])
    let alteredCards = configured.pack.responseCards.map { card in
      guard card.id == "card-materials" else { return card }
      return replacing(card, citationPassageIDs: ["passage-product-roadmap"])
    }
    packs[productPackID] = replacing(
      configured,
      pack: replacing(configured.pack, responseCards: alteredCards)
    )

    let report = try run(with: packs)

    XCTAssertEqual(report.verdict, .fail)
    let audit = try XCTUnwrap(report.packAudits.first { $0.packID == productPackID })
    XCTAssertTrue(
      audit.findings.contains {
        $0.code == "card.provenance_not_cited" && $0.recordID == "card-materials"
      })
    XCTAssertEqual(report.checks.first { $0.name == "citation_resolution" }?.passed, false)
    XCTAssertEqual(report.replayAudit?.verdict, .fail)
  }

  func testCrossPackCitationReferenceFailsClosedInsideOwningPack() throws {
    var packs = try loadPacks()
    let configured = try XCTUnwrap(packs[productPackID])
    let alteredCards = configured.pack.responseCards.map { card in
      guard card.id == "card-materials" else { return card }
      return replacing(card, citationPassageIDs: ["passage-operating-2020-actual"])
    }
    packs[productPackID] = replacing(
      configured,
      pack: replacing(configured.pack, responseCards: alteredCards)
    )

    let report = try run(with: packs)

    XCTAssertEqual(report.verdict, .fail)
    XCTAssertNil(report.replayAudit)
    let audit = try XCTUnwrap(report.packAudits.first { $0.packID == productPackID })
    XCTAssertTrue(audit.findings.contains { $0.code == "loader.card.unknown_passage" })
    XCTAssertTrue(audit.findings.contains { $0.code == "citation.unresolved" })
  }

  private let hospitalityPackID = "synthetic-hotel-2020-v1"
  private let productPackID = "nestarc-go-product-pitch-v1"

  private var registry: KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func run(
    with packs: [String: KnowledgeReplayBenchmarkPack]
  ) throws -> KnowledgeCorrectnessGateReport {
    try KnowledgeCorrectnessGateRunner(packs: packs, profileRegistry: registry).run(
      loadCorrectnessSpec(),
      benchmark: loadBenchmarkSpec()
    )
  }

  private func loadPacks() throws -> [String: KnowledgeReplayBenchmarkPack] {
    let spec = try loadCorrectnessSpec()
    var packs: [String: KnowledgeReplayBenchmarkPack] = [:]
    for reference in spec.packs {
      let directory = fixtureRoot().appendingPathComponent(
        reference.relativePath,
        isDirectory: true
      )
      let pack = try KnowledgePackLoader(profileRegistry: registry).load(from: directory)
      packs[reference.packID] = KnowledgeReplayBenchmarkPack(
        pack: pack,
        rootDirectory: directory,
        termAliases: registry.termAliases(for: pack.manifest)
      )
    }
    return packs
  }

  private func loadCorrectnessSpec() throws -> KnowledgeCorrectnessGateSpec {
    try JSONDecoder().decode(
      KnowledgeCorrectnessGateSpec.self,
      from: Data(contentsOf: fixtureRoot().appendingPathComponent("correctness-gate-v1.json"))
    )
  }

  private func loadBenchmarkSpec() throws -> KnowledgeReplayBenchmarkSpec {
    try JSONDecoder().decode(
      KnowledgeReplayBenchmarkSpec.self,
      from: Data(contentsOf: fixtureRoot().appendingPathComponent("replay-benchmark-v1.json"))
    )
  }

  private func fixtureRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures", isDirectory: true)
  }

  private func replacing(
    _ configured: KnowledgeReplayBenchmarkPack,
    pack: KnowledgePack
  ) -> KnowledgeReplayBenchmarkPack {
    KnowledgeReplayBenchmarkPack(
      pack: pack,
      rootDirectory: configured.rootDirectory,
      termAliases: configured.termAliases
    )
  }

  private func replacing(
    _ pack: KnowledgePack,
    assertions: [KnowledgeAssertion]? = nil,
    responseCards: [KnowledgeResponseCard]? = nil
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: assertions ?? pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: responseCards ?? pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
  }

  private func replacing(
    _ assertion: KnowledgeAssertion,
    value: KnowledgeValue? = nil,
    qualifiers: [String: String]? = nil
  ) -> KnowledgeAssertion {
    KnowledgeAssertion(
      id: assertion.id,
      subject: assertion.subject,
      predicate: assertion.predicate,
      value: value ?? assertion.value,
      qualifiers: qualifiers ?? assertion.qualifiers,
      kind: assertion.kind,
      confidence: assertion.confidence,
      evidenceLinkIDs: assertion.evidenceLinkIDs
    )
  }

  private func replacing(
    _ card: KnowledgeResponseCard,
    evidenceState: KnowledgeEvidenceState? = nil,
    citationPassageIDs: [String]? = nil
  ) -> KnowledgeResponseCard {
    KnowledgeResponseCard(
      id: card.id,
      title: card.title,
      answer: card.answer,
      evidenceState: evidenceState ?? card.evidenceState,
      questionFamilyIDs: card.questionFamilyIDs,
      assertionIDs: card.assertionIDs,
      citationPassageIDs: citationPassageIDs ?? card.citationPassageIDs,
      calculationIDs: card.calculationIDs,
      reviewStatus: card.reviewStatus
    )
  }
}
