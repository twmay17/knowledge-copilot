import Foundation
import XCTest

@testable import OpenOatsKit

/// Logic-level coverage only: bookmark *persistence* (the UserDefaults
/// round trip, corrupt/missing-data fallbacks, and the stale-bookmark
/// refresh) is exercised directly against temp directories, which needs no
/// sandbox entitlements and behaves identically whether or not the test
/// binary is sandboxed. What is NOT covered here — and needs a maintainer
/// running the real, sandboxed app to verify — is whether a bookmark
/// actually survives a fresh launch under App Sandbox / TCC folder-access
/// prompts, and the `NSOpenPanel` picker itself (`SidecastCorpusBookmark.pick`),
/// which is a modal UI call this suite cannot drive headlessly.
final class SidecastCorpusBookmarkTests: XCTestCase {

    // Matches the established pattern in AppSettingsTests/SettingsStoreTests:
    // a UUID-suffixed suite name needs no explicit teardown, since it can
    // never collide with another test's domain.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.openoats.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTempFolder(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecast-corpus-bookmark-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 1. Save writes under the exact key the brief specifies

    func testSaveWritesBookmarkDataUnderExactDefaultsKey() throws {
        let defaults = makeIsolatedDefaults()
        let folder = makeTempFolder("save")
        defer { try? FileManager.default.removeItem(at: folder) }

        SidecastCorpusBookmark.save(folder, defaults: defaults)

        XCTAssertEqual(SidecastCorpusBookmark.defaultsKey, "sidecast.corpus.bookmark")
        XCTAssertNotNil(defaults.data(forKey: "sidecast.corpus.bookmark"))
    }

    // MARK: - 2. Resolve with nothing stored

    func testResolveReturnsNilWhenNoBookmarkStored() {
        let defaults = makeIsolatedDefaults()
        XCTAssertNil(SidecastCorpusBookmark.resolve(defaults: defaults))
    }

    // MARK: - 3. Resolve with corrupt data fails gracefully, not by throwing/crashing

    func testResolveReturnsNilWhenBookmarkDataIsCorrupt() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: SidecastCorpusBookmark.defaultsKey)

        XCTAssertNil(SidecastCorpusBookmark.resolve(defaults: defaults))
    }

    // MARK: - 4. Save then resolve round-trips to the same path

    func testSaveThenResolveRoundTripsToTheSamePath() throws {
        let defaults = makeIsolatedDefaults()
        let folder = makeTempFolder("roundtrip")
        defer { try? FileManager.default.removeItem(at: folder) }

        SidecastCorpusBookmark.save(folder, defaults: defaults)
        let resolved = try XCTUnwrap(SidecastCorpusBookmark.resolve(defaults: defaults))

        XCTAssertEqual(resolved.standardizedFileURL.path, folder.standardizedFileURL.path)
    }

    // MARK: - 5. Stale bookmark (folder renamed since bookmarking) is refreshed on resolve

    func testResolveFollowsARenamedFolderAndRefreshesTheStoredBookmark() throws {
        let defaults = makeIsolatedDefaults()
        let parent = makeTempFolder("stale-parent")
        defer { try? FileManager.default.removeItem(at: parent) }

        let original = parent.appendingPathComponent("original", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        SidecastCorpusBookmark.save(original, defaults: defaults)
        let bookmarkBeforeRename = try XCTUnwrap(defaults.data(forKey: SidecastCorpusBookmark.defaultsKey))

        let renamed = parent.appendingPathComponent("renamed", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: renamed)

        let resolved = try XCTUnwrap(SidecastCorpusBookmark.resolve(defaults: defaults))
        XCTAssertEqual(
            resolved.standardizedFileURL.path, renamed.standardizedFileURL.path,
            "a security-scoped bookmark tracks the file even after it moves")

        let bookmarkAfterRename = defaults.data(forKey: SidecastCorpusBookmark.defaultsKey)
        XCTAssertNotEqual(
            bookmarkAfterRename, bookmarkBeforeRename,
            "resolving a stale bookmark must refresh the stored data to point at the new location")

        // The refreshed bookmark itself now resolves cleanly to the same
        // (no-longer-stale) path.
        let resolvedAgain = try XCTUnwrap(SidecastCorpusBookmark.resolve(defaults: defaults))
        XCTAssertEqual(resolvedAgain.standardizedFileURL.path, renamed.standardizedFileURL.path)
    }

    // MARK: - 6. Clear removes the stored bookmark

    func testClearRemovesStoredBookmark() throws {
        let defaults = makeIsolatedDefaults()
        let folder = makeTempFolder("clear")
        defer { try? FileManager.default.removeItem(at: folder) }

        SidecastCorpusBookmark.save(folder, defaults: defaults)
        XCTAssertNotNil(defaults.data(forKey: SidecastCorpusBookmark.defaultsKey))

        SidecastCorpusBookmark.clear(defaults: defaults)

        XCTAssertNil(defaults.data(forKey: SidecastCorpusBookmark.defaultsKey))
        XCTAssertNil(SidecastCorpusBookmark.resolve(defaults: defaults))
    }
}
