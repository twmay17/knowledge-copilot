import AppKit
import SwiftUI

/// Owns the whiteboard's `NSWindow` and the SwiftUI content hosted inside
/// it.
///
/// The one non-negotiable property of this window, and the reason it is a
/// hand-built `NSWindow` rather than a SwiftUI `Window(id:)` scene: it must
/// NEVER be capturable by screen sharing. `sharingType = .none` is set
/// exactly once, in `init`, before the window is ever shown — matching
/// `MiniBarPanel`/`OverlayPanel`'s documented one-way ratchet (macOS
/// refuses to make a window capturable again once excluded), except this
/// window has no toggle and no rebuild-to-re-enable path at all: unlike
/// those panels, which follow the user's "hide from screen share" setting
/// and can be asked to become `.readOnly` again, the whiteboard has no
/// visible-in-share mode, full stop. Nothing in this type may ever assign
/// `sharingType` a second time.
///
/// The window object itself is created in `init` (so `sharingType` can be
/// set immediately — see above), but its SwiftUI content is deliberately
/// NOT installed there. `NSHostingView`'s content "appears" (running the
/// hosted view's `.task`, in this case the corpus bookmark resolve-and-read)
/// as soon as it is installed as a window's `contentView` — independent of
/// whether that window is ever ordered front. Installing it eagerly here
/// would fire that `.task` — and its possibly multi-MB recursive disk read
/// — the moment this controller is constructed, whether or not the window
/// is ever shown. `show()` installs the content on its first call instead,
/// so the trigger is genuinely tied to the window actually being shown, not
/// merely to the controller existing. (Proven empirically in review: an
/// instrumented counter plus a wait with no `show()` call showed the `.task`
/// firing anyway, before this fix.)
@MainActor
final class SidecastWhiteboardWindowController {
    let window: NSWindow
    let model: SidecastWhiteboardModel
    let corpusService: SidecastCorpusService
    private var hasInstalledContent = false

    init(
        model: SidecastWhiteboardModel = SidecastWhiteboardModel(),
        corpusService: SidecastCorpusService = SidecastCorpusService()
    ) {
        self.model = model
        self.corpusService = corpusService

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.identifier = NSUserInterfaceItemIdentifier("SidecastWhiteboardWindow")
        newWindow.title = "Whiteboard"
        newWindow.minSize = NSSize(width: 480, height: 360)
        newWindow.isReleasedWhenClosed = false

        // NEVER appear in a screen share. Set once, here, unconditionally —
        // see the type-level doc above. Do not add another assignment.
        newWindow.sharingType = .none

        // The board's palette (warm-white, ported from the bench's fixed
        // CSS custom properties) is deliberately not dark-mode-aware —
        // locking the window to the light appearance keeps every dynamic
        // system color used anywhere in its content (SwiftUI `.secondary`
        // and friends included) resolving against a light backdrop, rather
        // than depending on every current and future use in the hosted view
        // being manually pinned to the fixed palette.
        newWindow.appearance = NSAppearance(named: .aqua)

        newWindow.setFrameAutosaveName("SidecastWhiteboardWindow")

        self.window = newWindow
    }

    /// Installs the SwiftUI content on first call (see the type doc for
    /// why that installation is deferred rather than done in `init`), then
    /// orders the window front.
    func show() {
        if !hasInstalledContent {
            hasInstalledContent = true
            window.contentView = NSHostingView(
                rootView: SidecastWhiteboardView(model: model, corpusService: corpusService)
            )
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    var isVisible: Bool { window.isVisible }
}
