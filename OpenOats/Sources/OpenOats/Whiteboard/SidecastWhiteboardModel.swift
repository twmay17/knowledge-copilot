import Foundation
import Observation

/// Live view-model for the whiteboard window: the rolling note stream, the
/// status strip's state, and export. Owns no session/orchestrator wiring —
/// that lands in WB-4; every mutation for WB-3 happens through the small,
/// directly-testable API below (`receive(note:)`, the `noteDiag...` family,
/// the auto-scroll transitions), so a future `LiveSessionController` only
/// has to call these same methods rather than reach into stored state.
///
/// Swift port of the bench's whiteboard state (`main.ts`'s module-level
/// `streamNotes`/`diag`/`isAutoScroll`/`answeringCount`, plus `ui.ts`'s
/// `WhiteboardNote`), narrowed to what the native corpus-only flow needs —
/// every note here is a grounded corpus answer; the bench's broader
/// "anticipation" persona-tinted note kind never appears on this board.
@MainActor
@Observable
final class SidecastWhiteboardModel {
    /// One note on the board: the question the listener spotted and the
    /// grounded answer the orchestrator produced, with the absolute
    /// wall-clock time it landed. Swift port of the bench's `WhiteboardNote`
    /// (`ui.ts`), narrowed to the fields the native board shows.
    struct DisplayNote: Identifiable, Equatable, Sendable {
        let id: UUID
        let question: String
        let answer: String
        let timestamp: Date

        init(id: UUID = UUID(), question: String, answer: String, timestamp: Date) {
            self.id = id
            self.question = question
            self.answer = answer
            self.timestamp = timestamp
        }
    }

    /// Status-strip state. A deliberate reduction of the bench's many
    /// `setStatus(state, text)` call sites (`main.ts`'s `refreshIdleStatus`)
    /// down to the shapes WB-3 needs without a live session driving it —
    /// WB-4 maps real `LiveSessionController` states onto these.
    enum Status: Equatable {
        case ready
        case live
        case answering(count: Int)
        case paused
        case error(String)
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
    /// The configured LLM model id, for the export payload's optional
    /// `model` field. Not read from `AppSettings` directly — the model has
    /// no settings dependency of its own — the window controller (or
    /// WB-4's live wiring) passes it in when it is trivially reachable.
    var configuredModel: String?

    private(set) var isAutoScroll = true

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
        }
    }

    var statusDotColor: StatusDotColor {
        switch status {
        case .ready: .gray
        case .live: .green
        case .answering: .amber
        case .paused: .green
        case .error: .red
        }
    }

    /// Only `.live` pulses — matches the bench, which adds the `.live`
    /// pulse class solely alongside its "ok" playing state (`main.ts`'s
    /// `refreshIdleStatus`).
    var isStatusPulsing: Bool { isLiveStatus }

    // MARK: - Diagnostics

    /// Mirrors the bench's `renderDiag` (`main.ts`): blank until something
    /// has actually happened (heard a line, run a listen pass, or gone
    /// live), then `heard N · listens N · questions N · answers N`.
    var diagText: String {
        guard heardCount != 0 || listensCount != 0 || isLiveStatus else { return "" }
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
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private struct ExportNote: Encodable {
        let timestamp: String
        let question: String
        let text: String
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
    func exportJSON(now: Date = Date()) -> Data {
        let payload = ExportPayload(
            exportedAt: Self.exportedAtFormatter.string(from: now),
            model: configuredModel,
            notes: notes.map {
                ExportNote(timestamp: sessionRelativeTime(for: $0.timestamp), question: $0.question, text: $0.answer)
            },
            totalNotes: notes.count
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(payload)) ?? Data()
    }
}
