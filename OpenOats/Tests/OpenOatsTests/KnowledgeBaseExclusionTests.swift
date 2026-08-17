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
}
