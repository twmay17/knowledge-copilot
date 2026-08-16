import Foundation

public struct KnowledgeLiveEventReplaySpec: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let name: String
  public let maximumFalsePositiveRate: Double
  public let revisions: [KnowledgeLiveEventReplayRevision]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    name: String,
    maximumFalsePositiveRate: Double,
    revisions: [KnowledgeLiveEventReplayRevision]
  ) {
    self.schemaVersion = schemaVersion
    self.name = name
    self.maximumFalsePositiveRate = maximumFalsePositiveRate
    self.revisions = revisions
  }
}

public struct KnowledgeLiveEventReplayRevision: Codable, Equatable, Sendable {
  public let streamID: String
  public let sequence: Int
  public let text: String
  public let stability: KnowledgeLiveEventReplayStability
  public let expectedKinds: [KnowledgeLiveEventKind]

  public init(
    streamID: String,
    sequence: Int,
    text: String,
    stability: KnowledgeLiveEventReplayStability,
    expectedKinds: [KnowledgeLiveEventKind]
  ) {
    self.streamID = streamID
    self.sequence = sequence
    self.text = text
    self.stability = stability
    self.expectedKinds = expectedKinds
  }
}

public enum KnowledgeLiveEventReplayStability: String, Codable, Equatable, Sendable {
  case partial
  case final
}

public enum KnowledgeLiveEventReplayValidationError: Error, Equatable, CustomStringConvertible {
  case unsupportedSchema(Int)
  case emptyName
  case invalidFalsePositiveRate
  case noRevisions
  case emptyStreamID(index: Int)
  case invalidSequence(index: Int)
  case noExpectedKinds(index: Int)

  public var description: String {
    switch self {
    case .unsupportedSchema(let version):
      "Live event replay schema \(version) is unsupported; expected \(KnowledgeLiveEventReplaySpec.currentSchemaVersion)."
    case .emptyName:
      "Live event replay name must not be empty."
    case .invalidFalsePositiveRate:
      "Maximum false-positive rate must be between zero and one."
    case .noRevisions:
      "Live event replay requires at least one revision."
    case .emptyStreamID(let index):
      "Live event replay revision \(index + 1) has an empty stream ID."
    case .invalidSequence(let index):
      "Live event replay revision \(index + 1) must have a positive sequence."
    case .noExpectedKinds(let index):
      "Live event replay revision \(index + 1) must declare at least one expected event kind."
    }
  }
}

public enum KnowledgeLiveEventReplayVerdict: String, Codable, Equatable, Sendable {
  case pass = "PASS"
  case fail = "FAIL"
}

public struct KnowledgeLiveEventTrace: Codable, Equatable, Sendable {
  public let index: Int
  public let streamID: String
  public let sequence: Int
  public let text: String
  public let stability: KnowledgeLiveEventReplayStability
  public let expectedKinds: [KnowledgeLiveEventKind]
  public let actualKinds: [KnowledgeLiveEventKind]
  public let eventDescriptions: [String]
  public let passed: Bool

  public init(
    index: Int,
    streamID: String,
    sequence: Int,
    text: String,
    stability: KnowledgeLiveEventReplayStability,
    expectedKinds: [KnowledgeLiveEventKind],
    actualKinds: [KnowledgeLiveEventKind],
    eventDescriptions: [String],
    passed: Bool
  ) {
    self.index = index
    self.streamID = streamID
    self.sequence = sequence
    self.text = text
    self.stability = stability
    self.expectedKinds = expectedKinds
    self.actualKinds = actualKinds
    self.eventDescriptions = eventDescriptions
    self.passed = passed
  }
}

public struct KnowledgeLiveEventReplayReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let replayName: String
  public let verdict: KnowledgeLiveEventReplayVerdict
  public let maximumFalsePositiveRate: Double
  public let falsePositiveRate: Double
  public let negativeRevisionCount: Int
  public let falsePositiveRevisionCount: Int
  public let falseNegativeRevisionCount: Int
  public let exactTraceMatchCount: Int
  public let traces: [KnowledgeLiveEventTrace]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    replayName: String,
    verdict: KnowledgeLiveEventReplayVerdict,
    maximumFalsePositiveRate: Double,
    falsePositiveRate: Double,
    negativeRevisionCount: Int,
    falsePositiveRevisionCount: Int,
    falseNegativeRevisionCount: Int,
    exactTraceMatchCount: Int,
    traces: [KnowledgeLiveEventTrace]
  ) {
    self.schemaVersion = schemaVersion
    self.replayName = replayName
    self.verdict = verdict
    self.maximumFalsePositiveRate = maximumFalsePositiveRate
    self.falsePositiveRate = falsePositiveRate
    self.negativeRevisionCount = negativeRevisionCount
    self.falsePositiveRevisionCount = falsePositiveRevisionCount
    self.falseNegativeRevisionCount = falseNegativeRevisionCount
    self.exactTraceMatchCount = exactTraceMatchCount
    self.traces = traces
  }
}

/// Replays transcript fixtures through a fresh event detector and measures actionable false
/// positives on revisions whose expected result is only `NoAction`.
public struct KnowledgeLiveEventReplayRunner: Sendable {
  private let questionFamilies: [KnowledgeQuestionFamily]
  private let termAliases: [KnowledgeTermAlias]

  public init(
    questionFamilies: [KnowledgeQuestionFamily],
    termAliases: [KnowledgeTermAlias] = []
  ) {
    self.questionFamilies = questionFamilies
    self.termAliases = termAliases
  }

  public func run(_ spec: KnowledgeLiveEventReplaySpec) throws -> KnowledgeLiveEventReplayReport {
    try validate(spec)
    var detector = KnowledgeLiveEventDetector(
      questionFamilies: questionFamilies,
      termAliases: termAliases
    )
    var traces: [KnowledgeLiveEventTrace] = []
    var negativeRevisionCount = 0
    var falsePositiveRevisionCount = 0
    var falseNegativeRevisionCount = 0

    for (index, input) in spec.revisions.enumerated() {
      let events = detector.process(
        TranscriptRevision(
          streamID: input.streamID,
          sequence: input.sequence,
          text: input.text,
          stability: input.stability == .final ? .final : .partial
        ))
      let actualKinds = events.map(\.kind)
      let expectedActionable = input.expectedKinds.filter(\.isActionable)
      let actualActionable = actualKinds.filter(\.isActionable)
      if expectedActionable.isEmpty {
        negativeRevisionCount += 1
        if !actualActionable.isEmpty { falsePositiveRevisionCount += 1 }
      } else if actualActionable.isEmpty {
        falseNegativeRevisionCount += 1
      }
      traces.append(
        KnowledgeLiveEventTrace(
          index: index,
          streamID: input.streamID,
          sequence: input.sequence,
          text: input.text,
          stability: input.stability,
          expectedKinds: input.expectedKinds,
          actualKinds: actualKinds,
          eventDescriptions: events.map(Self.describe),
          passed: actualKinds == input.expectedKinds
        ))
    }

    let falsePositiveRate =
      negativeRevisionCount == 0
      ? 0
      : Double(falsePositiveRevisionCount) / Double(negativeRevisionCount)
    let exactTraceMatchCount = traces.filter(\.passed).count
    let passed =
      exactTraceMatchCount == traces.count
      && falsePositiveRate <= spec.maximumFalsePositiveRate
      && falseNegativeRevisionCount == 0
    return KnowledgeLiveEventReplayReport(
      replayName: spec.name,
      verdict: passed ? .pass : .fail,
      maximumFalsePositiveRate: spec.maximumFalsePositiveRate,
      falsePositiveRate: falsePositiveRate,
      negativeRevisionCount: negativeRevisionCount,
      falsePositiveRevisionCount: falsePositiveRevisionCount,
      falseNegativeRevisionCount: falseNegativeRevisionCount,
      exactTraceMatchCount: exactTraceMatchCount,
      traces: traces
    )
  }

  private func validate(_ spec: KnowledgeLiveEventReplaySpec) throws {
    guard spec.schemaVersion == KnowledgeLiveEventReplaySpec.currentSchemaVersion else {
      throw KnowledgeLiveEventReplayValidationError.unsupportedSchema(spec.schemaVersion)
    }
    guard !spec.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw KnowledgeLiveEventReplayValidationError.emptyName
    }
    guard (0...1).contains(spec.maximumFalsePositiveRate) else {
      throw KnowledgeLiveEventReplayValidationError.invalidFalsePositiveRate
    }
    guard !spec.revisions.isEmpty else {
      throw KnowledgeLiveEventReplayValidationError.noRevisions
    }
    for (index, revision) in spec.revisions.enumerated() {
      guard !revision.streamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw KnowledgeLiveEventReplayValidationError.emptyStreamID(index: index)
      }
      guard revision.sequence > 0 else {
        throw KnowledgeLiveEventReplayValidationError.invalidSequence(index: index)
      }
      guard !revision.expectedKinds.isEmpty else {
        throw KnowledgeLiveEventReplayValidationError.noExpectedKinds(index: index)
      }
    }
  }

  private static func describe(_ event: KnowledgeLiveEvent) -> String {
    switch event {
    case .questionCandidate(let candidate):
      "QuestionCandidate:\(candidate.id):\(candidate.questionFamilyID)"
    case .questionStable(let candidate):
      "QuestionStable:\(candidate.id):\(candidate.questionFamilyID)"
    case .claimCandidate(let candidate):
      "ClaimCandidate:\(candidate.id)"
    case .claimStable(let candidate):
      "ClaimStable:\(candidate.id)"
    case .topicShift(let shift):
      "TopicShift:\(shift.fromTopicIDs.joined(separator: ","))->\(shift.toTopicIDs.joined(separator: ","))"
    case .answerSuperseded(let supersession):
      "AnswerSuperseded:\(supersession.previousEventID):\(supersession.reason.rawValue)"
    case .noAction(let noAction):
      "NoAction:\(noAction.reason.rawValue)"
    }
  }
}
