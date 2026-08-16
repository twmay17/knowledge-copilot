import Foundation

public struct KnowledgeReplayBenchmarkSpec: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let name: String
  public let minimumScenarioCount: Int
  public let maximumFalseCardRate: Double
  public let maximumP95ProcessingLatencyMilliseconds: Double
  public let redistributable: Bool
  public let packs: [KnowledgeReplayBenchmarkPackReference]
  public let scenarioTemplates: [KnowledgeReplayBenchmarkScenarioTemplate]
  public let scenarios: [KnowledgeReplayBenchmarkScenario]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    name: String,
    minimumScenarioCount: Int,
    maximumFalseCardRate: Double,
    maximumP95ProcessingLatencyMilliseconds: Double,
    redistributable: Bool,
    packs: [KnowledgeReplayBenchmarkPackReference],
    scenarioTemplates: [KnowledgeReplayBenchmarkScenarioTemplate],
    scenarios: [KnowledgeReplayBenchmarkScenario]
  ) {
    self.schemaVersion = schemaVersion
    self.name = name
    self.minimumScenarioCount = minimumScenarioCount
    self.maximumFalseCardRate = maximumFalseCardRate
    self.maximumP95ProcessingLatencyMilliseconds = maximumP95ProcessingLatencyMilliseconds
    self.redistributable = redistributable
    self.packs = packs
    self.scenarioTemplates = scenarioTemplates
    self.scenarios = scenarios
  }

  public var expandedScenarios: [KnowledgeReplayBenchmarkScenario] {
    let generated = scenarioTemplates.flatMap { template in
      template.utterances.enumerated().map { index, utterance in
        let scenarioID = "\(template.id)-\(index + 1)"
        return KnowledgeReplayBenchmarkScenario(
          id: scenarioID,
          packID: template.packID,
          categories: template.categories,
          countsTowardFalseCardRate: nil,
          revisions: [
            KnowledgeReplayBenchmarkRevision(
              streamID: scenarioID,
              sequence: 1,
              text: utterance,
              stability: .final,
              expectedKinds: [.questionStable]
            )
          ],
          expected: template.expected
        )
      }
    }
    return generated + scenarios
  }
}

public struct KnowledgeReplayBenchmarkPackReference: Codable, Equatable, Sendable {
  public let packID: String
  public let relativePath: String

  public init(packID: String, relativePath: String) {
    self.packID = packID
    self.relativePath = relativePath
  }
}

public enum KnowledgeReplayBenchmarkCategory: String, Codable, CaseIterable, Equatable, Sendable {
  case direct
  case partial
  case corrected
  case ambiguous
  case conflicting
  case missing
  case rhetorical
  case rapidFollowUp = "rapid_follow_up"
  case interpretive
  case crossPack = "cross_pack"
}

public struct KnowledgeReplayBenchmarkScenarioTemplate: Codable, Equatable, Sendable {
  public let id: String
  public let packID: String
  public let categories: [KnowledgeReplayBenchmarkCategory]
  public let utterances: [String]
  public let expected: KnowledgeReplayBenchmarkExpectation

  public init(
    id: String,
    packID: String,
    categories: [KnowledgeReplayBenchmarkCategory],
    utterances: [String],
    expected: KnowledgeReplayBenchmarkExpectation
  ) {
    self.id = id
    self.packID = packID
    self.categories = categories
    self.utterances = utterances
    self.expected = expected
  }
}

public struct KnowledgeReplayBenchmarkScenario: Codable, Equatable, Sendable {
  public let id: String
  public let packID: String
  public let categories: [KnowledgeReplayBenchmarkCategory]
  public let countsTowardFalseCardRate: Bool?
  public let revisions: [KnowledgeReplayBenchmarkRevision]
  public let expected: KnowledgeReplayBenchmarkExpectation

  public init(
    id: String,
    packID: String,
    categories: [KnowledgeReplayBenchmarkCategory],
    countsTowardFalseCardRate: Bool? = nil,
    revisions: [KnowledgeReplayBenchmarkRevision],
    expected: KnowledgeReplayBenchmarkExpectation
  ) {
    self.id = id
    self.packID = packID
    self.categories = categories
    self.countsTowardFalseCardRate = countsTowardFalseCardRate
    self.revisions = revisions
    self.expected = expected
  }
}

public struct KnowledgeReplayBenchmarkRevision: Codable, Equatable, Sendable {
  public let streamID: String
  public let sequence: Int
  public let text: String
  public let stability: KnowledgeReplayBenchmarkStability
  public let expectedKinds: [KnowledgeLiveEventKind]

  public init(
    streamID: String,
    sequence: Int,
    text: String,
    stability: KnowledgeReplayBenchmarkStability,
    expectedKinds: [KnowledgeLiveEventKind]
  ) {
    self.streamID = streamID
    self.sequence = sequence
    self.text = text
    self.stability = stability
    self.expectedKinds = expectedKinds
  }
}

public enum KnowledgeReplayBenchmarkStability: String, Codable, Equatable, Sendable {
  case partial
  case final
}

public enum KnowledgeReplayBenchmarkAnswerMode: String, Codable, Equatable, Sendable {
  case reviewed
  case fallback
  case none
}

public struct KnowledgeReplayBenchmarkExpectation: Codable, Equatable, Sendable {
  public let answerMode: KnowledgeReplayBenchmarkAnswerMode
  public let questionFamilyID: String?
  public let responseCardID: String?
  public let evidenceState: KnowledgeEvidenceState?
  public let answerContains: [String]
  public let citationPassageIDs: [String]

  public init(
    answerMode: KnowledgeReplayBenchmarkAnswerMode,
    questionFamilyID: String? = nil,
    responseCardID: String? = nil,
    evidenceState: KnowledgeEvidenceState? = nil,
    answerContains: [String] = [],
    citationPassageIDs: [String] = []
  ) {
    self.answerMode = answerMode
    self.questionFamilyID = questionFamilyID
    self.responseCardID = responseCardID
    self.evidenceState = evidenceState
    self.answerContains = answerContains
    self.citationPassageIDs = citationPassageIDs
  }
}

public enum KnowledgeReplayBenchmarkValidationError: Error, Equatable, CustomStringConvertible {
  case unsupportedSchema(Int)
  case emptyName
  case invalidMinimumScenarioCount
  case invalidFalseCardRate
  case invalidLatencyBudget
  case notRedistributable
  case noPacks
  case duplicatePackID(String)
  case emptyPackPath(String)
  case emptyTemplateID(Int)
  case emptyTemplateUtterances(String)
  case emptyScenarioID(Int)
  case duplicateScenarioID(String)
  case unknownPackID(scenarioID: String, packID: String)
  case noCategories(String)
  case noRevisions(String)
  case invalidRevision(scenarioID: String, index: Int)
  case incoherentExpectation(String)
  case belowMinimumScenarioCount(actual: Int, minimum: Int)
  case missingLoadedPack(String)
  case loadedPackIDMismatch(expected: String, actual: String)

  public var description: String {
    switch self {
    case .unsupportedSchema(let version):
      "Replay benchmark schema \(version) is unsupported; expected \(KnowledgeReplayBenchmarkSpec.currentSchemaVersion)."
    case .emptyName:
      "Replay benchmark name must not be empty."
    case .invalidMinimumScenarioCount:
      "Replay benchmark minimum scenario count must be greater than zero."
    case .invalidFalseCardRate:
      "Replay benchmark maximum false-card rate must be between zero and one."
    case .invalidLatencyBudget:
      "Replay benchmark p95 processing-latency budget must be greater than zero."
    case .notRedistributable:
      "Replay benchmark must explicitly declare its fixtures redistributable."
    case .noPacks:
      "Replay benchmark requires at least one KnowledgePack."
    case .duplicatePackID(let packID):
      "Replay benchmark declares pack ID '\(packID)' more than once."
    case .emptyPackPath(let packID):
      "Replay benchmark pack '\(packID)' has an empty relative path."
    case .emptyTemplateID(let index):
      "Replay benchmark template \(index + 1) has an empty ID."
    case .emptyTemplateUtterances(let templateID):
      "Replay benchmark template '\(templateID)' has no utterances."
    case .emptyScenarioID(let index):
      "Replay benchmark scenario \(index + 1) has an empty ID."
    case .duplicateScenarioID(let scenarioID):
      "Replay benchmark scenario ID '\(scenarioID)' is duplicated."
    case .unknownPackID(let scenarioID, let packID):
      "Replay benchmark scenario '\(scenarioID)' references unknown pack '\(packID)'."
    case .noCategories(let scenarioID):
      "Replay benchmark scenario '\(scenarioID)' has no coverage categories."
    case .noRevisions(let scenarioID):
      "Replay benchmark scenario '\(scenarioID)' has no transcript revisions."
    case .invalidRevision(let scenarioID, let index):
      "Replay benchmark scenario '\(scenarioID)' has an invalid revision at index \(index)."
    case .incoherentExpectation(let scenarioID):
      "Replay benchmark scenario '\(scenarioID)' has an incoherent answer expectation."
    case .belowMinimumScenarioCount(let actual, let minimum):
      "Replay benchmark expands to \(actual) scenarios; at least \(minimum) are required."
    case .missingLoadedPack(let packID):
      "Replay benchmark did not receive loaded pack '\(packID)'."
    case .loadedPackIDMismatch(let expected, let actual):
      "Replay benchmark expected pack '\(expected)' but loaded '\(actual)'."
    }
  }
}

public struct KnowledgeReplayBenchmarkPack: Sendable {
  public let pack: KnowledgePack
  public let rootDirectory: URL
  public let termAliases: [KnowledgeTermAlias]

  public init(
    pack: KnowledgePack,
    rootDirectory: URL,
    termAliases: [KnowledgeTermAlias] = []
  ) {
    self.pack = pack
    self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
    self.termAliases = termAliases
  }
}

public struct KnowledgeReplayBenchmarkTrace: Codable, Equatable, Sendable {
  public let index: Int
  public let streamID: String
  public let sequence: Int
  public let stability: KnowledgeReplayBenchmarkStability
  public let text: String
  public let expectedKinds: [KnowledgeLiveEventKind]
  public let actualKinds: [KnowledgeLiveEventKind]
  public let processingLatencyMilliseconds: Double
  public let activeQuestionFamilyID: String?
  public let activeResponseCardID: String?
  public let activeEvidenceState: KnowledgeEvidenceState?
  public let passed: Bool

  public init(
    index: Int,
    streamID: String,
    sequence: Int,
    stability: KnowledgeReplayBenchmarkStability,
    text: String,
    expectedKinds: [KnowledgeLiveEventKind],
    actualKinds: [KnowledgeLiveEventKind],
    processingLatencyMilliseconds: Double,
    activeQuestionFamilyID: String?,
    activeResponseCardID: String?,
    activeEvidenceState: KnowledgeEvidenceState?,
    passed: Bool
  ) {
    self.index = index
    self.streamID = streamID
    self.sequence = sequence
    self.stability = stability
    self.text = text
    self.expectedKinds = expectedKinds
    self.actualKinds = actualKinds
    self.processingLatencyMilliseconds = processingLatencyMilliseconds
    self.activeQuestionFamilyID = activeQuestionFamilyID
    self.activeResponseCardID = activeResponseCardID
    self.activeEvidenceState = activeEvidenceState
    self.passed = passed
  }
}

public struct KnowledgeReplayBenchmarkScenarioReport: Codable, Equatable, Sendable,
  Identifiable
{
  public let id: String
  public let packID: String
  public let categories: [KnowledgeReplayBenchmarkCategory]
  public let verdict: KnowledgeProofVerdict
  public let falseCard: Bool
  public let checks: [KnowledgeProofCheck]
  public let traces: [KnowledgeReplayBenchmarkTrace]
  public let finalQuestionFamilyID: String?
  public let finalResponseCardID: String?
  public let finalEvidenceState: KnowledgeEvidenceState?

  public init(
    id: String,
    packID: String,
    categories: [KnowledgeReplayBenchmarkCategory],
    verdict: KnowledgeProofVerdict,
    falseCard: Bool,
    checks: [KnowledgeProofCheck],
    traces: [KnowledgeReplayBenchmarkTrace],
    finalQuestionFamilyID: String?,
    finalResponseCardID: String?,
    finalEvidenceState: KnowledgeEvidenceState?
  ) {
    self.id = id
    self.packID = packID
    self.categories = categories
    self.verdict = verdict
    self.falseCard = falseCard
    self.checks = checks
    self.traces = traces
    self.finalQuestionFamilyID = finalQuestionFamilyID
    self.finalResponseCardID = finalResponseCardID
    self.finalEvidenceState = finalEvidenceState
  }
}

public struct KnowledgeReplayBenchmarkReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let benchmarkName: String
  public let verdict: KnowledgeProofVerdict
  public let scenarioCount: Int
  public let passedScenarioCount: Int
  public let scenariosByPack: [String: Int]
  public let scenariosByCategory: [String: Int]
  public let negativeScenarioCount: Int
  public let falseCardCount: Int
  public let falseCardRate: Double
  public let maximumFalseCardRate: Double
  public let latency: KnowledgeProofLatencySummary
  public let maximumP95ProcessingLatencyMilliseconds: Double
  public let checks: [KnowledgeProofCheck]
  public let scenarios: [KnowledgeReplayBenchmarkScenarioReport]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    benchmarkName: String,
    verdict: KnowledgeProofVerdict,
    scenarioCount: Int,
    passedScenarioCount: Int,
    scenariosByPack: [String: Int],
    scenariosByCategory: [String: Int],
    negativeScenarioCount: Int,
    falseCardCount: Int,
    falseCardRate: Double,
    maximumFalseCardRate: Double,
    latency: KnowledgeProofLatencySummary,
    maximumP95ProcessingLatencyMilliseconds: Double,
    checks: [KnowledgeProofCheck],
    scenarios: [KnowledgeReplayBenchmarkScenarioReport]
  ) {
    self.schemaVersion = schemaVersion
    self.benchmarkName = benchmarkName
    self.verdict = verdict
    self.scenarioCount = scenarioCount
    self.passedScenarioCount = passedScenarioCount
    self.scenariosByPack = scenariosByPack
    self.scenariosByCategory = scenariosByCategory
    self.negativeScenarioCount = negativeScenarioCount
    self.falseCardCount = falseCardCount
    self.falseCardRate = falseCardRate
    self.maximumFalseCardRate = maximumFalseCardRate
    self.latency = latency
    self.maximumP95ProcessingLatencyMilliseconds = maximumP95ProcessingLatencyMilliseconds
    self.checks = checks
    self.scenarios = scenarios
  }
}

/// Replays a multi-pack, versioned scenario corpus through the same live detector and reviewed-card
/// resolver used by the product. Every scenario starts from clean state.
public struct KnowledgeReplayBenchmarkRunner: Sendable {
  private let packs: [String: KnowledgeReplayBenchmarkPack]

  public init(packs: [String: KnowledgeReplayBenchmarkPack]) {
    self.packs = packs
  }

  public func run(_ spec: KnowledgeReplayBenchmarkSpec) throws -> KnowledgeReplayBenchmarkReport {
    let scenarios = try validate(spec)
    var reports: [KnowledgeReplayBenchmarkScenarioReport] = []
    var latencySamples: [Double] = []

    for scenario in scenarios {
      guard let configuredPack = packs[scenario.packID] else {
        throw KnowledgeReplayBenchmarkValidationError.missingLoadedPack(scenario.packID)
      }
      guard configuredPack.pack.manifest.packID == scenario.packID else {
        throw KnowledgeReplayBenchmarkValidationError.loadedPackIDMismatch(
          expected: scenario.packID,
          actual: configuredPack.pack.manifest.packID
        )
      }
      let result = run(scenario, with: configuredPack)
      reports.append(result.report)
      latencySamples.append(contentsOf: result.latencySamples)
    }

    let scenarioCount = reports.count
    let passedScenarioCount = reports.filter { $0.verdict == .pass }.count
    let negativeReports = zip(scenarios, reports).filter { scenario, _ in
      scenario.countsTowardFalseCardRate == true
    }
    let falseCardCount = negativeReports.filter { $0.1.falseCard }.count
    let falseCardRate =
      negativeReports.isEmpty ? 0 : Double(falseCardCount) / Double(negativeReports.count)
    let latency = Self.latencySummary(latencySamples)
    let scenarioCountPass = scenarioCount >= spec.minimumScenarioCount
    let scenariosPass = passedScenarioCount == scenarioCount
    let falseCardsPass = falseCardRate <= spec.maximumFalseCardRate
    let latencyPass = latency.p95Milliseconds <= spec.maximumP95ProcessingLatencyMilliseconds
    let checks = [
      KnowledgeProofCheck(
        name: "scenario_count",
        passed: scenarioCountPass,
        detail: "Expanded \(scenarioCount) scenarios; minimum is \(spec.minimumScenarioCount)."
      ),
      KnowledgeProofCheck(
        name: "scenario_results",
        passed: scenariosPass,
        detail: "\(passedScenarioCount) of \(scenarioCount) scenarios passed."
      ),
      KnowledgeProofCheck(
        name: "false_card_rate",
        passed: falseCardsPass,
        detail:
          "Observed \(Self.formatted(falseCardRate)); maximum is \(Self.formatted(spec.maximumFalseCardRate))."
      ),
      KnowledgeProofCheck(
        name: "processing_latency_p95",
        passed: latencyPass,
        detail:
          "Observed \(Self.formatted(latency.p95Milliseconds)) ms; maximum is \(Self.formatted(spec.maximumP95ProcessingLatencyMilliseconds)) ms."
      ),
      KnowledgeProofCheck(
        name: "redistributable_fixtures",
        passed: spec.redistributable,
        detail: "The benchmark explicitly declares its synthetic fixtures redistributable."
      ),
    ]
    return KnowledgeReplayBenchmarkReport(
      benchmarkName: spec.name,
      verdict: checks.allSatisfy(\.passed) ? .pass : .fail,
      scenarioCount: scenarioCount,
      passedScenarioCount: passedScenarioCount,
      scenariosByPack: Self.counts(reports.map(\.packID)),
      scenariosByCategory: Self.counts(
        reports.flatMap { $0.categories.map(\.rawValue) }
      ),
      negativeScenarioCount: negativeReports.count,
      falseCardCount: falseCardCount,
      falseCardRate: falseCardRate,
      maximumFalseCardRate: spec.maximumFalseCardRate,
      latency: latency,
      maximumP95ProcessingLatencyMilliseconds: spec.maximumP95ProcessingLatencyMilliseconds,
      checks: checks,
      scenarios: reports
    )
  }

  private func run(
    _ scenario: KnowledgeReplayBenchmarkScenario,
    with configuredPack: KnowledgeReplayBenchmarkPack
  ) -> (report: KnowledgeReplayBenchmarkScenarioReport, latencySamples: [Double]) {
    var detector = KnowledgeLiveEventDetector(
      questionFamilies: configuredPack.pack.questionFamilies,
      termAliases: configuredPack.termAliases
    )
    let resolver = KnowledgeAnswerCardResolver(
      pack: configuredPack.pack,
      rootDirectory: configuredPack.rootDirectory
    )
    var activeCandidate: QuestionCandidate?
    var activeAnswer: KnowledgeAnswerCard?
    var answerEverAppeared = false
    var traces: [KnowledgeReplayBenchmarkTrace] = []
    var latencySamples: [Double] = []

    for (index, input) in scenario.revisions.enumerated() {
      let start = ContinuousClock.now
      let events = detector.process(
        TranscriptRevision(
          streamID: input.streamID,
          sequence: input.sequence,
          text: input.text,
          stability: input.stability == .final ? .final : .partial
        ))
      for event in events {
        switch event {
        case .questionCandidate(let candidate):
          activeCandidate = candidate
          activeAnswer = nil
        case .questionStable(let candidate):
          activeCandidate = candidate
          activeAnswer = resolver.resolve(candidate)
          if activeAnswer != nil { answerEverAppeared = true }
        case .answerSuperseded(let supersession):
          if activeCandidate?.id == supersession.previousEventID {
            activeCandidate = nil
            activeAnswer = nil
          }
        case .claimCandidate, .claimStable, .topicShift, .noAction:
          break
        }
      }
      let latency = Self.milliseconds(start.duration(to: .now))
      latencySamples.append(latency)
      let actualKinds = events.map(\.kind)
      traces.append(
        KnowledgeReplayBenchmarkTrace(
          index: index,
          streamID: input.streamID,
          sequence: input.sequence,
          stability: input.stability,
          text: input.text,
          expectedKinds: input.expectedKinds,
          actualKinds: actualKinds,
          processingLatencyMilliseconds: latency,
          activeQuestionFamilyID: activeCandidate?.questionFamilyID,
          activeResponseCardID: activeAnswer?.responseCardID,
          activeEvidenceState: activeAnswer?.evidenceState,
          passed: actualKinds == input.expectedKinds
        ))
    }

    let checks = makeChecks(
      expectation: scenario.expected,
      candidate: activeCandidate,
      answer: activeAnswer,
      traces: traces,
      rootDirectory: configuredPack.rootDirectory
    )
    let falseCard = scenario.countsTowardFalseCardRate == true && answerEverAppeared
    return (
      KnowledgeReplayBenchmarkScenarioReport(
        id: scenario.id,
        packID: scenario.packID,
        categories: scenario.categories,
        verdict: checks.allSatisfy(\.passed) ? .pass : .fail,
        falseCard: falseCard,
        checks: checks,
        traces: traces,
        finalQuestionFamilyID: activeCandidate?.questionFamilyID,
        finalResponseCardID: activeAnswer?.responseCardID,
        finalEvidenceState: activeAnswer?.evidenceState
      ),
      latencySamples
    )
  }

  private func makeChecks(
    expectation: KnowledgeReplayBenchmarkExpectation,
    candidate: QuestionCandidate?,
    answer: KnowledgeAnswerCard?,
    traces: [KnowledgeReplayBenchmarkTrace],
    rootDirectory: URL
  ) -> [KnowledgeProofCheck] {
    let eventPass = traces.allSatisfy(\.passed)
    let modePass: Bool
    switch expectation.answerMode {
    case .reviewed:
      modePass = answer != nil && answer?.isFallback == false
    case .fallback:
      modePass = answer?.isFallback == true
    case .none:
      modePass = answer == nil
    }
    let answerFragmentsPass = expectation.answerContains.allSatisfy { fragment in
      answer?.answer.localizedCaseInsensitiveContains(fragment) == true
    }
    let citations = answer?.citations ?? []
    let expectedCitations = Set(expectation.citationPassageIDs)
    let actualCitations = Set(citations.map(\.passageID))
    let citationFilesPass = citations.allSatisfy {
      FileManager.default.fileExists(atPath: $0.fileURL.path)
        && Self.isInsideRoot($0.fileURL, root: rootDirectory)
    }
    let citationsPass = actualCitations == expectedCitations && citationFilesPass
    return [
      KnowledgeProofCheck(
        name: "events",
        passed: eventPass,
        detail: eventPass
          ? "Every revision emitted the expected event kinds."
          : "One or more revision event traces differed."
      ),
      KnowledgeProofCheck(
        name: "answer_mode",
        passed: modePass,
        detail:
          "Expected \(expectation.answerMode.rawValue); observed \(Self.answerMode(answer).rawValue)."
      ),
      KnowledgeProofCheck(
        name: "question_family",
        passed: candidate?.questionFamilyID == expectation.questionFamilyID,
        detail:
          "Expected \(expectation.questionFamilyID ?? "none"); observed \(candidate?.questionFamilyID ?? "none")."
      ),
      KnowledgeProofCheck(
        name: "response_card",
        passed: answer?.responseCardID == expectation.responseCardID,
        detail:
          "Expected \(expectation.responseCardID ?? "none"); observed \(answer?.responseCardID ?? "none")."
      ),
      KnowledgeProofCheck(
        name: "evidence_state",
        passed: answer?.evidenceState == expectation.evidenceState,
        detail:
          "Expected \(expectation.evidenceState?.rawValue ?? "none"); observed \(answer?.evidenceState.rawValue ?? "none")."
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
        passed: citationsPass,
        detail: citationsPass
          ? "Citation IDs and pack-local files matched."
          : "Citation IDs or pack-local files differed."
      ),
    ]
  }

  private func validate(
    _ spec: KnowledgeReplayBenchmarkSpec
  ) throws -> [KnowledgeReplayBenchmarkScenario] {
    guard spec.schemaVersion == KnowledgeReplayBenchmarkSpec.currentSchemaVersion else {
      throw KnowledgeReplayBenchmarkValidationError.unsupportedSchema(spec.schemaVersion)
    }
    guard !spec.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw KnowledgeReplayBenchmarkValidationError.emptyName
    }
    guard spec.minimumScenarioCount > 0 else {
      throw KnowledgeReplayBenchmarkValidationError.invalidMinimumScenarioCount
    }
    guard (0...1).contains(spec.maximumFalseCardRate) else {
      throw KnowledgeReplayBenchmarkValidationError.invalidFalseCardRate
    }
    guard spec.maximumP95ProcessingLatencyMilliseconds > 0 else {
      throw KnowledgeReplayBenchmarkValidationError.invalidLatencyBudget
    }
    guard spec.redistributable else {
      throw KnowledgeReplayBenchmarkValidationError.notRedistributable
    }
    guard !spec.packs.isEmpty else { throw KnowledgeReplayBenchmarkValidationError.noPacks }
    var packIDs: Set<String> = []
    for pack in spec.packs {
      guard packIDs.insert(pack.packID).inserted else {
        throw KnowledgeReplayBenchmarkValidationError.duplicatePackID(pack.packID)
      }
      guard !pack.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw KnowledgeReplayBenchmarkValidationError.emptyPackPath(pack.packID)
      }
    }
    for (index, template) in spec.scenarioTemplates.enumerated() {
      guard !template.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw KnowledgeReplayBenchmarkValidationError.emptyTemplateID(index)
      }
      guard !template.utterances.isEmpty else {
        throw KnowledgeReplayBenchmarkValidationError.emptyTemplateUtterances(template.id)
      }
    }
    let scenarios = spec.expandedScenarios
    guard scenarios.count >= spec.minimumScenarioCount else {
      throw KnowledgeReplayBenchmarkValidationError.belowMinimumScenarioCount(
        actual: scenarios.count,
        minimum: spec.minimumScenarioCount
      )
    }
    var scenarioIDs: Set<String> = []
    for (index, scenario) in scenarios.enumerated() {
      guard !scenario.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw KnowledgeReplayBenchmarkValidationError.emptyScenarioID(index)
      }
      guard scenarioIDs.insert(scenario.id).inserted else {
        throw KnowledgeReplayBenchmarkValidationError.duplicateScenarioID(scenario.id)
      }
      guard packIDs.contains(scenario.packID) else {
        throw KnowledgeReplayBenchmarkValidationError.unknownPackID(
          scenarioID: scenario.id,
          packID: scenario.packID
        )
      }
      guard !scenario.categories.isEmpty else {
        throw KnowledgeReplayBenchmarkValidationError.noCategories(scenario.id)
      }
      guard !scenario.revisions.isEmpty else {
        throw KnowledgeReplayBenchmarkValidationError.noRevisions(scenario.id)
      }
      for (revisionIndex, revision) in scenario.revisions.enumerated() {
        guard !revision.streamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          revision.sequence > 0,
          !revision.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !revision.expectedKinds.isEmpty
        else {
          throw KnowledgeReplayBenchmarkValidationError.invalidRevision(
            scenarioID: scenario.id,
            index: revisionIndex
          )
        }
      }
      guard Self.expectationIsCoherent(scenario.expected) else {
        throw KnowledgeReplayBenchmarkValidationError.incoherentExpectation(scenario.id)
      }
      guard scenario.countsTowardFalseCardRate != true || scenario.expected.answerMode == .none
      else {
        throw KnowledgeReplayBenchmarkValidationError.incoherentExpectation(scenario.id)
      }
    }
    return scenarios
  }

  private static func expectationIsCoherent(
    _ expectation: KnowledgeReplayBenchmarkExpectation
  ) -> Bool {
    switch expectation.answerMode {
    case .reviewed:
      return expectation.questionFamilyID != nil
        && expectation.responseCardID != nil
        && expectation.evidenceState != nil
        && !expectation.answerContains.isEmpty
    case .fallback:
      return expectation.questionFamilyID != nil
        && expectation.responseCardID == nil
        && expectation.evidenceState != nil
        && !expectation.answerContains.isEmpty
    case .none:
      return expectation.questionFamilyID == nil
        && expectation.responseCardID == nil
        && expectation.evidenceState == nil
        && expectation.answerContains.isEmpty
        && expectation.citationPassageIDs.isEmpty
    }
  }

  private static func answerMode(_ answer: KnowledgeAnswerCard?)
    -> KnowledgeReplayBenchmarkAnswerMode
  {
    guard let answer else { return .none }
    return answer.isFallback ? .fallback : .reviewed
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

  private static func counts(_ values: [String]) -> [String: Int] {
    values.reduce(into: [:]) { counts, value in counts[value, default: 0] += 1 }
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  private static func isInsideRoot(_ fileURL: URL, root: URL) -> Bool {
    let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
    return fileURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(rootPath)
  }

  private static func formatted(_ value: Double) -> String {
    String(format: "%.6f", value)
  }
}
