import Foundation

/// One file loaded into the corpus, as reported in `SidecastCorpusState`.
struct SidecastCorpusFile: Equatable {
    let name: String
    let chars: Int
}

/// Snapshot of a loaded corpus folder: which files were read, which were
/// skipped (and why), and the total character count across loaded files.
struct SidecastCorpusState: Equatable {
    let folder: URL
    let files: [SidecastCorpusFile]
    let skipped: [String]
    let totalChars: Int
}

enum SidecastCorpusError: LocalizedError {
    case notADirectory(String)

    var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            "Not a folder: \(path)"
        }
    }
}

/// Reads a local folder of frontier-model-prepared corpus text (see
/// CORPUS_PREP_PROMPT.md in the bench) and answers retrieval queries against
/// it for the live whiteboard session.
///
/// Swift port of the bench's `tools/sidecast-debug/src/corpus.ts` plus its
/// server-side `/api/corpus` folder scan — semantics ported verbatim,
/// including treating string length as UTF-16 code units (`.utf16.count`)
/// everywhere corpus.ts uses JavaScript's `String.length`, so the character
/// math (chunk sizes, caps) lines up exactly with the reference.
actor SidecastCorpusService {
    private struct LoadedFile {
        let name: String
        let text: String
    }

    private struct Chunk {
        let name: String
        let text: String
    }

    // Text formats only — mixed media (.xlsm, .pdf) is digested offline by a
    // frontier model into markdown this can read.
    private static let supportedExtensions: Set<String> = ["md", "txt", "csv"]
    private static let perFileCap = 2 * 1024 * 1024
    private static let totalCap = 6 * 1024 * 1024

    private static let wholeCorpusCharLimit = 10_000
    private static let chunkChars = 900
    private static let topKChunks = 8
    private static let evidenceCharCap = 9_000

    private var loadedFiles: [LoadedFile] = []
    private(set) var state: SidecastCorpusState?

    // MARK: - Reading

    /// Reads `.md`/`.txt`/`.csv` files recursively from `folder`, skipping
    /// dotfiles (silently — not reported), unsupported extensions (reported
    /// in `skipped` by relative path), and files that blow the per-file
    /// (2MB) or cumulative (6MB) cap (reported in `skipped` with a reason
    /// suffix). Files are processed in a deterministic (sorted-by-relative-
    /// path) order so the cumulative-cap cutoff is reproducible.
    func read(folder: URL) throws -> SidecastCorpusState {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let root = folder.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SidecastCorpusError.notADirectory(root.path)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            throw SidecastCorpusError.notADirectory(root.path)
        }

        var candidates: [(url: URL, relativePath: String)] = []
        for case let url as URL in enumerator {
            let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegularFile else { continue }
            // Dotfiles are dropped by leaf name only (matching the bench's
            // `entry.name.startsWith(".")`) — a file inside a non-dot folder
            // still counts even if some ancestor folder name starts with ".".
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            candidates.append((url, Self.relativePath(of: url, in: root)))
        }
        candidates.sort { $0.relativePath < $1.relativePath }

        var files: [SidecastCorpusFile] = []
        var loaded: [LoadedFile] = []
        var skipped: [String] = []
        var totalBytes = 0

        for candidate in candidates {
            let ext = candidate.url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                skipped.append(candidate.relativePath)
                continue
            }

            let fileSize = (try? candidate.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if fileSize > Self.perFileCap {
                skipped.append("\(candidate.relativePath) (over per-file cap)")
                continue
            }
            if totalBytes + fileSize > Self.totalCap {
                skipped.append("\(candidate.relativePath) (total cap reached)")
                continue
            }

            // Lossy decode, never throws — matches the bench's
            // `fs.readFile(path, "utf-8")`, which substitutes U+FFFD for
            // invalid byte sequences and keeps going rather than rejecting
            // the whole read. A throwing decode here would abort every other
            // file in the folder over one malformed one; the reference never
            // does that.
            let data = try Data(contentsOf: candidate.url)
            let text = String(decoding: data, as: UTF8.self)
            totalBytes += fileSize
            loaded.append(LoadedFile(name: candidate.relativePath, text: text))
            files.append(SidecastCorpusFile(name: candidate.relativePath, chars: text.utf16.count))
        }

        let newState = SidecastCorpusState(
            folder: root,
            files: files,
            skipped: skipped,
            totalChars: files.reduce(0) { $0 + $1.chars }
        )

        loadedFiles = loaded
        state = newState
        return newState
    }

    func clear() {
        loadedFiles = []
        state = nil
    }

    // MARK: - Retrieval

    /// Evidence for one generation turn: the whole corpus when it is small
    /// enough, otherwise the best-matching chunks for `query`. Digit-bearing
    /// tokens score double — this is financial data, and the numbers are
    /// usually what the conversation is reaching for.
    func retrieveEvidence(query: String) -> String? {
        guard !loadedFiles.isEmpty else { return nil }

        let total = loadedFiles.reduce(0) { $0 + $1.text.utf16.count }
        if total <= Self.wholeCorpusCharLimit {
            return loadedFiles
                .map { "--- \($0.name) ---\n\($0.text)" }
                .joined(separator: "\n\n")
        }

        let queryTokens = Set(Self.tokenize(query))

        let chunks = loadedFiles.flatMap { Self.chunkFile(name: $0.name, text: $0.text) }
        var scored: [(chunk: Chunk, score: Int, index: Int)] = []
        scored.reserveCapacity(chunks.count)
        for (index, chunk) in chunks.enumerated() {
            var score = 0
            for token in Self.tokenize(chunk.text) where queryTokens.contains(token) {
                score += Self.isDigitBearing(token) ? 2 : 1
            }
            if score > 0 {
                scored.append((chunk, score, index))
            }
        }

        // Foundation's `sorted(by:)` is not stable, unlike JS's `Array#sort`
        // (stable since ES2019) — break ties on original index so equal-
        // score chunks keep document order deterministically.
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
        }

        let top = scored.prefix(Self.topKChunks)
        guard !top.isEmpty else { return nil }

        var out = ""
        for entry in top {
            let piece = "--- \(entry.chunk.name) ---\n\(entry.chunk.text)\n\n"
            if out.utf16.count + piece.utf16.count > Self.evidenceCharCap { break }
            out += piece
        }

        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Chunking

    /// Chunks a file's text on line boundaries near `chunkChars`; a single
    /// line longer than the target is kept whole rather than split mid-line
    /// (matching the bench's line-accumulate-then-flush algorithm exactly).
    /// CSV chunks re-carry the header line so rows stay legible on their own.
    private static func chunkFile(name: String, text: String) -> [Chunk] {
        guard text.utf16.count > Self.chunkChars else {
            return [Chunk(name: name, text: text)]
        }

        let lines = text.components(separatedBy: "\n")
        let isCSV = name.lowercased().hasSuffix(".csv")
        let header = isCSV ? (lines.first ?? "") : ""

        var chunks: [Chunk] = []
        var current: [String] = []
        var size = 0

        func flush() {
            guard !current.isEmpty else { return }
            let body = current.joined(separator: "\n")
            let chunkText = (isCSV && !body.hasPrefix(header)) ? "\(header)\n\(body)" : body
            chunks.append(Chunk(name: name, text: chunkText))
            current = []
            size = 0
        }

        for line in lines {
            if size + line.utf16.count > Self.chunkChars && !current.isEmpty {
                flush()
            }
            current.append(line)
            size += line.utf16.count + 1
        }
        flush()

        return chunks
    }

    // MARK: - Tokenizing

    private static let tokenScalars: Set<Unicode.Scalar> = Set("abcdefghijklmnopqrstuvwxyz0123456789.$%".unicodeScalars)
    private static let digitCharacters: Set<Character> = Set("0123456789")

    /// Lowercases and splits on runs of characters outside `[a-z0-9.$%]`,
    /// keeping tokens longer than 2 characters. Mirrors corpus.ts's
    /// `text.toLowerCase().split(/[^a-z0-9.$%]+/).filter(w => w.length > 2)`.
    /// Walks Unicode scalars (not grapheme clusters) so combining sequences
    /// split the same way the regex's UTF-16-oriented matching would.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if Self.tokenScalars.contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                tokens.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { tokens.append(String(current)) }
        return tokens.filter { $0.utf16.count > 2 }
    }

    private static func isDigitBearing(_ token: String) -> Bool {
        token.contains { Self.digitCharacters.contains($0) }
    }

    // MARK: - Paths

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        let dropped = path.dropFirst(rootPath.count).drop(while: { $0 == "/" })
        return dropped.isEmpty ? url.lastPathComponent : String(dropped)
    }
}
