import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgePackLoaderTests: XCTestCase {
  func testValidKnowledgePackPassesStructuralValidation() {
    let report = makeLoader().validate(makeValidPack())

    XCTAssertTrue(report.isValid)
    XCTAssertTrue(report.errors.isEmpty)
  }

  func testCalculatedCardRequiresRecordedCalculation() {
    let valid = makeValidPack()
    let invalidCard = KnowledgeResponseCard(
      id: "card-revpar",
      title: "2020 RevPAR",
      answer: "$89.50",
      evidenceState: .calculated,
      questionFamilyIDs: ["question-revpar"],
      assertionIDs: ["assertion-revpar"],
      citationPassageIDs: ["passage-revpar"],
      calculationIDs: [],
      reviewStatus: .reviewed
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions,
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: [invalidCard],
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "card.calculation_missing_derivation" })
  }

  func testAssertionCannotBorrowAnotherAssertionsEvidence() {
    let valid = makeValidPack()
    let mismatched = KnowledgeAssertion(
      id: "assertion-other",
      subject: "synthetic-hotel",
      predicate: "hospitality.occupancy",
      value: KnowledgeValue(type: .number, number: 0.75, unit: "ratio", scale: 1),
      qualifiers: ["period": "2020"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: ["evidence-revpar"]
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions + [mismatched],
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "assertion.mismatched_evidence" })
  }

  func testUnknownDomainProfileFailsClosed() {
    let valid = makeValidPack()
    let manifest = KnowledgePackManifest(
      schemaVersion: valid.manifest.schemaVersion,
      packID: valid.manifest.packID,
      title: valid.manifest.title,
      createdAt: valid.manifest.createdAt,
      defaultLocale: valid.manifest.defaultLocale,
      domainProfiles: [DomainProfileReference(id: "unregistered-domain", version: "1.0.0")]
    )
    let invalid = KnowledgePack(
      manifest: manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions,
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "profile.unknown" })
  }

  func testHospitalityProfileRejectsUnregisteredPredicate() {
    let valid = makeValidPack()
    let unknown = KnowledgeAssertion(
      id: "assertion-unregistered-metric",
      subject: "synthetic-hotel",
      predicate: "hospitality.unregistered_metric",
      value: KnowledgeValue(type: .number, number: 1, unit: "USD", scale: 1),
      qualifiers: ["period": "2020"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: []
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions + [unknown],
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "profile.unknown_predicate" })
  }

  @MainActor
  func testAppStoreLoadsAndSummarizesFixture() async {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixture = repositoryRoot.appendingPathComponent(
      "fixtures/knowledge-packs/minimal-hospitality",
      isDirectory: true
    )
    let store = KnowledgePackStore(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))

    await store.load(fromPath: fixture.path)

    guard case .loaded(_, let summary) = store.state else {
      return XCTFail("Expected the app KnowledgePack store to load the fixture; got \(store.state)")
    }
    XCTAssertEqual(summary.title, "Synthetic Hotel 2020 Reference Pack")
    XCTAssertEqual(summary.sourceCount, 1)
    XCTAssertEqual(summary.assertionCount, 3)
    XCTAssertEqual(summary.responseCardCount, 1)
  }

  private func makeLoader() -> KnowledgePackLoader {
    KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))
  }

  private func makeValidPack() -> KnowledgePack {
    let manifest = KnowledgePackManifest(
      schemaVersion: 1,
      packID: "test-pack",
      title: "Test Pack",
      createdAt: Date(timeIntervalSince1970: 0),
      defaultLocale: "en-US",
      domainProfiles: [DomainProfileReference(id: "hospitality", version: "0.1.0")]
    )
    let source = KnowledgeSource(
      id: "source-operating-statement",
      kind: .spreadsheet,
      title: "Operating Statement",
      relativePath: "sources/operating-statement.csv",
      sha256: String(repeating: "a", count: 64),
      importedAt: Date(timeIntervalSince1970: 0)
    )
    let passage = KnowledgePassage(
      id: "passage-revpar",
      sourceID: source.id,
      text: "2020 RevPAR was $89.50.",
      locator: KnowledgeSourceLocator(sheet: "Operating Statement", cellRange: "D2")
    )
    let roomRevenueEvidence = KnowledgeEvidenceLink(
      id: "evidence-room-revenue",
      assertionID: "assertion-room-revenue",
      passageID: passage.id,
      relation: .supports
    )
    let availableRoomNightsEvidence = KnowledgeEvidenceLink(
      id: "evidence-available-room-nights",
      assertionID: "assertion-available-room-nights",
      passageID: passage.id,
      relation: .supports
    )
    let evidence = KnowledgeEvidenceLink(
      id: "evidence-revpar",
      assertionID: "assertion-revpar",
      passageID: passage.id,
      relation: .derives
    )
    let roomRevenue = KnowledgeAssertion(
      id: "assertion-room-revenue",
      subject: "synthetic-hotel",
      predicate: "hospitality.room_revenue",
      value: KnowledgeValue(type: .number, number: 3_266_750, unit: "USD", scale: 1),
      qualifiers: ["period": "2020"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: [roomRevenueEvidence.id]
    )
    let availableRoomNights = KnowledgeAssertion(
      id: "assertion-available-room-nights",
      subject: "synthetic-hotel",
      predicate: "hospitality.available_room_nights",
      value: KnowledgeValue(type: .number, number: 36_500, unit: "room_night", scale: 1),
      qualifiers: ["period": "2020"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: [availableRoomNightsEvidence.id]
    )
    let assertion = KnowledgeAssertion(
      id: "assertion-revpar",
      subject: "synthetic-hotel",
      predicate: "hospitality.revpar",
      value: KnowledgeValue(type: .number, number: 89.5, unit: "USD_per_available_room", scale: 1),
      qualifiers: ["period": "2020"],
      kind: .calculated,
      confidence: 1,
      evidenceLinkIDs: [evidence.id]
    )
    let calculation = KnowledgeCalculation(
      id: "calculation-revpar",
      name: "RevPAR",
      version: "1.0.0",
      expression: "room_revenue / available_room_nights",
      inputAssertionIDs: [roomRevenue.id, availableRoomNights.id],
      outputAssertionID: assertion.id
    )
    let question = KnowledgeQuestionFamily(
      id: "question-revpar",
      canonicalQuestion: "What was RevPAR in 2020?",
      variants: ["What was revenue per available room in 2020?"]
    )
    let card = KnowledgeResponseCard(
      id: "card-revpar",
      title: "2020 RevPAR",
      answer: "$89.50",
      evidenceState: .calculated,
      questionFamilyIDs: [question.id],
      assertionIDs: [assertion.id],
      citationPassageIDs: [passage.id],
      calculationIDs: [calculation.id],
      reviewStatus: .reviewed
    )

    return KnowledgePack(
      manifest: manifest,
      sources: [source],
      passages: [passage],
      assertions: [roomRevenue, availableRoomNights, assertion],
      evidenceLinks: [roomRevenueEvidence, availableRoomNightsEvidence, evidence],
      calculations: [calculation],
      responseCards: [card],
      questionFamilies: [question]
    )
  }
}
