import Foundation
import Observation

struct KnowledgePackSummary: Equatable, Sendable {
  let packID: String
  let title: String
  let profileReferences: [DomainProfileReference]
  let sourceCount: Int
  let assertionCount: Int
  let responseCardCount: Int

  init(pack: KnowledgePack) {
    packID = pack.manifest.packID
    title = pack.manifest.title
    profileReferences = pack.manifest.domainProfiles
    sourceCount = pack.sources.count
    assertionCount = pack.assertions.count
    responseCardCount = pack.responseCards.count
  }
}

enum KnowledgePackLoadState: Equatable, Sendable {
  case idle
  case loading(path: String)
  case loaded(path: String, summary: KnowledgePackSummary)
  case failed(path: String, message: String)
}

@MainActor
@Observable
final class KnowledgePackStore {
  private let loader: KnowledgePackLoader
  let profileRegistry: KnowledgeDomainProfileRegistry
  private(set) var selectedPack: KnowledgePack?
  private(set) var selectedPackDirectory: URL?
  private(set) var searchIndex: KnowledgePackSearchIndex?
  private(set) var searchRebuildReport: KnowledgePackSearchRebuildReport?
  private(set) var evidenceOutcomeEvaluator: KnowledgeEvidenceOutcomeEvaluator?
  private(set) var tieredAnswerResolver: KnowledgeTieredAnswerResolver?
  private(set) var state: KnowledgePackLoadState = .idle
  private(set) var activeQuestionCandidates: [String: QuestionCandidate] = [:]
  private(set) var activeAnswerCards: [String: KnowledgeAnswerCard] = [:]
  private(set) var latestQuestionCandidateEvents: [QuestionCandidateEvent] = []
  private(set) var latestLiveKnowledgeEvents: [KnowledgeLiveEvent] = []
  private var requestedPath = ""
  private var liveEventDetector: KnowledgeLiveEventDetector?
  private var answerCardResolver: KnowledgeAnswerCardResolver?
  private var liveRevisionSequenceByStream: [String: Int] = [:]

  init(profileRegistry: KnowledgeDomainProfileRegistry) {
    self.profileRegistry = profileRegistry
    loader = KnowledgePackLoader(profileRegistry: profileRegistry)
  }

  func load(fromPath path: String) async {
    let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedPath.isEmpty else {
      clear()
      return
    }
    if requestedPath == normalizedPath {
      switch state {
      case .loading, .loaded:
        return
      case .idle, .failed:
        break
      }
    }

    requestedPath = normalizedPath
    state = .loading(path: normalizedPath)
    let loader = loader
    let previousPack = selectedPack
    let previousIndex = searchIndex
    let directory = URL(fileURLWithPath: normalizedPath, isDirectory: true).standardizedFileURL

    do {
      let result = try await Task.detached(priority: .userInitiated) {
        let pack = try loader.load(from: directory)
        let searchBuild = try KnowledgePackSearchIndexer.build(
          pack: pack,
          previousPack: previousPack,
          previousIndex: previousIndex
        )
        let evidenceOutcomeEvaluator = try KnowledgeEvidenceOutcomeEvaluator(
          pack: pack,
          searchIndex: searchBuild.index,
          rootDirectory: directory
        )
        let tieredAnswerResolver = try KnowledgeTieredAnswerResolver(
          pack: pack,
          searchIndex: searchBuild.index,
          evidenceEvaluator: evidenceOutcomeEvaluator,
          rootDirectory: directory
        )
        return (pack, searchBuild, evidenceOutcomeEvaluator, tieredAnswerResolver)
      }.value
      guard requestedPath == normalizedPath, !Task.isCancelled else { return }
      selectedPack = result.0
      selectedPackDirectory = directory
      searchIndex = result.1.index
      searchRebuildReport = result.1.report
      evidenceOutcomeEvaluator = result.2
      tieredAnswerResolver = result.3
      configureLiveKnowledgePath(for: result.0, rootDirectory: directory)
      state = .loaded(path: normalizedPath, summary: KnowledgePackSummary(pack: result.0))
    } catch {
      guard requestedPath == normalizedPath, !Task.isCancelled else { return }
      selectedPack = nil
      selectedPackDirectory = nil
      searchIndex = nil
      searchRebuildReport = nil
      evidenceOutcomeEvaluator = nil
      tieredAnswerResolver = nil
      clearQuestionCandidateDetector()
      state = .failed(path: normalizedPath, message: String(describing: error))
    }
  }

  func retry() async {
    let path = requestedPath
    requestedPath = ""
    await load(fromPath: path)
  }

  func reload() async {
    let path = requestedPath
    guard !path.isEmpty else { return }
    requestedPath = ""
    await load(fromPath: path)
  }

  func clear() {
    requestedPath = ""
    selectedPack = nil
    selectedPackDirectory = nil
    searchIndex = nil
    searchRebuildReport = nil
    evidenceOutcomeEvaluator = nil
    tieredAnswerResolver = nil
    clearQuestionCandidateDetector()
    state = .idle
  }

  func searchKnowledgePack(
    _ query: KnowledgePackSearchQuery
  ) throws -> [KnowledgePackSearchResult] {
    guard let searchIndex else { throw KnowledgePackSearchError.indexUnavailable }
    return try searchIndex.search(query)
  }

  func searchKnowledgePack(
    _ query: KnowledgePackSearchQuery,
    vectorAdapter: any KnowledgePackVectorSearchAdapter
  ) async throws -> [KnowledgePackSearchResult] {
    guard let searchIndex else { throw KnowledgePackSearchError.indexUnavailable }
    return try await searchIndex.search(query, vectorAdapter: vectorAdapter)
  }

  func evaluateKnowledgeEvidence(
    _ query: KnowledgeEvidenceQuery
  ) throws -> KnowledgeEvidenceOutcome {
    guard let evidenceOutcomeEvaluator else { throw KnowledgePackSearchError.indexUnavailable }
    return try evidenceOutcomeEvaluator.evaluate(query)
  }

  func answerUpdates(
    for event: KnowledgeLiveEvent,
    vectorAdapter: (any KnowledgePackVectorSearchAdapter)? = nil,
    synthesizer: (any KnowledgeConstrainedAnswerSynthesizer)? = nil
  ) -> AsyncStream<KnowledgeTieredAnswerUpdate> {
    guard let tieredAnswerResolver else {
      return AsyncStream { $0.finish() }
    }
    return tieredAnswerResolver.updates(
      for: event,
      vectorAdapter: vectorAdapter,
      synthesizer: synthesizer
    )
  }

  @discardableResult
  func processTranscriptRevision(_ revision: TranscriptRevision) -> [QuestionCandidateEvent] {
    _ = processLiveTranscriptRevision(revision)
    return latestQuestionCandidateEvents
  }

  @discardableResult
  func processLiveTranscriptRevision(_ revision: TranscriptRevision) -> [KnowledgeLiveEvent] {
    guard var detector = liveEventDetector else { return [] }
    liveRevisionSequenceByStream[revision.streamID] = max(
      liveRevisionSequenceByStream[revision.streamID] ?? Int.min,
      revision.sequence
    )
    let events = detector.process(revision)
    liveEventDetector = detector
    apply(events)
    return events
  }

  @discardableResult
  func processTranscriptText(
    streamID: String,
    text: String,
    stability: TranscriptRevision.Stability
  ) -> [QuestionCandidateEvent] {
    let sequence = (liveRevisionSequenceByStream[streamID] ?? 0) + 1
    return processTranscriptRevision(
      TranscriptRevision(
        streamID: streamID,
        sequence: sequence,
        text: text,
        stability: stability
      ))
  }

  @discardableResult
  func cancelTranscriptStream(_ streamID: String) -> [QuestionCandidateEvent] {
    processTranscriptText(streamID: streamID, text: "", stability: .partial)
  }

  func activeQuestionCandidate(forStreamID streamID: String) -> QuestionCandidate? {
    activeQuestionCandidates[streamID]
  }

  func activeAnswerCard(forStreamID streamID: String) -> KnowledgeAnswerCard? {
    activeAnswerCards[streamID]
  }

  private func configureLiveKnowledgePath(for pack: KnowledgePack, rootDirectory: URL) {
    clearQuestionCandidateDetector()
    liveEventDetector = KnowledgeLiveEventDetector(
      questionFamilies: pack.questionFamilies,
      termAliases: profileRegistry.termAliases(for: pack.manifest)
    )
    answerCardResolver = KnowledgeAnswerCardResolver(pack: pack, rootDirectory: rootDirectory)
  }

  private func clearQuestionCandidateDetector() {
    guard var detector = liveEventDetector else {
      activeQuestionCandidates.removeAll()
      activeAnswerCards.removeAll()
      latestQuestionCandidateEvents = []
      latestLiveKnowledgeEvents = []
      answerCardResolver = nil
      return
    }
    let sequence = activeQuestionCandidates.values.map(\.revisionSequence).max() ?? 0
    let events = detector.cancelAll(sequence: sequence + 1)
    liveEventDetector = nil
    apply(events)
    answerCardResolver = nil
  }

  private func apply(_ events: [KnowledgeLiveEvent]) {
    latestLiveKnowledgeEvents = events
    var questionEvents: [QuestionCandidateEvent] = []
    for event in events {
      switch event {
      case .questionCandidate(let candidate), .questionStable(let candidate):
        questionEvents.append(.upsert(candidate))
        activeQuestionCandidates[candidate.streamID] = candidate
        if let answerCard = answerCardResolver?.resolve(candidate) {
          activeAnswerCards[candidate.streamID] = answerCard
        } else {
          activeAnswerCards.removeValue(forKey: candidate.streamID)
        }
      case .answerSuperseded(let supersession):
        guard
          activeQuestionCandidates[supersession.previousStreamID]?.id
            == supersession.previousEventID
        else { continue }
        let cancellation = QuestionCandidateCancellation(
          candidateID: supersession.previousEventID,
          streamID: supersession.previousStreamID,
          revisionSequence: supersession.revisionSequence,
          reason: Self.cancellationReason(for: supersession.reason)
        )
        questionEvents.append(.cancel(cancellation))
        activeQuestionCandidates.removeValue(forKey: supersession.previousStreamID)
        activeAnswerCards.removeValue(forKey: supersession.previousStreamID)
      case .claimCandidate, .claimStable, .topicShift, .noAction:
        continue
      }
    }
    latestQuestionCandidateEvents = questionEvents
  }

  private static func cancellationReason(
    for reason: KnowledgeAnswerSupersessionReason
  ) -> QuestionCandidateCancellationReason {
    switch reason {
    case .cleared: .cleared
    case .corrected: .corrected
    case .followUp, .interrupted: .superseded
    case .packChanged: .packChanged
    }
  }
}
