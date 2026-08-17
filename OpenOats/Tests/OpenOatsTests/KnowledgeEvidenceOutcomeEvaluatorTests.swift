import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeEvidenceOutcomeEvaluatorTests: XCTestCase {
  func testConflictingAssertionsRemainSeparateWithEveryContributingSource() throws {
    let pack = try loadFixture()
    let outcome = try makeEvaluator(pack: pack).evaluate(revPARQuery())

    XCTAssertEqual(outcome.state, .contested)
    XCTAssertEqual(outcome.reason, .conflictingAssertions)
    XCTAssertEqual(
      outcome.claims.map(\.assertionID),
      [
        "assertion-revpar-calculated-2020",
        "assertion-revpar-memo-2020",
        "assertion-revpar-reported-2020",
      ]
    )
    XCTAssertEqual(
      Set(outcome.claims.map(\.displayValue)),
      ["89.5 USD_per_available_room", "92 USD_per_available_room"])
    XCTAssertTrue(outcome.claims.allSatisfy { !$0.attributions.isEmpty })
    XCTAssertEqual(
      Set(outcome.contributingSources.map(\.sourceID)),
      ["source-investment-memo", "source-operating-statement"]
    )
    XCTAssertTrue(
      outcome.contributingSources.allSatisfy {
        $0.fileURL.isFileURL && FileManager.default.fileExists(atPath: $0.fileURL.path)
      }
    )

    let encoded = try JSONEncoder().encode(outcome)
    XCTAssertEqual(try JSONDecoder().decode(KnowledgeEvidenceOutcome.self, from: encoded), outcome)
  }

  func testIncompatibleDefinitionVersionsStayVisibleInsteadOfMerging() throws {
    let pack = try loadFixture()
    let claims = [
      sourcedAssertion(
        id: "definition-draft",
        predicate: "generic.available_inventory_definition",
        value: KnowledgeValue(type: .text, text: "All rooms in physical inventory"),
        qualifiers: ["version": "draft"]
      ),
      sourcedAssertion(
        id: "definition-approved",
        predicate: "generic.available_inventory_definition",
        value: KnowledgeValue(type: .text, text: "Sellable rooms after out-of-order exclusions"),
        qualifiers: ["version": "approved"],
        passageID: "passage-memo-revpar-2020"
      ),
    ]
    let expanded = copy(
      pack,
      assertions: pack.assertions + claims.map(\.assertion),
      evidenceLinks: pack.evidenceLinks + claims.map(\.evidence)
    )

    let outcome = try makeEvaluator(pack: expanded).evaluate(
      KnowledgeEvidenceQuery(
        subject: "synthetic-hotel",
        predicate: "generic.available_inventory_definition",
        requiredFields: [.entity]
      ))

    XCTAssertEqual(outcome.state, .contested)
    XCTAssertEqual(outcome.reason, .incompatibleContexts)
    XCTAssertEqual(
      Set(outcome.claims.compactMap { $0.qualifiers["version"] }), ["draft", "approved"])
    XCTAssertEqual(outcome.claims.count, 2)
    XCTAssertTrue(outcome.claims.allSatisfy { !$0.attributions.isEmpty })
  }

  func testInterpretiveClaimIsLabeledAndAttributed() throws {
    let pack = try loadFixture()
    let interpretation = sourcedAssertion(
      id: "positioning-interpretation",
      predicate: "generic.market_positioning",
      value: KnowledgeValue(type: .text, text: "The asset appears operationally resilient"),
      qualifiers: ["version": "analyst-v1"],
      kind: .interpretive,
      relation: .contextualizes
    )
    let expanded = copy(
      pack,
      assertions: pack.assertions + [interpretation.assertion],
      evidenceLinks: pack.evidenceLinks + [interpretation.evidence]
    )

    let outcome = try makeEvaluator(pack: expanded).evaluate(
      KnowledgeEvidenceQuery(
        subject: "synthetic-hotel",
        predicate: "generic.market_positioning",
        qualifiers: ["version": "analyst-v1"],
        requiredFields: [.entity, .version]
      ))

    XCTAssertEqual(outcome.state, .interpretive)
    XCTAssertEqual(outcome.reason, .interpretiveClaims)
    XCTAssertEqual(outcome.claims.map(\.kind), [.interpretive])
    XCTAssertEqual(outcome.claims.first?.attributions.first?.relation, .contextualizes)
    XCTAssertEqual(outcome.contributingSources.map(\.sourceID), ["source-operating-statement"])
  }

  func testMissingRequiredEntityPeriodScopeAndVersionNeedsClarification() throws {
    let outcome = try makeEvaluator(pack: loadFixture()).evaluate(
      KnowledgeEvidenceQuery(
        predicate: "hospitality.revpar",
        requiredFields: [.entity, .period, .scope, .version]
      ))

    XCTAssertEqual(outcome.state, .needsClarification)
    XCTAssertEqual(outcome.reason, .insufficientContext)
    XCTAssertEqual(outcome.missingFields, [.entity, .period, .scope, .version])
    XCTAssertTrue(outcome.claims.isEmpty)
  }

  func testAbsentSupportReturnsNotFoundInCorpusWithoutInventingAClaim() throws {
    let outcome = try makeEvaluator(pack: loadFixture()).evaluate(
      KnowledgeEvidenceQuery(
        subject: "synthetic-hotel",
        predicate: "hospitality.revpar",
        qualifiers: ["period": "2018", "scope": "rooms", "status": "actual"],
        requiredFields: [.entity, .period, .scope]
      ))

    XCTAssertEqual(outcome.state, .notFoundInCorpus)
    XCTAssertEqual(outcome.reason, .noMatchingAssertions)
    XCTAssertTrue(outcome.claims.isEmpty)
    XCTAssertTrue(outcome.contributingSources.isEmpty)
  }

  func testProposedClaimContradictedBySingleCorpusValueIsExplicit() throws {
    let outcome = try makeEvaluator(pack: loadFixture()).evaluate(
      KnowledgeEvidenceQuery(
        subject: "synthetic-hotel",
        predicate: "hospitality.room_count",
        qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
        requiredFields: [.entity, .period, .scope],
        proposedValue: KnowledgeValue(
          type: .number,
          number: 120,
          unit: "room",
          scale: 1
        )
      ))

    XCTAssertEqual(outcome.state, .contradictedByCorpus)
    XCTAssertEqual(outcome.reason, .claimContradicted)
    XCTAssertEqual(outcome.claims.map(\.displayValue), ["100 room"])
    XCTAssertEqual(outcome.contributingSources.map(\.sourceID), ["source-room-inventory"])
  }

  func testUnavailableEvidenceFailsClosedButRetainsTheTypedClaimForDiagnosis() throws {
    let pack = try loadFixture()
    let missingRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("missing-evidence-\(UUID().uuidString)", isDirectory: true)
    let outcome = try makeEvaluator(pack: pack, rootDirectory: missingRoot).evaluate(
      KnowledgeEvidenceQuery(
        subject: "synthetic-hotel",
        predicate: "hospitality.room_count",
        qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
        requiredFields: [.entity, .period, .scope]
      ))

    XCTAssertEqual(outcome.state, .needsClarification)
    XCTAssertEqual(outcome.reason, .evidenceUnavailable)
    XCTAssertEqual(outcome.claims.map(\.assertionID), ["assertion-room-count-2020"])
    XCTAssertEqual(outcome.unresolvedAssertionIDs, ["assertion-room-count-2020"])
    XCTAssertTrue(outcome.contributingSources.isEmpty)
  }

  @MainActor
  func testStoreBuildsAndClearsTheEvaluatorWithTheActivePack() async throws {
    let store = KnowledgePackStore(profileRegistry: registry)
    await store.load(fromPath: fixtureURL().path)

    let outcome = try store.evaluateKnowledgeEvidence(revPARQuery())
    XCTAssertEqual(outcome.state, .contested)
    XCTAssertEqual(outcome.packID, "synthetic-hotel-2020-v1")

    store.clear()
    XCTAssertThrowsError(try store.evaluateKnowledgeEvidence(revPARQuery())) { error in
      XCTAssertEqual(error as? KnowledgePackSearchError, .indexUnavailable)
    }
  }

  func testEvaluatorRejectsAnIndexFromDifferentPackContent() throws {
    let pack = try loadFixture()
    let index = try KnowledgePackSearchIndex(pack: pack)
    let changedManifest = KnowledgePackManifest(
      schemaVersion: pack.manifest.schemaVersion,
      packID: "another-pack",
      title: pack.manifest.title,
      createdAt: pack.manifest.createdAt,
      defaultLocale: pack.manifest.defaultLocale,
      domainProfiles: pack.manifest.domainProfiles
    )
    let changed = KnowledgePack(
      manifest: changedManifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )

    XCTAssertThrowsError(
      try KnowledgeEvidenceOutcomeEvaluator(
        pack: changed,
        searchIndex: index,
        rootDirectory: fixtureURL()
      )
    ) { error in
      XCTAssertEqual(error as? KnowledgeEvidenceOutcomeError, .staleIndex)
    }
  }

  func testMoreThanSearchLimitFailsClosedInsteadOfDroppingACompetingClaim() throws {
    let pack = try loadFixture()
    let claims = (0...100).map { index in
      sourcedAssertion(
        id: "large-set-\(index)",
        predicate: "generic.large_claim_set",
        value: KnowledgeValue(type: .number, number: Double(index), unit: "count", scale: 1),
        qualifiers: ["period": "2026"]
      )
    }
    let expanded = copy(
      pack,
      assertions: pack.assertions + claims.map(\.assertion),
      evidenceLinks: pack.evidenceLinks + claims.map(\.evidence)
    )

    let outcome = try makeEvaluator(pack: expanded).evaluate(
      KnowledgeEvidenceQuery(
        subject: "synthetic-hotel",
        predicate: "generic.large_claim_set",
        qualifiers: ["period": "2026"],
        requiredFields: [.entity, .period]
      ))

    XCTAssertEqual(outcome.state, .needsClarification)
    XCTAssertEqual(outcome.reason, .retrievalIncomplete)
    XCTAssertEqual(outcome.unresolvedAssertionIDs.count, 1)
    XCTAssertTrue(outcome.claims.isEmpty)
  }

  private var registry: KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func revPARQuery() -> KnowledgeEvidenceQuery {
    KnowledgeEvidenceQuery(
      subject: "synthetic-hotel",
      predicate: "hospitality.revpar",
      qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
      requiredFields: [.entity, .period, .scope]
    )
  }

  private func makeEvaluator(
    pack: KnowledgePack,
    rootDirectory: URL? = nil
  ) throws -> KnowledgeEvidenceOutcomeEvaluator {
    try KnowledgeEvidenceOutcomeEvaluator(
      pack: pack,
      searchIndex: KnowledgePackSearchIndex(pack: pack),
      rootDirectory: rootDirectory ?? fixtureURL()
    )
  }

  private func loadFixture() throws -> KnowledgePack {
    try KnowledgePackLoader(profileRegistry: registry).load(from: fixtureURL())
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }

  private func sourcedAssertion(
    id: String,
    predicate: String,
    value: KnowledgeValue,
    qualifiers: [String: String],
    passageID: String = "passage-operating-2020-actual",
    kind: KnowledgeAssertionKind = .stated,
    relation: KnowledgeEvidenceRelation = .supports
  ) -> (assertion: KnowledgeAssertion, evidence: KnowledgeEvidenceLink) {
    let assertionID = "assertion-\(id)"
    let evidenceID = "evidence-\(id)"
    return (
      KnowledgeAssertion(
        id: assertionID,
        subject: "synthetic-hotel",
        predicate: predicate,
        value: value,
        qualifiers: qualifiers,
        kind: kind,
        confidence: 0.8,
        evidenceLinkIDs: [evidenceID]
      ),
      KnowledgeEvidenceLink(
        id: evidenceID,
        assertionID: assertionID,
        passageID: passageID,
        relation: relation,
        note: "Synthetic evaluator test evidence."
      )
    )
  }

  private func copy(
    _ pack: KnowledgePack,
    assertions: [KnowledgeAssertion],
    evidenceLinks: [KnowledgeEvidenceLink]
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: assertions,
      evidenceLinks: evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
  }

  func testFractionalPercentClaimIsNotFalselyContradictedThroughEvaluatePath() throws {
    let pack = try loadFixture()
    let stored = sourcedAssertion(
      id: "assertion-cancellation-rate-2020",
      predicate: "generic.cancellation_rate",
      value: KnowledgeValue(type: .number, number: 0.0805, unit: "ratio", scale: 1),
      qualifiers: ["period": "2020"]
    )
    let expanded = copy(
      pack,
      assertions: pack.assertions + [stored.assertion],
      evidenceLinks: pack.evidenceLinks + [stored.evidence]
    )

    // Exactly the live parse path for a spoken "8.05%": divide by 100, unit ratio.
    let spoken = KnowledgeValue(type: .number, number: 8.05 / 100.0, unit: "ratio", scale: 1)
    let outcome = try makeEvaluator(pack: expanded).evaluate(
      KnowledgeEvidenceQuery(
        predicate: "generic.cancellation_rate",
        qualifiers: ["period": "2020"],
        proposedValue: spoken
      )
    )
    XCTAssertEqual(outcome.state, .directlySourced)

    // A genuinely different spoken value must still be contradicted.
    let different = KnowledgeValue(type: .number, number: 9.05 / 100.0, unit: "ratio", scale: 1)
    let contradicted = try makeEvaluator(pack: expanded).evaluate(
      KnowledgeEvidenceQuery(
        predicate: "generic.cancellation_rate",
        qualifiers: ["period": "2020"],
        proposedValue: different
      )
    )
    XCTAssertEqual(contradicted.state, .contradictedByCorpus)
    XCTAssertEqual(contradicted.reason, .claimContradicted)
  }
}
