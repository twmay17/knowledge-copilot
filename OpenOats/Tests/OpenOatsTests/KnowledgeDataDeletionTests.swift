import Foundation
import XCTest

@testable import OpenOatsKit

final class KnowledgeDataDeletionTests: XCTestCase {
  func testDeletesPackTranscriptAudioAndCacheWithAbsenceReceipt() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let pack = root.appendingPathComponent("packs/deal-a", isDirectory: true)
    let transcript = root.appendingPathComponent("sessions/session-a/transcript.jsonl")
    let audio = root.appendingPathComponent("sessions/session-a/audio", isDirectory: true)
    let cache = root.appendingPathComponent("cache/index.sqlite")
    try seedDirectory(pack)
    try seedFile(pack.appendingPathComponent("manifest.json"))
    try seedFile(transcript)
    try seedDirectory(audio)
    try seedFile(audio.appendingPathComponent("mic.caf"))
    try seedFile(cache)

    let receipt = try KnowledgeDataDeletionService().delete([
      KnowledgeDeletionTarget(kind: .knowledgePack, url: pack, allowedRoot: root),
      KnowledgeDeletionTarget(kind: .transcript, url: transcript, allowedRoot: root),
      KnowledgeDeletionTarget(kind: .audio, url: audio, allowedRoot: root),
      KnowledgeDeletionTarget(kind: .cache, url: cache, allowedRoot: root),
    ])

    XCTAssertTrue(receipt.isComplete)
    XCTAssertEqual(receipt.removedKinds, Set(KnowledgeDeletionArtifactKind.allCases))
    XCTAssertEqual(receipt.results.map(\.kind), KnowledgeDeletionArtifactKind.allCases)
    XCTAssertTrue(receipt.results.allSatisfy { $0.existedBefore && $0.absentAfter })
    XCTAssertFalse(FileManager.default.fileExists(atPath: pack.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: transcript.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
  }

  func testDeletionIsIdempotentAndReportsAlreadyAbsentTarget() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try seedDirectory(root)
    let cache = root.appendingPathComponent("cache/missing.json")

    let receipt = try KnowledgeDataDeletionService().delete([
      KnowledgeDeletionTarget(kind: .cache, url: cache, allowedRoot: root)
    ])

    XCTAssertTrue(receipt.isComplete)
    XCTAssertEqual(receipt.results.first?.existedBefore, false)
    XCTAssertEqual(receipt.results.first?.absentAfter, true)
  }

  func testRejectsTargetOutsideAllowedRoot() throws {
    let root = temporaryRoot()
    let outside = temporaryRoot()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: outside)
    }
    try seedDirectory(root)
    try seedFile(outside.appendingPathComponent("private.txt"))

    XCTAssertThrowsError(
      try KnowledgeDataDeletionService().delete([
        KnowledgeDeletionTarget(kind: .transcript, url: outside, allowedRoot: root)
      ])
    ) { error in
      XCTAssertEqual(
        error as? KnowledgeDataDeletionError,
        .targetOutsideAllowedRoot(.transcript)
      )
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
  }

  func testRejectsBroadRootDeletion() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try seedDirectory(root)

    XCTAssertThrowsError(
      try KnowledgeDataDeletionService().delete([
        KnowledgeDeletionTarget(kind: .knowledgePack, url: root, allowedRoot: root)
      ])
    ) { error in
      XCTAssertEqual(
        error as? KnowledgeDataDeletionError,
        .targetIsAllowedRoot(.knowledgePack)
      )
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "knowledge-deletion-\(UUID().uuidString)",
      isDirectory: true
    )
  }

  private func seedDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func seedFile(_ url: URL) throws {
    try seedDirectory(url.deletingLastPathComponent())
    try Data("private-test-data".utf8).write(to: url, options: .atomic)
  }
}
