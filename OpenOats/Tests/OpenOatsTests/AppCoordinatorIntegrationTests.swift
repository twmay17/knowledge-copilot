import XCTest
@testable import OpenOatsKit

@MainActor
final class AppCoordinatorIntegrationTests: XCTestCase {

    /// Create a coordinator + controller pair wired together for integration tests.
    private func makeTestHarness(
        root: URL,
        notesDirectory: URL,
        scripted: [Utterance]
    ) -> (AppCoordinator, LiveSessionController, AppSettings, SessionRepository) {
        let suiteName = "com.openoats.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(notesDirectory.path, forKey: "notesFolderPath")
        defaults.set(true, forKey: "hasAcknowledgedRecordingConsent")

        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: .ephemeral,
            defaultNotesDirectory: notesDirectory,
            runMigrations: false
        )
        let settings = AppSettings(storage: storage)
        let transcriptStore = TranscriptStore()
        let sessionRepository = SessionRepository(rootDirectory: root)
        let coordinator = AppCoordinator(
            sessionRepository: sessionRepository,
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
            defaults: defaults,
            appSupportDirectory: root,
            notesDirectory: notesDirectory
        )
        let controller = LiveSessionController(coordinator: coordinator, container: container)
        coordinator.liveSessionController = controller

        return (coordinator, controller, settings, sessionRepository)
    }

    private func makeTempDirs() -> (root: URL, notes: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OpenOatsCoordinatorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        return (root, notesDirectory)
    }

    private func makeCalendarEvent(title: String = "Calendar Planning") -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: Date().addingTimeInterval(-300),
            endDate: Date().addingTimeInterval(1_800),
            organizer: nil,
            participants: [],
            isOnlineMeeting: true,
            meetingURL: URL(string: "https://meet.example.com/calendar-planning")
        )
    }

    func testUserStoppedFinalizesSessionAndRefreshesHistory() async {
        let dirs = makeTempDirs()
        let (coordinator, _controller, settings, sessionRepository) = makeTestHarness(
            root: dirs.root,
            notesDirectory: dirs.notes,
            scripted: [
                Utterance(text: "Let me walk through the rollout plan.", speaker: .you),
                Utterance(text: "The pilot scope sounds good to me.", speaker: .them),
            ]
        )

        let metadata = MeetingMetadata(
            detectionContext: DetectionContext(
                signal: .manual,
                detectedAt: Date(),
                meetingApp: nil,
                calendarEvent: nil
            ),
            calendarEvent: nil,
            title: "Coordinator Test",
            startedAt: Date(),
            endedAt: nil
        )

        coordinator.handle(.userStarted(metadata), settings: settings)

        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        coordinator.handle(.userStopped, settings: settings)

        for _ in 0..<50 {
            if coordinator.lastEndedSession != nil, !coordinator.sessionHistory.isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let endedSession = coordinator.lastEndedSession else {
            XCTFail("Expected finalized session")
            return
        }

        XCTAssertEqual(endedSession.utteranceCount, 2)
        XCTAssertTrue(coordinator.sessionHistory.contains(where: { $0.id == endedSession.id }))

        let indices = await sessionRepository.listSessions()
        let persisted = indices.first(where: { $0.id == endedSession.id })
        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.utteranceCount, 2)
        XCTAssertFalse(persisted?.hasNotes ?? true)

        // Keep controller alive for the duration of the test (weak ref in coordinator)
        withExtendedLifetime(_controller) {}
    }

    func testFinalizationFallsBackToCalendarEventTitle() async {
        let dirs = makeTempDirs()
        let (coordinator, _controller, settings, sessionRepository) = makeTestHarness(
            root: dirs.root,
            notesDirectory: dirs.notes,
            scripted: [
                Utterance(text: "Let's start with the project timeline.", speaker: .you),
            ]
        )

        let event = makeCalendarEvent(title: "Calendar Planning")
        coordinator.handle(.userStarted(.manual(calendarEvent: event)), settings: settings)

        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        coordinator.handle(.userStopped, settings: settings)

        for _ in 0..<50 {
            if case .idle = coordinator.state, coordinator.lastEndedSession != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let endedSession = coordinator.lastEndedSession else {
            XCTFail("Expected finalized session")
            return
        }

        XCTAssertEqual(endedSession.title, "Calendar Planning")

        let indices = await sessionRepository.listSessions()
        let persisted = indices.first(where: { $0.id == endedSession.id })
        XCTAssertEqual(persisted?.title, "Calendar Planning")

        withExtendedLifetime(_controller) {}
    }

    func testFinalizationWritesSidecarWithCorrectMetadata() async {
        let dirs = makeTempDirs()
        let (coordinator, _controller, settings, sessionRepository) = makeTestHarness(
            root: dirs.root,
            notesDirectory: dirs.notes,
            scripted: [
                Utterance(text: "Hello from you.", speaker: .you),
                Utterance(text: "Hello from them.", speaker: .them),
            ]
        )

        let metadata = MeetingMetadata.manual()
        coordinator.handle(.userStarted(metadata), settings: settings)

        // Wait for engine to start
        for _ in 0..<20 {
            if coordinator.transcriptionEngine?.isRunning == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        coordinator.handle(.userStopped, settings: settings)

        // Wait for finalization
        for _ in 0..<50 {
            if case .idle = coordinator.state, coordinator.lastEndedSession != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Verify state returned to idle
        XCTAssertEqual(coordinator.state, .idle)

        // Verify session metadata was written
        let indices = await sessionRepository.listSessions()
        XCTAssertFalse(indices.isEmpty)
        let session = indices.first!
        XCTAssertFalse(session.hasNotes)
        XCTAssertEqual(session.utteranceCount, 2)

        withExtendedLifetime(_controller) {}
    }

    func testFinalizationTimeoutForcesIdleState() async {
        let coordinator = AppCoordinator()
        let metadata = MeetingMetadata.manual()

        coordinator.handle(.userStarted(metadata))
        XCTAssertEqual(coordinator.isRecording, true)

        coordinator.handle(.userStopped)
        coordinator.handle(.finalizationTimeout)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testDiscardReturnsToIdleWithoutFinalization() async {
        let coordinator = AppCoordinator()
        let metadata = MeetingMetadata.manual()

        coordinator.handle(.userStarted(metadata))
        XCTAssertEqual(coordinator.isRecording, true)

        coordinator.handle(.userDiscarded)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.lastEndedSession)
    }

    // MARK: - Post-review fix: recording consent gates the detection-accepted path too

    private func makeDetectionAcceptedMetadata(appLaunched: Bool) -> MeetingMetadata {
        let signal: DetectionSignal
        let app: MeetingApp?
        if appLaunched {
            let meetingApp = MeetingApp(bundleID: "us.zoom.xos", name: "Zoom")
            signal = .appLaunched(meetingApp)
            app = meetingApp
        } else {
            // .audioActivity is handleDetectionAccepted's own fallback signal
            // when no specific app is identified — a real value the
            // production chain produces, and one that (unlike .appLaunched/
            // .cameraActivated) doesn't reach the silence/app-exit monitoring
            // setup, so this test doesn't need a fully set-up
            // MeetingDetectionController (meetingDetector/notificationService)
            // just to exercise the consent-acknowledged path safely.
            signal = .audioActivity
            app = nil
        }
        return MeetingMetadata(
            detectionContext: DetectionContext(signal: signal, detectedAt: Date(), meetingApp: app, calendarEvent: nil),
            calendarEvent: nil,
            title: "Detected Meeting",
            startedAt: Date(),
            endedAt: nil
        )
    }

    /// `MeetingDetectionControllerTests` only ever exercises
    /// `MeetingDetectionController`'s own event stream in isolation, never
    /// `AppCoordinator.startDetectionEventLoop`'s consumption of it — this is
    /// the first test to drive the real `.accepted` chain the review traced
    /// (tapping a meeting-detected notification's default action) through
    /// `AppCoordinator` itself, using `MeetingDetectionController.yield(_:)`
    /// (explicitly "Visible for testing") rather than a lower-level proxy.
    func testDetectionAcceptedWithoutConsentDoesNotStartAndSurfacesMainWindow() async {
        let dirs = makeTempDirs()
        let (coordinator, controller, settings, _) = makeTestHarness(root: dirs.root, notesDirectory: dirs.notes, scripted: [])
        settings.hasAcknowledgedRecordingConsent = false

        let detectionController = MeetingDetectionController()
        coordinator.startDetectionEventLoop(detectionController)
        // startDetectionEventLoop copies activeSettings from the detection
        // controller (nil here — this test never calls its setup(settings:),
        // deliberately, to avoid constructing a real MeetingDetector/
        // NotificationService) once, at the top; overwriting afterward is
        // safe since nothing re-copies it on a later event.
        coordinator.activeSettings = settings

        var windowSurfaced = false
        coordinator.showMainWindowAction = { windowSurfaced = true }

        // .appLaunched deliberately: proves the silence/app-exit monitoring
        // setup is ALSO skipped, not just the session start (the guard sits
        // before that setup in the .accepted case, not just before
        // self.handle(.userStarted...)).
        detectionController.yield(.accepted(makeDetectionAcceptedMetadata(appLaunched: true)))
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(windowSurfaced, "must surface the app window so the user can acknowledge consent")
        XCTAssertEqual(coordinator.state, .idle, "must not start without consent")
        XCTAssertFalse(
            detectionController.isMonitoringSilence,
            "the monitoring setup that normally accompanies an accepted .appLaunched detection must also be skipped"
        )

        coordinator.stopDetectionEventLoop()
        withExtendedLifetime(controller) {}
    }

    func testDetectionAcceptedWithConsentStartsNormally() async {
        let dirs = makeTempDirs()
        let (coordinator, controller, settings, _) = makeTestHarness(root: dirs.root, notesDirectory: dirs.notes, scripted: [])
        // makeTestHarness's settings already have consent acknowledged.

        let detectionController = MeetingDetectionController()
        coordinator.startDetectionEventLoop(detectionController)
        coordinator.activeSettings = settings

        detectionController.yield(.accepted(makeDetectionAcceptedMetadata(appLaunched: false)))

        for _ in 0..<20 {
            if coordinator.isRecording { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(coordinator.isRecording, "consent acknowledged: an accepted detection must start a session exactly as before this fix")

        coordinator.stopDetectionEventLoop()
        withExtendedLifetime(controller) {}
    }
}
