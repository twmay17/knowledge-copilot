@preconcurrency import AVFoundation
import XCTest
@testable import OpenOatsKit

final class MicrophoneTapSafetyTests: XCTestCase {
    func testActualTapHandlerRunsOffMainHonorsMutePauseAndRejectsRetiredStream() async {
        let gate = AudioStreamGeneration()
        let id = gate.begin()
        let level = AudioLevel()
        let frames = SyncBool()
        let muted = SyncBool()
        let paused = SyncBool()
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let handler = MicCapture.makeTapHandler(generation: gate, streamID: id,
            level: level, hasFrames: frames, muted: muted, paused: paused,
            continuation: continuation)
        await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)!
            buffer.frameLength = 32
            for index in 0..<32 { buffer.floatChannelData![0][index] = 0.01 }
            let time = AVAudioTime(sampleTime: 0, atRate: 48_000)
            handler(buffer, time)
            XCTAssertTrue(frames.value)
            XCTAssertGreaterThan(level.value, 0)
            muted.value = true
            handler(buffer, time)
            muted.value = false
            paused.value = true
            handler(buffer, time)
            paused.value = false
            gate.invalidate()
            frames.value = false
            level.value = 0
            gate.begin()
            handler(buffer, time)
            XCTAssertFalse(frames.value)
            XCTAssertEqual(level.value, 0)
            continuation.finish()
        }.value
        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertEqual(count, 1, "Muted, paused and stale callbacks must not forward audio")
    }
}
