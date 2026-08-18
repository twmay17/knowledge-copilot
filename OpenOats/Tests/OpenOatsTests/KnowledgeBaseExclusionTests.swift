import Foundation
import XCTest

@testable import OpenOatsKit

final class KnowledgeBaseExclusionTests: XCTestCase {
  func testCollectSkipsTheExcludedPackTree() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("kb-exclusion-\(UUID().uuidString)", isDirectory: true)
    let kb = base.appendingPathComponent("kb", isDirectory: true)
    let pack = kb.appendingPathComponent("deals/pack", isDirectory: true)
    try FileManager.default.createDirectory(
      at: pack.appendingPathComponent("sources", isDirectory: true),
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    try "kb note".write(
      to: kb.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
    try "corpus text".write(
      to: pack.appendingPathComponent("sources/memo.md"), atomically: true, encoding: .utf8)

    let unexcluded = KnowledgeBase.collectFilesStatic(in: kb, excludingFolderAt: "")
    XCTAssertEqual(unexcluded.count, 2)

    let excluded = KnowledgeBase.collectFilesStatic(in: kb, excludingFolderAt: pack.path)
    XCTAssertEqual(excluded.map(\.lastPathComponent), ["note.md"])
  }

  func testIsExcludedResolvesSymlinkAliases() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("kb-alias-\(UUID().uuidString)", isDirectory: true)
    let real = base.appendingPathComponent("real", isDirectory: true)
    let link = base.appendingPathComponent("alias")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    defer { try? FileManager.default.removeItem(at: base) }
    try "x".write(to: real.appendingPathComponent("f.md"), atomically: true, encoding: .utf8)

    XCTAssertTrue(
      KnowledgeBase.isExcluded(
        fileURL: link.appendingPathComponent("f.md"), excludedFolderPath: real.path))
    XCTAssertFalse(
      KnowledgeBase.isExcluded(
        fileURL: real.appendingPathComponent("f.md"), excludedFolderPath: ""))
    XCTAssertFalse(
      KnowledgeBase.isExcluded(
        fileURL: base.appendingPathComponent("other.md"), excludedFolderPath: real.path))
  }

  func testCollectPrunesExcludedDirectoriesWithoutChangingResults() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("kb-prune-\(UUID().uuidString)", isDirectory: true)
    let kb = base.appendingPathComponent("kb", isDirectory: true)
    let pack = kb.appendingPathComponent("pack", isDirectory: true)
    let deep = pack.appendingPathComponent("a/b/c", isDirectory: true)
    try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try "keep".write(to: kb.appendingPathComponent("keep.md"), atomically: true, encoding: .utf8)
    for index in 0..<5 {
      try "skip".write(
        to: deep.appendingPathComponent("skip-\(index).md"), atomically: true, encoding: .utf8)
    }

    let collected = KnowledgeBase.collectFilesStatic(in: kb, excludingFolderAt: pack.path)
    XCTAssertEqual(collected.map(\.lastPathComponent), ["keep.md"])
  }

  func testPrunedEntriesDropsCachedChunksUnderExcludedFolder() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("kb-cache-prune-\(UUID().uuidString)", isDirectory: true)
    let kb = base.appendingPathComponent("kb", isDirectory: true)
    let pack = kb.appendingPathComponent("pack", isDirectory: true)
    try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try "keep".write(to: kb.appendingPathComponent("keep.md"), atomically: true, encoding: .utf8)
    try "skip".write(to: pack.appendingPathComponent("skip.md"), atomically: true, encoding: .utf8)

    let keepChunk = KBChunk(
      text: "keep", sourceFile: "keep.md", headerContext: "", embedding: [0.1],
      relativePath: "keep.md")
    let skipChunk = KBChunk(
      text: "skip", sourceFile: "skip.md", headerContext: "", embedding: [0.1],
      relativePath: "pack/skip.md")
    let entries: [String: [KBChunk]] = [
      "keep.md:hash-keep": [keepChunk],
      "skip.md:hash-skip": [skipChunk],
    ]

    let pruned = KnowledgeBase.prunedEntries(entries, folderURL: kb, excludedFolderPath: pack.path)

    XCTAssertEqual(pruned.count, 1)
    XCTAssertEqual(pruned["keep.md:hash-keep"]?.first?.relativePath, "keep.md")
    XCTAssertNil(pruned["skip.md:hash-skip"])
  }
}
