import SwiftUI
import AppKit
import AVFoundation
import Sparkle
import UniformTypeIdentifiers
import UserNotifications

enum OpenOatsWindowSizing {
    static let homeTimelinePaneMinWidth: CGFloat = 340
    static let meetingDetailPaneMinWidth: CGFloat = 700
    static let notesWorkspaceSidebarWidth: CGFloat = 250
    static let mainWindowCollapsedMinSize = CGSize(width: 520, height: 560)
    static let mainWindowExpandedMinSize = CGSize(width: 1080, height: 560)
    static let notesWorkspaceMinSize = CGSize(width: 980, height: 560)
    static let knowledgeReviewMinSize = CGSize(width: 1080, height: 650)
}

public struct OpenOatsRootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var settings: AppSettings
    @State private var coordinator: AppCoordinator
    @State private var container: AppContainer
    @State private var whatsNewController: WhatsNewController
    @State private var knowledgePackStore: KnowledgePackStore
    // Lazy, like MiniBarManager/OverlayManager's panels: constructing the
    // controller builds a real window-server-backed NSWindow, and its
    // hosted SwiftUI view's .task (corpus bookmark resolve + a possibly
    // multi-MB disk read) fires as soon as that content is installed —
    // building this eagerly at launch would run that on every launch for
    // every user, whether or not they ever open the whiteboard. Created on
    // first "Whiteboard" invocation (`showWhiteboardWindow()`), reused
    // thereafter. Share protection (sharingType = .none) is still set
    // unconditionally in the controller's own init, so it is in place
    // before this window is ever shown — see that type's doc comment.
    @State private var whiteboardWindowController: SidecastWhiteboardWindowController?
    private let updaterController: AppUpdaterController
    private let defaults: UserDefaults

    public init() {
        self.init(profileRegistry: .empty)
    }

    public init(profileRegistry: KnowledgeDomainProfileRegistry) {
        let context = AppContainer.bootstrap()
        self._settings = State(initialValue: context.settings)
        self._coordinator = State(initialValue: context.coordinator)
        self._container = State(initialValue: context.container)
        self._whatsNewController = State(initialValue: WhatsNewController(defaults: context.container.defaults))
        self._knowledgePackStore = State(
            initialValue: KnowledgePackStore(
                profileRegistry: profileRegistry,
                networkMode: context.settings.knowledgeNetworkMode
            )
        )
        self.updaterController = context.updaterController
        self.defaults = context.container.defaults
        AppLaunchBootstrap.context = .init(
            settings: context.settings,
            coordinator: context.coordinator,
            container: context.container,
            defaults: context.container.defaults
        )
        DiagnosticsSupport.record(category: "app", message: "App initialized")
    }

    public var body: some Scene {
        Window("OpenOats", id: "main") {
            ContentView(settings: settings)
                .environment(container)
                .environment(coordinator)
                .environment(knowledgePackStore)
                .defaultAppStorage(defaults)
                .onAppear {
                    appDelegate.configure(
                        coordinator: coordinator,
                        settings: settings,
                        defaults: defaults,
                        container: container,
                        showMainWindow: { [self] in showMainWindow() },
                        checkForUpdates: { updaterController.checkForUpdatesFromMenuBar() }
                    )
                    DiagnosticsSupport.record(category: "app", message: "Main window appeared")
                    settings.applyScreenShareVisibility()
                }
                // WB-4: auto-open the whiteboard window when a session goes
                // live, through the exact same lazy path the "Whiteboard"
                // menu command uses (showWhiteboardWindow(), below) — a
                // window that's already open just gets reordered front, not
                // duplicated. Gated on the flag here too: with it off this
                // is a no-op, matching SidecastWhiteboardCoordinator staying
                // inert for the session itself.
                .onChange(of: coordinator.isRecording, initial: false) { wasRecording, isRecording in
                    guard isRecording, !wasRecording, settings.sidecastWhiteboardEnabled else { return }
                    showWhiteboardWindow()
                }
                .task {
                    await whatsNewController.presentPostUpdateReleaseNotesIfNeeded()
                }
                .task(id: settings.knowledgePackFolderPath) {
                    await knowledgePackStore.load(fromPath: settings.knowledgePackFolderPath)
                }
                .onChange(of: settings.knowledgeNetworkMode, initial: true) { _, mode in
                    knowledgePackStore.setNetworkMode(mode)
                }
                .onOpenURL { url in
                    guard let command = OpenOatsDeepLink.parse(url) else { return }
                    // Restore visibility when app is in background mode (LSUIElement)
                    if NSApp.activationPolicy() == .accessory {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    switch command {
                    case .openNotes(let sessionID):
                        coordinator.queueSessionSelection(sessionID)
                        openNotesWindow()
                    default:
                        coordinator.queueExternalCommand(command)
                    }
                }
                .sheet(
                    item: Binding(
                        get: { whatsNewController.presentedRelease },
                        set: { release in
                            if release == nil {
                                whatsNewController.markPresentedReleaseSeen()
                            }
                        }
                    )
                ) { release in
                    WhatsNewView(release: release) {
                        whatsNewController.markPresentedReleaseSeen()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: OpenOatsWindowSizing.mainWindowCollapsedMinSize.width,
            height: OpenOatsWindowSizing.mainWindowCollapsedMinSize.height
        )
        .commands {
            CommandGroup(after: .appInfo) {
                if case .live = container.mode {
                    CheckForUpdatesView(updater: updaterController.updater)

                    Divider()
                }

                Button("Toggle Meeting") {
                    appDelegate.toggleMeeting()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Notes Workspace") {
                    openNotesWindow()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Knowledge Review") {
                    openKnowledgeReviewWindow()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Whiteboard") {
                    showWhiteboardWindow()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Import Meeting Recording...") {
                    importMeetingRecording()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(coordinator.isRecording || isBatchEngineBusy)

                Button("GitHub Repository...") {
                    if let url = URL(string: "https://github.com/yazinsai/OpenOats") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Window("Notes Workspace", id: "notes") {
            NotesView(settings: settings)
                .environment(container)
                .environment(coordinator)
                .environment(knowledgePackStore)
                .defaultAppStorage(defaults)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: OpenOatsWindowSizing.notesWorkspaceMinSize.width,
            height: OpenOatsWindowSizing.notesWorkspaceMinSize.height
        )

        Window("Transcript", id: "transcript") {
            TranscriptWindowView()
                .environment(container)
                .environment(coordinator)
                .environment(knowledgePackStore)
                .environment(coordinator.transcriptStore)
                .defaultAppStorage(defaults)
        }
        .defaultSize(width: 600, height: 700)

        Window("Knowledge Review", id: "knowledge-review") {
            KnowledgeStudyReviewWorkspaceView()
                .environment(container)
                .environment(coordinator)
                .environment(knowledgePackStore)
                .defaultAppStorage(defaults)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: OpenOatsWindowSizing.knowledgeReviewMinSize.width,
            height: OpenOatsWindowSizing.knowledgeReviewMinSize.height
        )

        Settings {
            SettingsView(settings: settings, updater: updaterController.updater)
                .environment(container)
                .environment(coordinator)
                .environment(knowledgePackStore)
                .defaultAppStorage(defaults)
        }
    }
}

extension OpenOatsRootApp {
    static let mainWindowID = "main"

    private func openNotesWindow() {
        openWindow(id: "notes")
        bringWindowToFront(id: "notes", title: "Notes Workspace")
    }

    private func openKnowledgeReviewWindow() {
        openWindow(id: "knowledge-review")
        bringWindowToFront(id: "knowledge-review", title: "Knowledge Review")
    }

    /// Builds the whiteboard's window controller on first use and reuses it
    /// thereafter — construction and `show()` always happen back to back,
    /// right here, so the window (and the corpus bookmark resolve its
    /// hosted view triggers once shown) never comes into being before the
    /// user actually asks for it.
    ///
    /// `ensureViewServicesInitialized` runs first (idempotent, matching
    /// `startSession`'s own call — cheap and side-effect-free until a
    /// session actually feeds it) so `coordinator.sidecastWhiteboardCoordinator`
    /// exists even if this is reached before any session ever started (the
    /// menu command works that way today). The window is then built to
    /// share that coordinator's `model`/`corpusService` rather than the
    /// controller's own parameterless defaults — without this, a session's
    /// answers would land on a view-model this window was never showing,
    /// and the corpus this window's picker loads would be invisible to the
    /// orchestrator's retrieval. Falls back to fresh instances only in the
    /// unreachable case where services somehow still aren't set.
    private func showWhiteboardWindow() {
        container.ensureViewServicesInitialized(settings: settings, coordinator: coordinator)
        let controller = whiteboardWindowController ?? SidecastWhiteboardWindowController(
            model: coordinator.sidecastWhiteboardCoordinator?.model ?? SidecastWhiteboardModel(),
            corpusService: coordinator.sidecastWhiteboardCoordinator?.corpusService ?? SidecastCorpusService(),
            // WB-5/I6: Clear must also discard the coordinator's
            // orchestrator queue/in-flight work, not just the board — see
            // `SidecastWhiteboardCoordinator.clear()`.
            onClear: { coordinator.sidecastWhiteboardCoordinator?.clear() }
        )
        whiteboardWindowController = controller
        controller.show()
    }

    private func bringWindowToFront(id: String, title: String) {
        DispatchQueue.main.async {
            Self.focusWindow(id: id, title: title)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Self.focusWindow(id: id, title: title)
        }
    }

    private static func focusWindow(id: String, title: String) {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == id || $0.title == title
        }) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var isBatchEngineBusy: Bool {
        switch coordinator.batchStatus {
        case .idle, .completed, .failed, .cancelled: return false
        default: return true
        }
    }

    private func importMeetingRecording() {
        let panel = NSOpenPanel()
        panel.title = "Import Meeting Recording"
        panel.allowedContentTypes = [
            .audio,
            .init(filenameExtension: "m4a")!,
            .init(filenameExtension: "mp3")!,
            .init(filenameExtension: "wav")!,
            .init(filenameExtension: "caf")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        container.ensureRecordingServicesInitialized(settings: settings, coordinator: coordinator)
        guard let batchAudioTranscriber = coordinator.batchAudioTranscriber else { return }

        let model = settings.transcriptionModel
        let locale = settings.locale
        let customVocabulary = settings.transcriptionCustomVocabulary
        let apiKey = settings.cloudASRApiKey
        let removeFillerWords = settings.removeFillerWords
        let repo = coordinator.sessionRepository

        // Derive start date and duration from file
        let fm = FileManager.default
        let startDate: Date
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let creation = attrs[.creationDate] as? Date {
            startDate = creation
        } else {
            startDate = Date()
        }

        // Estimate duration from audio file for endedAt
        var estimatedEnd = startDate
        if let audioFile = try? AVAudioFile(forReading: fileURL) {
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            estimatedEnd = startDate.addingTimeInterval(duration)
        }

        let title = fileURL.deletingPathExtension().lastPathComponent

        Task {
            let sessionID = await repo.createImportedSession(
                config: .init(
                    title: title,
                    startedAt: startDate,
                    endedAt: estimatedEnd,
                    language: settings.transcriptionLocale,
                    engine: model.rawValue
                )
            )

            await batchAudioTranscriber.importFile(
                url: fileURL,
                sessionID: sessionID,
                model: model,
                locale: locale,
                customVocabulary: customVocabulary,
                apiKey: apiKey,
                removeFillerWords: removeFillerWords,
                sessionRepository: repo
            )

            // Check result
            let status = await batchAudioTranscriber.status
            if case .completed = status {
                await coordinator.loadHistory()
                coordinator.queueHomeSessionSelection(sessionID)
                showMainWindow()
            } else if case .failed = status {
                // Clean up the orphaned session
                await repo.deleteSession(sessionID: sessionID)
                await coordinator.loadHistory()
            } else if case .cancelled = status {
                await repo.deleteSession(sessionID: sessionID)
                await coordinator.loadHistory()
            }
        }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == Self.mainWindowID }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: Self.mainWindowID)
        }
    }
}

extension Notification.Name {
    static let toggleSuggestionPanel = Notification.Name("toggleSuggestionPanel")
    static let knowledgeOverlayCommand = Notification.Name("knowledgeOverlayCommand")
}

@MainActor
private enum AppLaunchBootstrap {
    struct Context {
        let settings: AppSettings
        let coordinator: AppCoordinator
        let container: AppContainer
        let defaults: UserDefaults
    }

    static var context: Context?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windowObserver: Any?
    private var menuBarController: MenuBarController?
    private var isTerminating = false
    var coordinator: AppCoordinator?
    var settings: AppSettings?
    var container: AppContainer?
    var defaults: UserDefaults = .standard
    var showMainWindowAction: (() -> Void)?
    var checkForUpdatesAction: (() -> Void)?

    func configure(
        coordinator: AppCoordinator,
        settings: AppSettings,
        defaults: UserDefaults,
        container: AppContainer,
        showMainWindow: (() -> Void)? = nil,
        checkForUpdates: (() -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.defaults = defaults
        self.container = container
        if let showMainWindow {
            showMainWindowAction = showMainWindow
            // Post-review fix: AppCoordinator.startDetectionEventLoop's
            // consent guard needs the same window-surfacing recovery the
            // other two consent fixes use, and has no reverse reference to
            // this delegate (or the app scene) to reach it any other way.
            coordinator.showMainWindowAction = showMainWindow
        }
        if let checkForUpdates {
            checkForUpdatesAction = checkForUpdates
        }
        if case .live = container.mode {
            DiagnosticsSupport.record(
                category: "menu",
                message: "Configuring menu bar controller from app delegate activationPolicy=\(activationPolicyDescription())"
            )
            setupMenuBarIfNeeded(coordinator: coordinator, settings: settings)
        }
    }

    func setupMenuBarIfNeeded(coordinator: AppCoordinator, settings: AppSettings) {
        if let menuBarController {
            menuBarController.refreshStatusItem()
            return
        }

        let controller = MenuBarController(
            coordinator: coordinator,
            settings: settings,
            onCheckForUpdates: { [weak self] in
                self?.checkForUpdatesAction?()
            },
            onToggleMeeting: { [weak self] in
                self?.toggleMeeting()
            }
        )
        controller.onShowMainWindow = { [weak self] in
            if let action = self?.showMainWindowAction {
                action()
            } else {
                self?.fallbackShowMainWindow()
            }
        }
        controller.onQuitApp = { [weak self] in
            self?.handleQuit()
        }
        menuBarController = controller
        DiagnosticsSupport.record(
            category: "menu",
            message: "Menu bar controller created activationPolicy=\(activationPolicyDescription())"
        )
    }

    private var isUITest: Bool {
        ProcessInfo.processInfo.environment["OPENOATS_UI_TEST"] != nil
    }

    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !isUITest {
            NSApp.setActivationPolicy(.regular)
        }

        if let context = AppLaunchBootstrap.context {
            DiagnosticsSupport.record(
                category: "menu",
                message: "Consuming launch bootstrap activationPolicy=\(activationPolicyDescription())"
            )
            configure(
                coordinator: context.coordinator,
                settings: context.settings,
                defaults: context.defaults,
                container: context.container
            )
            AppLaunchBootstrap.context = nil
        }

        let hidden = defaults.object(forKey: "hideFromScreenShare") == nil
            ? true
            : defaults.bool(forKey: "hideFromScreenShare")
        let sharingType: NSWindow.SharingType = hidden ? .none : .readOnly

        for window in NSApp.windows {
            window.sharingType = sharingType
        }

        if !isUITest {
            for window in NSApp.windows where window.identifier?.rawValue == OpenOatsRootApp.mainWindowID {
                window.delegate = self
            }
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let hide = self.defaults.object(forKey: "hideFromScreenShare") == nil
                    ? true
                    : self.defaults.bool(forKey: "hideFromScreenShare")
                let type: NSWindow.SharingType = hide ? .none : .readOnly
                for window in NSApp.windows {
                    window.sharingType = type
                }
            }
        }

        registerGlobalHotkey()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DiagnosticsSupport.record(
            category: "menu",
            message: "Application became active activationPolicy=\(activationPolicyDescription())"
        )
        if let coordinator, let settings, let container, case .live = container.mode {
            setupMenuBarIfNeeded(coordinator: coordinator, settings: settings)
        } else {
            menuBarController?.refreshStatusItem()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }

        if isTerminating {
            return .terminateNow
        }

        guard coordinator.isRecording else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Recording in Progress"
        alert.informativeText = "Stop recording and quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop & Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        isTerminating = true
        coordinator.handle(.userStopped, settings: settings)

        Task { @MainActor [weak self] in
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if case .idle = coordinator.state { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            self?.isTerminating = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        isUITest
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isUITest else { return true }

        let isMainWindow = sender.identifier?.rawValue == OpenOatsRootApp.mainWindowID

        if isMainWindow {
            sender.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            showBackgroundModeHintIfNeeded()
            return false
        }
        return true
    }

    // MARK: - One-Shot Background Notification

    private func showBackgroundModeHintIfNeeded() {
        guard !defaults.bool(forKey: "hasShownBackgroundModeHint") else { return }
        guard settings?.meetingAutoDetectEnabled == true else { return }
        // UNUserNotificationCenter asserts when there's no bundle identifier
        // (e.g. when built and run via `swift run`).
        guard Bundle.main.bundleIdentifier != nil else { return }

        defaults.set(true, forKey: "hasShownBackgroundModeHint")

        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert])
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = "OpenOats is still running"
            content.body = "Meeting detection is active. Click the menu bar icon to access controls."

            let request = UNNotificationRequest(
                identifier: "background-mode-hint",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func fallbackShowMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == OpenOatsRootApp.mainWindowID }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func activationPolicyDescription() -> String {
        switch NSApp.activationPolicy() {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }

    // MARK: - Global Hotkey (Cmd+Shift+L)

    private func registerGlobalHotkey() {
        let matchesMeetingHotkey: (NSEvent) -> Bool = { event in
            event.modifierFlags.contains([.command, .shift])
                && event.charactersIgnoringModifiers?.lowercased() == "l"
        }

        let matchesPanelHotkey: (NSEvent) -> Bool = { event in
            event.modifierFlags.contains([.command, .shift])
                && event.charactersIgnoringModifiers?.lowercased() == "o"
        }

        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if matchesMeetingHotkey(event) {
                Task { @MainActor in self?.toggleMeeting() }
            } else if matchesPanelHotkey(event) {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .toggleSuggestionPanel, object: nil)
                }
            }
        }

        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if matchesMeetingHotkey(event) {
                Task { @MainActor in self?.toggleMeeting() }
                return nil
            } else if matchesPanelHotkey(event) {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .toggleSuggestionPanel, object: nil)
                }
                return nil
            }
            return event
        }
    }

    func toggleMeeting() {
        guard let coordinator, let settings else { return }
        guard settings.hasAcknowledgedRecordingConsent else { return }

        container?.ensureMeetingServicesInitialized(settings: settings, coordinator: coordinator)

        if coordinator.isRecording {
            coordinator.handle(.userStopped, settings: settings)
        } else {
            let calEvent = settings.calendarIntegrationEnabled
                ? container?.calendarManager?.currentEvent(
                    excludingCalendarIDs: settings.excludedCalendarIDs
                )
                : nil
            coordinator.handle(.userStarted(.manual(calendarEvent: calEvent)), settings: settings)
        }
    }

    // MARK: - Quit

    private func handleQuit() {
        NSApp.terminate(nil)
    }
}
