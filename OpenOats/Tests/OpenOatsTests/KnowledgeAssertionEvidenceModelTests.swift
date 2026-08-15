import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeAssertionEvidenceModelTests: XCTestCase {
  func testAllTypedValuesValidateAndExposeNormalizedContext() {
    let context = [
      "period": "2026",
      "version": "approved",
      "scope": "product-alpha",
      "audience": "retail",
    ]
    let records = [
      sourcedAssertion(
        id: "text", value: KnowledgeValue(type: .text, text: "Launch is approved"),
        qualifiers: context),
      sourcedAssertion(
        id: "number",
        value: KnowledgeValue(type: .number, number: 12, unit: "count", scale: 1),
        qualifiers: context),
      sourcedAssertion(
        id: "boolean", value: KnowledgeValue(type: .boolean, boolean: true),
        qualifiers: context),
      sourcedAssertion(
        id: "date", value: KnowledgeValue(type: .date, date: "2026-08-15"),
        qualifiers: context),
      sourcedAssertion(
        id: "reference",
        value: KnowledgeValue(type: .reference, referenceID: "entity-product-alpha"),
        qualifiers: context),
    ]

    let report = KnowledgePackLoader().validate(
      makePack(
        assertions: records.map(\.assertion),
        evidenceLinks: records.map(\.evidence)
      ))

    XCTAssertTrue(report.isValid, report.errors.map(\.description).joined(separator: "\n"))
    let normalized = records[0].assertion.context
    XCTAssertEqual(normalized.period, "2026")
    XCTAssertEqual(normalized.version, "approved")
    XCTAssertEqual(normalized.scope, "product-alpha")
    XCTAssertEqual(normalized.additionalQualifiers, ["audience": "retail"])
    XCTAssertEqual(normalized.qualifiers, context)
  }

  func testAssertionKindsRemainDistinctWithEvidenceOrDerivation() {
    let context = ["period": "2026", "version": "approved", "scope": "product-alpha"]
    let input = sourcedAssertion(
      id: "input",
      value: KnowledgeValue(type: .number, number: 10, unit: "count", scale: 1),
      qualifiers: context
    )
    let stated = sourcedAssertion(
      id: "stated",
      value: KnowledgeValue(type: .text, text: "Directly stated"),
      qualifiers: context,
      kind: .stated,
      relation: .supports
    )
    let inferred = sourcedAssertion(
      id: "inferred",
      value: KnowledgeValue(type: .text, text: "Evidence-backed inference"),
      qualifiers: context,
      kind: .inferred,
      relation: .contextualizes
    )
    let interpretive = sourcedAssertion(
      id: "interpretive",
      value: KnowledgeValue(type: .text, text: "Evidence-backed interpretation"),
      qualifiers: context,
      kind: .interpretive,
      relation: .contextualizes
    )
    let calculated = KnowledgeAssertion(
      id: "assertion-calculated",
      subject: "subject",
      predicate: "generic.calculated",
      value: KnowledgeValue(type: .number, number: 20, unit: "count", scale: 1),
      qualifiers: context,
      kind: .calculated,
      confidence: 1,
      evidenceLinkIDs: []
    )
    let calculation = KnowledgeCalculation(
      id: "calculation-generic",
      name: "Double the input",
      version: "1.0.0",
      expression: "input * 2",
      inputAssertionIDs: [input.assertion.id],
      outputAssertionID: calculated.id
    )

    let report = KnowledgePackLoader().validate(
      makePack(
        assertions: [
          input.assertion, stated.assertion, inferred.assertion, interpretive.assertion, calculated,
        ],
        evidenceLinks: [input.evidence, stated.evidence, inferred.evidence, interpretive.evidence],
        calculations: [calculation]
      ))

    XCTAssertTrue(report.isValid, report.errors.map(\.description).joined(separator: "\n"))
    XCTAssertEqual(
      Set([
        stated.assertion.kind, calculated.kind, inferred.assertion.kind,
        interpretive.assertion.kind,
      ]),
      [.stated, .calculated, .inferred, .interpretive]
    )
  }

  func testAssertionsWithoutEvidenceOrDerivationFailClosed() {
    let stated = KnowledgeAssertion(
      id: "assertion-unsourced",
      subject: "subject",
      predicate: "generic.unsourced",
      value: KnowledgeValue(type: .text, text: "Unsupported"),
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: []
    )
    let calculated = KnowledgeAssertion(
      id: "assertion-underived",
      subject: "subject",
      predicate: "generic.underived",
      value: KnowledgeValue(type: .number, number: 1, unit: "count", scale: 1),
      kind: .calculated,
      confidence: 1,
      evidenceLinkIDs: []
    )

    let report = KnowledgePackLoader().validate(
      makePack(assertions: [stated, calculated]))

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "assertion.missing_supporting_evidence" })
    XCTAssertTrue(report.errors.contains { $0.code == "assertion.missing_derivation" })
  }

  func testInvalidTypedValuesUnitsScalesAndQualifiersFailClosed() {
    let invalidRecords = [
      sourcedAssertion(
        id: "empty-text", value: KnowledgeValue(type: .text, text: " ")),
      sourcedAssertion(
        id: "invalid-number",
        value: KnowledgeValue(type: .number, number: .infinity, scale: 0)),
      sourcedAssertion(
        id: "invalid-date", value: KnowledgeValue(type: .date, date: "2026-02-30")),
      sourcedAssertion(
        id: "empty-reference",
        value: KnowledgeValue(type: .reference, referenceID: " ")),
      sourcedAssertion(
        id: "invalid-qualifier",
        value: KnowledgeValue(type: .boolean, boolean: true),
        qualifiers: ["Period": " 2026 "]
      ),
    ]

    let report = KnowledgePackLoader().validate(
      makePack(
        assertions: invalidRecords.map(\.assertion),
        evidenceLinks: invalidRecords.map(\.evidence)
      ))
    let codes = Set(report.errors.map(\.code))

    XCTAssertTrue(codes.contains("assertion.empty_text_value"))
    XCTAssertTrue(codes.contains("assertion.non_finite_number"))
    XCTAssertTrue(codes.contains("assertion.missing_numeric_unit"))
    XCTAssertTrue(codes.contains("assertion.invalid_numeric_scale"))
    XCTAssertTrue(codes.contains("assertion.invalid_date_value"))
    XCTAssertTrue(codes.contains("assertion.empty_reference_value"))
    XCTAssertTrue(codes.contains("assertion.invalid_qualifier_key"))
    XCTAssertTrue(codes.contains("assertion.invalid_qualifier_value"))
  }

  func testCalculationRejectsMixedAndMissingGenericContext() {
    let mismatched = sourcedAssertion(
      id: "mismatched-input",
      value: KnowledgeValue(type: .number, number: 10, unit: "count", scale: 1),
      qualifiers: ["period": "2025", "version": "draft", "scope": "portfolio"]
    )
    let missing = sourcedAssertion(
      id: "missing-input",
      value: KnowledgeValue(type: .number, number: 5, unit: "count", scale: 1)
    )
    let output = KnowledgeAssertion(
      id: "assertion-context-output",
      subject: "subject",
      predicate: "generic.context_output",
      value: KnowledgeValue(type: .number, number: 15, unit: "count", scale: 1),
      qualifiers: ["period": "2026", "version": "approved", "scope": "asset"],
      kind: .calculated,
      confidence: 1,
      evidenceLinkIDs: []
    )
    let calculation = KnowledgeCalculation(
      id: "calculation-context",
      name: "Context-sensitive sum",
      version: "1.0.0",
      expression: "mismatched + missing",
      inputAssertionIDs: [mismatched.assertion.id, missing.assertion.id],
      outputAssertionID: output.id
    )

    let report = KnowledgePackLoader().validate(
      makePack(
        assertions: [mismatched.assertion, missing.assertion, output],
        evidenceLinks: [mismatched.evidence, missing.evidence],
        calculations: [calculation]
      ))

    XCTAssertEqual(report.errors.filter { $0.code == "calculation.context_mismatch" }.count, 3)
    XCTAssertEqual(report.errors.filter { $0.code == "calculation.context_missing" }.count, 3)
  }

  func testEvidenceLinksMustBeClaimedAndDerivationRelationRequiresCalculatedKind() {
    let unclaimed = KnowledgeAssertion(
      id: "assertion-unclaimed",
      subject: "subject",
      predicate: "generic.unclaimed",
      value: KnowledgeValue(type: .text, text: "Claim"),
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: []
    )
    let unclaimedLink = KnowledgeEvidenceLink(
      id: "evidence-unclaimed",
      assertionID: unclaimed.id,
      passageID: passage.id,
      relation: .supports
    )
    let invalidDerivation = sourcedAssertion(
      id: "non-calculated-derivation",
      value: KnowledgeValue(type: .text, text: "Not calculated"),
      relation: .derives
    )

    let report = KnowledgePackLoader().validate(
      makePack(
        assertions: [unclaimed, invalidDerivation.assertion],
        evidenceLinks: [unclaimedLink, invalidDerivation.evidence]
      ))

    XCTAssertTrue(report.errors.contains { $0.code == "evidence.unclaimed_by_assertion" })
    XCTAssertTrue(report.errors.contains { $0.code == "evidence.derives_non_calculated" })
  }

  func testHospitalityExtendsContextWithStatusAndRequiresRoomScope() throws {
    let loader = KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))
    let pack = try loader.load(from: hospitalityFixtureURL())
    let roomRevenue = try XCTUnwrap(
      pack.assertions.first { $0.id == "assertion-room-revenue-2020" })
    var budgetQualifiers = roomRevenue.qualifiers
    budgetQualifiers["status"] = "budget"
    let budgetRoomRevenue = replacing(roomRevenue, qualifiers: budgetQualifiers)
    let statusMixed = replacing(
      pack,
      assertions: pack.assertions.map { $0.id == roomRevenue.id ? budgetRoomRevenue : $0 }
    )

    let statusReport = loader.validate(statusMixed)

    XCTAssertTrue(
      statusReport.errors.contains {
        $0.code == "calculation.context_mismatch" && $0.message.contains("status")
      })

    let revPAR = try XCTUnwrap(
      pack.assertions.first { $0.id == "assertion-revpar-calculated-2020" })
    var unscopedQualifiers = revPAR.qualifiers
    unscopedQualifiers.removeValue(forKey: "scope")
    let unscopedRevPAR = replacing(revPAR, qualifiers: unscopedQualifiers)
    let unscoped = replacing(
      pack,
      assertions: pack.assertions.map { $0.id == revPAR.id ? unscopedRevPAR : $0 }
    )

    let scopeReport = loader.validate(unscoped)

    XCTAssertTrue(
      scopeReport.errors.contains {
        $0.code == "profile.missing_qualifier" && $0.message.contains("scope")
      })
  }

  private var source: KnowledgeSource {
    KnowledgeSource(
      id: "source-generic",
      kind: .document,
      title: "Generic Source",
      relativePath: "generic-source.txt",
      sha256: String(repeating: "a", count: 64),
      importedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private var passage: KnowledgePassage {
    KnowledgePassage(
      id: "passage-generic",
      sourceID: source.id,
      text: "Generic source evidence.",
      locator: KnowledgeSourceLocator(block: 1)
    )
  }

  private func sourcedAssertion(
    id: String,
    value: KnowledgeValue,
    qualifiers: [String: String] = [:],
    kind: KnowledgeAssertionKind = .stated,
    relation: KnowledgeEvidenceRelation = .supports
  ) -> (assertion: KnowledgeAssertion, evidence: KnowledgeEvidenceLink) {
    let assertionID = "assertion-\(id)"
    let evidenceID = "evidence-\(id)"
    return (
      KnowledgeAssertion(
        id: assertionID,
        subject: "subject",
        predicate: "generic.\(id)",
        value: value,
        qualifiers: qualifiers,
        kind: kind,
        confidence: 1,
        evidenceLinkIDs: [evidenceID]
      ),
      KnowledgeEvidenceLink(
        id: evidenceID,
        assertionID: assertionID,
        passageID: passage.id,
        relation: relation
      )
    )
  }

  private func makePack(
    assertions: [KnowledgeAssertion],
    evidenceLinks: [KnowledgeEvidenceLink] = [],
    calculations: [KnowledgeCalculation] = []
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: KnowledgePackManifest(
        schemaVersion: KnowledgePackSchema.currentVersion,
        packID: "generic-assertion-test",
        title: "Generic Assertion Test",
        createdAt: Date(timeIntervalSince1970: 0),
        defaultLocale: "en-US",
        domainProfiles: []
      ),
      sources: [source],
      passages: [passage],
      assertions: assertions,
      evidenceLinks: evidenceLinks,
      calculations: calculations,
      responseCards: [],
      questionFamilies: []
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
    assertions: [KnowledgeAssertion]
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
  }

  private func hospitalityFixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }
}
