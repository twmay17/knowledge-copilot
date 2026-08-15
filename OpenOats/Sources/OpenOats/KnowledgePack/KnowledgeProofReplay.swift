import Foundation

public struct KnowledgeProofReplaySpec: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let name: String
  public let streamID: String
  public let responseDeadlineMilliseconds: Int
  public let maximumProcessingLatencyMilliseconds: Double
  public let requireAnswerBeforeFinal: Bool
  public let revisions: [KnowledgeProofReplayRevision]
  public let expected: KnowledgeProofReplayExpectation

  public init(
    schemaVersion: Int = currentSchemaVersion,
    name: String,
    streamID: String,
    responseDeadlineMilliseconds: Int,
    maximumProcessingLatencyMilliseconds: Double,
    requireAnswerBeforeFinal: Bool,
    revisions: [KnowledgeProofReplayRevision],
    expected: KnowledgeProofReplayExpectation
  ) {
    self.schemaVersion = schemaVersion
    self.name = name
    self.streamID = streamID
    self.responseDeadlineMilliseconds = responseDeadlineMilliseconds
    self.maximumProcessingLatencyMilliseconds = maximumProcessingLatencyMilliseconds
    self.requireAnswerBeforeFinal = requireAnswerBeforeFinal
    self.revisions = revisions
    self.expected = expected
  }
}

public struct KnowledgeProofReplayRevision: Codable, Equatable, Sendable {
  public enum Stability: String, Codable, Equatable, Sendable {
    case partial
    case final
  }

  public let atMilliseconds: Int
  public let text: String
  public let stability: Stability

  public init(atMilliseconds: Int, text: String, stability: Stability) {
    self.atMilliseconds = atMilliseconds
    self.text = text
    self.stability = stability
  }
}

public struct KnowledgeProofReplayExpectation: Codable, Equatable, Sendable {
  public let questionFamilyID: String
  public let responseCardID: String
  public let evidenceState: KnowledgeEvidenceState
  public let answerContains: [String]
  public let citationPassageIDs: [String]

  public init(
    questionFamilyID: String,
    responseCardID: String,
    evidenceState: KnowledgeEvidenceState,
    answerContains: [String],
    citationPassageIDs: [String]
  ) {
    self.questionFamilyID = questionFamilyID
    self.responseCardID = responseCardID
    self.evidenceState = evidenceState
    self.answerContains = answerContains
    self.citationPassageIDs = citationPassageIDs
  }
}

public enum KnowledgeProofReplayValidationError: Error, Equatable, CustomStringConvertible {
  case unsupportedSchema(Int)
  case emptyName
  case emptyStreamID
  case invalidDeadline
  case invalidLatencyBudget
  case tooFewRevisions
  case negativeRevisionTime(index: Int)
  case outOfOrderRevision(index: Int)
  case missingFinalRevision

  public var description: String {
    switch self {
    case .unsupportedSchema(let version):
      "Replay schema \(version) is unsupported; expected \(KnowledgeProofReplaySpec.currentSchemaVersion)."
    case .emptyName:
      "Replay name must not be empty."
    case .emptyStreamID:
      "Replay stream ID must not be empty."
    case .invalidDeadline:
      "Response deadline must be greater than zero."
    case .invalidLatencyBudget:
      "Maximum processing latency must be greater than zero."
    case .tooFewRevisions:
      "Replay requires at least two transcript revisions."
    case .negativeRevisionTime(let index):
      "Replay revision \(index + 1) has a negative timestamp."
    case .outOfOrderRevision(let index):
      "Replay revision \(index + 1) occurs before the previous revision."
    case .missingFinalRevision:
      "Replay requires at least one final transcript revision."
    }
  }
}

public enum KnowledgeProofVerdict: String, Codable, Equatable, Sendable {
  case pass = "PASS"
  case fail = "FAIL"
}

public struct KnowledgeProofCheck: Codable, Equatable, Sendable, Identifiable {
  public let name: String
  public let passed: Bool
  public let detail: String

  public var id: String { name }

  public init(name: String, passed: Bool, detail: String) {
    self.name = name
    self.passed = passed
    self.detail = detail
  }
}

public struct KnowledgeProofLatencySummary: Codable, Equatable, Sendable {
  public let sampleCount: Int
  public let medianMilliseconds: Double
  public let p95Milliseconds: Double
  public let maximumMilliseconds: Double

  public init(
    sampleCount: Int,
    medianMilliseconds: Double,
    p95Milliseconds: Double,
    maximumMilliseconds: Double
  ) {
    self.sampleCount = sampleCount
    self.medianMilliseconds = medianMilliseconds
    self.p95Milliseconds = p95Milliseconds
    self.maximumMilliseconds = maximumMilliseconds
  }
}

public struct KnowledgeProofRevisionResult: Codable, Equatable, Sendable {
  public let sequence: Int
  public let atMilliseconds: Int
  public let stability: KnowledgeProofReplayRevision.Stability
  public let text: String
  public let processingLatencyMilliseconds: Double
  public let emittedEvents: [String]
  public let activeCandidateID: String?
  public let activeCandidateStatus: QuestionCandidateStatus?
  public let activeQuestionFamilyID: String?
  public let activeResponseCardID: String?
  public let activeEvidenceState: KnowledgeEvidenceState?

  public init(
    sequence: Int,
    atMilliseconds: Int,
    stability: KnowledgeProofReplayRevision.Stability,
    text: String,
    processingLatencyMilliseconds: Double,
    emittedEvents: [String],
    activeCandidateID: String?,
    activeCandidateStatus: QuestionCandidateStatus?,
    activeQuestionFamilyID: String?,
    activeResponseCardID: String?,
    activeEvidenceState: KnowledgeEvidenceState?
  ) {
    self.sequence = sequence
    self.atMilliseconds = atMilliseconds
    self.stability = stability
    self.text = text
    self.processingLatencyMilliseconds = processingLatencyMilliseconds
    self.emittedEvents = emittedEvents
    self.activeCandidateID = activeCandidateID
    self.activeCandidateStatus = activeCandidateStatus
    self.activeQuestionFamilyID = activeQuestionFamilyID
    self.activeResponseCardID = activeResponseCardID
    self.activeEvidenceState = activeEvidenceState
  }
}

public struct KnowledgeProofCitationResult: Codable, Equatable, Sendable, Identifiable {
  public let passageID: String
  public let sourceID: String
  public let sourceTitle: String
  public let relativePath: String
  public let locatorLabel: String
  public let exists: Bool
  public let insidePack: Bool

  public var id: String { passageID }

  public init(
    passageID: String,
    sourceID: String,
    sourceTitle: String,
    relativePath: String,
    locatorLabel: String,
    exists: Bool,
    insidePack: Bool
  ) {
    self.passageID = passageID
    self.sourceID = sourceID
    self.sourceTitle = sourceTitle
    self.relativePath = relativePath
    self.locatorLabel = locatorLabel
    self.exists = exists
    self.insidePack = insidePack
  }
}

public struct KnowledgeProofReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let replayName: String
  public let packID: String
  public let packTitle: String
  public let verdict: KnowledgeProofVerdict
  public let responseDeadlineMilliseconds: Int
  public let answerTriggeredAtMilliseconds: Int?
  public let answerAppearedAtMilliseconds: Double?
  public let finalSpeechAtMilliseconds: Int
  public let deadlineHeadroomMilliseconds: Double?
  public let answerLeadBeforeFinalMilliseconds: Double?
  public let latency: KnowledgeProofLatencySummary
  public let checks: [KnowledgeProofCheck]
  public let revisions: [KnowledgeProofRevisionResult]
  public let citations: [KnowledgeProofCitationResult]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    replayName: String,
    packID: String,
    packTitle: String,
    verdict: KnowledgeProofVerdict,
    responseDeadlineMilliseconds: Int,
    answerTriggeredAtMilliseconds: Int?,
    answerAppearedAtMilliseconds: Double?,
    finalSpeechAtMilliseconds: Int,
    deadlineHeadroomMilliseconds: Double?,
    answerLeadBeforeFinalMilliseconds: Double?,
    latency: KnowledgeProofLatencySummary,
    checks: [KnowledgeProofCheck],
    revisions: [KnowledgeProofRevisionResult],
    citations: [KnowledgeProofCitationResult]
  ) {
    self.schemaVersion = schemaVersion
    self.replayName = replayName
    self.packID = packID
    self.packTitle = packTitle
    self.verdict = verdict
    self.responseDeadlineMilliseconds = responseDeadlineMilliseconds
    self.answerTriggeredAtMilliseconds = answerTriggeredAtMilliseconds
    self.answerAppearedAtMilliseconds = answerAppearedAtMilliseconds
    self.finalSpeechAtMilliseconds = finalSpeechAtMilliseconds
    self.deadlineHeadroomMilliseconds = deadlineHeadroomMilliseconds
    self.answerLeadBeforeFinalMilliseconds = answerLeadBeforeFinalMilliseconds
    self.latency = latency
    self.checks = checks
    self.revisions = revisions
    self.citations = citations
  }
}

public struct KnowledgeProofReplayRunner: Sendable {
  private let pack: KnowledgePack
  private let rootDirectory: URL
  private let termAliases: [KnowledgeTermAlias]

  public init(
    pack: KnowledgePack,
    rootDirectory: URL,
    termAliases: [KnowledgeTermAlias] = []
  ) {
    self.pack = pack
    self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
    self.termAliases = termAliases
  }

  public func run(_ spec: KnowledgeProofReplaySpec) throws -> KnowledgeProofReport {
    try validate(spec)

    var detector = QuestionCandidateDetector(
      questionFamilies: pack.questionFamilies,
      termAliases: termAliases
    )
    let resolver = KnowledgeAnswerCardResolver(pack: pack, rootDirectory: rootDirectory)
    var activeCandidate: QuestionCandidate?
    var activeAnswer: KnowledgeAnswerCard?
    var answerTriggeredAt: Int?
    var answerAppearedAt: Double?
    var firstAnswerCandidate: QuestionCandidate?
    var firstAnswer: KnowledgeAnswerCard?
    var revisionResults: [KnowledgeProofRevisionResult] = []
    var latencySamples: [Double] = []

    for (index, input) in spec.revisions.enumerated() {
      let start = ContinuousClock.now
      let revision = TranscriptRevision(
        streamID: spec.streamID,
        sequence: index + 1,
        text: input.text,
        stability: input.stability == .final ? .final : .partial
      )
      let events = detector.process(revision)
      for event in events {
        switch event {
        case .upsert(let candidate):
          activeCandidate = candidate
          activeAnswer = resolver.resolve(candidate)
        case .cancel(let cancellation):
          if activeCandidate?.id == cancellation.candidateID {
            activeCandidate = nil
            activeAnswer = nil
          }
        }
      }
      let latency = Self.milliseconds(start.duration(to: .now))
      latencySamples.append(latency)

      if answerAppearedAt == nil, let activeAnswer {
        answerTriggeredAt = input.atMilliseconds
        answerAppearedAt = Double(input.atMilliseconds) + latency
        firstAnswerCandidate = activeCandidate
        firstAnswer = activeAnswer
      }

      revisionResults.append(
        KnowledgeProofRevisionResult(
          sequence: index + 1,
          atMilliseconds: input.atMilliseconds,
          stability: input.stability,
          text: input.text,
          processingLatencyMilliseconds: latency,
          emittedEvents: events.map(Self.eventDescription),
          activeCandidateID: activeCandidate?.id,
          activeCandidateStatus: activeCandidate?.status,
          activeQuestionFamilyID: activeCandidate?.questionFamilyID,
          activeResponseCardID: activeAnswer?.responseCardID,
          activeEvidenceState: activeAnswer?.evidenceState
        ))
    }

    let finalSpeechAt = spec.revisions.filter { $0.stability == .final }
      .map(\.atMilliseconds).min()!
    let citations = citationResults(for: firstAnswer)
    let latency = Self.latencySummary(latencySamples)
    let checks = makeChecks(
      spec: spec,
      candidate: firstAnswerCandidate,
      answer: firstAnswer,
      answerAppearedAt: answerAppearedAt,
      finalSpeechAt: finalSpeechAt,
      latency: latency,
      citations: citations
    )
    let verdict: KnowledgeProofVerdict = checks.allSatisfy(\.passed) ? .pass : .fail

    return KnowledgeProofReport(
      replayName: spec.name,
      packID: pack.manifest.packID,
      packTitle: pack.manifest.title,
      verdict: verdict,
      responseDeadlineMilliseconds: spec.responseDeadlineMilliseconds,
      answerTriggeredAtMilliseconds: answerTriggeredAt,
      answerAppearedAtMilliseconds: answerAppearedAt,
      finalSpeechAtMilliseconds: finalSpeechAt,
      deadlineHeadroomMilliseconds: answerAppearedAt.map {
        Double(spec.responseDeadlineMilliseconds) - $0
      },
      answerLeadBeforeFinalMilliseconds: answerAppearedAt.map { Double(finalSpeechAt) - $0 },
      latency: latency,
      checks: checks,
      revisions: revisionResults,
      citations: citations
    )
  }

  private func validate(_ spec: KnowledgeProofReplaySpec) throws {
    guard spec.schemaVersion == KnowledgeProofReplaySpec.currentSchemaVersion else {
      throw KnowledgeProofReplayValidationError.unsupportedSchema(spec.schemaVersion)
    }
    guard !spec.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw KnowledgeProofReplayValidationError.emptyName
    }
    guard !spec.streamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw KnowledgeProofReplayValidationError.emptyStreamID
    }
    guard spec.responseDeadlineMilliseconds > 0 else {
      throw KnowledgeProofReplayValidationError.invalidDeadline
    }
    guard spec.maximumProcessingLatencyMilliseconds > 0 else {
      throw KnowledgeProofReplayValidationError.invalidLatencyBudget
    }
    guard spec.revisions.count >= 2 else {
      throw KnowledgeProofReplayValidationError.tooFewRevisions
    }
    var previousTime = -1
    for (index, revision) in spec.revisions.enumerated() {
      guard revision.atMilliseconds >= 0 else {
        throw KnowledgeProofReplayValidationError.negativeRevisionTime(index: index)
      }
      guard revision.atMilliseconds >= previousTime else {
        throw KnowledgeProofReplayValidationError.outOfOrderRevision(index: index)
      }
      previousTime = revision.atMilliseconds
    }
    guard spec.revisions.contains(where: { $0.stability == .final }) else {
      throw KnowledgeProofReplayValidationError.missingFinalRevision
    }
  }

  private func makeChecks(
    spec: KnowledgeProofReplaySpec,
    candidate: QuestionCandidate?,
    answer: KnowledgeAnswerCard?,
    answerAppearedAt: Double?,
    finalSpeechAt: Int,
    latency: KnowledgeProofLatencySummary,
    citations: [KnowledgeProofCitationResult]
  ) -> [KnowledgeProofCheck] {
    let expected = spec.expected
    let answerFragmentsPass = expected.answerContains.allSatisfy { fragment in
      answer?.answer.localizedCaseInsensitiveContains(fragment) == true
    }
    let expectedCitations = Set(expected.citationPassageIDs)
    let actualCitations = Set(citations.map(\.passageID))
    let citationsValid =
      citations.allSatisfy { $0.exists && $0.insidePack }
      && actualCitations == expectedCitations
    let timingPass =
      answerAppearedAt.map { $0 <= Double(spec.responseDeadlineMilliseconds) } ?? false
    let beforeFinalPass =
      !spec.requireAnswerBeforeFinal
      || (answerAppearedAt.map { $0 < Double(finalSpeechAt) } ?? false)

    return [
      KnowledgeProofCheck(
        name: "question_family",
        passed: candidate?.questionFamilyID == expected.questionFamilyID,
        detail:
          "Expected \(expected.questionFamilyID); observed \(candidate?.questionFamilyID ?? "none")."
      ),
      KnowledgeProofCheck(
        name: "reviewed_response_card",
        passed: answer?.responseCardID == expected.responseCardID && answer?.isFallback == false,
        detail: "Expected \(expected.responseCardID); observed \(answer?.responseCardID ?? "none")."
      ),
      KnowledgeProofCheck(
        name: "evidence_state",
        passed: answer?.evidenceState == expected.evidenceState,
        detail:
          "Expected \(expected.evidenceState.rawValue); observed \(answer?.evidenceState.rawValue ?? "none")."
      ),
      KnowledgeProofCheck(
        name: "answer_content",
        passed: answerFragmentsPass,
        detail: answerFragmentsPass
          ? "All expected answer fragments were present."
          : "One or more expected answer fragments were missing."
      ),
      KnowledgeProofCheck(
        name: "citations",
        passed: citationsValid,
        detail: citationsValid
          ? "All expected citations exist inside the selected KnowledgePack."
          : "Citation IDs, file existence, or pack containment did not match."
      ),
      KnowledgeProofCheck(
        name: "response_deadline",
        passed: timingPass,
        detail:
          "Answer appeared at \(answerAppearedAt.map(Self.formatted) ?? "never") ms; deadline is \(spec.responseDeadlineMilliseconds) ms."
      ),
      KnowledgeProofCheck(
        name: "before_final_speech",
        passed: beforeFinalPass,
        detail:
          "Answer appeared at \(answerAppearedAt.map(Self.formatted) ?? "never") ms; final speech arrived at \(finalSpeechAt) ms."
      ),
      KnowledgeProofCheck(
        name: "processing_latency",
        passed: latency.maximumMilliseconds <= spec.maximumProcessingLatencyMilliseconds,
        detail:
          "Maximum processing latency was \(Self.formatted(latency.maximumMilliseconds)) ms; budget is \(Self.formatted(spec.maximumProcessingLatencyMilliseconds)) ms."
      ),
    ]
  }

  private func citationResults(
    for answer: KnowledgeAnswerCard?
  ) -> [KnowledgeProofCitationResult] {
    guard let answer else { return [] }
    return answer.citations.map { citation in
      let source = pack.sources.first(where: { $0.id == citation.sourceID })
      return KnowledgeProofCitationResult(
        passageID: citation.passageID,
        sourceID: citation.sourceID,
        sourceTitle: citation.sourceTitle,
        relativePath: source?.relativePath ?? "",
        locatorLabel: citation.locatorLabel,
        exists: FileManager.default.fileExists(atPath: citation.fileURL.path),
        insidePack: Self.isInsideRoot(citation.fileURL, root: rootDirectory)
      )
    }.sorted { $0.passageID < $1.passageID }
  }

  private static func eventDescription(_ event: QuestionCandidateEvent) -> String {
    switch event {
    case .upsert(let candidate):
      "upsert:\(candidate.status.rawValue)"
    case .cancel(let cancellation):
      "cancel:\(cancellation.reason.rawValue)"
    }
  }

  private static func latencySummary(_ samples: [Double]) -> KnowledgeProofLatencySummary {
    let sorted = samples.sorted()
    return KnowledgeProofLatencySummary(
      sampleCount: sorted.count,
      medianMilliseconds: percentile(0.50, in: sorted),
      p95Milliseconds: percentile(0.95, in: sorted),
      maximumMilliseconds: sorted.last ?? 0
    )
  }

  private static func percentile(_ percentile: Double, in sorted: [Double]) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = Int(ceil(percentile * Double(sorted.count))) - 1
    return sorted[min(max(index, 0), sorted.count - 1)]
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return (Double(components.seconds) * 1_000)
      + (Double(components.attoseconds) / 1_000_000_000_000_000)
  }

  private static func isInsideRoot(_ fileURL: URL, root: URL) -> Bool {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return fileURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(rootPath)
  }

  private static func formatted(_ value: Double) -> String {
    String(format: "%.3f", value)
  }
}
