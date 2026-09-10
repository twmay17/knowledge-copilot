import AVFoundation
import XCTest

@testable import OpenOatsKit

final class AudioCaptureVerificationTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("AudioCaptureVerificationTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  func testCompleteTwoTrackSessionPasses() throws {
    let session = try makeSession(duration: 10)
    let anchors = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 240_000, date: session.startedAt.addingTimeInterval(5)),
      TestAnchor(frame: 480_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    try writeBatchMeta(micAnchors: anchors, sysAnchors: anchors, effectiveSystemRate: 48_000)
    try writeSineTrack(named: "mic.caf", duration: 10)
    try writeSineTrack(named: "sys.caf", duration: 10)

    let report = try AudioCaptureVerifier.verify(
      sessionDirectory: root,
      policy: policy,
      attestations: confirmedAttestations
    )

    XCTAssertTrue(report.passed, report.issues.joined(separator: "\n"))
    XCTAssertTrue(report.microphone.passed)
    XCTAssertTrue(report.system.passed)
    XCTAssertEqual(report.microphone.timingAnchorCount, 3)
    XCTAssertEqual(report.system.maximumUnrecoveredGapSeconds ?? -1, 0, accuracy: 0.001)
  }

  func testMissingSystemTrackFailsClosed() throws {
    let session = try makeSession(duration: 10)
    let anchors = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 480_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    try writeBatchMeta(micAnchors: anchors, sysAnchors: [], effectiveSystemRate: nil)
    try writeSineTrack(named: "mic.caf", duration: 10)

    let report = try AudioCaptureVerifier.verify(
      sessionDirectory: root,
      policy: policy,
      attestations: confirmedAttestations
    )

    XCTAssertFalse(report.passed)
    XCTAssertFalse(report.system.exists)
    XCTAssertTrue(report.issues.contains { $0.contains("Missing audio/sys.caf") })
  }

  func testPeriodicTimingAnchorsExposeUnrecoveredDropout() throws {
    let session = try makeSession(duration: 10)
    let healthy = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 240_000, date: session.startedAt.addingTimeInterval(5)),
      TestAnchor(frame: 480_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    let withDropout = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 240_000, date: session.startedAt.addingTimeInterval(5)),
      TestAnchor(frame: 288_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    try writeBatchMeta(
      micAnchors: healthy,
      sysAnchors: withDropout,
      effectiveSystemRate: 48_000
    )
    try writeSineTrack(named: "mic.caf", duration: 10)
    try writeSineTrack(named: "sys.caf", duration: 10)

    let report = try AudioCaptureVerifier.verify(
      sessionDirectory: root,
      policy: policy,
      attestations: confirmedAttestations
    )

    XCTAssertFalse(report.passed)
    XCTAssertEqual(report.system.maximumUnrecoveredGapSeconds ?? -1, 4, accuracy: 0.01)
    XCTAssertTrue(report.system.issues.contains { $0.contains("exceeds the allowed") })
  }

  func testHumanEvidenceMustBeExplicitlyAttested() throws {
    let session = try makeSession(duration: 10)
    let anchors = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 480_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    try writeBatchMeta(micAnchors: anchors, sysAnchors: anchors, effectiveSystemRate: 48_000)
    try writeSineTrack(named: "mic.caf", duration: 10)
    try writeSineTrack(named: "sys.caf", duration: 10)

    let report = try AudioCaptureVerifier.verify(
      sessionDirectory: root,
      policy: policy,
      attestations: AudioCaptureVerificationAttestations(
        teamsSessionConfirmed: false,
        participantConsentConfirmed: false,
        recordingIndicatorConfirmed: false
      )
    )

    XCTAssertFalse(report.passed)
    XCTAssertTrue(report.issues.contains { $0.contains("Participant consent") })
    XCTAssertTrue(report.issues.contains { $0.contains("recording indicator") })
  }

  func testAudioRecorderAddsPeriodicTimingAnchors() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let recorder = AudioRecorder(outputDirectory: root, now: { clock.value })
    recorder.startSession()
    let buffer = makeSineBuffer(frameCount: 480)

    recorder.writeMicBuffer(buffer)
    recorder.writeSysBuffer(buffer)
    clock.advance(by: 6)
    recorder.writeMicBuffer(buffer)
    recorder.writeSysBuffer(buffer)

    let anchors = recorder.timingAnchors()
    XCTAssertEqual(anchors.micAnchors.count, 3)
    XCTAssertEqual(anchors.sysAnchors.count, 3)
    XCTAssertEqual(anchors.micAnchors[1].frame, 480)
    XCTAssertEqual(anchors.sysAnchors[1].frame, 480)
    XCTAssertEqual(anchors.micAnchors[2].frame, 960)
    XCTAssertEqual(anchors.sysAnchors[2].frame, 960)

    clock.advance(by: 4)
    recorder.markCaptureStopRequested()
    clock.advance(by: 20)
    let terminalSnapshot = recorder.timingAnchors()
    XCTAssertEqual(terminalSnapshot.micAnchors.last?.frame, 960)
    XCTAssertEqual(
      terminalSnapshot.micAnchors.last?.date,
      Date(timeIntervalSince1970: 1_700_000_010)
    )
    XCTAssertEqual(terminalSnapshot.sysAnchors.last?.frame, 960)
    XCTAssertEqual(
      terminalSnapshot.sysAnchors.last?.date,
      Date(timeIntervalSince1970: 1_700_000_010)
    )
    recorder.discardRecording()
  }

  func testSparseMutedTrackCannotNormalizeMissingTimeIntoFullCoverage() throws {
    let session = try makeSession(duration: 10)
    let healthy = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 480_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    let muted = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 48_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    try writeBatchMeta(micAnchors: muted, sysAnchors: healthy, effectiveSystemRate: 48_000)
    try writeSineTrack(named: "mic.caf", duration: 1)
    try writeSineTrack(named: "sys.caf", duration: 10)
    let report = try AudioCaptureVerifier.verify(
      sessionDirectory: root, policy: policy, attestations: confirmedAttestations
    )
    XCTAssertFalse(report.passed)
    XCTAssertFalse(report.microphone.passed)
    XCTAssertEqual(report.microphone.effectiveSampleRate, 48_000)
    XCTAssertEqual(report.microphone.coverageRatio ?? -1, 0.1, accuracy: 0.001)
    XCTAssertEqual(report.microphone.maximumUnrecoveredGapSeconds ?? -1, 9, accuracy: 0.001)
  }

  func testUniformDropoutAcrossEveryIntervalCannotMasqueradeAsLowerRate() throws {
    let session = try makeSession(duration: 10)
    let anchors = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 48_000, date: session.startedAt.addingTimeInterval(5)),
      TestAnchor(frame: 96_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    try writeBatchMeta(micAnchors: anchors, sysAnchors: anchors, effectiveSystemRate: 9_600)
    try writeSineTrack(named: "mic.caf", duration: 2)
    try writeSineTrack(named: "sys.caf", duration: 2)
    let report = try AudioCaptureVerifier.verify(
      sessionDirectory: root, policy: policy, attestations: confirmedAttestations
    )
    XCTAssertFalse(report.microphone.passed)
    XCTAssertFalse(report.system.passed)
    XCTAssertEqual(report.system.coverageRatio ?? -1, 0.2, accuracy: 0.001)
    XCTAssertEqual(report.system.maximumUnrecoveredGapSeconds ?? -1, 4, accuracy: 0.001)
  }

  func testRoundedAnchorIntervalsDoNotChangeDeclaredFrameDuration() throws {
    let session = try makeSession(duration: 10)
    let anchors = [
      TestAnchor(frame: 0, date: session.startedAt),
      TestAnchor(frame: 244_800, date: session.startedAt.addingTimeInterval(5)),
      TestAnchor(frame: 480_000, date: session.startedAt.addingTimeInterval(10)),
    ]
    try writeBatchMeta(micAnchors: anchors, sysAnchors: anchors, effectiveSystemRate: 48_000)
    try writeSineTrack(named: "mic.caf", duration: 10)
    try writeSineTrack(named: "sys.caf", duration: 10)
    let report = try AudioCaptureVerifier.verify(
      sessionDirectory: root, policy: policy, attestations: confirmedAttestations
    )
    XCTAssertTrue(report.passed, report.issues.joined(separator: "\n"))
    XCTAssertEqual(report.microphone.effectiveSampleRate, 48_000)
    XCTAssertEqual(report.microphone.coverageRatio ?? -1, 1, accuracy: 0.001)
  }

  private var policy: AudioCaptureVerificationPolicy {
    AudioCaptureVerificationPolicy(
      minimumSessionDurationSeconds: 9.5,
      minimumTrackCoverageRatio: 0.95,
      maximumUnrecoveredGapSeconds: 1,
      minimumAudiblePeak: 0.01
    )
  }

  private var confirmedAttestations: AudioCaptureVerificationAttestations {
    AudioCaptureVerificationAttestations(
      teamsSessionConfirmed: true,
      participantConsentConfirmed: true,
      recordingIndicatorConfirmed: true,
      verifiedBy: "Test Operator"
    )
  }

  @discardableResult
  private func makeSession(duration: TimeInterval) throws -> TestSession {
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let session = TestSession(
      id: "session-teams-verification",
      startedAt: startedAt,
      endedAt: startedAt.addingTimeInterval(duration),
      meetingApp: "Microsoft Teams"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(session).write(
      to: root.appendingPathComponent("session.json"),
      options: .atomic
    )
    return session
  }

  private func writeBatchMeta(
    micAnchors: [TestAnchor],
    sysAnchors: [TestAnchor],
    effectiveSystemRate: Double?
  ) throws {
    let audioDirectory = root.appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    let fixture = TestBatchMeta(
      micStartDate: micAnchors.first?.date,
      sysStartDate: sysAnchors.first?.date,
      micAnchors: micAnchors,
      sysAnchors: sysAnchors,
      sysEffectiveSampleRate: effectiveSystemRate
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(fixture).write(
      to: audioDirectory.appendingPathComponent("batch-meta.json"),
      options: .atomic
    )
  }

  private func writeSineTrack(named name: String, duration: Double) throws {
    let audioDirectory = root.appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let file = try AVAudioFile(
      forWriting: audioDirectory.appendingPathComponent(name),
      settings: format.settings
    )
    let framesPerChunk: AVAudioFrameCount = 48_000
    for _ in 0..<Int(duration) {
      try file.write(from: makeSineBuffer(frameCount: framesPerChunk))
    }
  }

  private func makeSineBuffer(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
    let sampleRate = 48_000.0
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]
    for index in 0..<Int(frameCount) {
      samples[index] = sin(Float(index) / Float(sampleRate) * 440 * 2 * .pi) * 0.25
    }
    return buffer
  }
}

private struct TestSession: Codable {
  let id: String
  let startedAt: Date
  let endedAt: Date
  let meetingApp: String?
}

private struct TestBatchMeta: Codable {
  let micStartDate: Date?
  let sysStartDate: Date?
  let micAnchors: [TestAnchor]
  let sysAnchors: [TestAnchor]
  let sysEffectiveSampleRate: Double?
}

private struct TestAnchor: Codable {
  let frame: Int64
  let date: Date
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) {
    self.date = date
  }

  var value: Date {
    lock.withLock { date }
  }

  func advance(by seconds: TimeInterval) {
    lock.withLock { date = date.addingTimeInterval(seconds) }
  }
}
