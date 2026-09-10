import AppKit
import SwiftUI

/// Owns the presenter window. Requests capture exclusion with `.none`, but
/// this setting is not proof of invisibility to ScreenCaptureKit or Teams.
/// Actual selected-window/full-display behavior requires a remote observer.
/// Content is installed lazily when first shown, not during app construction.
@MainActor
final class SidecastWhiteboardWindowController {
    let window: NSWindow
    let model: SidecastWhiteboardModel
    let knowledgePackStore: KnowledgePackStore
    private let onChoosePack: (URL) -> Void
    private let onOpenSaved: () -> Void
    /// WB-5/I6: the hosted view's Clear button action. Defaults to a
    /// model-only clear (the pre-fix behavior) when no richer closure is
    /// supplied — production always supplies one (see
    /// `OpenOatsRootApp.showWhiteboardWindow`, which wires
    /// `coordinator.sidecastWhiteboardCoordinator?.clear()` so the
    /// orchestrator's queued/in-flight work is discarded too, not just the
    /// board); callers with no coordinator to reach (this type's own
    /// parameterless test construction, `SidecastWhiteboardSharingTests`)
    /// get the harmless fallback instead.
    private let onClear: () -> Void
    private var hasInstalledContent = false

    init(
        model: SidecastWhiteboardModel = SidecastWhiteboardModel(),
        knowledgePackStore: KnowledgePackStore = KnowledgePackStore(profileRegistry: .empty),
        onChoosePack: ((URL) -> Void)? = nil,
        onOpenSaved: @escaping () -> Void = {},
        onClear: (() -> Void)? = nil
    ) {
        self.model = model
        self.knowledgePackStore = knowledgePackStore
        self.onOpenSaved = onOpenSaved
        self.onChoosePack = onChoosePack ?? { folder in Task { await knowledgePackStore.load(fromPath: folder.path) } }
        self.onClear = onClear ?? { model.clear() }

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

        // Best-effort exclusion request; see the visible sharing warning.
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
                rootView: SidecastWhiteboardView(model: model, knowledgePackStore: knowledgePackStore,
                                                onChoosePack: onChoosePack, onOpenSaved: onOpenSaved, onClear: onClear)
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
