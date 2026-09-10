import Foundation
import Observation

struct WhiteboardEvidenceSnapshot: Codable, Equatable, Sendable {
    let sessionID: String
    let eventID: String
    let revisionSequence: Int
    let packID: String
    let packContentHash: String
    let evidenceState: KnowledgeEvidenceState
    let sources: [KnowledgeOverlaySource]
    let isProvisional: Bool
    let engine: String
}

/// Presenter state and export for the evidence-backed coordinator. Evidence
/// states include uncertainty and abstention, not just factual answers.
@MainActor
@Observable
final class SidecastWhiteboardModel {
    /// A displayed question/result pair with an immutable evidence snapshot.
    /// Evidence is optional solely for the retained prototype model tests.
    struct DisplayNote: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let question: String
        let answer: String
        let timestamp: Date
        let evidence: WhiteboardEvidenceSnapshot?
        var isSuperseded = false

        init(id: UUID = UUID(), question: String, answer: String, timestamp: Date, evidence: WhiteboardEvidenceSnapshot? = nil) {
            self.id = id
            self.question = question
            self.answer = answer
            self.timestamp = timestamp
            self.evidence = evidence
        }
    }

    /// Lifecycle status supplied by the coordinator.
    enum Status: Equatable {
        case ready
        case live
        case answering(count: Int)
        case paused
        case error(String)
        /// Accepted notes remain available; unfinished work cannot publish.
        case ended
    }

    /// Status-dot color — matches the bench's `--ok`/`--warn`/`--err`/
    /// `--muted` CSS variables (`ui.ts`).
    enum StatusDotColor: Equatable {
        case gray
        case green
        case amber
        case red
    }

    private(set) var notes: [DisplayNote] = []
    var sessionStart: Date?
    var status: Status = .ready
    /// Legacy prototype export metadata. Production exports identify the
    /// actual local engine in each evidence snapshot, not a settings choice.
    var configuredModel: String?

    private(set) var isAutoScroll = true

    /// Authoritative readiness. A requested pack that fails validation pauses
    /// assistance; it must not silently keep answering from the previous pack.
    var corpusStatusLine: String?

    /// True when `corpusStatusLine` describes a failure rather than
    /// purely-informational text — lets the view render it in the same
    /// error red as its own (unrelated) `corpusStatusText`/
    /// `corpusStatusIsError` pair. Meaningless while `corpusStatusLine`
    /// is `nil`; always `false` there (see `clear()`).
    var corpusStatusLineIsError = false
    var storageStatusLine: String?

    private(set) var heardCount = 0
    private(set) var listensCount = 0
    private(set) var questionsCount = 0
    private(set) var answersCount = 0

    init(configuredModel: String? = nil) {
        self.configuredModel = configuredModel
    }

    /// True only for `.live` — pulled out since both `isStatusPulsing` and
    /// `diagText`'s visibility gate key off the same condition.
    private var isLiveStatus: Bool {
        if case .live = status { return true }
        return false
    }

    // MARK: - Notes

    /// Appends a landed answer to the board and counts it toward the
    /// answers diagnostic — mirrors the bench, where the orchestrator's
    /// `onNote` callback does both in one step (`diag.answers++` then
    /// `addBoardNote`, `main.ts`).
    func receive(note: SidecastAnsweredNote) {
        notes.append(DisplayNote(question: note.question, answer: note.answer, timestamp: note.timestamp))
        noteDiagAnswer()
    }

    /// Production entry point: only the common evidence-gated result type.
    func receive(card: KnowledgeOverlayCard, question: String, timestamp: Date,
                 sessionID: String, packID: String, packContentHash: String) {
        let evidence = WhiteboardEvidenceSnapshot(
            sessionID: sessionID, eventID: card.eventID, revisionSequence: card.revisionSequence,
            packID: packID, packContentHash: packContentHash, evidenceState: card.evidenceState,
            sources: card.sources, isProvisional: card.isProvisional, engine: "local-knowledge-pack")
        if let index = notes.firstIndex(where: { $0.evidence?.eventID == card.eventID && $0.evidence?.sessionID == sessionID }) {
            guard (notes[index].evidence?.revisionSequence ?? 0) <= card.revisionSequence else { return }
            notes[index] = DisplayNote(id: notes[index].id, question: question, answer: card.answer,
                                      timestamp: timestamp, evidence: evidence)
        } else {
            notes.append(DisplayNote(question: question, answer: card.answer, timestamp: timestamp, evidence: evidence))
            noteDiagAnswer()
        }
    }

    func supersede(eventID: String) {
        for index in notes.indices where notes[index].evidence?.eventID == eventID {
            notes[index].isSuperseded = true
        }
    }

    func supersedeAll() {
        for index in notes.indices { notes[index].isSuperseded = true }
    }

    func restore(_ archive: WhiteboardSessionArchive) {
        clear()
        notes = archive.notes
        sessionStart = archive.startedAt
        configuredModel = nil
        status = .ended
        answersCount = notes.count
        corpusStatusLine = "Saved session · historical evidence; source files may have changed."
    }

    /// Resets the board to a fresh, empty session. `configuredModel` is
    /// deliberately left untouched — it tracks app settings, not board
    /// state, and clearing the board is not a settings change.
    func clear() {
        notes = []
        sessionStart = nil
        status = .ready
        isAutoScroll = true
        heardCount = 0
        listensCount = 0
        questionsCount = 0
        answersCount = 0
        corpusStatusLine = nil
        corpusStatusLineIsError = false
    }

    // MARK: - Session-relative time

    /// `m:ss` — minutes unpadded, seconds zero-padded to 2 digits, floored
    /// at 0. Exact port of the bench's `formatWhiteboardTime` (`ui.ts`) /
    /// `formatExportTime` (`main.ts`) — identical logic under two names in
    /// the bench; unified here since both the live header and the export
    /// header line need the same session-relative computation over our
    /// absolute-`Date` notes (the bench worked directly from an
    /// already-relative video/session-clock number of seconds).
    static func formatSessionTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let secs = total % 60
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    /// Seconds elapsed since `sessionStart`, formatted as `m:ss` — a note
    /// timestamped before `sessionStart` (clock skew, or no session started
    /// yet) reads as `0:00` rather than a negative time.
    func sessionRelativeTime(for date: Date) -> String {
        guard let sessionStart else { return Self.formatSessionTime(0) }
        return Self.formatSessionTime(max(0, date.timeIntervalSince(sessionStart)))
    }

    // MARK: - Status strip

    var statusText: String {
        switch status {
        case .ready: "Ready"
        case .live: "Live — listening"
        case .answering(let count): "Answering \(count) question\(count == 1 ? "" : "s")…"
        case .paused: "Paused"
        case .error(let message): message
        case .ended: "Ended"
        }
    }

    var statusDotColor: StatusDotColor {
        switch status {
        case .ready: .gray
        case .live: .green
        case .answering: .amber
        case .paused: .green
        case .error: .red
        case .ended: .gray
        }
    }

    /// Only `.live` pulses — matches the bench, which adds the `.live`
    /// pulse class solely alongside its "ok" playing state (`main.ts`'s
    /// `refreshIdleStatus`).
    var isStatusPulsing: Bool { isLiveStatus }

    // MARK: - Diagnostics

    /// Mirrors the bench's `renderDiag` (`main.ts`): blank until something
    /// has actually happened (heard a line, run a listen pass, gone live, or
    /// — WB-4 extension — spotted a question or landed an answer), then
    /// `heard N · listens N · questions N · answers N`. The bench's own
    /// guard (and WB-3's initial port) only checked heard/listens/live, an
    /// inherited quirk: a listen pass that already turned up a question or
    /// an answer would trivially also have bumped `listensCount`, so the
    /// gap was unreachable UNTIL WB-4 gave the counters an independent
    /// path to move without going through this model's own diag calls in
    /// lockstep — worth covering explicitly now that a live coordinator
    /// drives them.
    var diagText: String {
        guard heardCount != 0 || listensCount != 0 || questionsCount != 0 || answersCount != 0 || isLiveStatus else {
            return ""
        }
        return "heard \(heardCount) · listens \(listensCount) · questions \(questionsCount) · answers \(answersCount)"
    }

    func noteDiagHeard() { heardCount += 1 }
    func noteDiagListen() { listensCount += 1 }
    func noteDiagQuestions(_ count: Int) { questionsCount += count }
    func noteDiagAnswer() { answersCount += 1 }

    // MARK: - Auto-scroll

    /// The reader scrolled away from the newest note — pause the roll until
    /// they return to the bottom. Mirrors the bench's scroll listener
    /// (`main.ts`: `isAutoScroll = isNearBottom()`), split into two named
    /// transitions so the view only has to report which edge it crossed,
    /// not recompute the near-bottom threshold itself.
    func userScrolledUp() { isAutoScroll = false }
    func scrolledToBottom() { isAutoScroll = true }

    // MARK: - Export

    private static let exportedAtFormatter = ISO8601DateFormatter()

    /// Plain-text export — exact per-note structure port of the bench's
    /// `exportText` (`main.ts`): a preamble, then for every note a
    /// `[m:ss] question` header line, the answer text, and a blank line.
    /// The preamble date is rendered as ISO 8601 rather than the bench's
    /// locale-formatted `toLocaleString()` — deterministic across machines
    /// where the bench's original relied on the browser's locale. The
    /// `Model:` line is included only when `configuredModel` is set
    /// (symmetric with the JSON export's optional `model` field), rather
    /// than the bench's unconditional line.
    func exportText(now: Date = Date()) -> String {
        var lines = ["Whiteboard notes — \(Self.exportedAtFormatter.string(from: now))"]
        if let configuredModel {
            lines.append("Model: \(configuredModel)")
        }
        lines.append("")
        for note in notes {
            lines.append("[\(sessionRelativeTime(for: note.timestamp))] \(note.question)")
            lines.append(note.answer)
            if let evidence = note.evidence {
                lines.append("\(evidence.evidenceState.overlayLabel) · \(evidence.packID) · \(evidence.packContentHash)")
                if evidence.isProvisional { lines.append("Provisional — question may change.") }
                if note.isSuperseded { lines.append("Historical/superseded — verify current context.") }
                for source in evidence.sources { lines.append("Source: \(source.title) · \(source.locator)\n\(source.excerpt)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the plain-text export straight to `url`. The write is the
    /// only part of this path that can actually fail — `exportText` itself
    /// is pure string building — so this throwing wrapper is what
    /// `SidecastWhiteboardView`'s Export button now calls (WB-5/I4 fix,
    /// replacing a bare `try?` that dropped the error on the floor), and
    /// what a test with no `NSSavePanel` in reach can drive directly to
    /// prove the failure path actually surfaces something.
    func writeExportText(to url: URL, now: Date = Date()) throws {
        try exportText(now: now).write(to: url, atomically: true, encoding: .utf8)
    }

    private struct ExportNote: Encodable {
        let timestamp: String
        let question: String
        let text: String
        let evidence: WhiteboardEvidenceSnapshot?
        let isSuperseded: Bool
    }

    private struct ExportPayload: Encodable {
        let exportedAt: String
        let model: String?
        let notes: [ExportNote]
        let totalNotes: Int
    }

    /// JSON export — exact field-shape port of the bench's `exportJSON`
    /// (`main.ts`): `exportedAt` / `model` / `notes[{timestamp,question,
    /// text}]` / `totalNotes`. `model`'s synthesized `Encodable` conformance
    /// uses `encodeIfPresent`, so the key is omitted entirely (not written
    /// as `null`) when `configuredModel` is unset.
    ///
    /// WB-5/I4 fix: throws rather than swallowing an encode failure into
    /// an empty `Data()` — an export button that "succeeds" silently with
    /// a zero-byte file on disk was worse than surfacing the real error to
    /// the caller.
    func exportJSON(now: Date = Date()) throws -> Data {
        let payload = ExportPayload(
            exportedAt: Self.exportedAtFormatter.string(from: now),
            model: configuredModel,
            notes: notes.map {
                ExportNote(timestamp: sessionRelativeTime(for: $0.timestamp), question: $0.question, text: $0.answer,
                           evidence: $0.evidence, isSuperseded: $0.isSuperseded)
            },
            totalNotes: notes.count
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    /// Writes the JSON export straight to `url` — see
    /// `writeExportText(to:)`.
    func writeExportJSON(to url: URL, now: Date = Date()) throws {
        try exportJSON(now: now).write(to: url)
    }
}
