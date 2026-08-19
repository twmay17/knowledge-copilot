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
/// The window and its `NSHostingView` are created once, here, and persist
/// for the controller's lifetime; `show()`/`hide()` only order it
/// front/out, so the hosted SwiftUI view's `.task` (the corpus
/// auto-resolve-on-launch) runs once per app launch rather than on every
/// reopen.
@MainActor
final class SidecastWhiteboardWindowController {
    let window: NSWindow
    let model: SidecastWhiteboardModel
    let corpusService: SidecastCorpusService

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

        newWindow.setFrameAutosaveName("SidecastWhiteboardWindow")

        newWindow.contentView = NSHostingView(
            rootView: SidecastWhiteboardView(model: model, corpusService: corpusService)
        )

        self.window = newWindow
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    var isVisible: Bool { window.isVisible }
}
