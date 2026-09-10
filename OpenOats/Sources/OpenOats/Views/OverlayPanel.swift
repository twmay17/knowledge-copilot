import AppKit
import SwiftUI

/// A floating NSPanel that can opt out of supported window-capture APIs.
final class OverlayPanel: NSPanel {
    var onClose: (() -> Void)?

    init(
        contentRect: NSRect,
        defaults: UserDefaults = .standard,
        alwaysOnTop: Bool = true,
        hideFromScreenShare: Bool? = nil
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = alwaysOnTop
        level = alwaysOnTop ? .floating : .normal
        let hidden = hideFromScreenShare
            ?? (defaults.object(forKey: "hideFromScreenShare") == nil
                ? true
                : defaults.bool(forKey: "hideFromScreenShare"))
        sharingType = hidden ? .none : .readOnly
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Remember position
        setFrameAutosaveName("OverlayPanel")
    }

    /// Update the always-on-top state of an existing panel.
    func applyAlwaysOnTop(_ enabled: Bool) {
        isFloatingPanel = enabled
        level = enabled ? .floating : .normal
    }

    func applyHideFromScreenShare(_ enabled: Bool) {
        sharingType = enabled ? .none : .readOnly
    }

    override func close() {
        super.close()
        onClose?()
    }
}

/// Manages the floating suggestion side panel lifecycle.
@MainActor
final class OverlayManager: ObservableObject {
    private(set) var panel: OverlayPanel?
    private(set) var sidecastPanel: OverlayPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var sidecastHostingView: NSHostingView<AnyView>?
    private var globalKeyboardMonitor: Any?
    private var localKeyboardMonitor: Any?
    var defaults: UserDefaults = .standard
    // Injectable readback keeps the fallback test independent of OS behavior.
    var captureSharingType: (NSWindow) -> NSWindow.SharingType = { $0.sharingType }

    // Classic suggestions panel dimensions
    private static let classicWidth: CGFloat = 320
    private static let classicMinHeight: CGFloat = 100
    private static let classicMaxHeight: CGFloat = 400

    // Sidecast sidebar dimensions
    private static let sidecastDefaultWidth: CGFloat = 380
    private static let sidecastMinWidth: CGFloat = 300
    private static let sidecastMaxWidth: CGFloat = 550

    func showSidePanel<Content: View>(content: Content) {
        let erased = AnyView(content)

        if panel == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            let rect = NSRect(
                x: screenFrame.maxX - Self.classicWidth - 12,
                y: screenFrame.midY - Self.classicMaxHeight / 2,
                width: Self.classicWidth,
                height: Self.classicMaxHeight
            )
            let alwaysOnTop = defaults.object(forKey: "suggestionsAlwaysOnTop") == nil
                ? true
                : defaults.bool(forKey: "suggestionsAlwaysOnTop")
            let newPanel = OverlayPanel(contentRect: rect, defaults: defaults, alwaysOnTop: alwaysOnTop)
            newPanel.onClose = { [weak self] in self?.stopKeyboardMonitoringIfHidden() }
            newPanel.minSize = NSSize(width: Self.classicWidth, height: Self.classicMinHeight)
            newPanel.maxSize = NSSize(width: Self.classicWidth + 120, height: Self.classicMaxHeight)
            newPanel.setFrameAutosaveName("SuggestionSidePanel")
            panel = newPanel
        }

        if let hostingView {
            hostingView.rootView = erased
        } else {
            let newHostingView = NSHostingView(rootView: erased)
            hostingView = newHostingView
            panel?.contentView = newHostingView
        }
        panel?.orderFront(nil)
        startKeyboardMonitoringIfNeeded()
    }

    /// Show the full-height sidecast sidebar docked to the right edge.
    func showSidecastSidebar<Content: View>(content: Content) {
        let erased = AnyView(content)

        if sidecastPanel == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            // Full height, docked to right edge
            let rect = NSRect(
                x: screenFrame.maxX - Self.sidecastDefaultWidth,
                y: screenFrame.minY,
                width: Self.sidecastDefaultWidth,
                height: screenFrame.height
            )
            let newPanel = OverlayPanel(contentRect: rect, defaults: defaults)
            newPanel.onClose = { [weak self] in self?.stopKeyboardMonitoringIfHidden() }
            newPanel.minSize = NSSize(width: Self.sidecastMinWidth, height: 300)
            newPanel.maxSize = NSSize(width: Self.sidecastMaxWidth, height: screenFrame.height)
            newPanel.setFrameAutosaveName("SidecastSidebar")
            sidecastPanel = newPanel
        }

        if let sidecastHostingView {
            sidecastHostingView.rootView = erased
        } else {
            let newHostingView = NSHostingView(rootView: erased)
            sidecastHostingView = newHostingView
            sidecastPanel?.contentView = newHostingView
        }
        sidecastPanel?.orderFront(nil)
        startKeyboardMonitoringIfNeeded()
    }

    func hide() {
        panel?.orderOut(nil)
        // Clear the SwiftUI content so the NSHostingView stops participating
        // in the 60Hz display cycle (observation tracking + layout) while hidden.
        hostingView?.rootView = AnyView(EmptyView())

        sidecastPanel?.orderOut(nil)
        sidecastHostingView?.rootView = AnyView(EmptyView())
        stopKeyboardMonitoring()
    }

    func toggle<Content: View>(content: Content) {
        if panel?.isVisible == true {
            hide()
        } else {
            showSidePanel(content: content)
        }
    }

    func toggleSidecast<Content: View>(content: Content) {
        if sidecastPanel?.isVisible == true {
            sidecastPanel?.orderOut(nil)
            sidecastHostingView?.rootView = AnyView(EmptyView())
            if panel?.isVisible != true {
                stopKeyboardMonitoring()
            }
        } else {
            showSidecastSidebar(content: content)
        }
    }

    var isVisible: Bool {
        panel?.isVisible == true || sidecastPanel?.isVisible == true
    }

    /// Update the always-on-top state for the classic suggestions panel.
    func updateAlwaysOnTop(_ enabled: Bool) {
        panel?.applyAlwaysOnTop(enabled)
    }

    func updateHideFromScreenShare(_ enabled: Bool) {
        panel = Self.panelHonoringScreenShare(panel, hidden: enabled, defaults: defaults, readSharingType: captureSharingType)
        sidecastPanel = Self.panelHonoringScreenShare(
            sidecastPanel, hidden: enabled, defaults: defaults, readSharingType: captureSharingType
        )
    }

    /// Apply the requested setting; rebuild only if readback refuses it.
    /// Readback is not proof of actual Teams/Zoom capture behavior.
    private static func panelHonoringScreenShare(
        _ existing: OverlayPanel?,
        hidden: Bool,
        defaults: UserDefaults,
        readSharingType: (NSWindow) -> NSWindow.SharingType
    ) -> OverlayPanel? {
        guard let existing else { return nil }
        existing.applyHideFromScreenShare(hidden)
        guard !hidden, readSharingType(existing) != .readOnly else { return existing }

        let frame = existing.frame
        let wasVisible = existing.isVisible
        let autosaveName = existing.frameAutosaveName
        let content = existing.contentView
        let replacement = OverlayPanel(
            contentRect: frame,
            defaults: defaults,
            alwaysOnTop: existing.isFloatingPanel,
            hideFromScreenShare: false
        )
        replacement.onClose = existing.onClose
        replacement.minSize = existing.minSize
        replacement.maxSize = existing.maxSize
        existing.onClose = nil
        existing.close()
        replacement.contentView = content
        if !autosaveName.isEmpty {
            replacement.setFrameAutosaveName(autosaveName)
        }
        replacement.setFrame(frame, display: false)
        if wasVisible {
            replacement.orderFront(nil)
        }
        return replacement
    }

    /// Hide after a delay (used for session end).
    func hideAfterDelay(seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            hide()
        }
    }

    private func startKeyboardMonitoringIfNeeded() {
        guard globalKeyboardMonitor == nil, localKeyboardMonitor == nil else { return }

        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard let command = KnowledgeOverlayKeyboardShortcuts.command(for: event) else { return }
            Task { @MainActor in
                NotificationCenter.default.post(name: .knowledgeOverlayCommand, object: command)
            }
        }

        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let command = KnowledgeOverlayKeyboardShortcuts.command(for: event) else {
                return event
            }
            Task { @MainActor in
                NotificationCenter.default.post(name: .knowledgeOverlayCommand, object: command)
            }
            return nil
        }
    }

    private func stopKeyboardMonitoring() {
        if let globalKeyboardMonitor {
            NSEvent.removeMonitor(globalKeyboardMonitor)
            self.globalKeyboardMonitor = nil
        }
        if let localKeyboardMonitor {
            NSEvent.removeMonitor(localKeyboardMonitor)
            self.localKeyboardMonitor = nil
        }
    }

    private func stopKeyboardMonitoringIfHidden() {
        guard !isVisible else { return }
        stopKeyboardMonitoring()
    }
}
