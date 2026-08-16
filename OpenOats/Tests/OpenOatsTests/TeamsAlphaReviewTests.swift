import XCTest

@testable import OpenOatsKit

final class TeamsAlphaReviewTests: XCTestCase {
  func testSubmissionTemplateDecodesWithEveryObservationFailingClosed() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let template = try decoder.decode(
      TeamsAlphaReviewSubmission.self,
      from: Data(contentsOf: submissionTemplateURL())
    )

    XCTAssertFalse(template.attestations.participantConsentConfirmed)
    XCTAssertFalse(template.attestations.recordingIndicatorConfirmed)
    XCTAssertFalse(template.attestations.nonConfidentialScenarioConfirmed)
    XCTAssertFalse(template.attestations.shareSafePresentationConfirmed)
    XCTAssertFalse(template.attestations.adminFreePathConfirmed)
    XCTAssertFalse(template.checks.remoteSpeechTranscribed)
    XCTAssertFalse(template.checks.preparedQuestionDetectedAutomatically)
    XCTAssertFalse(template.checks.groundedAnswerDisplayed)
    XCTAssertFalse(template.checks.sourceOpened)
    XCTAssertFalse(template.checks.correctedQuestionReplacedOldCard)
    XCTAssertFalse(template.checks.sessionNotesSaved)
    XCTAssertFalse(template.checks.sessionFinalizedCleanly)
  }

  func testCompleteReviewProducesUnconditionalGo() throws {
    let report = try TeamsAlphaReviewEvaluator.evaluate(
      submission: submission(),
      audioReport: audioReport(),
      generatedAt: date(3_000)
    )

    XCTAssertEqual(report.decision, .go)
    XCTAssertTrue(report.passed)
    XCTAssertTrue(report.gates.allSatisfy(\.passed))
    XCTAssertTrue(report.blockingReasons.isEmpty)
    XCTAssertTrue(report.conditions.isEmpty)
    XCTAssertEqual(report.sessionDurationSeconds, 1_900)
  }

  func testFailedEndToEndCheckProducesNoGoWithNamedGate() throws {
    let checks = TeamsAlphaReviewChecks(
      remoteSpeechTranscribed: true,
      preparedQuestionDetectedAutomatically: true,
      groundedAnswerDisplayed: true,
      sourceOpened: true,
      correctedQuestionReplacedOldCard: false,
      sessionNotesSaved: true,
      sessionFinalizedCleanly: true
    )

    let report = try TeamsAlphaReviewEvaluator.evaluate(
      submission: submission(checks: checks),
      audioReport: audioReport()
    )

    XCTAssertEqual(report.decision, .noGo)
    XCTAssertFalse(report.passed)
    XCTAssertEqual(
      report.gates.first { $0.id == "correction_replacement" }?.passed,
      false
    )
    XCTAssertTrue(report.blockingReasons.contains { $0.contains("Correction replacement") })
  }

  func testUnresolvedCriticalOrHighIssueBlocksAlpha() throws {
    let issues = [
      TeamsAlphaIssue(
        id: "ALPHA-1",
        severity: .high,
        title: "Old card remained visible",
        detail: "The prior card survived corrected speech.",
        disposition: .backlogged,
        resolutionNote: "Tracked for the next build."
      )
    ]

    let report = try TeamsAlphaReviewEvaluator.evaluate(
      submission: submission(issues: issues),
      audioReport: audioReport()
    )

    XCTAssertEqual(report.decision, .noGo)
    XCTAssertTrue(report.blockingReasons.contains { $0.contains("ALPHA-1") })
    XCTAssertEqual(report.issueCounts.first { $0.severity == .high }?.unresolved, 1)
  }

  func testUnresolvedMediumIssueProducesConditionalGo() throws {
    let issues = [
      TeamsAlphaIssue(
        id: "ALPHA-2",
        severity: .medium,
        title: "Source window opened slowly",
        detail: "The source took several seconds to appear.",
        disposition: .backlogged,
        resolutionNote: "Backlogged for source-navigation tuning."
      )
    ]

    let report = try TeamsAlphaReviewEvaluator.evaluate(
      submission: submission(issues: issues),
      audioReport: audioReport()
    )

    XCTAssertEqual(report.decision, .conditionalGo)
    XCTAssertFalse(report.passed)
    XCTAssertTrue(report.blockingReasons.isEmpty)
    XCTAssertEqual(report.conditions.count, 1)
  }

  func testFixedHighAndOpenLowIssuesDoNotBlockGo() throws {
    let issues = [
      TeamsAlphaIssue(
        id: "ALPHA-3",
        severity: .high,
        title: "Overlay hid after correction",
        detail: "The overlay briefly closed.",
        disposition: .fixed,
        resolutionNote: "Fixed and replayed successfully."
      ),
      TeamsAlphaIssue(
        id: "ALPHA-4",
        severity: .low,
        title: "Copy could be shorter",
        detail: "The answer wording was longer than preferred.",
        disposition: .open
      ),
    ]

    let report = try TeamsAlphaReviewEvaluator.evaluate(
      submission: submission(issues: issues),
      audioReport: audioReport()
    )

    XCTAssertEqual(report.decision, .go)
    XCTAssertTrue(report.passed)
    XCTAssertEqual(report.issueCounts.first { $0.severity == .high }?.unresolved, 0)
    XCTAssertEqual(report.issueCounts.first { $0.severity == .low }?.unresolved, 1)
  }

  func testFailedStrictAudioReportBlocksAlpha() throws {
    let report = try TeamsAlphaReviewEvaluator.evaluate(
      submission: submission(),
      audioReport: audioReport(passed: false)
    )

    XCTAssertEqual(report.decision, .noGo)
    XCTAssertEqual(report.audioVerificationPassed, false)
    XCTAssertTrue(report.blockingReasons.contains { $0.contains("Audio capture verification") })
  }

  func testMismatchedAudioSessionFailsClosed() {
    XCTAssertThrowsError(
      try TeamsAlphaReviewEvaluator.evaluate(
        submission: submission(audioSessionID: "session-other"),
        audioReport: audioReport()
      )
    ) { error in
      XCTAssertEqual(
        error as? TeamsAlphaReviewError,
        .audioSessionMismatch(expected: "session-other", actual: "session-test")
      )
    }
  }

  func testMismatchedAudioSessionWindowFailsClosed() {
    let shiftedSubmission = TeamsAlphaReviewSubmission(
      testRunID: "teams-alpha-2026-08-16-shifted",
      testedCommit: "b4f7ffe6cb60caeb66f419571624934b651d2a21",
      knowledgePackID: "synthetic-hotel-2020-v1",
      audioSessionID: "session-test",
      startedAt: date(1_001),
      endedAt: date(2_901),
      attestations: passingAttestations(),
      checks: passingChecks(),
      issues: []
    )

    XCTAssertThrowsError(
      try TeamsAlphaReviewEvaluator.evaluate(
        submission: shiftedSubmission,
        audioReport: audioReport()
      )
    ) { error in
      XCTAssertEqual(error as? TeamsAlphaReviewError, .audioSessionWindowMismatch)
    }
  }

  func testDuplicateIssueIDsAndMissingResolutionNotesAreRejected() {
    let duplicate = TeamsAlphaIssue(
      id: "ALPHA-5",
      severity: .low,
      title: "Minor issue",
      detail: "Synthetic detail.",
      disposition: .open
    )
    XCTAssertThrowsError(
      try TeamsAlphaReviewEvaluator.evaluate(
        submission: submission(issues: [duplicate, duplicate]),
        audioReport: audioReport()
      )
    ) { error in
      XCTAssertEqual(error as? TeamsAlphaReviewError, .duplicateIssueID("ALPHA-5"))
    }

    let unresolved = TeamsAlphaIssue(
      id: "ALPHA-6",
      severity: .medium,
      title: "Backlogged issue",
      detail: "Synthetic detail.",
      disposition: .backlogged
    )
    XCTAssertThrowsError(
      try TeamsAlphaReviewEvaluator.evaluate(
        submission: submission(issues: [unresolved]),
        audioReport: audioReport()
      )
    ) { error in
      XCTAssertEqual(error as? TeamsAlphaReviewError, .invalidIssue("ALPHA-6"))
    }
  }

  func testPublicReportOmitsOperatorNotesAndAudioSessionID() throws {
    let report = try TeamsAlphaReviewEvaluator.evaluate(
      submission: submission(
        audioSessionID: "session-private",
        operatorNotes: "Private participant and tenant details"
      ),
      audioReport: audioReport(sessionID: "session-private")
    )
    let encoder = JSONEncoder()
    let encoded = try XCTUnwrap(String(data: encoder.encode(report), encoding: .utf8))

    XCTAssertFalse(encoded.contains("Private participant"))
    XCTAssertFalse(encoded.contains("session-private"))
  }

  private func submission(
    audioSessionID: String = "session-test",
    checks: TeamsAlphaReviewChecks? = nil,
    issues: [TeamsAlphaIssue] = [],
    operatorNotes: String? = nil
  ) -> TeamsAlphaReviewSubmission {
    TeamsAlphaReviewSubmission(
      testRunID: "teams-alpha-2026-08-16-01",
      testedCommit: "b4f7ffe6cb60caeb66f419571624934b651d2a21",
      knowledgePackID: "synthetic-hotel-2020-v1",
      audioSessionID: audioSessionID,
      startedAt: date(1_000),
      endedAt: date(2_900),
      attestations: passingAttestations(),
      checks: checks ?? passingChecks(),
      issues: issues,
      operatorNotes: operatorNotes
    )
  }

  private func passingAttestations() -> TeamsAlphaReviewAttestations {
    TeamsAlphaReviewAttestations(
      participantConsentConfirmed: true,
      recordingIndicatorConfirmed: true,
      nonConfidentialScenarioConfirmed: true,
      shareSafePresentationConfirmed: true,
      adminFreePathConfirmed: true
    )
  }

  private func passingChecks() -> TeamsAlphaReviewChecks {
    TeamsAlphaReviewChecks(
      remoteSpeechTranscribed: true,
      preparedQuestionDetectedAutomatically: true,
      groundedAnswerDisplayed: true,
      sourceOpened: true,
      correctedQuestionReplacedOldCard: true,
      sessionNotesSaved: true,
      sessionFinalizedCleanly: true
    )
  }

  private func audioReport(
    sessionID: String = "session-test",
    passed: Bool = true
  ) -> AudioCaptureVerificationReport {
    let track = AudioCaptureTrackVerification(
      kind: .microphone,
      relativePath: "audio/mic.caf",
      exists: true,
      declaredSampleRate: 48_000,
      effectiveSampleRate: 48_000,
      channelCount: 1,
      frameCount: 91_200_000,
      durationSeconds: 1_900,
      coverageRatio: 1,
      peakAmplitude: 0.5,
      rmsAmplitude: 0.1,
      audibleSampleRatio: 0.1,
      timingAnchorCount: 380,
      maximumUnrecoveredGapSeconds: 0.1,
      issues: passed ? [] : ["Synthetic failure"],
      passed: passed
    )
    let system = AudioCaptureTrackVerification(
      kind: .system,
      relativePath: "audio/sys.caf",
      exists: true,
      declaredSampleRate: 48_000,
      effectiveSampleRate: 48_000,
      channelCount: 1,
      frameCount: 91_200_000,
      durationSeconds: 1_900,
      coverageRatio: 1,
      peakAmplitude: 0.5,
      rmsAmplitude: 0.1,
      audibleSampleRatio: 0.1,
      timingAnchorCount: 380,
      maximumUnrecoveredGapSeconds: 0.1,
      issues: passed ? [] : ["Synthetic failure"],
      passed: passed
    )
    return AudioCaptureVerificationReport(
      generatedAt: date(2_901),
      sessionID: sessionID,
      meetingApp: "Microsoft Teams",
      startedAt: date(1_000),
      endedAt: date(2_900),
      sessionDurationSeconds: 1_900,
      policy: AudioCaptureVerificationPolicy(),
      attestations: AudioCaptureVerificationAttestations(
        teamsSessionConfirmed: true,
        participantConsentConfirmed: true,
        recordingIndicatorConfirmed: true,
        verifiedBy: "Synthetic test"
      ),
      microphone: track,
      system: system,
      issues: passed ? [] : ["Synthetic failure"],
      passed: passed
    )
  }

  private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
  }

  private func submissionTemplateURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/teams-alpha-review/submission-template.json")
  }
}
