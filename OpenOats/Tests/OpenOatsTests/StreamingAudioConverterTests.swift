import AVFoundation
import os
import XCTest
@testable import OpenOatsKit

final class StreamingAudioConverterTests: XCTestCase {
    private func buffer(
        rate: Double = 16_000, channels: UInt32 = 2,
        interleaved: Bool, frames: AVAudioFrameCount = 4_800
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate,
            channels: channels, interleaved: interleaved
        )!
        let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        result.frameLength = frames
        let data = result.floatChannelData!
        for frame in 0..<Int(frames) {
            for channel in 0..<Int(channels) {
                // Silence on the left makes dropped-right-channel regressions obvious.
                let value: Float = channels == 1 || channel == 1 ? 0.5 : 0
                if interleaved { data[0][frame * Int(channels) + channel] = value }
                else { data[channel][frame] = value }
            }
        }
        return result
    }

    func test16kStereoIncludesRightChannelInBothLayouts() throws {
        for interleaved in [false, true] {
            let output = try XCTUnwrap(StreamingAudioConverter().extractSamples(buffer(interleaved: interleaved)))
            XCTAssertEqual(output.count, 4_800)
            XCTAssertTrue(output.allSatisfy { $0 == 0.25 })
        }
    }

    func test16kMonoPassThroughInBothLayouts() throws {
        for interleaved in [false, true] {
            let output = try XCTUnwrap(StreamingAudioConverter().extractSamples(
                buffer(channels: 1, interleaved: interleaved)
            ))
            XCTAssertEqual(output, [Float](repeating: 0.5, count: 4_800))
        }
    }

    func testResampledStereoLayoutsAgreeAndPreserveRightChannel() throws {
        for rate in [44_100.0, 48_000.0] {
            let planar = try XCTUnwrap(StreamingAudioConverter().extractSamples(
                buffer(rate: rate, interleaved: false)
            ))
            let packed = try XCTUnwrap(StreamingAudioConverter().extractSamples(
                buffer(rate: rate, interleaved: true)
            ))
            XCTAssertFalse(packed.isEmpty)
            XCTAssertEqual(planar.count, packed.count)
            for (a, b) in zip(planar, packed) { XCTAssertEqual(a, b, accuracy: 0.00001) }
            let middle = Array(packed.dropFirst(100).dropLast(100))
            XCTAssertFalse(middle.isEmpty)
            XCTAssertTrue(middle.allSatisfy { abs($0 - 0.25) < 0.002 })
        }
    }

    func testEffectiveRateOverridesDeclaredRateForBothLayoutsAndMono() throws {
        for channels: UInt32 in [1, 2] {
            for interleaved in [false, true] {
                let input = buffer(rate: 48_000, channels: channels, interleaved: interleaved)
                let direct = try XCTUnwrap(StreamingAudioConverter().extractSamples(input, effectiveSampleRate: 16_000))
                XCTAssertEqual(direct.count, 4_800)
                XCTAssertTrue(direct.allSatisfy { $0 == (channels == 1 ? 0.5 : 0.25) })
                let corrected = try XCTUnwrap(StreamingAudioConverter().extractSamples(input, effectiveSampleRate: 44_100))
                let reference = try XCTUnwrap(StreamingAudioConverter().extractSamples(
                    buffer(rate: 44_100, channels: channels, interleaved: interleaved)
                ))
                XCTAssertEqual(corrected, reference)
            }
        }
    }

    func testEmptyAndInvalidRatesFailClosed() {
        let input = buffer(interleaved: true)
        for rate in [0.0, -1, .nan, .infinity] {
            XCTAssertNil(StreamingAudioConverter().extractSamples(input, effectiveSampleRate: rate))
        }
        input.frameLength = 0
        XCTAssertNil(StreamingAudioConverter().extractSamples(input))
    }

    func testRepeatedBuffersMaintainDurationAndSignal() throws {
        let converter = StreamingAudioConverter()
        var samples: [Float] = []
        var counts: [Int] = []
        for _ in 0..<100 {
            let output = try XCTUnwrap(converter.extractSamples(buffer(rate: 48_000, interleaved: true)))
            samples += output
            counts.append(output.count)
        }
        // The first buffer pays the resampler's priming latency. Subsequent
        // 100 ms buffers must each produce exactly 1,600 frames: no accumulating loss.
        XCTAssertGreaterThan(counts[0], 0)
        XCTAssertLessThanOrEqual(counts[0], 1_600)
        XCTAssertTrue(counts.dropFirst().allSatisfy { $0 == 1_600 })
        XCTAssertEqual(samples.count, counts[0] + 99 * 1_600)
        XCTAssertTrue(samples.dropFirst(200).allSatisfy { abs($0 - 0.25) < 0.002 })
    }

    func testRateChangesRebuildConverter() throws {
        let converter = StreamingAudioConverter()
        for rate in [48_000.0, 16_000, 44_100, 48_000] {
            let input = buffer(rate: rate, interleaved: true)
            let actual = try XCTUnwrap(converter.extractSamples(input))
            let expected = try XCTUnwrap(StreamingAudioConverter().extractSamples(input))
            XCTAssertEqual(actual, expected)
        }
    }

    func testIntegerStereoLayoutsNormalizeCorrectly() throws {
        for common in [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32] {
            for interleaved in [false, true] {
                let format = AVAudioFormat(commonFormat: common, sampleRate: 16_000, channels: 2, interleaved: interleaved)!
                let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8)!
                input.frameLength = 8
                for frame in 0..<8 {
                    for channel in 0..<2 {
                        let pointer = interleaved ? 0 : channel
                        let index = interleaved ? frame * 2 + channel : frame
                        if let data = input.int16ChannelData { data[pointer][index] = channel == 0 ? 0 : 16_384 }
                        if let data = input.int32ChannelData { data[pointer][index] = channel == 0 ? 0 : 1_073_741_824 }
                    }
                }
                XCTAssertEqual(try XCTUnwrap(StreamingAudioConverter().extractSamples(input)), [Float](repeating: 0.25, count: 8))
            }
        }
    }

    func testInputProviderUsesCorrectExhaustionStatus() {
        for exhausted in [AVAudioConverterInputStatus.noDataNow, .endOfStream] {
            let provider = SingleUseAudioConverterInput(buffer(interleaved: false))
            var status = AVAudioConverterInputStatus.noDataNow
            XCTAssertNotNil(provider.next(status: &status, exhausted: exhausted))
            XCTAssertEqual(status, .haveData)
            XCTAssertNil(provider.next(status: &status, exhausted: exhausted))
            XCTAssertEqual(status, exhausted)
        }
    }

    func testInputProviderSuppliesBufferOnlyOnceUnderConcurrentRequests() {
        let provider = SingleUseAudioConverterInput(buffer(interleaved: false))
        let count = OSAllocatedUnfairLock(initialState: 0)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            var status = AVAudioConverterInputStatus.noDataNow
            if provider.next(status: &status, exhausted: .noDataNow) != nil {
                count.withLock { $0 += 1 }
            }
        }
        XCTAssertEqual(count.withLock { $0 }, 1)
    }
}
