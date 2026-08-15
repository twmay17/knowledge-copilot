import XCTest

@testable import OpenOatsKit

final class KnowledgeDocumentIngestorTests: XCTestCase {
  private let importedAt = Date(timeIntervalSince1970: 0)

  func testPDFFixtureIngestsPagesAndFlagsLowQualityOCR() throws {
    let root = fixtureDirectory()
    let result = try KnowledgeDocumentIngestor().ingest(
      fileAt: root.appendingPathComponent("sample-evidence.pdf"),
      relativePath: "sample-evidence.pdf",
      importedAt: importedAt
    )

    XCTAssertEqual(result.source.kind, .document)
    XCTAssertEqual(result.passages.map(\.locator.page), [1, 2])
    XCTAssertTrue(result.allPassagesResolveToSource)
    XCTAssertTrue(
      result.passages.allSatisfy {
        result.resolvedSourceURL(for: $0, relativeTo: root) != nil
      })

    let warning = try XCTUnwrap(result.warnings.first)
    XCTAssertEqual(warning.flag, .lowQualityOCR)
    XCTAssertEqual(warning.locator.page, 2)
    let lowQualityPassage = try XCTUnwrap(
      result.passages.first { $0.locator.page == warning.locator.page })
    XCTAssertEqual(lowQualityPassage.extraction?.quality, .low)
    XCTAssertEqual(lowQualityPassage.extraction?.flags, [.lowQualityOCR])
  }

  func testDOCXFixtureIngestsNarrativeAndTableWithStableLineage() throws {
    let root = fixtureDirectory()
    let fileURL = root.appendingPathComponent("sample-evidence.docx")
    let first = try KnowledgeDocumentIngestor().ingest(
      fileAt: fileURL,
      relativePath: "sample-evidence.docx",
      importedAt: importedAt
    )
    let second = try KnowledgeDocumentIngestor().ingest(
      fileAt: fileURL,
      relativePath: "sample-evidence.docx",
      importedAt: importedAt.addingTimeInterval(60)
    )

    XCTAssertEqual(first.passages.count, 6)
    XCTAssertTrue(first.allPassagesResolveToSource)
    XCTAssertTrue(first.warnings.isEmpty)
    XCTAssertEqual(first.source.id, second.source.id)
    XCTAssertEqual(first.passages.map(\.id), second.passages.map(\.id))
    XCTAssertEqual(first.passages.map(\.locator), second.passages.map(\.locator))

    let table = try XCTUnwrap(first.passages.first { $0.locator.table == 1 })
    XCTAssertTrue(table.text.contains("RevPAR\t92.04\t89.50\tUSD"))
    XCTAssertEqual(table.locator.sectionPath, ["Operations Summary", "Selected Metrics"])
    XCTAssertEqual(table.extraction?.method, .docxXML)
    XCTAssertNotNil(first.resolvedSourceURL(for: table, relativeTo: root))
  }

  func testIngestedPassagesPassPackHashValidation() throws {
    let root = fixtureDirectory()
    let result = try KnowledgeDocumentIngestor().ingest(
      fileAt: root.appendingPathComponent("sample-evidence.pdf"),
      relativePath: "sample-evidence.pdf",
      importedAt: importedAt
    )
    let pack = makePack(source: result.source, passages: result.passages)

    let report = KnowledgePackLoader().validate(pack)

    XCTAssertTrue(report.isValid)
    XCTAssertEqual(
      report.warnings.filter { $0.code == "passage.low_quality_extraction" }.count,
      1
    )
  }

  func testChangedPassageTextFailsClosedAgainstLocatorHash() throws {
    let root = fixtureDirectory()
    let result = try KnowledgeDocumentIngestor().ingest(
      fileAt: root.appendingPathComponent("sample-evidence.docx"),
      relativePath: "sample-evidence.docx",
      importedAt: importedAt
    )
    let original = try XCTUnwrap(result.passages.first)
    let changed = KnowledgePassage(
      id: original.id,
      sourceID: original.sourceID,
      text: original.text + " changed",
      locator: original.locator,
      extraction: original.extraction
    )
    XCTAssertNil(result.source(for: changed))

    let report = KnowledgePackLoader().validate(
      makePack(source: result.source, passages: [changed]))

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "passage.content_hash_mismatch" })
  }

  func testUnsafePackRelativePathIsRejected() {
    let fileURL = fixtureDirectory().appendingPathComponent("sample-evidence.pdf")

    XCTAssertThrowsError(
      try KnowledgeDocumentIngestor().ingest(
        fileAt: fileURL,
        relativePath: "../outside.pdf",
        importedAt: importedAt
      )
    ) { error in
      guard case KnowledgeDocumentIngestionError.unsafeRelativePath = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  private func fixtureDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/document-ingestion", isDirectory: true)
  }

  private func makePack(source: KnowledgeSource, passages: [KnowledgePassage]) -> KnowledgePack {
    KnowledgePack(
      manifest: KnowledgePackManifest(
        schemaVersion: KnowledgePackSchema.currentVersion,
        packID: "document-ingestion-test",
        title: "Document Ingestion Test",
        createdAt: importedAt,
        defaultLocale: "en-US",
        domainProfiles: []
      ),
      sources: [source],
      passages: passages,
      assertions: [],
      evidenceLinks: [],
      calculations: [],
      responseCards: [],
      questionFamilies: []
    )
  }
}
