import XCTest

@testable import OpenOatsKit

final class KnowledgeVectorCandidateSelectionTests: XCTestCase {
  private func document(_ id: Int, body: String = "body") -> SearchDocument {
    SearchDocument(
      kind: .passage,
      recordID: String(format: "record-%03d", id),
      title: "Title \(id)",
      body: body,
      aliases: [],
      qualifiers: [:],
      sourceIDs: []
    )
  }

  func testCapsCandidateCountAndPrefersLocalRank() {
    let documents = (0..<100).map { document($0) }
    let exact: Set<String> = [documents[90].id]
    let scores: [String: Double] = [documents[95].id: 0.9, documents[96].id: 0.5]

    let selected = KnowledgePackSearchIndex.vectorCandidateSelection(
      documents,
      exactDocumentIDs: exact,
      fullTextScores: scores,
      maximumCount: 10,
      maximumPayloadBytes: 1_000_000
    )

    XCTAssertEqual(selected.count, 10)
    let selectedIDs = Set(selected.map(\.id))
    XCTAssertTrue(selectedIDs.contains(documents[90].id), "exact hit must survive the cap")
    XCTAssertTrue(selectedIDs.contains(documents[95].id), "top full-text hit must survive the cap")
    XCTAssertTrue(selectedIDs.contains(documents[96].id))
    // Output is deterministically ordered by document ID.
    XCTAssertEqual(selected.map(\.id), selected.map(\.id).sorted())
  }

  func testCapsTotalPayloadBytesAndSkipsOversizedDocuments() {
    let huge = document(0, body: String(repeating: "x", count: 2_000))
    let small = (1...5).map { document($0, body: "small body \($0)") }
    let selected = KnowledgePackSearchIndex.vectorCandidateSelection(
      [huge] + small,
      exactDocumentIDs: [huge.id],
      fullTextScores: [:],
      maximumCount: 10,
      maximumPayloadBytes: 200
    )

    XCTAssertFalse(
      selected.map(\.id).contains(huge.id),
      "oversized document is dropped, not truncated"
    )
    XCTAssertFalse(selected.isEmpty)
    let totalBytes = selected.reduce(0) { $0 + $1.searchableText.utf8.count }
    XCTAssertLessThanOrEqual(totalBytes, 200)
  }

  func testEmptyInputYieldsEmptySelection() {
    XCTAssertTrue(
      KnowledgePackSearchIndex.vectorCandidateSelection(
        [], exactDocumentIDs: [], fullTextScores: [:], maximumCount: 64,
        maximumPayloadBytes: 1_000
      ).isEmpty)
  }
}
