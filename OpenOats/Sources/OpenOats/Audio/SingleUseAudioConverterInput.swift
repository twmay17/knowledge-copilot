@preconcurrency import AVFoundation
import Foundation

/// Supplies a completed, immutable buffer at most once per conversion call.
/// AVAudioConverter's sendable callback must not capture a mutable local flag.
/// The caller must not mutate the buffer until conversion returns.
final class SingleUseAudioConverterInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var consumed = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>,
        exhausted: AVAudioConverterInputStatus
    ) -> AVAudioBuffer? {
        lock.withLock {
            guard !consumed else {
                status.pointee = exhausted
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
    }
}
