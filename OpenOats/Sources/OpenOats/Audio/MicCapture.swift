@preconcurrency import AVFoundation
import Accelerate
import CoreAudio
import Foundation
import os


/// Captures microphone audio via AVAudioEngine and streams PCM buffers.
final class MicCapture: @unchecked Sendable {
    private static let maxRetiredEngineCount = 8

    private var engine = AVAudioEngine()
    private var retiredEngines: [AVAudioEngine] = []
    private var hasTapInstalled = false
    private var configChangeObserver: NSObjectProtocol?
    private let _audioLevel = AudioLevel()
    private let _hasCapturedFrames = SyncBool()
    private let _error = SyncString()
    private let _streamContinuation = OSAllocatedUnfairLock<AsyncStream<AVAudioPCMBuffer>.Continuation?>(uncheckedState: nil)
    private let _muted = SyncBool()
    private let _paused = SyncBool()
    private let generation = AudioStreamGeneration()
    /// The coordinator owns restart ordering; never restart hardware on a notification thread.
    @MainActor var onConfigurationChange: (() -> Void)?
    @MainActor init() {}

    var audioLevel: Float { (_muted.value || _paused.value) ? 0 : _audioLevel.value }
    var hasCapturedFrames: Bool { _hasCapturedFrames.value }
    var captureError: String? { _error.value }

    /// When muted, buffers are not forwarded to the stream and audio level reads as 0.
    var isMuted: Bool {
        get { _muted.value }
        set { _muted.value = newValue }
    }

    /// When paused, buffers are not forwarded (independent of mute).
    var isPaused: Bool {
        get { _paused.value }
        set { _paused.value = newValue }
    }

    /// Set a specific input device by its AudioDeviceID. Pass nil to use system default.
    func setInputDevice(_ deviceID: AudioDeviceID?) {
        guard let id = deviceID else { return }
        guard let audioUnit = engine.inputNode.audioUnit else {
            _error.value = "Microphone audio unit is unavailable."
            return
        }
        var deviceID = id
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    @MainActor func bufferStream(deviceID: AudioDeviceID? = nil, echoCancellation: Bool = false) -> AsyncStream<AVAudioPCMBuffer> {
        let streamID = generation.begin()
        // Defensive cleanup of any prior state
        _streamContinuation.withLock { $0?.finish(); $0 = nil }
        if hasTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        engine.stop()

        let level = _audioLevel
        let errorHolder = _error

        return AsyncStream { continuation in
            self._streamContinuation.withLock { $0 = continuation }
            errorHolder.value = nil
            self._hasCapturedFrames.value = false

            Log.mic.info("bufferStream called, deviceID=\(String(describing: deviceID), privacy: .public)")

            let engine = self.makeFreshEngine()
            Log.mic.info("Fresh engine created")

            let inputNode = engine.inputNode
            Log.mic.info("Input node ready")

            // Enable voice processing (AEC + noise suppression) if requested
            if echoCancellation {
                do {
                    try inputNode.setVoiceProcessingEnabled(true)
                    Log.mic.info("Voice processing (AEC) enabled")
                } catch {
                    Log.mic.error("Failed to enable voice processing: \(error, privacy: .public)")
                }
            }

            engine.prepare()

            // Set input device before accessing inputNode format
            var resolvedDeviceID: AudioDeviceID?
            if let id = deviceID {
                guard let inAU = inputNode.audioUnit else {
                    let msg = "inputNode has no audio unit after prepare"
                    Log.mic.error("\(msg, privacy: .public)")
                    errorHolder.value = msg
                    continuation.finish()
                    return
                }
                var devID = id
                let inStatus = AudioUnitSetProperty(
                    inAU,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &devID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                Log.mic.info("setInputDevice status=\(inStatus, privacy: .public) (0=ok)")
                guard inStatus == noErr else {
                    errorHolder.value = "Could not select the microphone (CoreAudio \(inStatus)). Choose an available device in Settings > Transcription."
                    continuation.finish()
                    return
                }
                resolvedDeviceID = id
            } else {
                Log.mic.info("No deviceID, using system default")
                resolvedDeviceID = Self.defaultInputDeviceID()
            }

            let format = inputNode.outputFormat(forBus: 0)

            // The inputNode format may lag behind a device switch (e.g. USB mic at 48 kHz
            // while the engine still reports 44.1 kHz). Query the hardware sample rate
            // directly and prefer it when it differs from the inputNode format.
            var sampleRate = format.sampleRate
            if let devID = resolvedDeviceID,
               let hwRate = Self.deviceNominalSampleRate(for: devID),
               hwRate > 0, hwRate != sampleRate {
                Log.mic.info("Hardware sr=\(hwRate, privacy: .public) differs from inputNode sr=\(sampleRate, privacy: .public), using hardware rate")
                sampleRate = hwRate
            }

            Log.mic.info("inputNode format: sr=\(format.sampleRate, privacy: .public) ch=\(format.channelCount, privacy: .public) interleaved=\(format.isInterleaved, privacy: .public) commonFormat=\(format.commonFormat.rawValue, privacy: .public), effective sr=\(sampleRate, privacy: .public)")

            guard sampleRate > 0 && format.channelCount > 0 else {
                let msg = "Invalid audio format: sr=\(sampleRate) ch=\(format.channelCount)"
                Log.mic.error("\(msg, privacy: .public)")
                errorHolder.value = msg
                continuation.finish()
                return
            }

            // Try multiple tap formats — some devices report formats that don't
            // round-trip through AVAudioFormat(standardFormat:). Fall back to the
            // native input format as a last resort.
            let tapFormat: AVAudioFormat
            if let f = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: format.channelCount) {
                tapFormat = f
            } else if sampleRate != format.sampleRate,
                      let f = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: format.channelCount) {
                Log.mic.info("Hardware-rate format failed, using node rate \(format.sampleRate, privacy: .public)")
                tapFormat = f
            } else {
                Log.mic.info("Standard formats failed, using native input format")
                tapFormat = format
            }

            Log.mic.info("tapFormat: sr=\(tapFormat.sampleRate, privacy: .public) ch=\(tapFormat.channelCount, privacy: .public)")

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat,
                block: Self.makeTapHandler(generation: self.generation, streamID: streamID,
                    level: level, hasFrames: self._hasCapturedFrames, muted: self._muted,
                    paused: self._paused, continuation: continuation))
            self.hasTapInstalled = true

            Log.mic.info("Tap installed, preparing engine")

            continuation.onTermination = { _ in
                Log.mic.info("Stream terminated")
                // Audio hardware teardown handled by stop() — not here,
                // so finishStream() can drain without premature engine shutdown.
            }

            do {
                Log.mic.info("Engine prepared, starting")
                try engine.start()
                Log.mic.info("Engine started successfully, isRunning=\(engine.isRunning, privacy: .public)")
                self.observeConfigurationChanges(for: engine, streamID: streamID)
            } catch {
                let msg = "Mic failed: \(error.localizedDescription)"
                Log.mic.error("Mic failed: \(error, privacy: .public)")
                errorHolder.value = msg
                inputNode.removeTap(onBus: 0)
                self.hasTapInstalled = false
                continuation.finish()
            }
        }
    }

    /// Created outside actor isolation and exercised off-main without opening hardware.
    static func makeTapHandler(
        generation: AudioStreamGeneration, streamID: UUID, level: AudioLevel,
        hasFrames: SyncBool, muted: SyncBool, paused: SyncBool,
        continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        let tapCounter = OSAllocatedUnfairLock(initialState: 0)
        return { @Sendable buffer, _ in
            generation.withCurrent(streamID) {
                let count = tapCounter.withLock { count in count += 1; return count }
                hasFrames.value = true
                let rms = Self.normalizedRMS(from: buffer)
                level.value = min(rms * 25, 1.0)
                if count <= 5 || count % 100 == 0 {
                    Log.mic.debug("tap #\(count, privacy: .public): frames=\(buffer.frameLength, privacy: .public) rms=\(rms, privacy: .public) level=\(level.value, privacy: .public)")
                }
                guard !muted.value && !paused.value else { return }
                continuation.yield(buffer)
            }
        }
    }

    /// AVAudioEngine stops (without erroring) when the underlying hardware
    /// configuration changes mid-session — e.g. another app (Teams, Zoom) takes
    /// exclusive control of the mic or the OS renegotiates the audio graph.
    /// The existing tap stays installed, but no buffers arrive until the engine
    /// is restarted. Observe the notification and restart it automatically.
    @MainActor private func observeConfigurationChanges(for engine: AVAudioEngine, streamID: UUID) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation.accepts(streamID),
                      self.hasTapInstalled, !self.engine.isRunning else { return }
                self._hasCapturedFrames.value = false
                self._error.value = "Microphone configuration changed; reconnecting."
                Log.mic.info("Audio configuration changed; requesting serialized mic restart")
                self.onConfigurationChange?()
            }
        }
    }

    private func removeConfigurationObserver() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
    }

    /// Finish the async stream so consumers exit their for-await loop.
    /// Call this before stop() when you need a graceful drain.
    func finishStream() {
        generation.invalidate()
        _hasCapturedFrames.value = false
        _audioLevel.value = 0
        _streamContinuation.withLock { $0?.finish(); $0 = nil }
    }

    func stop() {
        finishStream()
        removeConfigurationObserver()
        if hasTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        engine.stop()
        engine.reset()
        _audioLevel.value = 0
        _hasCapturedFrames.value = false
    }

    private func makeFreshEngine() -> AVAudioEngine {
        let oldEngine = engine
        removeConfigurationObserver()
        if hasTapInstalled {
            oldEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        oldEngine.stop()
        oldEngine.reset()
        retainRetiredEngine(oldEngine)

        let freshEngine = AVAudioEngine()
        engine = freshEngine
        return freshEngine
    }

    private func retainRetiredEngine(_ oldEngine: AVAudioEngine) {
        retiredEngines.append(oldEngine)

        // AVAudioEngine teardown can race with AVAudioIOUnit property callbacks when
        // macOS is changing routes (common with AirPods). Keep recently stopped
        // engines alive for a few swaps so AVFAudio's internal queues can drain.
        if retiredEngines.count > Self.maxRetiredEngineCount {
            retiredEngines.removeFirst(retiredEngines.count - Self.maxRetiredEngineCount)
        }
    }

    private static func normalizedRMS(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        // Float32 path — use vDSP for hardware-accelerated RMS
        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            if channelCount == 1 || buffer.format.isInterleaved {
                // Single channel or interleaved: compute RMS directly on contiguous samples
                let totalSamples = buffer.format.isInterleaved ? frameLength * channelCount : frameLength
                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(totalSamples))
                return rms
            } else {
                // Multi-channel non-interleaved: average RMS across all channels
                // to preserve the original semantics
                var totalRMS: Float = 0
                for ch in 0..<channelCount {
                    var chRMS: Float = 0
                    vDSP_rmsqv(channelData[ch], 1, &chRMS, vDSP_Length(frameLength))
                    totalRMS += chRMS * chRMS
                }
                return sqrt(totalRMS / Float(channelCount))
            }
        }

        // Int16 fallback — convert to float, then vDSP
        // Rare in practice (mic is typically Float32)
        if let channelData = buffer.int16ChannelData {
            var floats = [Float](repeating: 0, count: frameLength)
            vDSP_vflt16(channelData[0], 1, &floats, 1, vDSP_Length(frameLength))
            var scale: Float = 1 / Float(Int16.max)
            vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(frameLength))
            var rms: Float = 0
            vDSP_rmsqv(floats, 1, &rms, vDSP_Length(frameLength))
            return rms
        }

        if let channelData = buffer.int32ChannelData {
            let scale: Float = 1 / Float(Int32.max)
            var floats = [Float](repeating: 0, count: frameLength)
            for i in 0..<frameLength { floats[i] = Float(channelData[0][i]) * scale }
            var rms: Float = 0
            vDSP_rmsqv(floats, 1, &rms, vDSP_Length(frameLength))
            return rms
        }

        return 0
    }

    // MARK: - List available input devices

    static func availableInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        var result: [(id: AudioDeviceID, name: String)] = []

        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var bufferListSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &bufferListSize)
            guard status == noErr, bufferListSize > 0 else { continue }

            // AudioBufferList is variable-sized; one struct is insufficient for
            // devices exposing multiple input buffers (e.g. multichannel interfaces).
            let storage = UnsafeMutableRawPointer.allocate(
                byteCount: max(Int(bufferListSize), MemoryLayout<AudioBufferList>.size),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { storage.deallocate() }
            let bufferListPtr = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
            status = AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &bufferListSize, bufferListPtr)
            guard status == noErr else { continue }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
            guard status == noErr, let name else { continue }

            result.append((id: deviceID, name: name.takeUnretainedValue() as String))
        }

        return result
    }

    /// Convert a CoreAudio AudioDeviceID to its stable UID string.
    static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { return nil }
        return uid.takeUnretainedValue() as String
    }

    /// Query the nominal sample rate of a CoreAudio device directly from hardware.
    static func deviceNominalSampleRate(for deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return status == noErr ? sampleRate : nil
    }

    /// Resolve a stable CoreAudio UID string back to the current AudioDeviceID, if the device is connected.
    static func inputDeviceID(forUID uid: String) -> AudioDeviceID? {
        for device in availableInputDevices() {
            if deviceUID(for: device.id) == uid { return device.id }
        }
        return nil
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

}

/// Simple thread-safe float holder for audio level.
final class AudioLevel: @unchecked Sendable {
    private var _value: Float = 0
    private let lock = NSLock()

    var value: Float {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Simple thread-safe optional string holder.
final class SyncString: @unchecked Sendable {
    private var _value: String?
    private let lock = NSLock()

    var value: String? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Simple thread-safe double holder.
final class SyncDouble: @unchecked Sendable {
    private var _value: Double = 0
    private let lock = NSLock()

    var value: Double {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }

    func add(_ delta: Double) {
        lock.withLock { _value += delta }
    }
}

/// Simple thread-safe bool holder.
final class SyncBool: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
