import SwiftUI
import XCTest
@testable import OpenOatsKit

/// Post-review fix (following WB-4): `MeetingDetailPane.startRecording`
/// was one of two paths found to bypass the recording-consent gate
/// entirely. That method itself is a SwiftUI view's private method with
/// `NSApp`/`openWindow` side effects and no view-level test harness in
/// this codebase, so its decision logic was pulled out into
/// `shouldStartRecording(settings:)` — a pure, `static`, directly testable
/// function — which this file exercises. `SessionFolderMenuItems` is
/// generic but unused by this function, so any concrete `View` type works
/// as the substitution; `EmptyView` is the lightest available.
@MainActor
final class MeetingDetailPaneTests: XCTestCase {
    private func makeSettings(hasAcknowledgedRecordingConsent: Bool) -> AppSettings {
        let suiteName = "com.openoats.tests.meetingdetailpane.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(hasAcknowledgedRecordingConsent, forKey: "hasAcknowledgedRecordingConsent")

        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: .ephemeral,
            defaultNotesDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("MeetingDetailPaneTests"),
            runMigrations: false
        )
        return AppSettings(storage: storage)
    }

    func testShouldStartRecordingIsFalseWithoutAcknowledgedConsent() {
        let settings = makeSettings(hasAcknowledgedRecordingConsent: false)
        XCTAssertFalse(MeetingDetailPane<EmptyView>.shouldStartRecording(settings: settings))
    }

    func testShouldStartRecordingIsTrueWithAcknowledgedConsent() {
        let settings = makeSettings(hasAcknowledgedRecordingConsent: true)
        XCTAssertTrue(MeetingDetailPane<EmptyView>.shouldStartRecording(settings: settings))
    }
}
