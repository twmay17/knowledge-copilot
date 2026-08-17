import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeDuplicateRecordGuardTests: XCTestCase {
  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }

  private func makeLoader() -> KnowledgePackLoader {
    KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))
  }

  private func loadCleanFixturePack() throws -> KnowledgePack {
    try makeLoader().load(from: fixtureURL())
  }

  private func packDuplicatingFirstAssertion() throws -> KnowledgePack {
    let pack = try loadCleanFixturePack()
    guard let duplicate = pack.assertions.first else {
      throw XCTSkip("fixture has assertions")
    }
    return KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions + [duplicate],
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
  }

  func testIndexInitThrowsOnDuplicateRecordIDsInsteadOfTrapping() throws {
    let pack = try packDuplicatingFirstAssertion()
    XCTAssertThrowsError(try KnowledgePackSearchIndex(pack: pack)) { error in
      guard case KnowledgePackSearchError.duplicateRecordIDs(let ids) = error else {
        return XCTFail("expected duplicateRecordIDs, got \(error)")
      }
      XCTAssertFalse(ids.isEmpty)
    }
  }

  func testEvaluatorInitThrowsOnDuplicateRecordIDsInsteadOfTrapping() throws {
    let clean = try loadCleanFixturePack()
    let index = try KnowledgePackSearchIndex(pack: clean)
    let pack = try packDuplicatingFirstAssertion()
    XCTAssertThrowsError(
      try KnowledgeEvidenceOutcomeEvaluator(
        pack: pack, searchIndex: index, rootDirectory: FileManager.default.temporaryDirectory)
    ) { error in
      guard case KnowledgeEvidenceOutcomeError.duplicateRecordIDs = error else {
        return XCTFail("expected duplicateRecordIDs, got \(error)")
      }
    }
  }

  func testIndexerBuildThrowsOnDuplicatePack() throws {
    let pack = try packDuplicatingFirstAssertion()
    XCTAssertThrowsError(try KnowledgePackSearchIndexer.build(pack: pack)) { error in
      guard case KnowledgePackSearchError.duplicateRecordIDs = error else {
        return XCTFail("expected duplicateRecordIDs, got \(error)")
      }
    }
  }

  func testInvalidatorPlanThrowsOnDuplicatePreviousPack() throws {
    let clean = try loadCleanFixturePack()
    let duplicated = try packDuplicatingFirstAssertion()
    XCTAssertThrowsError(
      try KnowledgePackDependencyInvalidator().plan(from: duplicated, to: clean)
    ) { error in
      guard case KnowledgePackSearchError.duplicateRecordIDs = error else {
        return XCTFail("expected duplicateRecordIDs, got \(error)")
      }
    }
  }
}
