import Foundation
import XCTest

@testable import OpenOatsKit

final class SidecastCorpusServiceTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeTempFolder(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecast-corpus-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeBytes(count: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(repeating: 0x61, count: count)
        try data.write(to: url)
    }

    // MARK: - 1. Recursive read; skip unsupported extensions and dotfiles

    func testReadRecursesAndSkipsUnsupportedAndDotfiles() throws {
        let root = makeTempFolder("basic")
        defer { try? FileManager.default.removeItem(at: root) }

        let aContent = "Alpha content."
        let bContent = "Beta content in a subfolder."
        let cContent = "h1,h2\nv1,v2"

        try write(aContent, to: root.appendingPathComponent("a.md"))
        try write(bContent, to: root.appendingPathComponent("sub/b.txt"))
        try write(cContent, to: root.appendingPathComponent("c.csv"))
        try write("wrong extension for the corpus reader", to: root.appendingPathComponent("notes.pdf"))
        try write("hidden content", to: root.appendingPathComponent(".hidden.md"))

        let service = SidecastCorpusService()
        let state = try service.read(folder: root)

        XCTAssertEqual(state.files.map(\.name), ["a.md", "c.csv", "sub/b.txt"])
        XCTAssertEqual(state.skipped, ["notes.pdf"])

        let expectedChars = [aContent, bContent, cContent].reduce(0) { $0 + $1.utf16.count }
        XCTAssertEqual(state.totalChars, expectedChars)
        XCTAssertEqual(state.files.first(where: { $0.name == "a.md" })?.chars, aContent.utf16.count)
        XCTAssertEqual(state.files.first(where: { $0.name == "sub/b.txt" })?.chars, bContent.utf16.count)
        XCTAssertEqual(state.files.first(where: { $0.name == "c.csv" })?.chars, cContent.utf16.count)
    }

    // MARK: - 2. Whole-corpus injection under the 10k limit

    func testRetrieveEvidenceReturnsWholeCorpusUnderLimit() throws {
        let root = makeTempFolder("whole")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("Alpha content here.", to: root.appendingPathComponent("a.md"))
        try write("Beta content here.", to: root.appendingPathComponent("b.txt"))

        let service = SidecastCorpusService()
        _ = try service.read(folder: root)

        let evidence = service.retrieveEvidence(query: "")
        XCTAssertEqual(
            evidence,
            "--- a.md ---\nAlpha content here.\n\n--- b.txt ---\nBeta content here."
        )
    }

    // MARK: - 3. Over the limit: only matching chunks come back; no match is nil

    func testRetrieveEvidenceOverLimitReturnsOnlyMatchingChunks() throws {
        let root = makeTempFolder("chunked")
        defer { try? FileManager.default.removeItem(at: root) }

        let fillerLine = "filler padding text with no special tokens repeated for bulk.\n"
        let filler = String(repeating: fillerLine, count: 200)
        let signal = "This chunk mentions uniquexyzterm once for signal."
        XCTAssertGreaterThan(
            filler.utf16.count + signal.utf16.count, 10_000,
            "fixture must clear the whole-corpus threshold, else this exercises the wrong retrieval branch")

        try write(filler, to: root.appendingPathComponent("filler.txt"))
        try write(signal, to: root.appendingPathComponent("signal.txt"))

        let service = SidecastCorpusService()
        _ = try service.read(folder: root)

        guard let matched = service.retrieveEvidence(query: "uniquexyzterm") else {
            XCTFail("expected matching evidence")
            return
        }
        XCTAssertTrue(matched.contains("uniquexyzterm"))
        XCTAssertTrue(matched.contains("signal.txt"))
        XCTAssertFalse(matched.contains("filler.txt"))

        XCTAssertNil(service.retrieveEvidence(query: "zzznomatchqqq"))
    }

    // MARK: - 4. Digit-bearing tokens score double and rank first

    func testDigitBearingTokenOutranksWordToken() throws {
        let root = makeTempFolder("digits")
        defer { try? FileManager.default.removeItem(at: root) }

        // Fixture names are deliberately adversarial to the expected result.
        // read() processes candidates sorted by relative path, and a same-
        // score tie breaks on that original chunk index — so if digit
        // weighting were removed, both chunks would tie at score 1 and the
        // tie-break would decide the order instead. Naming the word-only
        // file so it sorts BEFORE the numeric file ("aaa-" < "zzz-") means
        // that fallback tie-break would rank the word file first: the
        // opposite of the assertion below. A pass is therefore only
        // possible through genuine x2 digit-bearing scoring overturning
        // that ordering, not through fixture/document order.
        let fillerLine = "padding text with no special tokens here.\n"
        let filler = String(repeating: fillerLine, count: 250)
        try write(filler, to: root.appendingPathComponent("filler.txt"))
        try write("Revenue increased this quarter.", to: root.appendingPathComponent("aaa-words.txt"))
        try write("Unit price hit 89.50 today.", to: root.appendingPathComponent("zzz-numeric.txt"))

        let service = SidecastCorpusService()
        _ = try service.read(folder: root)

        guard let evidence = service.retrieveEvidence(query: "revenue 89.50") else {
            XCTFail("expected evidence")
            return
        }

        guard let wordRange = evidence.range(of: "aaa-words.txt"),
              let numericRange = evidence.range(of: "zzz-numeric.txt") else {
            XCTFail("expected both chunks present")
            return
        }
        XCTAssertTrue(
            numericRange.lowerBound < wordRange.lowerBound,
            """
            digit-bearing match (89.50, score 2) should outrank the word-only \
            match (revenue, score 1) despite sorting after it in document order
            """
        )
    }

    // MARK: - 5. CSV chunk continuation carries the header line

    func testCSVChunksCarryHeaderLine() throws {
        let root = makeTempFolder("csv")
        defer { try? FileManager.default.removeItem(at: root) }

        var lines = ["id,name,value"]
        for index in 1...900 {
            if index == 120 {
                lines.append("\(index),zzzqueryrowmarker,12.34")
            } else {
                lines.append("\(index),item\(index),0.00")
            }
        }
        let csv = lines.joined(separator: "\n")
        XCTAssertGreaterThan(csv.utf16.count, 10_000, "fixture must clear the whole-corpus threshold alone")

        try write(csv, to: root.appendingPathComponent("data.csv"))

        let service = SidecastCorpusService()
        _ = try service.read(folder: root)

        guard let evidence = service.retrieveEvidence(query: "zzzqueryrowmarker") else {
            XCTFail("expected evidence")
            return
        }
        guard let markerRange = evidence.range(of: "--- data.csv ---\n") else {
            XCTFail("expected a data.csv block")
            return
        }

        let body = evidence[markerRange.upperBound...]
        XCTAssertTrue(body.hasPrefix("id,name,value"), "non-first CSV chunk should carry the header")
        XCTAssertTrue(body.contains("zzzqueryrowmarker"))
    }

    // MARK: - 6. Per-file cap and total cap

    func testOversizedFileIsSkippedWithReason() throws {
        let root = makeTempFolder("perfilecap")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("small ok content", to: root.appendingPathComponent("ok.txt"))
        try writeBytes(count: 2 * 1024 * 1024 + 10, to: root.appendingPathComponent("big.txt"))

        let service = SidecastCorpusService()
        let state = try service.read(folder: root)

        XCTAssertEqual(state.files.map(\.name), ["ok.txt"])
        XCTAssertEqual(state.skipped, ["big.txt (over per-file cap)"])
    }

    func testTotalCapSkipsFilesOnceCumulativeExceeds6MB() throws {
        let root = makeTempFolder("totalcap")
        defer { try? FileManager.default.removeItem(at: root) }

        // Sizes are chosen so the cumulative total after the third file
        // (6,150,000 bytes) lands strictly between a naive flat 6,000,000-
        // byte cap and the real binary 6 * 1024 * 1024 = 6,291,456-byte cap
        // — proving the real threshold is in effect rather than an
        // approximated round number (a flat-6,000,000 implementation would
        // already have rejected the third file at cumulative 4,100,000 +
        // 2,050,000 = 6,150,000). Each individual file also stays
        // comfortably under the 2 * 1024 * 1024 per-file cap, unlike a
        // naive 3,100,000-byte fixture, which the per-file cap alone would
        // reject before the total cap is ever exercised.
        let bigFileSize = 2_050_000
        for label in ["a", "b", "c"] {
            try writeBytes(count: bigFileSize, to: root.appendingPathComponent("big-\(label).txt"))
        }
        try writeBytes(count: 200_000, to: root.appendingPathComponent("big-d.txt"))

        let service = SidecastCorpusService()
        let state = try service.read(folder: root)

        XCTAssertEqual(
            state.files.map(\.name), ["big-a.txt", "big-b.txt", "big-c.txt"],
            "cumulative 6,150,000 bytes must fit under the real 6,291,456-byte cap")
        XCTAssertEqual(state.skipped, ["big-d.txt (total cap reached)"])
    }

    // MARK: - 7. Evidence char cap keeps output bounded and keeps the best chunks

    func testEvidenceStaysUnderCapAndKeepsHighestScoringChunks() throws {
        let root = makeTempFolder("evidencecap")
        defer { try? FileManager.default.removeItem(at: root) }

        for score in 1...9 {
            var text = Array(repeating: "marker", count: score).joined(separator: " ") + " "
            while text.utf16.count < 1150 {
                text += "x"
            }
            try write(text, to: root.appendingPathComponent("score\(score).txt"))
        }

        let service = SidecastCorpusService()
        _ = try service.read(folder: root)

        guard let evidence = service.retrieveEvidence(query: "marker") else {
            XCTFail("expected evidence")
            return
        }

        XCTAssertLessThanOrEqual(evidence.utf16.count, 9_000)
        XCTAssertTrue(evidence.contains("score9.txt"), "highest-scoring chunk should be retained")
        XCTAssertTrue(evidence.contains("score7.txt"))
        XCTAssertFalse(evidence.contains("score2.txt"), "dropped once the cap is exceeded")
        XCTAssertFalse(evidence.contains("score1.txt"), "beyond the top-8 cutoff")
    }

    // MARK: - 8. clear()

    func testClearEmptiesStateAndEvidence() throws {
        let root = makeTempFolder("clear")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("Some content.", to: root.appendingPathComponent("a.md"))

        let service = SidecastCorpusService()
        _ = try service.read(folder: root)
        XCTAssertNotNil(service.state)

        service.clear()

        XCTAssertNil(service.state)
        XCTAssertNil(service.retrieveEvidence(query: "content"))
    }

    // MARK: - 9. Invalid UTF-8 decodes lossily instead of aborting the read

    func testInvalidUTF8BytesAreDecodedLossilyWithoutAbortingTheRead() throws {
        let root = makeTempFolder("badutf8")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("Valid sibling content.", to: root.appendingPathComponent("ok.txt"))
        let invalidData = Data([0x48, 0x69, 0xFF, 0xFE])  // "Hi" followed by invalid UTF-8 bytes
        try invalidData.write(to: root.appendingPathComponent("bad.txt"))

        let service = SidecastCorpusService()
        let state = try service.read(folder: root)

        XCTAssertEqual(state.files.map(\.name), ["bad.txt", "ok.txt"])
        XCTAssertTrue(state.skipped.isEmpty, "invalid UTF-8 should not be skipped, nor abort the read")

        guard let badFile = state.files.first(where: { $0.name == "bad.txt" }) else {
            XCTFail("expected bad.txt to still be read despite invalid bytes")
            return
        }
        XCTAssertGreaterThan(badFile.chars, 0)

        // Whole-corpus injection (well under the 10k limit) surfaces the
        // lossily decoded text regardless of query — matching the bench's
        // fs.readFile(path, "utf-8"), which substitutes U+FFFD for invalid
        // byte sequences and never throws.
        let evidence = service.retrieveEvidence(query: "irrelevant")
        XCTAssertTrue(
            evidence?.contains("\u{FFFD}") ?? false,
            "invalid bytes should surface as the U+FFFD replacement character")
    }
}
