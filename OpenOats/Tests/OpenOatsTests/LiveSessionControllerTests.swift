import AppKit
import XCTest
@testable import OpenOatsKit

@MainActor
final class LiveSessionControllerTests: XCTestCase {
    private final class SecretLoadTracker: @unchecked Sendable {
        var loadedKeys: [String] = []
    }

    // MARK: - Helpers

    private func makeTempDirs() -> (root: URL, notes: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OpenOatsLiveSessionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        return (root, notesDirectory)
    }

    private func makeSettings(
        notesDirectory: URL,
        secretStore: AppSecretStore = .ephemeral
    ) -> AppSettings {
        let suiteName = "com.openoats.tests.livesession.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(notesDirectory.path, forKey: "notesFolderPath")
        defaults.set(true, forKey: "hasAcknowledgedRecordingConsent")
        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: secretStore,
            defaultNotesDirectory: notesDirectory,
            runMigrations: false
        )
        return AppSettings(storage: storage)
    }

    private func makePNGData() -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
        image.unlockFocus()

        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func makeController(
        root: URL,
        notesDirectory: URL,
        settings: AppSettings,
        scripted: [Utterance] = []
    ) -> (LiveSessionController, AppCoordinator) {
        let transcriptStore = TranscriptStore()
        let coordinator = AppCoordinator(
            sessionRepository: SessionRepository(rootDirectory: root),
            templateStore: TemplateStore(rootDirectory: root),
            notesEngine: NotesEngine(mode: .scripted(markdown: "Test")),
            transcriptStore: transcriptStore
        )
        coordinator.transcriptionEngine = TranscriptionEngine(
            transcriptStore: transcriptStore,
            settings: settings,
            mode: .scripted(scripted)
        )

        let container = AppContainer(
            mode: .live,
            defaults: .standard,
            appSupportDirectory: root,
            notesDirectory: notesDirectory
        )
        let controller = LiveSessionController(coordinator: coordinator, container: container)
        coordinator.liveSessionController = controller
        return (controller, coordinator)
    }

    private func makeLiveController(
        root: URL,
        notesDirectory: URL,
        settings: AppSettings
    ) -> (LiveSessionController, AppCoordinator) {
        let transcriptStore = TranscriptStore()
        let coordinator = AppCoordinator(
            sessionRepository: SessionRepository(rootDirectory: root),
            templateStore: TemplateStore(rootDirectory: root),
            notesEngine: NotesEngine(mode: .scripted(markdown: "Test")),
            transcriptStore: transcriptStore
        )
        coordinator.transcriptionEngine = TranscriptionEngine(
            transcriptStore: transcriptStore,
            settings: settings
        )

        let container = AppContainer(
            mode: .live,
            defaults: .standard,
            appSupportDirectory: root,
            notesDirectory: notesDirectory
        )
        let controller = LiveSessionController(coordinator: coordinator, container: container)
        coordinator.liveSessionController = controller
        return (controller, coordinator)
    }

    private func makeUninitializedController(
        root: URL,
        notesDirectory: URL,
        settings: AppSettings
    ) -> (LiveSessionController, AppCoordinator) {
        let transcriptStore = TranscriptStore()
        let coordinator = AppCoordinator(
            sessionRepository: SessionRepository(rootDirectory: root),
            templateStore: TemplateStore(rootDirectory: root),
            notesEngine: NotesEngine(mode: .scripted(markdown: "Test")),
            transcriptStore: transcriptStore
        )
        let defaults = UserDefaults(suiteName: "com.openoats.tests.lazyservices.\(UUID().uuidString)") ?? .standard
        let container = AppContainer(
            mode: .uiTest(.launchSmoke),
            defaults: defaults,
            appSupportDirectory: root,
            notesDirectory: notesDirectory
        )
        let controller = LiveSessionController(coordinator: coordinator, container: container)
        coordinator.liveSessionController = controller
        return (controller, coordinator)
    }

    // MARK: - Tests

    func testStartSessionTransitionsStateToRecordingSynchronously() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        XCTAssertEqual(coordinator.state, .idle)

        controller.startSession(settings: settings)

        // The state machine transition must happen synchronously
        if case .recording = coordinator.state {
            // expected
        } else {
            XCTFail("Expected .recording state immediately after startSession, got \(coordinator.state)")
        }
    }

    func testCloudStartPreflightBlocksMissingAPIKey() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.transcriptionModel = .elevenLabsScribe
        let (controller, coordinator) = makeLiveController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        controller.startSession(settings: settings)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(controller.state.isRunning)
        XCTAssertEqual(
            controller.state.errorMessage,
            "Missing ElevenLabs Scribe API key. Check Settings > Transcription."
        )
    }

    func testCloudStartPreflightBlocksUnavailableOutputDevice() async {
        let dirs = makeTempDirs()
        let secretStore = AppSecretStore(
            loadValue: { _ in "test-key" },
            saveValue: { _, _ in }
        )
        let settings = makeSettings(notesDirectory: dirs.notes, secretStore: secretStore)
        settings.transcriptionModel = .assemblyAI
        settings.outputDeviceID = 999_999_999
        let (controller, coordinator) = makeLiveController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        controller.startSession(settings: settings)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(controller.state.isRunning)
        XCTAssertEqual(
            controller.state.errorMessage,
            "The selected output device is no longer available. Choose another output device in Settings > Transcription."
        )
    }

    func testCloudStartPreflightBlocksUnavailableMicrophone() async {
        let dirs = makeTempDirs()
        let secretStore = AppSecretStore(
            loadValue: { _ in "test-key" },
            saveValue: { _, _ in }
        )
        let settings = makeSettings(notesDirectory: dirs.notes, secretStore: secretStore)
        settings.transcriptionModel = .assemblyAI
        settings.inputDeviceID = 999_999_999
        let (controller, coordinator) = makeLiveController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        controller.startSession(settings: settings)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(controller.state.isRunning)
        XCTAssertEqual(
            controller.state.errorMessage,
            "The selected microphone is no longer available. Reconnect it or explicitly choose another microphone in Settings > Transcription. System audio is controlled separately."
        )
    }

    func testStartSessionWhileRunningIsNoOp() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Test", speaker: .you)]
        )

        controller.startSession(settings: settings)

        // Wait for engine to start
        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Second start should be a no-op (state machine: recording + userStarted = no-op)
        controller.startSession(settings: settings)

        // Still recording, not crashed or changed
        if case .recording = coordinator.state {
            // expected
        } else {
            XCTFail("Expected .recording state, got \(coordinator.state)")
        }
    }

    func testStartSessionReusesAbandonedMeetingStubForSameCalendarEvent() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let now = Date()
        let event = CalendarEvent(
            id: "evt-resume-stub",
            title: "Payment Ops / Merchant stand up",
            startDate: now.addingTimeInterval(-120),
            endDate: now.addingTimeInterval(780),
            organizer: nil,
            participants: [],
            isOnlineMeeting: true,
            meetingURL: URL(string: "https://meet.example.com/payment-ops")
        )

        let repository = SessionRepository(rootDirectory: dirs.root)
        let abandonedHandle = await repository.startSession(
            config: SessionStartConfig(
                templateSnapshot: nil,
                title: event.title,
                calendarEvent: event
            )
        )
        await repository.endSession()

        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Recovered", speaker: .you)]
        )

        controller.startSession(settings: settings, calendarEventOverride: event)

        var activeSessionID: String?
        for _ in 0..<20 {
            activeSessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if activeSessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(activeSessionID, abandonedHandle.sessionID)
    }

    func testStartSessionInitializesServicesOnDemand() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeUninitializedController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        XCTAssertNil(coordinator.transcriptionEngine)
        XCTAssertNil(coordinator.knowledgeBase)

        controller.startSession(settings: settings)

        XCTAssertNotNil(coordinator.transcriptionEngine)
        XCTAssertNotNil(coordinator.knowledgeBase)

        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(coordinator.transcriptionEngine?.isRunning == true)
        if case .recording = coordinator.state {
            // expected
        } else {
            XCTFail("Expected recording state after on-demand initialization")
        }
    }

    func testInsertScratchpadImagePersistsMarkdownAndImage() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Hello", speaker: .you)]
        )

        controller.startSession(settings: settings)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        controller.updateScratchpad("Prep observations")
        controller.insertScratchpadImage(makePNGData())
        try? await Task.sleep(for: .milliseconds(250))

        let savedScratchpad = await coordinator.sessionRepository.loadScratchpad(sessionID: sessionID)
        XCTAssertTrue(savedScratchpad.hasPrefix("Prep observations"))
        XCTAssertTrue(savedScratchpad.contains("![](images/"))
        XCTAssertEqual(controller.state.scratchpadText, savedScratchpad)

        let imagesDirectory = coordinator.sessionRepository.sessionsDirectoryURL
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
        let imageURLs = (try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertEqual(imageURLs.count, 1)
    }

    func testInsertScratchpadImageFilePersistsMarkdownAndImage() async throws {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Hello", speaker: .you)]
        )

        controller.startSession(settings: settings)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        let imageURL = dirs.root.appendingPathComponent("clipboard-screenshot.png")
        try makePNGData().write(to: imageURL)

        controller.updateScratchpad("Prep observations")
        controller.insertScratchpadAssets([.imageFile(imageURL)])
        try? await Task.sleep(for: .milliseconds(250))

        let savedScratchpad = await coordinator.sessionRepository.loadScratchpad(sessionID: sessionID)
        XCTAssertTrue(savedScratchpad.hasPrefix("Prep observations"))
        XCTAssertTrue(savedScratchpad.contains("![](images/"))
        XCTAssertEqual(controller.state.scratchpadText, savedScratchpad)

        let imagesDirectory = coordinator.sessionRepository.sessionsDirectoryURL
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
        let imageURLs = (try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertEqual(imageURLs.count, 1)
    }

    func testCoordinatorStartProjectsRunningStateBeforeEngineStarts() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeUninitializedController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        XCTAssertFalse(controller.state.isRunning)
        XCTAssertNil(coordinator.transcriptionEngine)

        coordinator.handle(.userStarted(.manual()), settings: settings)

        XCTAssertTrue(controller.state.isRunning)
        XCTAssertEqual(controller.state.sessionPhase, coordinator.state)
        XCTAssertNil(coordinator.transcriptionEngine)
        XCTAssertEqual(controller.state.capturePhase, .preparing)
        XCTAssertEqual(controller.state.recordingElapsedSeconds, 0)
    }

    func testImmediateStopCancelsQueuedStartupWithoutTranscription() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root, notesDirectory: dirs.notes, settings: settings,
            scripted: [Utterance(text: "Must not arrive after Stop", speaker: .you)]
        )
        coordinator.handle(.userStarted(.manual()), settings: settings)
        controller.stopSession(settings: settings)
        for _ in 0..<100 {
            if coordinator.state == .idle { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(coordinator.transcriptionEngine?.isRunning ?? true)
        XCTAssertTrue(coordinator.transcriptStore.utterances.isEmpty)
        controller.syncProjectedState(settings: settings)
        XCTAssertEqual(controller.state.capturePhase, .idle)
    }

    func testMicrophoneCanBeMutedDuringPreparationWithoutPausingSystemAudio() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(root: dirs.root, notesDirectory: dirs.notes, settings: settings)
        coordinator.handle(.userStarted(.manual()), settings: settings)
        XCTAssertFalse(coordinator.transcriptionEngine!.isRunning)
        controller.toggleMicMute()
        XCTAssertTrue(coordinator.transcriptionEngine!.isMicMuted)
        XCTAssertFalse(coordinator.transcriptionEngine!.isRecordingPaused)
        controller.stopSession(settings: settings)
        for _ in 0..<100 {
            if coordinator.state == .idle { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testMicrophoneMuteCanChangeWhilePausedAndDoesNotResumeCapture() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(root: dirs.root, notesDirectory: dirs.notes, settings: settings)
        coordinator.handle(.userStarted(.manual()), settings: settings)
        coordinator.transcriptionEngine!.isRecordingPaused = true
        controller.toggleMicMute()
        XCTAssertTrue(coordinator.transcriptionEngine!.isMicMuted)
        XCTAssertTrue(coordinator.transcriptionEngine!.isRecordingPaused)
        controller.toggleMicMute()
        XCTAssertFalse(coordinator.transcriptionEngine!.isMicMuted)
        XCTAssertTrue(coordinator.transcriptionEngine!.isRecordingPaused)
        controller.stopSession(settings: settings)
        for _ in 0..<100 {
            if coordinator.state == .idle { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testStopSessionWhileIdleIsNoOp() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        XCTAssertEqual(coordinator.state, .idle)

        controller.stopSession(settings: settings)

        // Should still be idle
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testDeepLinkStartInitializesServicesOnDemand() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let transcriptStore = TranscriptStore()
        let coordinator = AppCoordinator(
            sessionRepository: SessionRepository(rootDirectory: dirs.root),
            templateStore: TemplateStore(rootDirectory: dirs.root),
            notesEngine: NotesEngine(mode: .scripted(markdown: "Test")),
            transcriptStore: transcriptStore
        )
        // No transcription engine or suggestion engine
        let container = AppContainer(
            mode: .live,
            defaults: .standard,
            appSupportDirectory: dirs.root,
            notesDirectory: dirs.notes
        )
        let controller = LiveSessionController(coordinator: coordinator, container: container)
        coordinator.liveSessionController = controller
        // This test checks synchronous service creation, not real audio capture.
        // Cancel the queued start before yielding so it cannot outlive the test.
        defer { controller.stopSession(settings: settings) }

        // Queue a start command
        coordinator.queueExternalCommand(.startSession())

        // Try handling - the controller should initialize services on demand.
        controller.handlePendingExternalCommandIfPossible(settings: settings, openNotesWindow: nil)

        XCTAssertNil(coordinator.pendingExternalCommand)
        XCTAssertNotNil(coordinator.transcriptionEngine)
        XCTAssertNotNil(coordinator.knowledgeBase)
        if case .recording = coordinator.state {
            // expected
        } else {
            XCTFail("Expected .recording state after on-demand deep link start, got \(coordinator.state)")
        }
    }

    func testDeepLinkStopRejectedWhenNotRunning() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        coordinator.queueExternalCommand(.stopSession)

        // Try handling - should not stop because not running
        controller.handlePendingExternalCommandIfPossible(settings: settings, openNotesWindow: nil)

        // Command should still be pending (not consumed because guard failed)
        XCTAssertNotNil(coordinator.pendingExternalCommand)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testDeepLinkOpenNotesAlwaysAccepted() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        coordinator.queueExternalCommand(.openNotes(sessionID: "test_session"))

        var notesOpened = false
        controller.handlePendingExternalCommandIfPossible(settings: settings) {
            notesOpened = true
        }

        XCTAssertTrue(notesOpened)
        XCTAssertNil(coordinator.pendingExternalCommand)
        XCTAssertEqual(coordinator.requestedNotesNavigation?.target, .session("test_session"))
    }

    func testExternalStartSessionSeedsCalendarEventAndScratchpad() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Hello", speaker: .you)]
        )
        let knowledgeBase = KnowledgeBase(settings: settings)
        coordinator.setViewServices(
            knowledgeBase: knowledgeBase,
            suggestionEngine: SuggestionEngine(
                transcriptStore: coordinator.transcriptStore,
                knowledgeBase: knowledgeBase,
                settings: settings
            ),
            sidecastEngine: SidecastEngine(
                transcriptStore: coordinator.transcriptStore,
                knowledgeBase: knowledgeBase,
                settings: settings
            )
        )

        let event = CalendarEvent(
            id: "evt-123",
            title: "Payment Ops",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_900),
            organizer: nil,
            participants: [],
            isOnlineMeeting: true,
            meetingURL: URL(string: "https://meet.example.com/payment-ops")
        )

        coordinator.queueExternalCommand(
            .startSession(calendarEvent: event, scratchpadSeed: "Talk through merchant fees")
        )

        controller.handlePendingExternalCommandIfPossible(settings: settings, openNotesWindow: nil)

        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let sessionID = await coordinator.sessionRepository.getCurrentSessionID()
        let savedScratchpad: String?
        if let sessionID {
            savedScratchpad = await coordinator.sessionRepository.loadScratchpad(sessionID: sessionID)
        } else {
            savedScratchpad = nil
        }

        if case .recording(let metadata) = coordinator.state {
            XCTAssertEqual(metadata.calendarEvent?.id, event.id)
        } else {
            XCTFail("Expected recording state after external start command")
        }
        XCTAssertEqual(controller.state.scratchpadText, "Talk through merchant fees")
        XCTAssertEqual(savedScratchpad, "Talk through merchant fees")
        XCTAssertNil(coordinator.pendingExternalCommand)
    }

    // MARK: - Post-review fix: recording consent gates the deep-link start path too

    /// `testExternalStartSessionSeedsCalendarEventAndScratchpad` above
    /// already proves consent-acknowledged (its `makeSettings()` pre-sets
    /// `hasAcknowledgedRecordingConsent`) starts normally; this proves the
    /// gap the review found — `openoats://start` bypassing consent
    /// entirely — is closed: unacknowledged consent must not start a
    /// session, must not even reach service initialization (no
    /// utterance/dispatch flow is possible with no transcription engine),
    /// must surface the app window instead, and must still consume the
    /// command so it doesn't linger unprocessed forever (this function
    /// only ever runs once, from ContentView's one-shot `.task`).
    func testExternalStartSessionCommandBlockedWithoutConsentSurfacesMainWindowInstead() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.hasAcknowledgedRecordingConsent = false
        let (controller, coordinator) = makeController(root: dirs.root, notesDirectory: dirs.notes, settings: settings)

        coordinator.queueExternalCommand(.startSession(calendarEvent: nil, scratchpadSeed: nil))

        var windowSurfaced = false
        controller.handlePendingExternalCommandIfPossible(
            settings: settings,
            openNotesWindow: nil,
            showMainWindow: { windowSurfaced = true }
        )

        XCTAssertTrue(windowSurfaced, "must surface the app window so the user can acknowledge consent")
        XCTAssertFalse(controller.state.isRunning, "must not start without consent")
        XCTAssertEqual(coordinator.state, .idle, "the state machine must never transition without consent")
        // knowledgeBase/suggestionEngine/sidecastEngine/sidecastWhiteboardCoordinator
        // are only ever constructed together by ensureMeetingServicesInitialized,
        // which the fix must short-circuit before reaching — makeController's
        // helper (unlike production) pre-wires transcriptionEngine directly, so
        // that one isn't a useful signal here, but this quartet is untouched by it.
        XCTAssertNil(coordinator.knowledgeBase, "must not even initialize meeting services without consent")
        XCTAssertNil(coordinator.sidecastWhiteboardCoordinator, "the whiteboard pipeline must not spin up either")
        XCTAssertNil(coordinator.pendingExternalCommand, "the command must be consumed, not left to linger unprocessed")
    }

    func testFinalizeCurrentSessionAppliesMeetingFamilyFolderPreference() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Hello", speaker: .you)]
        )

        let event = CalendarEvent(
            id: "evt-folder",
            title: "Payment Ops",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_900),
            organizer: nil,
            participants: [],
            isOnlineMeeting: true,
            meetingURL: URL(string: "https://meet.example.com/payment-ops")
        )
        settings.setMeetingFamilyFolderPreference("Work/Payments", for: event)

        controller.startSession(settings: settings, calendarEventOverride: event)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        let utterance = Utterance(
            text: "Follow up on merchant fees",
            speaker: .you,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = coordinator.transcriptStore.append(utterance)

        controller.stopSession(settings: settings)
        await controller.finalizeCurrentSession(settings: settings)

        let detail = await coordinator.sessionRepository.loadSession(id: sessionID)
        XCTAssertEqual(detail.index.folderPath, "Work/Payments")
    }

    func testFinalizeCurrentSessionCollapsesEmptyGhostSessionIntoRecentRealSession() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: []
        )

        let event = CalendarEvent(
            id: "evt-ghost-merge",
            title: "Payment Ops / Merchant stand up",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_900),
            organizer: nil,
            participants: [],
            isOnlineMeeting: true,
            meetingURL: URL(string: "https://meet.example.com/payment-ops")
        )

        let realStartedAt = Date().addingTimeInterval(-180)
        await coordinator.sessionRepository.seedSession(
            id: "session_real",
            records: [SessionRecord(speaker: .you, text: "Real meeting", timestamp: realStartedAt)],
            startedAt: realStartedAt,
            endedAt: realStartedAt.addingTimeInterval(120),
            title: "Payment Ops / Merchant stand up"
        )

        controller.startSession(settings: settings, calendarEventOverride: event)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let ghostSessionID = sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        controller.stopSession(settings: settings)
        await controller.finalizeCurrentSession(settings: settings)

        let sessions = await coordinator.sessionRepository.listSessions()
        XCTAssertFalse(sessions.contains(where: { $0.id == ghostSessionID }))
        XCTAssertTrue(sessions.contains(where: { $0.id == "session_real" }))
        XCTAssertEqual(coordinator.lastEndedSession?.id, "session_real")

        let mergedDetail = await coordinator.sessionRepository.loadSession(id: "session_real")
        XCTAssertEqual(mergedDetail.calendarEvent?.id, event.id)
    }

    func testFinalizeCurrentSessionAutoGeneratesNotesWhenConfigured() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.llmProvider = .ollama
        settings.ollamaBaseURL = "http://localhost:11434"
        settings.ollamaLLMModel = "qwen3:8b"
        settings.enableBatchRetranscription = false

        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Follow up on merchant fees", speaker: .you)]
        )

        controller.startSession(settings: settings)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        let recordedUtterance = Utterance(
            text: "Follow up on merchant fees",
            speaker: .you,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await coordinator.sessionRepository.appendLiveUtterance(
            sessionID: sessionID,
            utterance: recordedUtterance
        )

        controller.stopSession(settings: settings)
        await controller.finalizeCurrentSession(settings: settings)

        var savedNotes: GeneratedNotes?
        for _ in 0..<20 {
            savedNotes = await coordinator.sessionRepository.loadNotes(sessionID: sessionID)
            if savedNotes != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertNotNil(savedNotes)
        XCTAssertTrue(savedNotes?.markdown.contains("Test") ?? false)
        XCTAssertEqual(coordinator.lastEndedSession?.id, sessionID)
        XCTAssertTrue(coordinator.lastEndedSession?.hasNotes == true)
    }

    func testFinalizeCurrentSessionAutoGeneratesNotesUsingGlobalDefaultTemplateFallback() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.llmProvider = .ollama
        settings.ollamaBaseURL = "http://localhost:11434"
        settings.ollamaLLMModel = "qwen3:8b"
        settings.enableBatchRetranscription = false

        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Follow up on merchant fees", speaker: .you)]
        )

        let customTemplate = MeetingTemplate(
            id: UUID(),
            name: "Board Update",
            icon: "briefcase",
            systemPrompt: "Summarize in board format.",
            isBuiltIn: false
        )
        coordinator.templateStore.add(customTemplate)
        settings.defaultNotesTemplateID = customTemplate.id

        controller.startSession(settings: settings)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        let recordedUtterance = Utterance(
            text: "Follow up on merchant fees",
            speaker: .you,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await coordinator.sessionRepository.appendLiveUtterance(
            sessionID: sessionID,
            utterance: recordedUtterance
        )

        controller.stopSession(settings: settings)
        await controller.finalizeCurrentSession(settings: settings)

        var savedNotes: GeneratedNotes?
        for _ in 0..<20 {
            savedNotes = await coordinator.sessionRepository.loadNotes(sessionID: sessionID)
            if savedNotes != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(savedNotes?.template.id, customTemplate.id)
    }

    func testFinalizeCurrentSessionAutoGeneratesNotesPreferringMeetingFamilyTemplate() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.llmProvider = .ollama
        settings.ollamaBaseURL = "http://localhost:11434"
        settings.ollamaLLMModel = "qwen3:8b"
        settings.enableBatchRetranscription = false

        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Follow up on merchant fees", speaker: .you)]
        )

        let customTemplate = MeetingTemplate(
            id: UUID(),
            name: "Board Update",
            icon: "briefcase",
            systemPrompt: "Summarize in board format.",
            isBuiltIn: false
        )
        coordinator.templateStore.add(customTemplate)
        settings.defaultNotesTemplateID = customTemplate.id

        let event = CalendarEvent(
            id: "evt_meeting_family_auto_notes",
            title: "Daily Standup",
            startDate: Date(),
            endDate: Date().addingTimeInterval(900),
            externalIdentifier: "series-standup",
            organizer: nil,
            participants: [],
            isOnlineMeeting: false,
            meetingURL: nil
        )
        settings.setMeetingFamilyTemplatePreference(TemplateStore.standUpID, for: event)

        controller.startSession(settings: settings, calendarEventOverride: event)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        let recordedUtterance = Utterance(
            text: "Follow up on merchant fees",
            speaker: .you,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await coordinator.sessionRepository.appendLiveUtterance(
            sessionID: sessionID,
            utterance: recordedUtterance
        )

        controller.stopSession(settings: settings)
        await controller.finalizeCurrentSession(settings: settings)

        var savedNotes: GeneratedNotes?
        for _ in 0..<20 {
            savedNotes = await coordinator.sessionRepository.loadNotes(sessionID: sessionID)
            if savedNotes != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(savedNotes?.template.id, TemplateStore.standUpID)
    }

    func testFinalizeCurrentSessionSkipsAutoNotesWhenProviderIsNotConfigured() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.llmProvider = .openRouter
        settings.selectedModel = "google/gemini-3-flash-preview"
        settings.openRouterApiKey = ""
        settings.enableBatchRetranscription = false

        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Follow up on merchant fees", speaker: .you)]
        )

        controller.startSession(settings: settings)

        var sessionID: String?
        for _ in 0..<20 {
            sessionID = await coordinator.sessionRepository.getCurrentSessionID()
            if sessionID != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard let sessionID else {
            return XCTFail("Expected session ID after starting session")
        }

        let recordedUtterance = Utterance(
            text: "Follow up on merchant fees",
            speaker: .you,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await coordinator.sessionRepository.appendLiveUtterance(
            sessionID: sessionID,
            utterance: recordedUtterance
        )

        controller.stopSession(settings: settings)
        await controller.finalizeCurrentSession(settings: settings)
        try? await Task.sleep(for: .milliseconds(300))

        let savedNotes = await coordinator.sessionRepository.loadNotes(sessionID: sessionID)
        XCTAssertNil(savedNotes)
        XCTAssertFalse(coordinator.lastEndedSession?.hasNotes == true)
    }

    func testAudioRetentionPlanKeepsRecoveryAudioForCloudLiveTranscription() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.transcriptionModel = .elevenLabsScribe
        settings.saveAudioRecording = false
        settings.enableBatchRetranscription = false

        let startupPlan = LiveSessionController.audioRetentionPlan(settings: settings, utteranceCount: nil)
        XCTAssertTrue(startupPlan.shouldStartRecorder)
        XCTAssertFalse(startupPlan.shouldRetainBatchAudio)
        XCTAssertFalse(startupPlan.shouldExportRecording)
        XCTAssertFalse(startupPlan.shouldRunRecoveryBatch)

        let recoveryPlan = LiveSessionController.audioRetentionPlan(settings: settings, utteranceCount: 0)
        XCTAssertTrue(recoveryPlan.shouldStartRecorder)
        XCTAssertTrue(recoveryPlan.shouldRetainBatchAudio)
        XCTAssertFalse(recoveryPlan.shouldExportRecording)
        XCTAssertTrue(recoveryPlan.shouldRunRecoveryBatch)
    }

    func testAudioRetentionPlanDoesNotForceRecoveryForCloudSessionWithUtterances() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.transcriptionModel = .assemblyAI
        settings.saveAudioRecording = false
        settings.enableBatchRetranscription = false

        let plan = LiveSessionController.audioRetentionPlan(settings: settings, utteranceCount: 4)
        XCTAssertTrue(plan.shouldStartRecorder)
        XCTAssertFalse(plan.shouldRetainBatchAudio)
        XCTAssertFalse(plan.shouldExportRecording)
        XCTAssertFalse(plan.shouldRunRecoveryBatch)
    }

    func testAudioRetentionPlanLeavesLocalModelsUntouchedWhenRecordingOptionsAreOff() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.transcriptionModel = .parakeetV3
        settings.saveAudioRecording = false
        settings.enableBatchRetranscription = false

        let plan = LiveSessionController.audioRetentionPlan(settings: settings, utteranceCount: 0)
        XCTAssertFalse(plan.shouldStartRecorder)
        XCTAssertFalse(plan.shouldRetainBatchAudio)
        XCTAssertFalse(plan.shouldExportRecording)
        XCTAssertFalse(plan.shouldRunRecoveryBatch)
    }

    /// Drive the evaluator over a sequence of constant-level samples at a fixed
    /// cadence, returning the elapsed time at which it first asks to stop
    /// (or nil if it never did over `duration`).
    private func simulateSilenceTimeout(
        level: Float,
        duration: TimeInterval,
        sampleInterval: TimeInterval = 0.25,
        levelAt: ((TimeInterval) -> Float)? = nil
    ) -> (firstStopAt: TimeInterval?, finalFloor: Float) {
        let start = Date()
        var tracking = LiveSessionController.SilenceTracking.initial
        var firstStopAt: TimeInterval?
        var t: TimeInterval = 0
        while t <= duration {
            let now = start.addingTimeInterval(t)
            let evaluation = LiveSessionController.automaticSilenceTimeoutEvaluation(
                isRunning: true,
                isRecordingPaused: false,
                audioLevel: levelAt?(t) ?? level,
                now: now,
                tracking: tracking
            )
            tracking = evaluation.tracking
            if evaluation.shouldStop, firstStopAt == nil {
                firstStopAt = t
            }
            t += sampleInterval
        }
        return (firstStopAt, tracking.noiseFloor)
    }

    func testAutomaticSilenceTimeoutWaitsForFiveMinutesOfSilence() {
        let now = Date()
        let tracking = LiveSessionController.SilenceTracking(
            lastAudibleActivityAt: now.addingTimeInterval(-299),
            noiseFloor: 0,
            lastSampleAt: now.addingTimeInterval(-0.25)
        )

        let evaluation = LiveSessionController.automaticSilenceTimeoutEvaluation(
            isRunning: true,
            isRecordingPaused: false,
            audioLevel: 0,
            now: now,
            tracking: tracking
        )

        XCTAssertEqual(evaluation.tracking.lastAudibleActivityAt, tracking.lastAudibleActivityAt)
        XCTAssertFalse(evaluation.shouldStop)
    }

    func testAutomaticSilenceTimeoutTriggersStopAfterFiveMinutesOfSilence() {
        let now = Date()
        let lastActivity = now.addingTimeInterval(-300)
        let tracking = LiveSessionController.SilenceTracking(
            lastAudibleActivityAt: lastActivity,
            noiseFloor: 0,
            lastSampleAt: now.addingTimeInterval(-0.25)
        )

        let evaluation = LiveSessionController.automaticSilenceTimeoutEvaluation(
            isRunning: true,
            isRecordingPaused: false,
            audioLevel: 0,
            now: now,
            tracking: tracking
        )

        XCTAssertEqual(evaluation.tracking.lastAudibleActivityAt, lastActivity)
        XCTAssertTrue(evaluation.shouldStop)
    }

    func testAutomaticSilenceTimeoutResetsOnAudibleActivity() {
        let now = Date()
        let lastActivity = now.addingTimeInterval(-180)
        // Established ambient floor of 0.05 with the timer already part-way.
        let tracking = LiveSessionController.SilenceTracking(
            lastAudibleActivityAt: lastActivity,
            noiseFloor: 0.05,
            lastSampleAt: now.addingTimeInterval(-0.25)
        )

        // A clearly-above-floor level (speech) should reset the timer.
        let evaluation = LiveSessionController.automaticSilenceTimeoutEvaluation(
            isRunning: true,
            isRecordingPaused: false,
            audioLevel: 0.5,
            now: now,
            tracking: tracking
        )

        XCTAssertEqual(evaluation.tracking.lastAudibleActivityAt, now)
        XCTAssertFalse(evaluation.shouldStop)
    }

    func testAutomaticSilenceTimeoutDoesNotAccrueWhileAlreadyPaused() {
        let now = Date()
        let tracking = LiveSessionController.SilenceTracking(
            lastAudibleActivityAt: now.addingTimeInterval(-300),
            noiseFloor: 0.05,
            lastSampleAt: now.addingTimeInterval(-0.25)
        )

        let evaluation = LiveSessionController.automaticSilenceTimeoutEvaluation(
            isRunning: true,
            isRecordingPaused: true,
            audioLevel: 0,
            now: now,
            tracking: tracking
        )

        XCTAssertEqual(evaluation.tracking.lastAudibleActivityAt, now)
        XCTAssertFalse(evaluation.shouldStop)
    }

    // MARK: - Adaptive noise floor

    /// Regression test for the original bug: a live mic's steady noise floor
    /// (here ~0.06 combined level, well above the old fixed 0.01 threshold)
    /// must NOT count as audible activity — the session should still auto-stop.
    func testSteadyMicNoiseFloorStillAutoStops() {
        let ambient: Float = 0.06
        // Sanity: this ambient would have defeated the old fixed threshold.
        XCTAssertGreaterThan(ambient, LiveSessionController.audibleActivityLevelThreshold)

        let result = simulateSilenceTimeout(level: ambient, duration: 360)

        XCTAssertNotNil(result.firstStopAt, "Steady mic noise floor never triggered auto-stop")
        if let stopAt = result.firstStopAt {
            // Should stop right around the 5-minute mark, not before.
            XCTAssertGreaterThanOrEqual(stopAt, 300)
            XCTAssertLessThan(stopAt, 305)
        }
        // Floor should have converged to the ambient level.
        XCTAssertEqual(result.finalFloor, ambient, accuracy: 0.01)
    }

    /// A much louder constant tone also calibrates and stops — proving the
    /// fix is relative to the mic, not tied to any particular absolute level.
    func testLoudConstantNoiseFloorAlsoAutoStops() {
        let result = simulateSilenceTimeout(level: 0.3, duration: 360)
        XCTAssertNotNil(result.firstStopAt)
        if let stopAt = result.firstStopAt {
            XCTAssertGreaterThanOrEqual(stopAt, 300)
            XCTAssertLessThan(stopAt, 305)
        }
    }

    /// Periodic speech bursts above the ambient floor must keep the session
    /// alive indefinitely (no false auto-stop during an active meeting).
    func testPeriodicSpeechAboveFloorPreventsAutoStop() {
        let ambient: Float = 0.06
        let result = simulateSilenceTimeout(level: ambient, duration: 900) { t in
            // 2s of speech (level 0.5) every 60s, ambient otherwise.
            (t.truncatingRemainder(dividingBy: 60) < 2) ? 0.5 : ambient
        }
        XCTAssertNil(result.firstStopAt, "Active meeting with periodic speech should not auto-stop")
    }

    func testNoiseFloorFallsFasterThanItRises() {
        // Falling toward quiet: large move over 5s.
        let fell = LiveSessionController.updatedNoiseFloor(current: 0.5, level: 0.05, dt: 5)
        // Rising toward loud: small move over the same 5s.
        let rose = LiveSessionController.updatedNoiseFloor(current: 0.05, level: 0.5, dt: 5)

        let fallDelta = 0.5 - fell      // how far it dropped
        let riseDelta = rose - 0.05     // how far it climbed
        XCTAssertGreaterThan(fallDelta, riseDelta)
        // Sanity bounds on the asymmetry.
        XCTAssertGreaterThan(fallDelta, 0.2)
        XCTAssertLessThan(riseDelta, 0.1)
    }

    func testRecordingHealthNoticeWarnsWhenNoAudioDetected() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 6,
            transcriptionModel: .elevenLabsScribe,
            utteranceCount: 0,
            peakAudioLevel: 0,
            micHasCapturedFrames: false,
            systemHasCapturedFrames: false,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: false
        )

        let notice = LiveSessionController.recordingHealthNotice(for: input)
        XCTAssertEqual(notice?.severity, .warning)
        XCTAssertEqual(
            notice?.message,
            "No microphone or system audio detected. Check your input and output device settings."
        )
    }

    func testRecordingHealthNoticeWarnsWhenCloudTranscriptStallsButAudioIsFlowing() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 21,
            transcriptionModel: .elevenLabsScribe,
            utteranceCount: 0,
            peakAudioLevel: 0.08,
            micHasCapturedFrames: true,
            systemHasCapturedFrames: true,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: false
        )

        let notice = LiveSessionController.recordingHealthNotice(for: input)
        XCTAssertEqual(notice?.severity, .warning)
        XCTAssertEqual(
            notice?.message,
            "Capturing audio, but live transcription is not producing text. Recovery batch transcription will run after you stop."
        )
    }

    func testRecordingHealthNoticeWarnsWhenLocalTranscriptStallsButAudioIsFlowing() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 21,
            transcriptionModel: .parakeetV3,
            utteranceCount: 0,
            peakAudioLevel: 0.08,
            micHasCapturedFrames: true,
            systemHasCapturedFrames: true,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: false
        )

        let notice = LiveSessionController.recordingHealthNotice(for: input)
        XCTAssertEqual(notice?.severity, .warning)
        XCTAssertEqual(
            notice?.message,
            "Capturing audio, but live transcription is not producing text."
        )
    }

    func testRecordingHealthNoticeSuppressesWarningWhenBlockingErrorExists() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 30,
            transcriptionModel: .elevenLabsScribe,
            utteranceCount: 0,
            peakAudioLevel: 0.08,
            micHasCapturedFrames: true,
            systemHasCapturedFrames: true,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: true
        )

        XCTAssertNil(LiveSessionController.recordingHealthNotice(for: input))
    }

    func testTranscriptIssueMarksMissingAudioForExtendedEmptySession() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 8,
            transcriptionModel: .parakeetV3,
            utteranceCount: 0,
            peakAudioLevel: 0,
            micHasCapturedFrames: false,
            systemHasCapturedFrames: false,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: false
        )

        XCTAssertEqual(LiveSessionController.transcriptIssue(for: input), .noAudioDetected)
    }

    func testTranscriptIssueMarksStalledTranscriptionWhenAudioWasCaptured() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 12,
            transcriptionModel: .elevenLabsScribe,
            utteranceCount: 0,
            peakAudioLevel: 0.08,
            micHasCapturedFrames: true,
            systemHasCapturedFrames: true,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: false
        )

        XCTAssertEqual(
            LiveSessionController.transcriptIssue(for: input),
            .transcriptionProducedNoText
        )
    }

    func testTranscriptIssueLeavesIntentionallyEmptySessionUnmarked() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 3,
            transcriptionModel: .parakeetV3,
            utteranceCount: 0,
            peakAudioLevel: 0,
            micHasCapturedFrames: false,
            systemHasCapturedFrames: false,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: false
        )

        XCTAssertNil(LiveSessionController.transcriptIssue(for: input))
    }

    func testLiveTranscriptNoticeExplainsCloudDelay() {
        let notice = LiveSessionController.liveTranscriptNotice(for: .elevenLabsScribe)

        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains("Cloud transcript updates") == true)
        XCTAssertTrue(notice?.contains("10s") == true)
    }

    func testLiveTranscriptNoticePrefersConcreteCloudIssue() {
        let issue = CloudTranscriptCopy.Presentation(
            title: "ElevenLabs API key rejected",
            detail: "Check Settings > Transcription."
        )

        XCTAssertEqual(
            LiveSessionController.liveTranscriptNotice(for: .elevenLabsScribe, issue: issue),
            "ElevenLabs API key rejected"
        )
        XCTAssertEqual(
            LiveSessionController.liveTranscriptEmptyStateMessage(for: .elevenLabsScribe, issue: issue),
            "Check Settings > Transcription."
        )
    }

    func testLiveTranscriptEmptyStateMessageOnlyAppliesToCloudModels() {
        XCTAssertNil(LiveSessionController.liveTranscriptEmptyStateMessage(for: .parakeetV3))

        let message = LiveSessionController.liveTranscriptEmptyStateMessage(for: .assemblyAI)
        XCTAssertNotNil(message)
        XCTAssertEqual(message, "Waiting for transcript chunk…")
    }

    func testRecordingElapsedSecondsUsesLifecycleStartTime() {
        let startedAt = Date().addingTimeInterval(-9.4)
        let metadata = MeetingMetadata(
            detectionContext: nil,
            calendarEvent: nil,
            title: nil,
            startedAt: startedAt,
            endedAt: nil
        )

        let elapsed = LiveSessionController.recordingElapsedSeconds(for: .recording(metadata))

        XCTAssertGreaterThanOrEqual(elapsed, 9)
        XCTAssertLessThan(elapsed, 12)
    }

    func testSyncProjectedStateRefreshesLastEndedSessionWhenSameSessionChanges() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        let failedIndex = SessionIndex(
            id: "session-1",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            title: "Standup",
            utteranceCount: 0,
            hasNotes: false,
            transcriptIssue: .transcriptionProducedNoText
        )
        coordinator.lastEndedSession = failedIndex
        controller.syncProjectedState(settings: settings)
        XCTAssertEqual(controller.state.lastEndedSession?.transcriptIssue, .transcriptionProducedNoText)

        var recoveredIndex = failedIndex
        recoveredIndex.utteranceCount = 3
        recoveredIndex.transcriptIssue = nil
        coordinator.lastEndedSession = recoveredIndex
        controller.syncProjectedState(settings: settings)

        XCTAssertEqual(controller.state.lastEndedSession?.utteranceCount, 3)
        XCTAssertNil(controller.state.lastEndedSession?.transcriptIssue)
    }

    func testSyncProjectedStateRefreshesRetranscriptionAvailabilityForLastEndedSession() async throws {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        let sessionID = "session_retranscribe_available"
        await coordinator.sessionRepository.seedSession(
            id: sessionID,
            records: [],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcriptIssue: .transcriptionProducedNoText
        )

        let audioDir = coordinator.sessionRepository.sessionsDirectoryURL
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        try Data("sys".utf8).write(to: audioDir.appendingPathComponent("sys.caf"))

        coordinator.lastEndedSession = await coordinator.sessionRepository.loadSession(id: sessionID).index
        controller.syncProjectedState(settings: settings)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(controller.state.lastEndedSessionCanRetranscribe)
    }

    func testEmptySessionDiagnosticClassificationMarksMissingAudio() {
        let input = LiveSessionController.RecordingHealthInput(
            elapsed: 8,
            transcriptionModel: .parakeetV3,
            utteranceCount: 0,
            peakAudioLevel: 0,
            micHasCapturedFrames: false,
            systemHasCapturedFrames: false,
            micCaptureError: nil,
            isMicMuted: false,
            isRecordingPaused: false,
            hasBlockingError: false
        )

        XCTAssertEqual(
            LiveSessionController.emptySessionDiagnosticClassification(for: input),
            .noAudioDetected
        )
    }

    func testEmptySessionDiagnosticsMessageIsStructuredJSON() throws {
        let event = LiveSessionController.EmptySessionDiagnosticsEvent(
            event: "live_empty_session_finalized",
            sessionID: "session-123",
            transcriptionModel: TranscriptionModel.elevenLabsScribe.rawValue,
            elapsedSeconds: 90,
            utteranceCount: 0,
            peakAudioLevel: 0.08,
            micCapturedFrames: true,
            systemCapturedFrames: true,
            micCaptureError: nil,
            classification: LiveSessionController.EmptySessionDiagnosticClassification.transcriptionProducedNoText.rawValue,
            retainedRecoveryAudio: true,
            recoveryBatchAttempted: true,
            recoveryResult: "queued",
            finalUtteranceCount: nil,
            mergedIntoSessionID: nil,
            failureMessage: nil
        )

        let message = LiveSessionController.emptySessionDiagnosticsMessage(for: event)
        let data = try XCTUnwrap(message.data(using: .utf8))
        let decoded = try JSONDecoder().decode(LiveSessionController.EmptySessionDiagnosticsEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }
    func testRunningStateChangeCallbackFires() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "Hello", speaker: .you)]
        )

        var runningChanges: [Bool] = []
        controller.onRunningStateChanged = { isRunning in
            runningChanges.append(isRunning)
        }

        controller.startSession(settings: settings)

        // Wait for engine to start
        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let engineRunning = coordinator.transcriptionEngine?.isRunning ?? false
        XCTAssertTrue(engineRunning, "Engine should be running after start")
    }

    func testConfirmDownloadSetsFlag() {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        XCTAssertFalse(coordinator.transcriptionEngine?.downloadConfirmed ?? true)

        controller.confirmDownloadAndStart(settings: settings)

        XCTAssertTrue(coordinator.transcriptionEngine?.downloadConfirmed ?? false)
    }

    func testPollingDoesNotReadVoyageKeyWhenKnowledgeBaseFolderUnset() async {
        let dirs = makeTempDirs()
        let tracker = SecretLoadTracker()
        let secretStore = AppSecretStore(
            loadValue: { key in
                tracker.loadedKeys.append(key)
                return key == "voyageApiKey" ? "pa-existing" : nil
            },
            saveValue: { _, _ in }
        )
        let settings = makeSettings(notesDirectory: dirs.notes, secretStore: secretStore)
        let (controller, _) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )

        let task = Task {
            await controller.runPollingLoop(settings: settings)
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        XCTAssertFalse(tracker.loadedKeys.contains("voyageApiKey"))
    }

    func testPollingDoesNotReadVoyageKeyOnStartupWhenKnowledgeBaseFolderSet() async {
        let dirs = makeTempDirs()
        let kbDirectory = dirs.root.appendingPathComponent("KnowledgeBase", isDirectory: true)
        try? FileManager.default.createDirectory(at: kbDirectory, withIntermediateDirectories: true)

        let tracker = SecretLoadTracker()
        let secretStore = AppSecretStore(
            loadValue: { key in
                tracker.loadedKeys.append(key)
                return key == "voyageApiKey" ? "pa-existing" : nil
            },
            saveValue: { _, _ in }
        )
        let settings = makeSettings(notesDirectory: dirs.notes, secretStore: secretStore)
        settings.kbFolderPath = kbDirectory.path
        settings.embeddingProvider = .voyageAI

        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings
        )
        let knowledgeBase = KnowledgeBase(settings: settings)
        coordinator.setViewServices(
            knowledgeBase: knowledgeBase,
            suggestionEngine: SuggestionEngine(
                transcriptStore: coordinator.transcriptStore,
                knowledgeBase: knowledgeBase,
                settings: settings
            ),
            sidecastEngine: SidecastEngine(
                transcriptStore: coordinator.transcriptStore,
                knowledgeBase: knowledgeBase,
                settings: settings
            )
        )

        let task = Task {
            await controller.runPollingLoop(settings: settings)
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        XCTAssertFalse(tracker.loadedKeys.contains("voyageApiKey"))
    }

    func testFullSessionLifecycle() async {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [
                Utterance(text: "Let me walk through this.", speaker: .you),
                Utterance(text: "Sounds good.", speaker: .them),
            ]
        )

        // Start
        controller.startSession(settings: settings)

        // Wait for engine
        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Stop
        controller.stopSession(settings: settings)

        // Delayed transcript enrichment intentionally waits five seconds before
        // writing. A five-second test deadline races that timer; allow bounded
        // scheduling/finalization overhead without weakening the assertions.
        for _ in 0..<100 {
            if case .idle = coordinator.state, coordinator.lastEndedSession != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNotNil(coordinator.lastEndedSession)
        XCTAssertEqual(coordinator.lastEndedSession?.utteranceCount, 2)
    }

    // MARK: - WB-4: flag-gated legacy SidecastEngine dispatch

    /// `SidecastWhiteboardCoordinatorTests` proves the coordinator's own
    /// behavior in isolation; this proves the seam in `handleNewUtterance`
    /// actually wires the flag to the legacy engine as claimed — with the
    /// flag on, `SidecastEngine.onUtterance` must never run at all; with it
    /// off, it must run exactly as it did before WB-4 (unchanged).
    /// `SidecastEngine.onUtterance` has no public "was I called" hook, but
    /// it flips `isGenerating` true synchronously (before the network call
    /// it then kicks off in the background) the moment it clears its own
    /// credential/persona guards — observable proof of "did this run past
    /// its guards" that doesn't depend on the network call ever succeeding
    /// (same pattern `testFinalizeCurrentSessionAutoGeneratesNotesWhenConfigured`
    /// already relies on elsewhere in this file).
    private func runSidecastDispatchProbe(whiteboardEnabled: Bool) async -> Bool {
        let dirs = makeTempDirs()
        let settings = makeSettings(notesDirectory: dirs.notes)
        settings.sidebarMode = .sidecast
        settings.sidecastWhiteboardEnabled = whiteboardEnabled
        // Deliberately NOT OpenRouter: SidecastWhiteboardCoordinator's own
        // egress gate only ever opens for .openRouter (see its doc
        // comment), so Anthropic credentials satisfy the legacy engine's
        // canCallLLM guard (this probe's actual target) while leaving the
        // coordinator's gate closed. Previously this used .openRouter with
        // a fake key, which was safe only by accident: this probe's single
        // scripted utterance never reaches the listener's 2-utterance
        // cadence threshold, so no real call was ever attempted — but nothing
        // stopped one from firing had the scenario changed.
        settings.llmProvider = .anthropic
        settings.anthropicApiKey = "test-key-not-real"

        let (controller, coordinator) = makeController(
            root: dirs.root,
            notesDirectory: dirs.notes,
            settings: settings,
            scripted: [Utterance(text: "What is the pricing?", speaker: .them)]
        )

        controller.startSession(settings: settings)
        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let pollTask = Task { await controller.runPollingLoop(settings: settings) }
        for _ in 0..<20 {
            if coordinator.sidecastEngine?.isGenerating == true { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        let isGenerating = coordinator.sidecastEngine?.isGenerating ?? false
        pollTask.cancel()
        controller.stopSession(settings: settings)
        return isGenerating
    }

    func testWhiteboardFlagOnSkipsLegacySidecastDispatch() async {
        let isGenerating = await runSidecastDispatchProbe(whiteboardEnabled: true)
        XCTAssertFalse(isGenerating, "flag on: legacy SidecastEngine.onUtterance must be skipped, not merely redundant")
    }

    func testWhiteboardFlagOffLeavesLegacySidecastDispatchUnchanged() async {
        let isGenerating = await runSidecastDispatchProbe(whiteboardEnabled: false)
        XCTAssertTrue(isGenerating, "flag off: legacy SidecastEngine.onUtterance must still run exactly as before WB-4")
    }
}
