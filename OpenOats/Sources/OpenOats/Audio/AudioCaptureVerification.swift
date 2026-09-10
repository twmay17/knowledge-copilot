@preconcurrency import AVFoundation
import Foundation

public struct AudioCaptureVerificationPolicy: Codable, Sendable, Equatable {
  public let minimumSessionDurationSeconds: Double
  public let minimumTrackCoverageRatio: Double
  public let maximumUnrecoveredGapSeconds: Double
  public let minimumAudiblePeak: Float

  public init(
    minimumSessionDurationSeconds: Double = 30 * 60,
    minimumTrackCoverageRatio: Double = 0.98,
    maximumUnrecoveredGapSeconds: Double = 2,
    minimumAudiblePeak: Float = 0.002
  ) {
    self.minimumSessionDurationSeconds = minimumSessionDurationSeconds
    self.minimumTrackCoverageRatio = minimumTrackCoverageRatio
    self.maximumUnrecoveredGapSeconds = maximumUnrecoveredGapSeconds
    self.minimumAudiblePeak = minimumAudiblePeak
  }
}

public struct AudioCaptureVerificationAttestations: Codable, Sendable, Equatable {
  public let teamsSessionConfirmed: Bool
  public let participantConsentConfirmed: Bool
  public let recordingIndicatorConfirmed: Bool
  public let verifiedBy: String?

  public init(
    teamsSessionConfirmed: Bool,
    participantConsentConfirmed: Bool,
    recordingIndicatorConfirmed: Bool,
    verifiedBy: String? = nil
  ) {
    self.teamsSessionConfirmed = teamsSessionConfirmed
    self.participantConsentConfirmed = participantConsentConfirmed
    self.recordingIndicatorConfirmed = recordingIndicatorConfirmed
    self.verifiedBy = verifiedBy
  }
}

public enum AudioCaptureTrackKind: String, Codable, Sendable {
  case microphone
  case system
}

public struct AudioCaptureTrackVerification: Codable, Sendable, Equatable {
  public let kind: AudioCaptureTrackKind
  public let relativePath: String
  public let exists: Bool
  public let declaredSampleRate: Double?
  public let effectiveSampleRate: Double?
  public let channelCount: UInt32?
  public let frameCount: Int64
  public let durationSeconds: Double?
  public let coverageRatio: Double?
  public let peakAmplitude: Float?
  public let rmsAmplitude: Float?
  public let audibleSampleRatio: Double?
  public let timingAnchorCount: Int
  public let maximumUnrecoveredGapSeconds: Double?
  public let issues: [String]
  public let passed: Bool
}

public struct AudioCaptureVerificationReport: Codable, Sendable, Equatable {
  public let generatedAt: Date
  public let sessionID: String?
  public let meetingApp: String?
  public let startedAt: Date?
  public let endedAt: Date?
  public let sessionDurationSeconds: Double?
  public let policy: AudioCaptureVerificationPolicy
  public let attestations: AudioCaptureVerificationAttestations
  public let microphone: AudioCaptureTrackVerification
  public let system: AudioCaptureTrackVerification
  public let issues: [String]
  public let passed: Bool

  public var textSummary: String {
    let status = passed ? "PASS" : "FAIL"
    var lines = ["Audio capture verification: \(status)"]
    if let sessionID { lines.append("Session: \(sessionID)") }
    if let meetingApp { lines.append("Meeting app: \(meetingApp)") }
    if let sessionDurationSeconds {
      lines.append(String(format: "Session duration: %.2f seconds", sessionDurationSeconds))
    }
    lines.append(Self.trackSummary(microphone))
    lines.append(Self.trackSummary(system))
    if issues.isEmpty {
      lines.append("All verification gates passed.")
    } else {
      lines.append("Issues:")
      lines.append(contentsOf: issues.map { "- \($0)" })
    }
    return lines.joined(separator: "\n")
  }

  private static func trackSummary(_ track: AudioCaptureTrackVerification) -> String {
    let duration = track.durationSeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
    let coverage = track.coverageRatio.map { String(format: "%.2f%%", $0 * 100) } ?? "n/a"
    let peak = track.peakAmplitude.map { String(format: "%.5f", $0) } ?? "n/a"
    let gap = track.maximumUnrecoveredGapSeconds.map { String(format: "%.3fs", $0) } ?? "n/a"
    return
      "\(track.kind.rawValue): \(track.passed ? "PASS" : "FAIL") · duration \(duration) · coverage \(coverage) · peak \(peak) · max gap \(gap) · anchors \(track.timingAnchorCount)"
  }
}

public enum AudioCaptureVerificationError: LocalizedError {
  case sessionDirectoryMissing(String)
  case sessionMetadataUnreadable(String)

  public var errorDescription: String? {
    switch self {
    case .sessionDirectoryMissing(let path):
      return "Session directory does not exist: \(path)"
    case .sessionMetadataUnreadable(let message):
      return "Unable to read session metadata: \(message)"
    }
  }
}

public enum AudioCaptureVerifier {
  public static func verify(
    sessionDirectory: URL,
    policy: AudioCaptureVerificationPolicy = AudioCaptureVerificationPolicy(),
    attestations: AudioCaptureVerificationAttestations
  ) throws -> AudioCaptureVerificationReport {
    let directory = sessionDirectory.standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw AudioCaptureVerificationError.sessionDirectoryMissing(directory.path)
    }

    let session = try loadSessionTiming(from: directory)
    let batchMeta = loadBatchMeta(from: directory)
    let sessionDuration = session.endedAt.map { max(0, $0.timeIntervalSince(session.startedAt)) }

    var reportIssues: [String] = []
    if sessionDuration == nil {
      reportIssues.append("Session metadata does not contain an end time.")
    } else if let sessionDuration,
      sessionDuration < policy.minimumSessionDurationSeconds
    {
      reportIssues.append(
        String(
          format: "Session duration %.2fs is below the required %.2fs.",
          sessionDuration,
          policy.minimumSessionDurationSeconds
        )
      )
    }
    if !attestations.teamsSessionConfirmed,
      !(session.meetingApp?.localizedCaseInsensitiveContains("teams") ?? false)
    {
      reportIssues.append("A Teams session was not confirmed by metadata or operator attestation.")
    }
    if !attestations.participantConsentConfirmed {
      reportIssues.append("Participant consent was not confirmed by the operator.")
    }
    if !attestations.recordingIndicatorConfirmed {
      reportIssues.append("The visible recording indicator was not confirmed by the operator.")
    }

    let microphone = analyzeTrack(
      kind: .microphone,
      url: trackURL(kind: .microphone, sessionDirectory: directory),
      sessionDuration: sessionDuration,
      anchors: batchMeta?.micAnchors ?? [],
      storedEffectiveSampleRate: nil,
      policy: policy
    )
    let system = analyzeTrack(
      kind: .system,
      url: trackURL(kind: .system, sessionDirectory: directory),
      sessionDuration: sessionDuration,
      anchors: batchMeta?.sysAnchors ?? [],
      storedEffectiveSampleRate: batchMeta?.sysEffectiveSampleRate,
      policy: policy
    )

    reportIssues.append(contentsOf: microphone.issues.map { "Microphone: \($0)" })
    reportIssues.append(contentsOf: system.issues.map { "System audio: \($0)" })

    return AudioCaptureVerificationReport(
      generatedAt: Date(),
      sessionID: session.id,
      meetingApp: session.meetingApp,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      sessionDurationSeconds: sessionDuration,
      policy: policy,
      attestations: attestations,
      microphone: microphone,
      system: system,
      issues: reportIssues,
      passed: reportIssues.isEmpty && microphone.passed && system.passed
    )
  }

  private static func analyzeTrack(
    kind: AudioCaptureTrackKind,
    url: URL,
    sessionDuration: Double?,
    anchors: [TimingAnchorFile],
    storedEffectiveSampleRate: Double?,
    policy: AudioCaptureVerificationPolicy
  ) -> AudioCaptureTrackVerification {
    let relativePath = "audio/\(url.lastPathComponent)"
    guard FileManager.default.fileExists(atPath: url.path) else {
      let issue = "Missing \(relativePath). Enable retained batch audio before the test."
      return AudioCaptureTrackVerification(
        kind: kind,
        relativePath: relativePath,
        exists: false,
        declaredSampleRate: nil,
        effectiveSampleRate: nil,
        channelCount: nil,
        frameCount: 0,
        durationSeconds: nil,
        coverageRatio: nil,
        peakAmplitude: nil,
        rmsAmplitude: nil,
        audibleSampleRatio: nil,
        timingAnchorCount: anchors.count,
        maximumUnrecoveredGapSeconds: nil,
        issues: [issue],
        passed: false
      )
    }

    do {
      let file = try AVAudioFile(forReading: url)
      let declaredRate = file.processingFormat.sampleRate
      // Frame progression is the evidence under test, not an independent clock
      // calibration. Deriving a rate from these same anchors can turn a muted or
      // consistently dropping stream into 100% coverage at a fictitious low rate.
      // Certify against the file's declared rate; fail closed on known mismatches.
      let effectiveRate = declaredRate
      let metrics = try sampleMetrics(file: file, audibleThreshold: policy.minimumAudiblePeak)
      let duration = effectiveRate > 0 ? Double(file.length) / effectiveRate : nil
      let coverage: Double? =
        if let duration, let sessionDuration, sessionDuration > 0 {
          duration / sessionDuration
        } else {
          nil
        }
      let maximumGap = maximumUnrecoveredGap(anchors: anchors, effectiveSampleRate: effectiveRate)

      var issues: [String] = []
      if let storedEffectiveSampleRate,
        !storedEffectiveSampleRate.isFinite
          || abs(storedEffectiveSampleRate - declaredRate) / declaredRate > 0.05
      {
        issues.append(
          "Stored sample-rate estimate differs from the file rate by more than 5% or is invalid. "
            + "Independent clock calibration is required; timing anchors cannot certify their own rate."
        )
      }
      if let coverage, coverage < policy.minimumTrackCoverageRatio {
        issues.append(
          String(
            format: "Track coverage %.2f%% is below the required %.2f%%.",
            coverage * 100,
            policy.minimumTrackCoverageRatio * 100
          )
        )
      } else if coverage == nil {
        issues.append("Track coverage could not be calculated.")
      }
      if metrics.peak < policy.minimumAudiblePeak {
        issues.append(
          String(
            format: "Peak amplitude %.5f is below the audible threshold %.5f.",
            metrics.peak,
            policy.minimumAudiblePeak
          )
        )
      }
      if anchors.count < 2 {
        issues.append("At least two timing anchors are required to measure unrecovered dropout.")
      } else if let maximumGap, maximumGap > policy.maximumUnrecoveredGapSeconds {
        issues.append(
          String(
            format: "Maximum unrecovered gap %.3fs exceeds the allowed %.3fs.",
            maximumGap,
            policy.maximumUnrecoveredGapSeconds
          )
        )
      }

      return AudioCaptureTrackVerification(
        kind: kind,
        relativePath: relativePath,
        exists: true,
        declaredSampleRate: declaredRate,
        effectiveSampleRate: effectiveRate,
        channelCount: file.processingFormat.channelCount,
        frameCount: file.length,
        durationSeconds: duration,
        coverageRatio: coverage,
        peakAmplitude: metrics.peak,
        rmsAmplitude: metrics.rms,
        audibleSampleRatio: metrics.audibleRatio,
        timingAnchorCount: anchors.count,
        maximumUnrecoveredGapSeconds: maximumGap,
        issues: issues,
        passed: issues.isEmpty
      )
    } catch {
      let issue = "Unable to inspect \(relativePath): \(error.localizedDescription)"
      return AudioCaptureTrackVerification(
        kind: kind,
        relativePath: relativePath,
        exists: true,
        declaredSampleRate: nil,
        effectiveSampleRate: nil,
        channelCount: nil,
        frameCount: 0,
        durationSeconds: nil,
        coverageRatio: nil,
        peakAmplitude: nil,
        rmsAmplitude: nil,
        audibleSampleRatio: nil,
        timingAnchorCount: anchors.count,
        maximumUnrecoveredGapSeconds: nil,
        issues: [issue],
        passed: false
      )
    }
  }

  private static func sampleMetrics(
    file: AVAudioFile,
    audibleThreshold: Float
  ) throws -> (peak: Float, rms: Float, audibleRatio: Double) {
    let format = file.processingFormat
    let chunkFrames: AVAudioFrameCount = 65_536
    var peak: Float = 0
    var sumSquares = 0.0
    var sampleCount = 0
    var audibleSampleCount = 0

    while file.framePosition < file.length {
      let remaining = file.length - file.framePosition
      let capacity = AVAudioFrameCount(min(Int64(chunkFrames), remaining))
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        break
      }
      try file.read(into: buffer, frameCount: capacity)
      guard buffer.frameLength > 0 else { break }

      let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
      for audioBuffer in buffers {
        guard let data = audioBuffer.mData else { continue }
        let byteCount = Int(audioBuffer.mDataByteSize)
        switch format.commonFormat {
        case .pcmFormatFloat32:
          let values = data.bindMemory(
            to: Float.self, capacity: byteCount / MemoryLayout<Float>.size)
          accumulate(
            values: UnsafeBufferPointer(start: values, count: byteCount / MemoryLayout<Float>.size),
            scale: 1,
            threshold: audibleThreshold,
            peak: &peak,
            sumSquares: &sumSquares,
            sampleCount: &sampleCount,
            audibleSampleCount: &audibleSampleCount
          )
        case .pcmFormatInt16:
          let values = data.bindMemory(
            to: Int16.self, capacity: byteCount / MemoryLayout<Int16>.size)
          accumulate(
            values: UnsafeBufferPointer(start: values, count: byteCount / MemoryLayout<Int16>.size),
            scale: 1 / Float(Int16.max),
            threshold: audibleThreshold,
            peak: &peak,
            sumSquares: &sumSquares,
            sampleCount: &sampleCount,
            audibleSampleCount: &audibleSampleCount
          )
        case .pcmFormatInt32:
          let values = data.bindMemory(
            to: Int32.self, capacity: byteCount / MemoryLayout<Int32>.size)
          accumulate(
            values: UnsafeBufferPointer(start: values, count: byteCount / MemoryLayout<Int32>.size),
            scale: 1 / Float(Int32.max),
            threshold: audibleThreshold,
            peak: &peak,
            sumSquares: &sumSquares,
            sampleCount: &sampleCount,
            audibleSampleCount: &audibleSampleCount
          )
        default:
          continue
        }
      }
    }

    let rms = sampleCount > 0 ? Float(sqrt(sumSquares / Double(sampleCount))) : 0
    let audibleRatio = sampleCount > 0 ? Double(audibleSampleCount) / Double(sampleCount) : 0
    return (peak, rms, audibleRatio)
  }

  private static func accumulate<T: BinaryInteger>(
    values: UnsafeBufferPointer<T>,
    scale: Float,
    threshold: Float,
    peak: inout Float,
    sumSquares: inout Double,
    sampleCount: inout Int,
    audibleSampleCount: inout Int
  ) {
    for raw in values {
      let value = Float(Int64(raw)) * scale
      accumulate(
        value: value,
        threshold: threshold,
        peak: &peak,
        sumSquares: &sumSquares,
        sampleCount: &sampleCount,
        audibleSampleCount: &audibleSampleCount
      )
    }
  }

  private static func accumulate(
    values: UnsafeBufferPointer<Float>,
    scale: Float,
    threshold: Float,
    peak: inout Float,
    sumSquares: inout Double,
    sampleCount: inout Int,
    audibleSampleCount: inout Int
  ) {
    for raw in values {
      accumulate(
        value: raw * scale,
        threshold: threshold,
        peak: &peak,
        sumSquares: &sumSquares,
        sampleCount: &sampleCount,
        audibleSampleCount: &audibleSampleCount
      )
    }
  }

  private static func accumulate(
    value: Float,
    threshold: Float,
    peak: inout Float,
    sumSquares: inout Double,
    sampleCount: inout Int,
    audibleSampleCount: inout Int
  ) {
    let magnitude = abs(value)
    peak = max(peak, magnitude)
    sumSquares += Double(value * value)
    sampleCount += 1
    if magnitude >= threshold { audibleSampleCount += 1 }
  }

  private static func maximumUnrecoveredGap(
    anchors: [TimingAnchorFile],
    effectiveSampleRate: Double
  ) -> Double? {
    guard anchors.count >= 2, effectiveSampleRate > 0 else { return nil }
    return zip(anchors, anchors.dropFirst()).reduce(0) { maximum, pair in
      let (first, second) = pair
      let wallSeconds = second.date.timeIntervalSince(first.date)
      let frameSeconds = Double(max(0, second.frame - first.frame)) / effectiveSampleRate
      return max(maximum, max(0, wallSeconds - frameSeconds))
    }
  }

  private static func trackURL(kind: AudioCaptureTrackKind, sessionDirectory: URL) -> URL {
    let fileName = kind == .microphone ? "mic.caf" : "sys.caf"
    let canonical = sessionDirectory.appendingPathComponent("audio", isDirectory: true)
      .appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: canonical.path) { return canonical }
    return sessionDirectory.appendingPathComponent(fileName)
  }

  private static func loadSessionTiming(from directory: URL) throws -> SessionTimingFile {
    let url = directory.appendingPathComponent("session.json")
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(SessionTimingFile.self, from: data)
    } catch {
      throw AudioCaptureVerificationError.sessionMetadataUnreadable(error.localizedDescription)
    }
  }

  private static func loadBatchMeta(from directory: URL) -> BatchMetaFile? {
    let canonical = directory.appendingPathComponent("audio", isDirectory: true)
      .appendingPathComponent("batch-meta.json")
    let legacy = directory.appendingPathComponent("batch-meta.json")
    let url = FileManager.default.fileExists(atPath: canonical.path) ? canonical : legacy
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(BatchMetaFile.self, from: data)
  }
}

private struct SessionTimingFile: Decodable {
  let id: String?
  let startedAt: Date
  let endedAt: Date?
  let meetingApp: String?
}

private struct BatchMetaFile: Decodable {
  let micAnchors: [TimingAnchorFile]
  let sysAnchors: [TimingAnchorFile]
  let sysEffectiveSampleRate: Double?
}

private struct TimingAnchorFile: Decodable {
  let frame: Int64
  let date: Date
}
