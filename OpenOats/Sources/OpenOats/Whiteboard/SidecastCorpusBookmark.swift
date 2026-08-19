import AppKit
import Foundation

/// Persists the user's chosen corpus folder as a security-scoped bookmark so
/// the whiteboard can re-read it on a later launch without re-prompting.
///
/// Swift port of the bench's `localStorage.setItem(CORPUS_PATH_KEY, folder)`
/// (`main.ts`) — a plain path string there, since a browser tab has no
/// sandbox to re-authorize. The native app does: a bare path would silently
/// fail to resolve (or, worse, resolve to a same-named folder the user never
/// granted access to) once App Sandbox is involved, so this stores a
/// security-scoped bookmark instead. Mirrors the same shape as
/// `SettingsStore`'s `saveNotesFolderBookmark`/`resolveNotesFolderBookmark`.
///
/// Only bookmark *persistence* is exercised by `SidecastCorpusBookmarkTests`
/// (the UserDefaults round trip, corrupt/missing data, and stale-bookmark
/// refresh — all of which need no sandbox entitlements). Whether a bookmark
/// actually survives a fresh launch under App Sandbox / TCC folder-access
/// prompts, and the `pick()` panel itself, are maintainer-verified only —
/// see that test file's header comment.
enum SidecastCorpusBookmark {
    static let defaultsKey = "sidecast.corpus.bookmark"

    /// Persists a security-scoped bookmark for `url`, so `resolve` can find
    /// it again later — on this launch after picking a new folder, or on a
    /// future one.
    static func save(_ url: URL, defaults: UserDefaults = .standard) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: defaultsKey)
        } catch {
            Log.sidecast.error("[corpus-bookmark] failed to save: \(error, privacy: .public)")
        }
    }

    /// Resolves the stored bookmark to a URL, refreshing the stored data if
    /// macOS reports it stale (the folder moved since it was bookmarked).
    /// Returns `nil` if no bookmark is stored, or it cannot be resolved
    /// (corrupt data, or the folder no longer exists anywhere).
    static func resolve(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                save(url, defaults: defaults)
            }
            return url
        } catch {
            Log.sidecast.error("[corpus-bookmark] failed to resolve: \(error, privacy: .public)")
            return nil
        }
    }

    /// Forgets the stored bookmark (e.g. the user picks a different folder
    /// and the old one should no longer be offered).
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Directories-only picker for choosing the corpus folder — same shape
    /// as the app's other folder pickers (`SettingsView.swift`'s
    /// `chooseKBFolder`/`chooseKnowledgePackFolder`), plus bookmark
    /// persistence on a successful pick. A modal `NSOpenPanel` call: not
    /// unit-testable headlessly, maintainer-verified only.
    @MainActor
    static func pick(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder prepared with CORPUS_PREP_PROMPT.md"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        save(url, defaults: defaults)
        return url
    }
}
