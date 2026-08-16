import Foundation

public enum TeamsAlphaIssueSeverity: String, CaseIterable, Codable, Equatable, Sendable {
  case critical
  case high
  case medium
  case low

  fileprivate var rank: Int {
    switch self {
    case .critical: 4
    case .high: 3
    case .medium: 2
    case .low: 1
    }
  }
}

public enum TeamsAlphaIssueDisposition: String, Codable, Equatable, Sendable {
  case open
  case fixed
  case backlogged

  fileprivate var isUnresolved: Bool { self != .fixed }
}

public struct TeamsAlphaIssue: Codable, Equatable, Sendable {
  public let id: String
  public let severity: TeamsAlphaIssueSeverity
  public let title: String
  public let detail: String
  public let disposition: TeamsAlphaIssueDisposition
  public let resolutionNote: String?

  public init(
    id: String,
    severity: TeamsAlphaIssueSeverity,
    title: String,
    detail: String,
    disposition: TeamsAlphaIssueDisposition,
    resolutionNote: String? = nil
  ) {
    self.id = id
    self.severity = severity
    self.title = title
    self.detail = detail
    self.disposition = disposition
    self.resolutionNote = resolutionNote
  }
}

public struct TeamsAlphaReviewAttestations: Codable, Equatable, Sendable {
  public let participantConsentConfirmed: Bool
  public let recordingIndicatorConfirmed: Bool
  public let nonConfidentialScenarioConfirmed: Bool
  public let shareSafePresentationConfirmed: Bool
  public let adminFreePathConfirmed: Bool

  public init(
    participantConsentConfirmed: Bool,
    recordingIndicatorConfirmed: Bool,
    nonConfidentialScenarioConfirmed: Bool,
    shareSafePresentationConfirmed: Bool,
    adminFreePathConfirmed: Bool
  ) {
    self.participantConsentConfirmed = participantConsentConfirmed
    self.recordingIndicatorConfirmed = recordingIndicatorConfirmed
    self.nonConfidentialScenarioConfirmed = nonConfidentialScenarioConfirmed
    self.shareSafePresentationConfirmed = shareSafePresentationConfirmed
    self.adminFreePathConfirmed = adminFreePathConfirmed
  }
}

public struct TeamsAlphaReviewChecks: Codable, Equatable, Sendable {
  public let remoteSpeechTranscribed: Bool
  public let preparedQuestionDetectedAutomatically: Bool
  public let groundedAnswerDisplayed: Bool
  public let sourceOpened: Bool
  public let correctedQuestionReplacedOldCard: Bool
  public let sessionNotesSaved: Bool
  public let sessionFinalizedCleanly: Bool

  public init(
    remoteSpeechTranscribed: Bool,
    preparedQuestionDetectedAutomatically: Bool,
    groundedAnswerDisplayed: Bool,
    sourceOpened: Bool,
    correctedQuestionReplacedOldCard: Bool,
    sessionNotesSaved: Bool,
    sessionFinalizedCleanly: Bool
  ) {
    self.remoteSpeechTranscribed = remoteSpeechTranscribed
    self.preparedQuestionDetectedAutomatically = preparedQuestionDetectedAutomatically
    self.groundedAnswerDisplayed = groundedAnswerDisplayed
    self.sourceOpened = sourceOpened
    self.correctedQuestionReplacedOldCard = correctedQuestionReplacedOldCard
    self.sessionNotesSaved = sessionNotesSaved
    self.sessionFinalizedCleanly = sessionFinalizedCleanly
  }
}

public struct TeamsAlphaReviewSubmission: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let testRunID: String
  public let testedCommit: String
  public let knowledgePackID: String
  public let audioSessionID: String
  public let startedAt: Date
  public let endedAt: Date
  public let attestations: TeamsAlphaReviewAttestations
  public let checks: TeamsAlphaReviewChecks
  public let issues: [TeamsAlphaIssue]
  public let operatorNotes: String?

  public init(
    schemaVersion: String = TeamsAlphaReviewSubmission.currentSchemaVersion,
    testRunID: String,
    testedCommit: String,
    knowledgePackID: String,
    audioSessionID: String,
    startedAt: Date,
    endedAt: Date,
    attestations: TeamsAlphaReviewAttestations,
    checks: TeamsAlphaReviewChecks,
    issues: [TeamsAlphaIssue],
    operatorNotes: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.testRunID = testRunID
    self.testedCommit = testedCommit
    self.knowledgePackID = knowledgePackID
    self.audioSessionID = audioSessionID
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.attestations = attestations
    self.checks = checks
    self.issues = issues
    self.operatorNotes = operatorNotes
  }
}

public enum TeamsAlphaGateDecision: String, Codable, Equatable, Sendable {
  case go
  case conditionalGo = "conditional_go"
  case noGo = "no_go"
}

public struct TeamsAlphaReviewGate: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let passed: Bool
  public let detail: String
}

public struct TeamsAlphaIssueCount: Codable, Equatable, Sendable {
  public let severity: TeamsAlphaIssueSeverity
  public let total: Int
  public let unresolved: Int
}

public struct TeamsAlphaReviewReport: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let generatedAt: Date
  public let testRunID: String
  public let testedCommit: String
  public let knowledgePackID: String
  public let sessionDurationSeconds: Double
  public let audioVerificationPassed: Bool
  public let gates: [TeamsAlphaReviewGate]
  public let issues: [TeamsAlphaIssue]
  public let issueCounts: [TeamsAlphaIssueCount]
  public let blockingReasons: [String]
  public let conditions: [String]
  public let decision: TeamsAlphaGateDecision

  public var passed: Bool { decision == .go }

  public var textSummary: String {
    var lines = ["Teams alpha review: \(decision.rawValue.uppercased())"]
    lines.append("Run: \(testRunID)")
    lines.append("Commit: \(testedCommit)")
    lines.append("KnowledgePack: \(knowledgePackID)")
    lines.append(
      "Required gates: \(gates.filter(\.passed).count)/\(gates.count) passed"
    )
    let issueSummary = issueCounts.map {
      "\($0.severity.rawValue) \($0.unresolved)/\($0.total) unresolved"
    }.joined(separator: "; ")
    lines.append("Issues: \(issueSummary)")
    if !blockingReasons.isEmpty {
      lines.append("Blocking reasons:")
      lines.append(contentsOf: blockingReasons.map { "- \($0)" })
    }
    if !conditions.isEmpty {
      lines.append("Conditions:")
      lines.append(contentsOf: conditions.map { "- \($0)" })
    }
    return lines.joined(separator: "\n")
  }
}

public enum TeamsAlphaReviewError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(String)
  case invalidTestRunID
  case invalidTestedCommit
  case blankKnowledgePackID
  case blankAudioSessionID
  case invalidSessionWindow
  case audioSessionMismatch(expected: String, actual: String?)
  case audioSessionWindowMismatch
  case duplicateIssueID(String)
  case invalidIssue(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      "Unsupported Teams alpha review schema version: \(version)"
    case .invalidTestRunID:
      "testRunID must be 3-80 characters using only letters, numbers, periods, underscores, or hyphens."
    case .invalidTestedCommit:
      "testedCommit must be a full 40-character Git SHA."
    case .blankKnowledgePackID:
      "knowledgePackID must not be blank."
    case .blankAudioSessionID:
      "audioSessionID must not be blank."
    case .invalidSessionWindow:
      "endedAt must be later than startedAt."
    case .audioSessionMismatch(let expected, let actual):
      "The alpha submission references audio session '\(expected)', but the audio report references '\(actual ?? "none")'."
    case .audioSessionWindowMismatch:
      "The alpha submission session window does not match the strict audio report."
    case .duplicateIssueID(let id):
      "Issue ID '\(id)' is duplicated."
    case .invalidIssue(let id):
      "Issue '\(id)' must have an ID, title, detail, and a resolution note when fixed or backlogged."
    }
  }
}

public enum TeamsAlphaReviewEvaluator {
  public static func evaluate(
    submission: TeamsAlphaReviewSubmission,
    audioReport: AudioCaptureVerificationReport,
    generatedAt: Date = Date()
  ) throws -> TeamsAlphaReviewReport {
    try validate(submission, audioReport: audioReport)

    let gates = makeGates(submission: submission, audioReport: audioReport)
    let sortedIssues = submission.issues.sorted {
      if $0.severity.rank != $1.severity.rank {
        return $0.severity.rank > $1.severity.rank
      }
      return $0.id < $1.id
    }
    let issueCounts = TeamsAlphaIssueSeverity.allCases.map { severity in
      let matching = sortedIssues.filter { $0.severity == severity }
      return TeamsAlphaIssueCount(
        severity: severity,
        total: matching.count,
        unresolved: matching.filter { $0.disposition.isUnresolved }.count
      )
    }
    let failedGates = gates.filter { !$0.passed }
    let blockingIssues = sortedIssues.filter {
      $0.disposition.isUnresolved && ($0.severity == .critical || $0.severity == .high)
    }
    let conditionalIssues = sortedIssues.filter {
      $0.disposition.isUnresolved && $0.severity == .medium
    }
    let blockingReasons =
      failedGates.map { "\($0.title): \($0.detail)" }
      + blockingIssues.map {
        "\($0.severity.rawValue.capitalized) issue \($0.id): \($0.title)"
      }
    let conditions = conditionalIssues.map {
      "Resolve or explicitly review medium issue \($0.id): \($0.title)"
    }
    let decision: TeamsAlphaGateDecision =
      if !blockingReasons.isEmpty {
        .noGo
      } else if !conditions.isEmpty {
        .conditionalGo
      } else {
        .go
      }

    return TeamsAlphaReviewReport(
      schemaVersion: TeamsAlphaReviewSubmission.currentSchemaVersion,
      generatedAt: generatedAt,
      testRunID: submission.testRunID,
      testedCommit: submission.testedCommit.lowercased(),
      knowledgePackID: submission.knowledgePackID,
      sessionDurationSeconds: submission.endedAt.timeIntervalSince(submission.startedAt),
      audioVerificationPassed: audioReport.passed,
      gates: gates,
      issues: sortedIssues,
      issueCounts: issueCounts,
      blockingReasons: blockingReasons,
      conditions: conditions,
      decision: decision
    )
  }

  private static func validate(
    _ submission: TeamsAlphaReviewSubmission,
    audioReport: AudioCaptureVerificationReport
  ) throws {
    guard submission.schemaVersion == TeamsAlphaReviewSubmission.currentSchemaVersion else {
      throw TeamsAlphaReviewError.unsupportedSchemaVersion(submission.schemaVersion)
    }
    guard
      submission.testRunID.range(
        of: "^[A-Za-z0-9._-]{3,80}$",
        options: .regularExpression
      ) != nil
    else { throw TeamsAlphaReviewError.invalidTestRunID }
    guard
      submission.testedCommit.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil
    else { throw TeamsAlphaReviewError.invalidTestedCommit }
    guard !submission.knowledgePackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TeamsAlphaReviewError.blankKnowledgePackID }
    guard !submission.audioSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TeamsAlphaReviewError.blankAudioSessionID }
    guard submission.endedAt > submission.startedAt else {
      throw TeamsAlphaReviewError.invalidSessionWindow
    }
    guard audioReport.sessionID == submission.audioSessionID else {
      throw TeamsAlphaReviewError.audioSessionMismatch(
        expected: submission.audioSessionID,
        actual: audioReport.sessionID
      )
    }
    guard
      let audioStartedAt = audioReport.startedAt,
      let audioEndedAt = audioReport.endedAt,
      abs(audioStartedAt.timeIntervalSince(submission.startedAt)) < 1,
      abs(audioEndedAt.timeIntervalSince(submission.endedAt)) < 1
    else {
      throw TeamsAlphaReviewError.audioSessionWindowMismatch
    }

    var issueIDs: Set<String> = []
    for issue in submission.issues {
      guard issueIDs.insert(issue.id).inserted else {
        throw TeamsAlphaReviewError.duplicateIssueID(issue.id)
      }
      let requiredValues = [issue.id, issue.title, issue.detail]
      let hasRequiredValues = requiredValues.allSatisfy {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      let needsResolution = issue.disposition != .open
      let hasResolution =
        !(issue.resolutionNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      guard hasRequiredValues, !needsResolution || hasResolution else {
        throw TeamsAlphaReviewError.invalidIssue(issue.id)
      }
    }
  }

  private static func makeGates(
    submission: TeamsAlphaReviewSubmission,
    audioReport: AudioCaptureVerificationReport
  ) -> [TeamsAlphaReviewGate] {
    let teamsConfirmed =
      audioReport.attestations.teamsSessionConfirmed
      || (audioReport.meetingApp?.localizedCaseInsensitiveContains("teams") ?? false)
    return [
      gate(
        id: "audio_capture",
        title: "Audio capture verification",
        passed: audioReport.passed,
        failure: "The strict microphone/system-audio verification report did not pass."
      ),
      gate(
        id: "teams_session",
        title: "Real Teams session",
        passed: teamsConfirmed,
        failure: "The audio evidence does not identify or attest a Microsoft Teams session."
      ),
      gate(
        id: "participant_consent",
        title: "Participant consent",
        passed: submission.attestations.participantConsentConfirmed
          && audioReport.attestations.participantConsentConfirmed,
        failure: "Participant consent was not confirmed in both evidence records."
      ),
      gate(
        id: "recording_indicator",
        title: "Visible recording indicator",
        passed: submission.attestations.recordingIndicatorConfirmed
          && audioReport.attestations.recordingIndicatorConfirmed,
        failure: "The OpenOats recording indicator was not confirmed in both evidence records."
      ),
      gate(
        id: "non_confidential_scenario",
        title: "Non-confidential test scenario",
        passed: submission.attestations.nonConfidentialScenarioConfirmed,
        failure: "The operator did not confirm a synthetic or non-confidential test scenario."
      ),
      gate(
        id: "share_safe_presentation",
        title: "Share-safe presentation",
        passed: submission.attestations.shareSafePresentationConfirmed,
        failure: "Private-overlay or screen-share-safe presentation was not confirmed."
      ),
      gate(
        id: "admin_free_path",
        title: "No-admin Microsoft path",
        passed: submission.attestations.adminFreePathConfirmed,
        failure:
          "The operator did not confirm that the test required no Microsoft 365 admin action."
      ),
      gate(
        id: "remote_transcription",
        title: "Remote speech transcription",
        passed: submission.checks.remoteSpeechTranscribed,
        failure: "Remote Teams speech was not observed in the live transcript."
      ),
      gate(
        id: "automatic_question_detection",
        title: "Automatic question detection",
        passed: submission.checks.preparedQuestionDetectedAutomatically,
        failure: "A prepared question was not detected automatically from remote speech."
      ),
      gate(
        id: "grounded_answer",
        title: "Grounded answer display",
        passed: submission.checks.groundedAnswerDisplayed,
        failure: "A corpus-grounded answer card was not displayed."
      ),
      gate(
        id: "source_inspection",
        title: "Source inspection",
        passed: submission.checks.sourceOpened,
        failure: "The answer's cited source was not opened successfully."
      ),
      gate(
        id: "correction_replacement",
        title: "Correction replacement",
        passed: submission.checks.correctedQuestionReplacedOldCard,
        failure: "Corrected speech did not replace the old answer card."
      ),
      gate(
        id: "session_notes",
        title: "Session notes saved",
        passed: submission.checks.sessionNotesSaved,
        failure: "The session transcript/notes artifact was not saved."
      ),
      gate(
        id: "clean_finalization",
        title: "Clean session finalization",
        passed: submission.checks.sessionFinalizedCleanly,
        failure: "The application did not stop and finalize the session cleanly."
      ),
    ]
  }

  private static func gate(
    id: String,
    title: String,
    passed: Bool,
    failure: String
  ) -> TeamsAlphaReviewGate {
    TeamsAlphaReviewGate(
      id: id,
      title: title,
      passed: passed,
      detail: passed ? "Confirmed." : failure
    )
  }
}
