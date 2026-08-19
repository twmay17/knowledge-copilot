import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Native SwiftUI port of the bench's whiteboard page (`tools/sidecast-debug/index.html`
/// + `src/ui.ts` + `src/main.ts`), narrowed to what WB-3 needs: the board,
/// the status strip, the corpus picker, and export. The bench's left
/// settings rail (LLM provider/key/model) and its YouTube source dock are
/// intentionally not ported here — this native app configures its LLM
/// elsewhere in Settings, and there is no video-source concept in the live
/// meeting flow. No `LiveSessionController` wiring — that is WB-4; today
/// this view only drives the corpus picker/read and renders whatever
/// `SidecastWhiteboardModel` already holds.
struct SidecastWhiteboardView: View {
    let model: SidecastWhiteboardModel
    let corpusService: SidecastCorpusService
    /// WB-5/I6: the Clear button's action, injected by
    /// `SidecastWhiteboardWindowController` rather than this view calling
    /// `model.clear()` directly — clearing must also discard whatever the
    /// live coordinator's orchestrator has queued or in flight, which this
    /// view has no reference to. See the window controller's `onClear`
    /// doc comment for what the production closure actually does.
    let onClear: () -> Void

    @State private var corpusStatusText = SidecastWhiteboardView.noCorpusMessage
    @State private var corpusStatusIsError = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let noCorpusMessage = "No corpus loaded — answers fall back to general knowledge."
    static let emptyBoardHint =
        "Grounded answers appear here as the conversation gives the board something worth saying. Nothing is echoed back — only formed responses drawn from the loaded source."

    private static let atBottomThreshold: CGFloat = 32
    private static let topFadeHeight: CGFloat = 42
    private static let boardMaxWidth: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
            Divider()
            headerControls
            Divider()
            board
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(Color.whiteboardBackground)
        .task { await loadSavedCorpusIfAny() }
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 8) {
            StatusDot(color: model.statusDotColor.color, isPulsing: model.isStatusPulsing, reduceMotion: reduceMotion)
            Text(model.statusText)
                .font(.system(size: 12))
                .foregroundStyle(Color.whiteboardMuted)
            Spacer(minLength: 12)
            Text(model.diagText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Color.whiteboardMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color.whiteboardPanel)
    }

    // MARK: - Header controls

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button("Choose Corpus…") { pickCorpus() }
                Button("Clear") { onClear() }
                Spacer()
                Button("Export .txt") { exportText() }
                Button("Export .json") { exportJSON() }
            }
            .font(.system(size: 12))

            // Always visible, even mid-session — a silently dead corpus once
            // cost an entire bench run (see the bench's own comment on
            // `readCorpus`'s catch block, `main.ts`).
            Text(corpusStatusText)
                .font(.system(size: 10.5))
                .foregroundStyle(corpusStatusIsError ? Color.whiteboardError : Color.whiteboardMuted)
                .lineLimit(1)
                .truncationMode(.middle)

            // The live coordinator's own periodic corpus-refresh status
            // (WB-4/WB-5) — distinct from `corpusStatusText` above, which
            // only covers this view's own interactive picker/initial-load
            // flow. `nil` (nothing rendered) whenever the coordinator has
            // nothing to report, e.g. the feature flag is off.
            if let corpusStatusLine = model.corpusStatusLine {
                Text(corpusStatusLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(model.corpusStatusLineIsError ? Color.whiteboardError : Color.whiteboardMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.whiteboardPanel)
    }

    // MARK: - Board

    private var board: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.notes.isEmpty {
                        Text(Self.emptyBoardHint)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.whiteboardMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                            .padding(.top, 64)
                    } else {
                        ForEach(model.notes) { note in
                            NoteRow(model: model, note: note)
                                .id(note.id)
                                .transition(
                                    reduceMotion
                                        ? .identity
                                        : .asymmetric(
                                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                                            removal: .opacity)
                                )
                        }
                    }
                }
                .frame(maxWidth: Self.boardMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                // Bottom padding lets the newest note settle mid-board
                // rather than pinned to the very bottom edge, matching the
                // bench's `24vh` — approximated here as a fixed value since
                // SwiftUI has no direct viewport-relative padding unit.
                .padding(.bottom, 160)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: model.notes.count)
            }
            .scrollIndicators(.hidden)
            .background(Color.whiteboardBoard)
            .mask(topFadeMask)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom =
                    geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y
                return distanceFromBottom < Self.atBottomThreshold
            } action: { _, isNearBottom in
                if isNearBottom {
                    model.scrolledToBottom()
                } else {
                    model.userScrolledUp()
                }
            }
            .onChange(of: model.notes.count) { _, _ in
                guard model.isAutoScroll, let lastID = model.notes.last?.id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if !model.isAutoScroll {
                    ResumeFollowingButton {
                        model.scrolledToBottom()
                        if let lastID = model.notes.last?.id {
                            withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    /// Fades the top ~42pt of the board to transparent, like credits
    /// dissolving — exact port of the bench's mask-image gradient (`ui.ts`'s
    /// `#sidecast-bubbles`).
    private var topFadeMask: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: min(1, Self.topFadeHeight / max(geometry.size.height, 1))),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Corpus

    private func pickCorpus() {
        guard let url = SidecastCorpusBookmark.pick() else { return }
        Task { await readCorpus(from: url) }
    }

    private func loadSavedCorpusIfAny() async {
        guard let url = SidecastCorpusBookmark.resolve() else { return }
        await readCorpus(from: url)
    }

    private func readCorpus(from url: URL) async {
        do {
            let state = try await corpusService.read(folder: url)
            corpusStatusIsError = false
            corpusStatusText =
                state.files.isEmpty
                ? "Folder read, but it holds no .md/.txt/.csv files — run the prep prompt first."
                : Self.describeCorpus(state)
        } catch {
            // Always visible, in red — see `headerControls`'s comment.
            corpusStatusIsError = true
            corpusStatusText = "Corpus unreadable — \(error.localizedDescription)"
        }
    }

    /// Port of the bench's `describeCorpus` (`main.ts`).
    private static func describeCorpus(_ state: SidecastCorpusState) -> String {
        let names = state.files.map(\.name)
        let head = names.prefix(2).joined(separator: ", ")
        let more = names.count > 2 ? " +\(names.count - 2) more" : ""
        let skippedCount = state.skipped.count
        let skippedText =
            skippedCount > 0 ? " · \(skippedCount) non-text file\(skippedCount == 1 ? "" : "s") skipped" : ""
        let kChars = Int((Double(state.totalChars) / 1000).rounded())
        let readAt = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        return "\(head)\(more) · \(kChars)k chars\(skippedText) · read \(readAt)"
    }

    // MARK: - Export

    private func exportText() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "whiteboard-\(Self.filenameTimestamp()).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.writeExportText(to: url)
        } catch {
            // WB-5/I4 fix: this used to be a bare `try?` — a failed export
            // (disk full, permission denied, …) silently vanished with no
            // sign anything went wrong. Reuses this view's own visible
            // status line/error flag rather than a separate mechanism.
            corpusStatusIsError = true
            corpusStatusText = "Export failed — \(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "whiteboard-\(Self.filenameTimestamp()).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.writeExportJSON(to: url)
        } catch {
            corpusStatusIsError = true
            corpusStatusText = "Export failed — \(error.localizedDescription)"
        }
    }

    private static func filenameTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}

// MARK: - Note row

private struct NoteRow: View {
    let model: SidecastWhiteboardModel
    let note: SidecastWhiteboardModel.DisplayNote

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(model.sessionRelativeTime(for: note.timestamp)) · \(note.question)")
                .font(.system(size: 10.5))
                .tracking(0.3)
                .foregroundStyle(Color.whiteboardMuted)
            Text(note.answer)
                .font(.system(size: 20))
                .lineSpacing(6)
                .foregroundStyle(Color.whiteboardInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.whiteboardHairline).frame(height: 1)
        }
    }
}

// MARK: - Status dot

/// Native approximation of the bench's `livePulse` CSS keyframe (an
/// expanding, fading box-shadow ring, `ui.ts`) via a repeating scale +
/// opacity animation on a stroked ring behind the solid dot.
private struct StatusDot: View {
    let color: Color
    let isPulsing: Bool
    let reduceMotion: Bool

    @State private var animating = false

    var body: some View {
        ZStack {
            if isPulsing && !reduceMotion {
                Circle()
                    .stroke(color.opacity(0.45), lineWidth: 2)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 2.6 : 1)
                    .opacity(animating ? 0 : 0.7)
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear { updateAnimation() }
        .onChange(of: isPulsing) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard isPulsing, !reduceMotion else {
            animating = false
            return
        }
        withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
            animating = true
        }
    }
}

// MARK: - Resume-following affordance

/// Shown when the reader has scrolled away from the newest note — lets them
/// jump back and resume the auto-roll with one click, rather than having to
/// scroll manually. Brief-sanctioned companion to (not a replacement for)
/// `onScrollGeometryChange`'s passive near-bottom detection above.
private struct ResumeFollowingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Resume following", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
}

// MARK: - Palette

extension SidecastWhiteboardModel.StatusDotColor {
    var color: Color {
        switch self {
        case .gray: Color(red: 0.541, green: 0.561, blue: 0.600)  // --muted
        case .green: Color(red: 0.184, green: 0.420, blue: 0.267)  // --ok
        case .amber: Color(red: 0.690, green: 0.478, blue: 0.071)  // --warn
        case .red: Color(red: 0.702, green: 0.251, blue: 0.165)  // --err
        }
    }
}

extension Color {
    /// Warm-white board family, ported from the bench's CSS custom
    /// properties (`ui.ts`'s `:root`).
    static let whiteboardBackground = Color(red: 0.984, green: 0.984, blue: 0.973)  // --bg #fbfbf8
    static let whiteboardPanel = Color.white  // --panel #ffffff
    static let whiteboardBoard = Color.white  // --board #ffffff
    static let whiteboardHairline = Color(red: 0.941, green: 0.937, blue: 0.914)  // --hair #f0efe9
    static let whiteboardInk = Color(red: 0.102, green: 0.114, blue: 0.141)  // --ink #1a1d24
    static let whiteboardMuted = Color(red: 0.541, green: 0.561, blue: 0.600)  // --muted #8a8f99
    static let whiteboardError = Color(red: 0.702, green: 0.251, blue: 0.165)  // --err #b3402a
}
