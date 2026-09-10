import XCTest
@testable import OpenOatsKit

final class CaptureStartupStateTests: XCTestCase {
    private func phase(
        _ stage: CaptureStartupPhase = .waitingForAudio,
        running: Bool = true, error: Bool = false,
        mic: Bool = false, system: Bool = false, muted: Bool = false
    ) -> CaptureStartupPhase {
        .resolve(stage: stage, engineRunning: running, hasError: error,
                 micFrames: mic, systemFrames: system, micMuted: muted, scripted: false)
    }

    func testStartupNeverClaimsLiveFromStaleFrames() {
        for stage: CaptureStartupPhase in [.preparing, .awaitingPermission, .loadingModels] {
            XCTAssertEqual(phase(stage, mic: true, system: true), stage)
            XCTAssertFalse(stage.isCapturing)
        }
    }

    func testWaitingForAudioHasNoLiveTimer() {
        XCTAssertEqual(phase(), .waitingForAudio)
        XCTAssertFalse(phase().isCapturing)
        XCTAssertEqual(phase(running: false), .preparing)
        XCTAssertEqual(phase(.startingAudio), .startingAudio)
    }

    func testBothStreamsRequiredUnlessMicrophoneIntentionallyMuted() {
        XCTAssertEqual(phase(mic: true, system: true), .live)
        XCTAssertEqual(phase(mic: true), .partialAudio)
        XCTAssertEqual(phase(system: true), .partialAudio)
        XCTAssertEqual(phase(system: true, muted: true), .live)
        XCTAssertEqual(phase(muted: true), .waitingForAudio)
    }

    func testFailureDoesNotClaimLiveWithoutAudio() {
        XCTAssertEqual(phase(error: true), .failed)
        XCTAssertEqual(phase(error: true, mic: true, system: true), .partialAudio)
        XCTAssertEqual(phase(.awaitingPermission, running: false, error: true), .failed)
    }

    func testStopInvalidatesPendingPermissionCompletion() {
        var gate = CaptureStartupGate()
        let attempt = gate.begin()
        gate.advance(.awaitingPermission, for: attempt)
        gate.invalidate()
        XCTAssertFalse(gate.accepts(attempt))
        gate.advance(.loadingModels, for: attempt)
        XCTAssertEqual(gate.phase, .idle)
    }

    func testOldAttemptCannotOverwriteNewStartup() {
        var gate = CaptureStartupGate()
        let old = gate.begin()
        let current = gate.begin()
        gate.advance(.awaitingPermission, for: current)
        gate.advance(.live, for: old)
        XCTAssertEqual(gate.phase, .awaitingPermission)
        XCTAssertFalse(gate.accepts(old))
        XCTAssertTrue(gate.accepts(current))
        XCTAssertFalse(gate.accepts(current, cancelled: true))
    }

    func testBuildIdentityExposesRevisionAndDateWithoutChangingSettingsIdentity() {
        XCTAssertEqual(AppBuildIdentity.displayName, "Knowledge Copilot Dev")
        XCTAssertEqual(AppBuildIdentity.detail(info: [
            "KnowledgeCopilotBuildRevision": "abc123-dirty",
            "KnowledgeCopilotBuildDate": "2026-09-10T12:00:00Z"
        ]), "abc123-dirty · 2026-09-10T12:00:00Z")
        XCTAssertTrue(AppBuildIdentity.detail(info: [:]).contains("unpackaged"))
    }
}
