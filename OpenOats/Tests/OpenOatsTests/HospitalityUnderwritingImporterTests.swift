import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class HospitalityUnderwritingImporterTests: XCTestCase {
  private let importedAt = Date(timeIntervalSince1970: 0)
  private let registry = KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])

  func testPathClassifierSeparatesEvidenceWorkProductAndKnownDocumentTypes() {
    let classifier = HospitalityUnderwritingPathClassifier()

    XCTAssertEqual(
      classifier.labels(
        for: "Deal/JMI Analysis/00 Extraction CSVs/Hotel_PL_2024_canonical.csv"
      ),
      HospitalityUnderwritingSourceLabels(
        role: .analysisExtraction,
        documentType: .profitAndLoss,
        valueStage: .canonical
      )
    )
    XCTAssertEqual(
      classifier.labels(for: "Deal/JMI Analysis/04 Flags & Verification/FLAGS_REGISTER.md")
        .role,
      .analysisVerification
    )
    XCTAssertEqual(
      classifier.labels(for: "Deal/08 Market/Hotel_Markets_Monthly.xlsx"),
      HospitalityUnderwritingSourceLabels(
        role: .brokerSource,
        documentType: .costarMarketsMonthly,
        valueStage: .exactTranscription
      )
    )
    XCTAssertEqual(
      classifier.labels(for: "Deal/JMI Analysis/06 Full Model/Hotel Full IM.xlsm")
        .valueStage,
      .modeled
    )
  }

  func testGenericDealAnalysisPathsClassifyLikeLegacyJMIPaths() {
    let classifier = HospitalityUnderwritingPathClassifier()
    XCTAssertEqual(
      classifier.labels(for: "Deal/Deal Analysis/00 Extraction CSVs/Hotel_PL_2024_canonical.csv")
        .role,
      .analysisExtraction
    )
    XCTAssertEqual(
      classifier.labels(for: "Deal/Deal Analysis/04 Flags & Verification/FLAGS_REGISTER.md").role,
      .analysisVerification
    )
    // Legacy folders keep working.
    XCTAssertEqual(
      classifier.labels(for: "Deal/JMI Analysis/00 Extraction CSVs/Synthetic_PL_2020.csv").role,
      .analysisExtraction
    )
  }

  func testRoleIdentifiersAreFirmNeutral() {
    for role in HospitalityUnderwritingSourceRole.allCases {
      XCTAssertFalse(role.rawValue.lowercased().contains("jmi"), role.rawValue)
    }
  }

  func testProfitAndLossImportPromotesMappedFactsWithProvenanceAndFailClosedWarnings() throws {
    let result = try importer.ingest(
      fileAt: fixtureDirectory().appendingPathComponent("Synthetic_PL_2020.csv"),
      relativePath: "Deal/JMI Analysis/00 Extraction CSVs/Synthetic_PL_2020.csv",
      assetID: "synthetic-hotel",
      importedAt: importedAt
    )

    XCTAssertEqual(result.profileVersion, "0.2.0")
    XCTAssertEqual(result.labels.role, .analysisExtraction)
    XCTAssertEqual(result.labels.documentType, .profitAndLoss)
    XCTAssertEqual(result.labels.valueStage, .exactTranscription)
    XCTAssertEqual(
      result.provenance["source_filename"],
      "Synthetic Hotel 2020 Operating Statement.pdf"
    )
    XCTAssertEqual(result.provenance["page/tab"], "page 4")
    XCTAssertEqual(result.assertions.count, 16)
    XCTAssertEqual(result.evidenceLinks.count, result.assertions.count)
    XCTAssertTrue(result.warnings.contains { $0.code == "unmapped_metric" && $0.row == 17 })

    let revPAR = try XCTUnwrap(
      result.assertions.first { $0.predicate == "hospitality.revpar" })
    XCTAssertEqual(revPAR.value.number, 89.5)
    XCTAssertEqual(revPAR.value.unit, "USD_per_available_room")
    XCTAssertEqual(revPAR.value.scale, 1)
    XCTAssertEqual(revPAR.qualifiers["period"], "2020")
    XCTAssertEqual(revPAR.qualifiers["status"], "actual")
    XCTAssertEqual(revPAR.qualifiers["benchmark"], "subject")
    XCTAssertEqual(revPAR.qualifiers["comparison_basis"], "direct_asset")
    XCTAssertEqual(revPAR.qualifiers["source_role"], "analysis_extraction")

    let occupancy = try XCTUnwrap(
      result.assertions.first { $0.predicate == "hospitality.occupancy" })
    XCTAssertEqual(occupancy.value.number, 68.49)
    XCTAssertEqual(occupancy.value.scale, 0.01)
    XCTAssertEqual(occupancy.qualifiers["scope"], "rooms")

    let report = loader.validate(pack(from: result))
    XCTAssertTrue(report.isValid, report.errors.map(\.description).joined(separator: "\n"))
  }

  func testSTARImportKeepsSubjectCompSetAndMarketProxyBasesDistinct() throws {
    let result = try importer.ingest(
      fileAt: fixtureDirectory().appendingPathComponent("Synthetic_STAR_summary.csv"),
      relativePath: "Deal/JMI Analysis/00 Extraction CSVs/Synthetic_STAR_summary.csv",
      assetID: "synthetic-hotel",
      importedAt: importedAt
    )

    XCTAssertEqual(result.labels.documentType, .strStar)
    XCTAssertEqual(result.assertions.count, 12)
    XCTAssertTrue(result.warnings.isEmpty)

    let compSetRevPAR = try XCTUnwrap(
      result.assertions.first {
        $0.predicate == "hospitality.revpar"
          && $0.qualifiers["period"] == "2020"
          && $0.qualifiers["benchmark"] == "comp_set"
      })
    XCTAssertEqual(compSetRevPAR.value.number, 87.5)
    XCTAssertEqual(compSetRevPAR.qualifiers["comparison_basis"], "star_compset")

    let marketIndex = try XCTUnwrap(
      result.assertions.first {
        $0.predicate == "hospitality.revpar_index"
          && $0.qualifiers["period"] == "TTM:2025-11"
      })
    XCTAssertEqual(marketIndex.value.number, 94.04)
    XCTAssertEqual(marketIndex.value.scale, 0.01)
    XCTAssertEqual(marketIndex.qualifiers["benchmark"], "market")
    XCTAssertEqual(marketIndex.qualifiers["comparison_basis"], "market_proxy")

    let report = loader.validate(pack(from: result))
    XCTAssertTrue(report.isValid, report.errors.map(\.description).joined(separator: "\n"))
  }

  func testUnderwritingProfileRejectsNonCanonicalPeriodAndMislabeledComparisonBasis() throws {
    let result = try importer.ingest(
      fileAt: fixtureDirectory().appendingPathComponent("Synthetic_STAR_summary.csv"),
      relativePath: "Deal/JMI Analysis/00 Extraction CSVs/Synthetic_STAR_summary.csv",
      assetID: "synthetic-hotel",
      importedAt: importedAt
    )
    let original = try XCTUnwrap(result.assertions.first { $0.predicate == "hospitality.revpar" })
    var qualifiers = original.qualifiers
    qualifiers["period"] = "trailing twelve months"
    qualifiers["benchmark"] = "comp_set"
    qualifiers["comparison_basis"] = "market_proxy"
    let changed = KnowledgeAssertion(
      id: original.id,
      subject: original.subject,
      predicate: original.predicate,
      value: original.value,
      qualifiers: qualifiers,
      kind: original.kind,
      confidence: original.confidence,
      evidenceLinkIDs: original.evidenceLinkIDs
    )
    let assertions = result.assertions.map { $0.id == changed.id ? changed : $0 }
    let invalidPack = KnowledgePack(
      manifest: manifest,
      sources: [result.source],
      passages: result.passages,
      assertions: assertions,
      evidenceLinks: result.evidenceLinks,
      calculations: [],
      responseCards: [],
      questionFamilies: []
    )

    let report = loader.validate(invalidPack)
    XCTAssertTrue(report.errors.contains { $0.code == "hospitality.invalid_reporting_period" })
    XCTAssertTrue(
      report.errors.contains { $0.code == "hospitality.incompatible_comparison_basis" })
  }

  func testVersionOneRemainsStrictlyBackwardCompatible() throws {
    let old = try XCTUnwrap(registry.schema(id: "hospitality", version: "0.1.0"))
    let underwriting = try XCTUnwrap(registry.schema(id: "hospitality", version: "0.2.0"))

    XCTAssertEqual(old.qualifiers.first { $0.key == "period" }?.valueType, .year)
    XCTAssertEqual(underwriting.qualifiers.first { $0.key == "period" }?.valueType, .text)
    XCTAssertNil(old.predicates.first { $0.predicate == "hospitality.revpar_index" })
    XCTAssertNotNil(underwriting.predicates.first { $0.predicate == "hospitality.revpar_index" })
  }

  private var importer: HospitalityUnderwritingCSVImporter {
    HospitalityUnderwritingCSVImporter()
  }

  private var loader: KnowledgePackLoader {
    KnowledgePackLoader(profileRegistry: registry)
  }

  private var manifest: KnowledgePackManifest {
    KnowledgePackManifest(
      schemaVersion: KnowledgePackSchema.currentVersion,
      packID: "hospitality-underwriting-import-test",
      title: "Hospitality Underwriting Import Test",
      createdAt: importedAt,
      defaultLocale: "en-US",
      domainProfiles: [DomainProfileReference(id: "hospitality", version: "0.2.0")]
    )
  }

  private func fixtureDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/hospitality-underwriting", isDirectory: true)
  }

  private func pack(from result: HospitalityUnderwritingImportResult) -> KnowledgePack {
    KnowledgePack(
      manifest: manifest,
      sources: [result.source],
      passages: result.passages,
      assertions: result.assertions,
      evidenceLinks: result.evidenceLinks,
      calculations: [],
      responseCards: [],
      questionFamilies: []
    )
  }
}
