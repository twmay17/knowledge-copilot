import XCTest
@testable import OpenOatsKit

@MainActor
final class TranscriptionStartupCancellationTests: XCTestCase {
    @MainActor private final class Barrier {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    private struct SuspendedBackend: TranscriptionBackend {
        let barrier: Barrier
        var displayName: String { "Suspended fixture" }
        func checkStatus() -> BackendStatus { .ready }
        func prepare(onStatus: @Sendable (String) -> Void,
                     onProgress: @escaping @Sendable (Double) -> Void) async throws {
            await barrier.wait()
            // Deliberately ignore cancellation to simulate an uncooperative loader.
            onStatus("Stale model completion")
            onProgress(0.9)
        }
        func transcribe(_ samples: [Float], locale: Locale, previousContext: String?) async throws -> String {
            XCTFail("Cancelled startup must never transcribe")
            return ""
        }
    }

    private func settings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "startup-tests.\(UUID().uuidString)")!
        let settings = AppSettings(storage: AppSettingsStorage(
            defaults: defaults, secretStore: .ephemeral,
            defaultNotesDirectory: URL(fileURLWithPath: NSTemporaryDirectory()), runMigrations: false
        ))
        // Cloud enum skips local disk-model checks; the injected backend never networks.
        settings.transcriptionModel = .assemblyAI
        return settings
    }

    private func waitUntilSuspended(_ barrier: Barrier) async {
        for _ in 0..<100 {
            if barrier.continuation != nil { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Startup did not reach the controlled suspension")
    }

    func testPermissionCompletionAfterStopCannotStartAudio() async {
        let barrier = Barrier()
        let engine = TranscriptionEngine(
            transcriptStore: TranscriptStore(), settings: settings(),
            permissionCheck: { await barrier.wait(); return true }
        )
        let startup = Task { await engine.start(locale: Locale(identifier: "en-US"), transcriptionModel: .assemblyAI) }
        await waitUntilSuspended(barrier)
        XCTAssertEqual(engine.captureStartupPhase, .awaitingPermission)
        XCTAssertFalse(engine.isRunning)
        startup.cancel()
        await engine.finalize()
        barrier.release()
        await startup.value
        XCTAssertFalse(engine.isRunning)
        XCTAssertNil(engine.activeTranscriptionSession)
        XCTAssertFalse(engine.captureHealthSnapshot.micHasCapturedFrames)
        XCTAssertFalse(engine.captureHealthSnapshot.systemHasCapturedFrames)
    }

    func testModelCompletionAndProgressAfterStopCannotReactivateStartup() async {
        let barrier = Barrier()
        let engine = TranscriptionEngine(
            transcriptStore: TranscriptStore(), settings: settings(),
            permissionCheck: { true }, backendFactory: { _ in SuspendedBackend(barrier: barrier) }
        )
        let startup = Task { await engine.start(locale: Locale(identifier: "en-US"), transcriptionModel: .assemblyAI) }
        await waitUntilSuspended(barrier)
        XCTAssertEqual(engine.captureStartupPhase, .loadingModels)
        startup.cancel()
        await engine.finalize()
        barrier.release()
        await startup.value
        // Drain status callbacks queued by the intentionally uncooperative backend.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(engine.isRunning)
        XCTAssertNil(engine.activeTranscriptionSession)
        XCTAssertNil(engine.downloadProgress)
        XCTAssertEqual(engine.assetStatus, "Ready")
        XCTAssertFalse(engine.captureHealthSnapshot.micHasCapturedFrames)
        XCTAssertFalse(engine.captureHealthSnapshot.systemHasCapturedFrames)
    }
}
