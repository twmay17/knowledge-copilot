import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeDomainProfileRegistryTests: XCTestCase {
  func testHospitalitySchemaRegistersTypedQualifiersVocabularyAndReferenceCalculations() throws {
    let schema = try XCTUnwrap(registry.schema(id: "hospitality", version: "0.1.0"))
    let qualifiers = Dictionary(uniqueKeysWithValues: schema.qualifiers.map { ($0.key, $0) })
    let predicates = Dictionary(uniqueKeysWithValues: schema.predicates.map { ($0.predicate, $0) })
    let calculations = Dictionary(uniqueKeysWithValues: schema.calculations.map { ($0.id, $0) })

    XCTAssertEqual(qualifiers["period"]?.valueType, .year)
    XCTAssertEqual(
      qualifiers["status"]?.allowedValues,
      ["actual", "budget", "forecast"]
    )
    XCTAssertTrue(predicates["hospitality.revpar"]?.aliases.contains("RevPAR") == true)
    XCTAssertEqual(calculations["hospitality.occupancy"]?.operation, .divide)
    XCTAssertEqual(calculations["hospitality.adr"]?.operation, .divide)
    XCTAssertEqual(calculations["hospitality.revpar"]?.operation, .divide)
    XCTAssertEqual(calculations["hospitality.net_operating_income"]?.operation, .subtract)
    XCTAssertEqual(calculations["hospitality.noi_margin"]?.operation, .divide)
    XCTAssertEqual(calculations["hospitality.total_revenue_growth"]?.operation, .growth)
  }

  func testTypedHospitalityQualifiersFailClosed() throws {
    let pack = try loadFixture()
    let roomCount = try XCTUnwrap(
      pack.assertions.first { $0.id == "assertion-room-count-2020" })
    var invalidQualifiers = roomCount.qualifiers
    invalidQualifiers["period"] = "20"
    invalidQualifiers["status"] = "historic"
    let invalid = replacing(
      pack,
      assertion: replacing(roomCount, qualifiers: invalidQualifiers)
    )

    let report = loader.validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertGreaterThanOrEqual(
      report.errors.filter { $0.code == "profile.invalid_qualifier_value" }.count,
      2
    )
  }

  func testRegisteredArithmeticAndUnitsFailClosedWhenTampered() throws {
    let pack = try loadFixture()
    let revPAR = try XCTUnwrap(
      pack.assertions.first { $0.id == "assertion-revpar-calculated-2020" })
    let wrongResult = replacing(
      revPAR,
      value: KnowledgeValue(
        type: .number,
        number: 90,
        unit: "USD_per_available_room",
        scale: 1
      )
    )
    let wrongResultReport = loader.validate(replacing(pack, assertion: wrongResult))

    XCTAssertTrue(
      wrongResultReport.errors.contains { $0.code == "profile.calculation_result_mismatch" })

    let roomRevenue = try XCTUnwrap(
      pack.assertions.first { $0.id == "assertion-room-revenue-2020" })
    let wrongUnit = replacing(
      roomRevenue,
      value: KnowledgeValue(type: .number, number: 3_266_750, unit: "EUR", scale: 1)
    )
    let wrongUnitReport = loader.validate(replacing(pack, assertion: wrongUnit))

    XCTAssertTrue(
      wrongUnitReport.errors.contains { $0.code == "profile.calculation_input_unit_mismatch" }
    )
  }

  func testUndefinedDivisionFailsClosed() throws {
    let pack = try loadFixture()
    let availableRoomNights = try XCTUnwrap(
      pack.assertions.first { $0.id == "assertion-available-room-nights-2020" })
    let zeroDenominator = replacing(
      availableRoomNights,
      value: KnowledgeValue(type: .number, number: 0, unit: "room_night", scale: 1)
    )

    let report = loader.validate(replacing(pack, assertion: zeroDenominator))

    XCTAssertTrue(
      report.errors.contains { $0.code == "profile.calculation_invalid_arithmetic" })
  }

  func testNOIMarginAndGrowthRulesValidateArithmeticAndOrderedPeriods() {
    let pack = makeReferenceCalculationPack()
    let validReport = loader.validate(pack)

    XCTAssertTrue(
      validReport.isValid, validReport.errors.map(\.description).joined(separator: "\n"))

    let growth = pack.assertions.first { $0.id == "assertion-growth" }!
    var mismatchedQualifiers = growth.qualifiers
    mismatchedQualifiers["prior_period"] = "2018"
    let invalid = replacing(
      pack,
      assertion: replacing(growth, qualifiers: mismatchedQualifiers)
    )
    let invalidReport = loader.validate(invalid)

    XCTAssertTrue(
      invalidReport.errors.contains { $0.code == "profile.calculation_period_mismatch" })
  }

  func testCalculationAnswerExposesResolvedOperandsAndTheirSources() throws {
    let pack = try loadFixture()
    let resolver = KnowledgeAnswerCardResolver(pack: pack, rootDirectory: fixtureURL())
    let candidate = QuestionCandidate(
      id: "remote#profile-test",
      streamID: "remote",
      revisionSequence: 1,
      questionFamilyID: "question-revpar-period",
      sourceText: "What was RevPAR for this asset in 2020?",
      confidence: 1,
      status: .stable,
      bindings: [
        ResolvedQuestionBinding(key: "period", value: "2020", surfaceText: "2020"),
        ResolvedQuestionBinding(
          key: "term",
          value: "hospitality.revpar",
          surfaceText: "RevPAR"
        ),
      ]
    )

    let answer = try XCTUnwrap(resolver.resolve(candidate))
    let calculation = try XCTUnwrap(answer.calculations.first)

    XCTAssertEqual(
      calculation.inputs.map(\.predicate),
      ["hospitality.room_revenue", "hospitality.available_room_nights"]
    )
    XCTAssertEqual(calculation.inputs.map(\.displayValue), ["3266750 USD", "36500 room_night"])
    XCTAssertTrue(calculation.inputs.allSatisfy { $0.qualifiers["status"] == "actual" })
    XCTAssertTrue(calculation.inputs.allSatisfy { !$0.citations.isEmpty })
    XCTAssertEqual(calculation.output?.predicate, "hospitality.revpar")
    XCTAssertEqual(calculation.output?.displayValue, "89.5 USD_per_available_room")
  }

  func testGenericPackLoadsWhenHospitalityProfileIsNotInstalled() {
    let source = KnowledgeSource(
      id: "source-generic",
      kind: .document,
      title: "Generic source",
      relativePath: "generic.txt",
      sha256: String(repeating: "a", count: 64),
      importedAt: Date(timeIntervalSince1970: 0)
    )
    let passage = KnowledgePassage(
      id: "passage-generic",
      sourceID: source.id,
      text: "The launch is approved.",
      locator: KnowledgeSourceLocator(block: 1)
    )
    let assertion = KnowledgeAssertion(
      id: "assertion-generic",
      subject: "product",
      predicate: "generic.launch_status",
      value: KnowledgeValue(type: .text, text: "approved"),
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: ["evidence-generic"]
    )
    let evidence = KnowledgeEvidenceLink(
      id: "evidence-generic",
      assertionID: assertion.id,
      passageID: passage.id,
      relation: .supports
    )
    let pack = KnowledgePack(
      manifest: KnowledgePackManifest(
        schemaVersion: KnowledgePackSchema.currentVersion,
        packID: "generic-pack",
        title: "Generic pack",
        createdAt: Date(timeIntervalSince1970: 0),
        defaultLocale: "en-US",
        domainProfiles: []
      ),
      sources: [source],
      passages: [passage],
      assertions: [assertion],
      evidenceLinks: [evidence],
      calculations: [],
      responseCards: [],
      questionFamilies: []
    )

    let report = KnowledgePackLoader(profileRegistry: .empty).validate(pack)

    XCTAssertTrue(report.isValid, report.errors.map(\.description).joined(separator: "\n"))
  }

  private var registry: KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private var loader: KnowledgePackLoader {
    KnowledgePackLoader(profileRegistry: registry)
  }

  private func loadFixture() throws -> KnowledgePack {
    try loader.load(from: fixtureURL())
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }

  private func makeReferenceCalculationPack() -> KnowledgePack {
    let source = KnowledgeSource(
      id: "source-reference",
      kind: .spreadsheet,
      title: "Reference operating statement",
      relativePath: "reference.csv",
      sha256: String(repeating: "b", count: 64),
      importedAt: Date(timeIntervalSince1970: 0)
    )
    let passage = KnowledgePassage(
      id: "passage-reference",
      sourceID: source.id,
      text: "Synthetic current and prior operating results.",
      locator: KnowledgeSourceLocator(sheet: "Reference", cellRange: "A1:F6")
    )
    let specifications:
      [(
        id: String,
        predicate: String,
        number: Double,
        unit: String,
        qualifiers: [String: String],
        kind: KnowledgeAssertionKind
      )] = [
        (
          "gop", "hospitality.gross_operating_profit", 1_500_000, "USD",
          ["period": "2020", "status": "actual"], .stated
        ),
        (
          "fixed", "hospitality.fixed_charges", 300_000, "USD",
          ["period": "2020", "status": "actual"], .stated
        ),
        (
          "noi", "hospitality.net_operating_income", 1_200_000, "USD",
          ["period": "2020", "status": "actual"], .calculated
        ),
        (
          "revenue-current", "hospitality.total_revenue", 4_000_000, "USD",
          ["period": "2020", "status": "actual"], .stated
        ),
        (
          "margin", "hospitality.noi_margin", 0.3, "ratio",
          ["period": "2020", "status": "actual"], .calculated
        ),
        (
          "revenue-prior", "hospitality.total_revenue", 3_600_000, "USD",
          ["period": "2019", "status": "actual"], .stated
        ),
        (
          "growth", "hospitality.total_revenue_growth", (4_000_000 / 3_600_000) - 1,
          "ratio",
          ["current_period": "2020", "prior_period": "2019", "status": "actual"],
          .calculated
        ),
      ]
    let assertions = specifications.map { specification in
      KnowledgeAssertion(
        id: "assertion-\(specification.id)",
        subject: "synthetic-hotel",
        predicate: specification.predicate,
        value: KnowledgeValue(
          type: .number,
          number: specification.number,
          unit: specification.unit,
          scale: 1
        ),
        qualifiers: specification.qualifiers,
        kind: specification.kind,
        confidence: 1,
        evidenceLinkIDs: ["evidence-\(specification.id)"]
      )
    }
    let evidence = assertions.map { assertion in
      KnowledgeEvidenceLink(
        id: assertion.evidenceLinkIDs[0],
        assertionID: assertion.id,
        passageID: passage.id,
        relation: assertion.kind == .calculated ? .derives : .supports
      )
    }
    let calculations = [
      KnowledgeCalculation(
        id: "calculation-noi",
        name: "Net operating income",
        version: "1.0.0",
        expression: "gross_operating_profit - fixed_charges",
        inputAssertionIDs: ["assertion-gop", "assertion-fixed"],
        outputAssertionID: "assertion-noi"
      ),
      KnowledgeCalculation(
        id: "calculation-margin",
        name: "NOI margin",
        version: "1.0.0",
        expression: "net_operating_income / total_revenue",
        inputAssertionIDs: ["assertion-noi", "assertion-revenue-current"],
        outputAssertionID: "assertion-margin"
      ),
      KnowledgeCalculation(
        id: "calculation-growth",
        name: "Total revenue growth",
        version: "1.0.0",
        expression: "(current_total_revenue / prior_total_revenue) - 1",
        inputAssertionIDs: ["assertion-revenue-current", "assertion-revenue-prior"],
        outputAssertionID: "assertion-growth"
      ),
    ]
    return KnowledgePack(
      manifest: KnowledgePackManifest(
        schemaVersion: KnowledgePackSchema.currentVersion,
        packID: "hospitality-reference-calculations",
        title: "Hospitality reference calculations",
        createdAt: Date(timeIntervalSince1970: 0),
        defaultLocale: "en-US",
        domainProfiles: [DomainProfileReference(id: "hospitality", version: "0.1.0")]
      ),
      sources: [source],
      passages: [passage],
      assertions: assertions,
      evidenceLinks: evidence,
      calculations: calculations,
      responseCards: [],
      questionFamilies: []
    )
  }

  private func replacing(
    _ assertion: KnowledgeAssertion,
    value: KnowledgeValue
  ) -> KnowledgeAssertion {
    KnowledgeAssertion(
      id: assertion.id,
      subject: assertion.subject,
      predicate: assertion.predicate,
      value: value,
      qualifiers: assertion.qualifiers,
      kind: assertion.kind,
      confidence: assertion.confidence,
      evidenceLinkIDs: assertion.evidenceLinkIDs
    )
  }

  private func replacing(
    _ assertion: KnowledgeAssertion,
    qualifiers: [String: String]
  ) -> KnowledgeAssertion {
    KnowledgeAssertion(
      id: assertion.id,
      subject: assertion.subject,
      predicate: assertion.predicate,
      value: assertion.value,
      qualifiers: qualifiers,
      kind: assertion.kind,
      confidence: assertion.confidence,
      evidenceLinkIDs: assertion.evidenceLinkIDs
    )
  }

  private func replacing(
    _ pack: KnowledgePack,
    assertion: KnowledgeAssertion
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions.map { $0.id == assertion.id ? assertion : $0 },
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
  }
}
