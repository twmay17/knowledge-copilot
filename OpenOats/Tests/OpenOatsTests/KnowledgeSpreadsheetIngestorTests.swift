import CryptoKit
import XCTest

@testable import OpenOatsKit

final class KnowledgeSpreadsheetIngestorTests: XCTestCase {
  private let importedAt = Date(timeIntervalSince1970: 0)

  func testXLSXRetainsSheetsCellsFormulasValuesAndContext() throws {
    let root = fixtureDirectory()
    let result = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: root.appendingPathComponent("sample-evidence.xlsx"),
      relativePath: "sample-evidence.xlsx",
      importedAt: importedAt
    )

    XCTAssertEqual(result.source.kind, .spreadsheet)
    XCTAssertEqual(result.passages.count, 9)
    XCTAssertTrue(result.warnings.isEmpty)
    XCTAssertTrue(result.allPassagesResolveToSource)
    XCTAssertTrue(
      result.passages.allSatisfy {
        result.resolvedSourceURL(for: $0, relativeTo: root) != nil
      })

    let revPAR = try XCTUnwrap(
      result.passages.first {
        $0.locator.sheet == "Operating Statement" && $0.locator.rowStart == 4
      })
    XCTAssertEqual(revPAR.locator.cellRange, "A4:F4")
    XCTAssertEqual(revPAR.locator.rowEnd, 4)
    XCTAssertEqual(revPAR.spreadsheet?.period, "2020")
    XCTAssertEqual(revPAR.spreadsheet?.unit, "USD_per_available_room")
    XCTAssertEqual(revPAR.spreadsheet?.isHeaderRow, false)

    let actual = try XCTUnwrap(revPAR.spreadsheet?.cells.first { $0.reference == "C4" })
    XCTAssertEqual(actual.header, "Actual")
    XCTAssertEqual(actual.value, "90")
    XCTAssertEqual(actual.valueType, .number)
    XCTAssertEqual(actual.formula, "=C2/C3")
    XCTAssertEqual(actual.numberFormat, "$0.00")
    XCTAssertTrue(revPAR.text.contains("Actual=90 [formula: =C2/C3]"))

    let linked = try XCTUnwrap(
      result.passages.first {
        $0.locator.sheet == "Assumptions" && $0.locator.rowStart == 5
      }?.spreadsheet?.cells.first { $0.reference == "C5" })
    XCTAssertEqual(linked.formula, "='Operating Statement'!C4")
    XCTAssertEqual(linked.value, "90")
  }

  func testXLSXLineageIsStableAcrossImportTimes() throws {
    let root = fixtureDirectory()
    let fileURL = root.appendingPathComponent("sample-evidence.xlsx")
    let first = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: fileURL,
      relativePath: "sample-evidence.xlsx",
      importedAt: importedAt
    )
    let second = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: fileURL,
      relativePath: "sample-evidence.xlsx",
      importedAt: importedAt.addingTimeInterval(60)
    )

    XCTAssertEqual(first.source.id, second.source.id)
    XCTAssertEqual(first.passages.map(\.id), second.passages.map(\.id))
    XCTAssertEqual(first.passages.map(\.locator), second.passages.map(\.locator))
  }

  func testCSVRetainsQuotedEscapedAndMultilineFieldsWithStableLocators() throws {
    let root = fixtureDirectory()
    let fileURL = root.appendingPathComponent("sample-evidence.csv")
    let first = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: fileURL,
      relativePath: "sample-evidence.csv",
      importedAt: importedAt
    )
    let second = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: fileURL,
      relativePath: "sample-evidence.csv",
      importedAt: importedAt.addingTimeInterval(60)
    )

    XCTAssertEqual(first.passages.count, 4)
    XCTAssertTrue(first.allPassagesResolveToSource)
    XCTAssertEqual(first.passages.map(\.id), second.passages.map(\.id))
    XCTAssertEqual(first.passages.map(\.locator), second.passages.map(\.locator))
    XCTAssertEqual(first.passages.map(\.locator.cellRange), ["A1:E1", "A2:E2", "A3:E3", "A4:E4"])

    let occupancyNote = try XCTUnwrap(
      first.passages[1].spreadsheet?.cells.first { $0.reference == "E2" })
    XCTAssertEqual(occupancyNote.value, "Synthetic, quoted note")
    let adrNote = try XCTUnwrap(
      first.passages[2].spreadsheet?.cells.first { $0.reference == "E3" })
    XCTAssertEqual(adrNote.value, "Escaped \"reviewed\" value")
    let revPARNote = try XCTUnwrap(
      first.passages[3].spreadsheet?.cells.first { $0.reference == "E4" })
    XCTAssertEqual(revPARNote.value, "Contains a\nmultiline note")
    XCTAssertEqual(first.passages[3].spreadsheet?.period, "2020")
    XCTAssertEqual(first.passages[3].spreadsheet?.unit, "USD_per_available_room")
  }

  func testCSVPreservesLeadingProvenanceCommentsAndFindsTheActualHeader() throws {
    let root = fixtureDirectory()
    let result = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: root.appendingPathComponent("commented-evidence.csv"),
      relativePath: "commented-evidence.csv",
      importedAt: importedAt
    )

    XCTAssertEqual(result.passages.count, 6)
    XCTAssertEqual(result.passages[0].locator.rowStart, 1)
    XCTAssertEqual(
      result.passages[0].spreadsheet?.cells.first?.value,
      "# source filename: Synthetic Hotel 2020 P&L.pdf"
    )
    XCTAssertEqual(result.passages[4].locator.rowStart, 5)
    XCTAssertTrue(result.passages[4].spreadsheet?.isHeaderRow == true)

    let dataRow = result.passages[5]
    XCTAssertEqual(dataRow.locator.cellRange, "A6:E6")
    XCTAssertEqual(
      dataRow.spreadsheet?.cells.first { $0.reference == "B6" }?.header,
      "metric"
    )
    XCTAssertEqual(
      dataRow.spreadsheet?.cells.first { $0.reference == "D6" }?.header,
      "FY"
    )
    XCTAssertTrue(result.allPassagesResolveToSource)
  }

  func testSpreadsheetPassagesPassPackValidation() throws {
    let root = fixtureDirectory()
    let result = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: root.appendingPathComponent("sample-evidence.xlsx"),
      relativePath: "sample-evidence.xlsx",
      importedAt: importedAt
    )

    let report = KnowledgePackLoader().validate(
      makePack(source: result.source, passages: result.passages))

    XCTAssertTrue(report.isValid)
    XCTAssertFalse(
      report.warnings.contains { $0.code == "passage.spreadsheet_formula_missing_value" })
  }

  func testChangedPassageTextFailsClosedAgainstLocatorHash() throws {
    let root = fixtureDirectory()
    let result = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: root.appendingPathComponent("sample-evidence.csv"),
      relativePath: "sample-evidence.csv",
      importedAt: importedAt
    )
    let original = try XCTUnwrap(result.passages.first)
    let changed = KnowledgePassage(
      id: original.id,
      sourceID: original.sourceID,
      text: original.text + " changed",
      locator: original.locator,
      spreadsheet: original.spreadsheet
    )

    XCTAssertFalse(result.resolvesToSource(changed))
    let report = KnowledgePackLoader().validate(
      makePack(source: result.source, passages: [changed]))
    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "passage.content_hash_mismatch" })
  }

  func testLoaderWarnsWhenFormulaHasNoCachedValue() throws {
    let text = "A1= [formula: =B1]"
    let passage = KnowledgePassage(
      id: "passage-formula-without-value",
      sourceID: "source-spreadsheet",
      text: text,
      locator: KnowledgeSourceLocator(
        sheet: "Sheet1",
        cellRange: "A1",
        rowStart: 1,
        rowEnd: 1,
        contentSHA256: sha256(text)
      ),
      spreadsheet: KnowledgeSpreadsheetPassage(
        cells: [
          KnowledgeSpreadsheetCell(
            reference: "A1",
            valueType: .blank,
            formula: "=B1"
          )
        ],
        isHeaderRow: false
      )
    )
    let source = KnowledgeSource(
      id: "source-spreadsheet",
      kind: .spreadsheet,
      title: "Spreadsheet",
      relativePath: "spreadsheet.xlsx",
      sha256: String(repeating: "0", count: 64),
      importedAt: importedAt
    )

    let report = KnowledgePackLoader().validate(makePack(source: source, passages: [passage]))

    XCTAssertTrue(report.isValid)
    XCTAssertTrue(
      report.warnings.contains { $0.code == "passage.spreadsheet_formula_missing_value" })
  }

  func testLoaderRejectsSpreadsheetPayloadOnDocumentSourceAndInvalidCell() throws {
    let text = "A0=value"
    let passage = KnowledgePassage(
      id: "passage-invalid-spreadsheet",
      sourceID: "source-document",
      text: text,
      locator: KnowledgeSourceLocator(
        sheet: "Sheet1",
        cellRange: "A0",
        rowStart: 0,
        rowEnd: 0,
        contentSHA256: sha256(text)
      ),
      spreadsheet: KnowledgeSpreadsheetPassage(
        cells: [
          KnowledgeSpreadsheetCell(
            reference: "A0",
            value: "value",
            valueType: .text
          )
        ]
      )
    )
    let source = KnowledgeSource(
      id: "source-document",
      kind: .document,
      title: "Document",
      relativePath: "document.pdf",
      sha256: String(repeating: "0", count: 64),
      importedAt: importedAt
    )

    let report = KnowledgePackLoader().validate(makePack(source: source, passages: [passage]))

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "passage.spreadsheet_source_kind" })
    XCTAssertTrue(report.errors.contains { $0.code == "passage.spreadsheet_invalid_cell" })
  }

  func testUnsafePackRelativePathIsRejected() {
    let fileURL = fixtureDirectory().appendingPathComponent("sample-evidence.xlsx")

    XCTAssertThrowsError(
      try KnowledgeSpreadsheetIngestor().ingest(
        fileAt: fileURL,
        relativePath: "../outside.xlsx",
        importedAt: importedAt
      )
    ) { error in
      guard case KnowledgeSpreadsheetIngestionError.unsafeRelativePath = error else {
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
      .appendingPathComponent("fixtures/spreadsheet-ingestion", isDirectory: true)
  }

  private func makePack(source: KnowledgeSource, passages: [KnowledgePassage]) -> KnowledgePack {
    KnowledgePack(
      manifest: KnowledgePackManifest(
        schemaVersion: KnowledgePackSchema.currentVersion,
        packID: "spreadsheet-ingestion-test",
        title: "Spreadsheet Ingestion Test",
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

  private func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
