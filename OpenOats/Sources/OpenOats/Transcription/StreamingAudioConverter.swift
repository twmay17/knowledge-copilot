@preconcurrency import AVFoundation

/// One instance per stream, called serially by StreamingTranscriber's consumer loop.
/// Normalize channel layout before resampling so interleaved stereo is never
/// indexed as an array of separate channel pointers.
final class StreamingAudioConverter {
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        standardFormatWithSampleRate: 16_000, channels: 1
    )!

    func extractSamples(_ buffer: AVAudioPCMBuffer, effectiveSampleRate: Double? = nil) -> [Float]? {
        let rate = effectiveSampleRate ?? buffer.format.sampleRate
        guard rate.isFinite, rate > 0,
              let samples = Self.monoSamples(buffer), !samples.isEmpty else { return nil }

        if rate == targetFormat.sampleRate {
            converter = nil
            return samples
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let data = input.floatChannelData?[0] else { return nil }
        input.frameLength = buffer.frameLength
        for index in samples.indices { data[index] = samples[index] }

        if converter?.inputFormat != format {
            converter = AVAudioConverter(from: format, to: targetFormat)
        }
        guard let converter else { return nil }
        let capacity = ceil(Double(input.frameLength) * targetFormat.sampleRate / rate)
        guard capacity > 0, capacity < Double(UInt32.max),
              let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(capacity)
              ) else { return nil }

        let provider = SingleUseAudioConverterInput(input)
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            provider.next(status: status, exhausted: .noDataNow)
        }
        guard result != .error, error == nil, let converted = output.floatChannelData?[0] else {
            return nil
        }
        return Array(UnsafeBufferPointer(start: converted, count: Int(output.frameLength)))
    }

    private static func monoSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, buffer.frameLength <= buffer.frameCapacity, channels > 0 else { return nil }
        let interleaved = buffer.format.isInterleaved
        var samples = [Float](repeating: 0, count: frames)

        func downmix<T>(_ data: UnsafePointer<UnsafeMutablePointer<T>>, value: (T) -> Float) {
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    let sample = interleaved ? data[0][frame * channels + channel] : data[channel][frame]
                    sum += value(sample) / Float(channels)
                }
                samples[frame] = sum
            }
        }

        if let data = buffer.floatChannelData {
            downmix(data, value: { $0 })
        } else if let data = buffer.int16ChannelData {
            downmix(data, value: { Float($0) / 32_768 })
        } else if let data = buffer.int32ChannelData {
            downmix(data, value: { Float($0) / 2_147_483_648 })
        } else {
            return nil
        }
        return samples
    }
}
