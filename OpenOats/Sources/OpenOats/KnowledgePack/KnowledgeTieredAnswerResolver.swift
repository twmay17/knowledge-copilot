import Foundation
import os

public enum KnowledgeAnswerLane: String, CaseIterable, Codable, Equatable, Sendable {
  case hot
  case warm
  case cold
}

public struct KnowledgeAnswerLatencyBudgets: Equatable, Sendable {
  public let hotMilliseconds: Int
  public let warmMilliseconds: Int
  public let coldMilliseconds: Int

  public init(
    hotMilliseconds: Int = 40,
    warmMilliseconds: Int = 250,
    coldMilliseconds: Int = 2_000
  ) {
    self.hotMilliseconds = max(1, hotMilliseconds)
    self.warmMilliseconds = max(1, warmMilliseconds)
    self.coldMilliseconds = max(1, coldMilliseconds)
  }

  public func milliseconds(for lane: KnowledgeAnswerLane) -> Int {
    switch lane {
    case .hot: hotMilliseconds
    case .warm: warmMilliseconds
    case .cold: coldMilliseconds
    }
  }
}

public struct KnowledgeAnswerLaneTiming: Equatable, Sendable {
  public let budgetMilliseconds: Int
  public let elapsedMilliseconds: Double

  public init(budgetMilliseconds: Int, elapsedMilliseconds: Double) {
    self.budgetMilliseconds = budgetMilliseconds
    self.elapsedMilliseconds = elapsedMilliseconds
  }
}

public enum KnowledgeAnswerSupportLevel: Int, Codable, Comparable, Equatable, Sendable {
  case abstention = 0
  case retrievedOnly = 1
  case corpusVerified = 2
  case reviewed = 3

  public static func < (
    lhs: KnowledgeAnswerSupportLevel,
    rhs: KnowledgeAnswerSupportLevel
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum KnowledgeAnswerPresentationQuality: Int, Codable, Comparable, Equatable, Sendable {
  case fallback = 0
  case evidencePreview = 1
  case exactEvidence = 2
  case constrainedSynthesis = 3
  case reviewedCard = 4

  public static func < (
    lhs: KnowledgeAnswerPresentationQuality,
    rhs: KnowledgeAnswerPresentationQuality
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct KnowledgeSynthesisEvidenceRecord: Equatable, Sendable, Identifiable {
  public let id: String
  public let kind: KnowledgePackSearchRecordKind
  public let title: String
  public let text: String
  public let sourceIDs: [String]
  public let qualifiers: [String: String]

  public init(
    id: String,
    kind: KnowledgePackSearchRecordKind,
    title: String,
    text: String,
    sourceIDs: [String],
    qualifiers: [String: String]
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.text = text
    self.sourceIDs = sourceIDs
    self.qualifiers = qualifiers
  }
}

public struct KnowledgeSynthesisCitationRequirement: Equatable, Sendable {
  public let anyOfEvidenceRecordIDs: Set<String>

  public init(anyOfEvidenceRecordIDs: Set<String>) {
    self.anyOfEvidenceRecordIDs = anyOfEvidenceRecordIDs
  }
}

/// The complete input exposed to optional answer synthesis.
///
/// It intentionally contains no pack, search index, URL loader, network client, tool callback, or
/// retrieval closure. An adapter can phrase only the evidence records admitted by the resolver.
public struct KnowledgeConstrainedSynthesisRequest: Equatable, Sendable {
  public let packID: String
  public let packContentHash: String
  public let eventID: String
  public let sourceText: String
  public let evidenceState: KnowledgeEvidenceState
  public let evidenceRecords: [KnowledgeSynthesisEvidenceRecord]
  public let citationRequirements: [KnowledgeSynthesisCitationRequirement]

  public init(
    packID: String,
    packContentHash: String,
    eventID: String,
    sourceText: String,
    evidenceState: KnowledgeEvidenceState,
    evidenceRecords: [KnowledgeSynthesisEvidenceRecord],
    citationRequirements: [KnowledgeSynthesisCitationRequirement]
  ) {
    self.packID = packID
    self.packContentHash = packContentHash
    self.eventID = eventID
    self.sourceText = sourceText
    self.evidenceState = evidenceState
    self.evidenceRecords = evidenceRecords
    self.citationRequirements = citationRequirements
  }
}

public struct KnowledgeConstrainedSynthesisOutput: Equatable, Sendable {
  public let title: String
  public let answer: String
  public let citedEvidenceRecordIDs: [String]

  public init(title: String, answer: String, citedEvidenceRecordIDs: [String]) {
    self.title = title
    self.answer = answer
    self.citedEvidenceRecordIDs = citedEvidenceRecordIDs
  }
}

/// Capability-poor by construction: implementations receive evidence, not a search or tool API.
public protocol KnowledgeConstrainedAnswerSynthesizer: Sendable {
  var dataDestination: KnowledgeDataDestination { get }

  func synthesize(
    _ envelope: KnowledgeConstrainedSynthesisEnvelope
  ) async throws -> KnowledgeConstrainedSynthesisOutput
}

extension KnowledgeConstrainedAnswerSynthesizer {
  public var dataDestination: KnowledgeDataDestination { .externalProvider }
}

public enum KnowledgeTieredAnswerPayload: Equatable, Sendable {
  case reviewedCard(KnowledgeAnswerCard)
  case exactEvidence(KnowledgeEvidenceOutcome)
  case retrievedEvidence([KnowledgePackSearchResult])
  case constrainedSynthesis(
    output: KnowledgeConstrainedSynthesisOutput,
    evidence: KnowledgeEvidenceOutcome
  )
}

public enum KnowledgeTieredAnswerUpdateAction: String, Codable, Equatable, Sendable {
  case show
  case supersede
  case refine
  case retract
}

public struct KnowledgeTieredAnswerUpdate: Equatable, Sendable, Identifiable {
  public let id: String
  public let eventID: String
  public let streamID: String
  public let revisionSequence: Int
  public let lane: KnowledgeAnswerLane?
  public let action: KnowledgeTieredAnswerUpdateAction
  public let supersedesUpdateID: String?
  public let supportLevel: KnowledgeAnswerSupportLevel
  public let presentationQuality: KnowledgeAnswerPresentationQuality
  public let isProvisional: Bool
  public let timing: KnowledgeAnswerLaneTiming?
  public let payload: KnowledgeTieredAnswerPayload?

  public init(
    id: String,
    eventID: String,
    streamID: String,
    revisionSequence: Int,
    lane: KnowledgeAnswerLane?,
    action: KnowledgeTieredAnswerUpdateAction,
    supersedesUpdateID: String?,
    supportLevel: KnowledgeAnswerSupportLevel,
    presentationQuality: KnowledgeAnswerPresentationQuality,
    isProvisional: Bool,
    timing: KnowledgeAnswerLaneTiming?,
    payload: KnowledgeTieredAnswerPayload?
  ) {
    self.id = id
    self.eventID = eventID
    self.streamID = streamID
    self.revisionSequence = revisionSequence
    self.lane = lane
    self.action = action
    self.supersedesUpdateID = supersedesUpdateID
    self.supportLevel = supportLevel
    self.presentationQuality = presentationQuality
    self.isProvisional = isProvisional
    self.timing = timing
    self.payload = payload
  }
}

/// Streams the fastest admissible answer and only replaces it with stronger support or a
/// same-evidence presentation refinement.
public struct KnowledgeTieredAnswerResolver: Sendable {
  fileprivate struct Input: Sendable {
    let eventID: String
    let streamID: String
    let revisionSequence: Int
    let sourceText: String
    let isProvisional: Bool
    let question: QuestionCandidate?
    let bindings: [KnowledgeLiveBinding]
    let proposedValue: KnowledgeValue?
  }

  private struct HotResolution: Sendable {
    let card: KnowledgeAnswerCard?
    let evidence: KnowledgeEvidenceOutcome?
  }

  private struct WarmResolution: Sendable {
    let results: [KnowledgePackSearchResult]
    let evidence: KnowledgeEvidenceOutcome?
  }

  private struct Budgeted<Value: Sendable>: Sendable {
    let value: Value?
    let timing: KnowledgeAnswerLaneTiming
  }

  fileprivate struct Proposal: Sendable {
    let eventID: String
    let streamID: String
    let revisionSequence: Int
    let lane: KnowledgeAnswerLane
    let supportLevel: KnowledgeAnswerSupportLevel
    let presentationQuality: KnowledgeAnswerPresentationQuality
    let evidenceFingerprint: String
    let isProvisional: Bool
    let timing: KnowledgeAnswerLaneTiming
    let payload: KnowledgeTieredAnswerPayload
  }

  private let pack: KnowledgePack
  private let searchIndex: KnowledgePackSearchIndex
  private let evidenceEvaluator: KnowledgeEvidenceOutcomeEvaluator
  private let answerCardResolver: KnowledgeAnswerCardResolver
  private let budgets: KnowledgeAnswerLatencyBudgets
  private let state = KnowledgeTieredAnswerState()

  public init(
    pack: KnowledgePack,
    searchIndex: KnowledgePackSearchIndex,
    evidenceEvaluator: KnowledgeEvidenceOutcomeEvaluator,
    rootDirectory: URL,
    budgets: KnowledgeAnswerLatencyBudgets = KnowledgeAnswerLatencyBudgets()
  ) throws {
    let contentHash = try KnowledgeStudyBundleBuilder().build(from: pack).packContentHash
    guard searchIndex.packID == pack.manifest.packID,
      searchIndex.packContentHash == contentHash,
      evidenceEvaluator.packID == pack.manifest.packID,
      evidenceEvaluator.packContentHash == contentHash
    else { throw KnowledgeEvidenceOutcomeError.staleIndex }
    self.pack = pack
    self.searchIndex = searchIndex
    self.evidenceEvaluator = evidenceEvaluator
    answerCardResolver = KnowledgeAnswerCardResolver(pack: pack, rootDirectory: rootDirectory)
    self.budgets = budgets
  }

  public func updates(
    for event: KnowledgeLiveEvent,
    vectorAdapter: (any KnowledgePackVectorSearchAdapter)? = nil,
    synthesizer: (any KnowledgeConstrainedAnswerSynthesizer)? = nil,
    networkMode: KnowledgeNetworkMode = .offline
  ) -> AsyncStream<KnowledgeTieredAnswerUpdate> {
    AsyncStream { continuation in
      let task = Task {
        await resolve(
          event,
          vectorAdapter: vectorAdapter,
          synthesizer: synthesizer,
          networkMode: networkMode,
          continuation: continuation
        )
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func resolve(
    _ event: KnowledgeLiveEvent,
    vectorAdapter: (any KnowledgePackVectorSearchAdapter)?,
    synthesizer: (any KnowledgeConstrainedAnswerSynthesizer)?,
    networkMode: KnowledgeNetworkMode,
    continuation: AsyncStream<KnowledgeTieredAnswerUpdate>.Continuation
  ) async {
    defer { continuation.finish() }

    if case .answerSuperseded(let supersession) = event {
      if let retraction = await state.retract(supersession) {
        continuation.yield(retraction)
      }
      return
    }
    guard let input = makeInput(event) else { return }
    let start = await state.begin(input)
    guard start.accepted else { return }
    if let retraction = start.retraction { continuation.yield(retraction) }
    guard !Task.isCancelled else { return }

    let hot = await runWithinBudget(lane: .hot) {
      let card = input.question.flatMap(answerCardResolver.resolve)
      let evidence = makeEvidenceQuery(input).flatMap { query in
        try? evidenceEvaluator.evaluate(query)
      }
      return HotResolution(card: card, evidence: evidence)
    }
    guard !Task.isCancelled else { return }
    var admittedEvidence = hot.value?.evidence
    if let hotValue = hot.value,
      let proposal = hotProposal(input: input, resolution: hotValue, timing: hot.timing),
      let update = await state.publish(proposal)
    {
      continuation.yield(update)
    }
    guard !Task.isCancelled, await state.isCurrent(input) else { return }

    let previouslyAdmittedEvidence = admittedEvidence
    let warm = await runWithinBudget(lane: .warm) {
      let query = makeSearchQuery(input)
      let results: [KnowledgePackSearchResult]
      if let vectorAdapter, networkMode.permits(vectorAdapter.dataDestination) {
        results = (try? await searchIndex.search(query, vectorAdapter: vectorAdapter)) ?? []
      } else {
        results = (try? searchIndex.search(query)) ?? []
      }
      let evidence =
        previouslyAdmittedEvidence
        ?? makeEvidenceQuery(input).flatMap { query in
          try? evidenceEvaluator.evaluate(query)
        }
      return WarmResolution(results: results, evidence: evidence)
    }
    guard !Task.isCancelled else { return }
    if let warmValue = warm.value {
      admittedEvidence = warmValue.evidence
      if let proposal = warmProposal(input: input, resolution: warmValue, timing: warm.timing),
        let update = await state.publish(proposal)
      {
        continuation.yield(update)
      }
    }
    guard !Task.isCancelled, await state.isCurrent(input), let synthesizer, let admittedEvidence,
      Self.isCorpusSupported(admittedEvidence.state),
      networkMode.permits(synthesizer.dataDestination)
    else { return }

    if await state.hasReviewedAnswer(for: input) { return }
    let synthesisRequest = makeSynthesisRequest(
      input: input,
      evidence: admittedEvidence,
      retrievalResults: warm.value?.results ?? []
    )
    guard !synthesisRequest.evidenceRecords.isEmpty,
      !synthesisRequest.citationRequirements.isEmpty
    else { return }
    guard
      let synthesisEnvelope = try? KnowledgeConstrainedSynthesisEnvelope(
        request: synthesisRequest,
        destination: synthesizer.dataDestination
      )
    else { return }

    let cold = await runWithinBudget(lane: .cold) {
      try? await synthesizer.synthesize(synthesisEnvelope)
    }
    guard !Task.isCancelled, let output = cold.value,
      Self.isValid(output, for: synthesisRequest),
      await state.isCurrent(input)
    else { return }
    let proposal = Proposal(
      eventID: input.eventID,
      streamID: input.streamID,
      revisionSequence: input.revisionSequence,
      lane: .cold,
      supportLevel: .corpusVerified,
      presentationQuality: .constrainedSynthesis,
      evidenceFingerprint: Self.evidenceFingerprint(admittedEvidence),
      isProvisional: input.isProvisional,
      timing: cold.timing,
      payload: .constrainedSynthesis(output: output, evidence: admittedEvidence)
    )
    if let update = await state.publish(proposal) { continuation.yield(update) }
  }

  private func makeInput(_ event: KnowledgeLiveEvent) -> Input? {
    switch event {
    case .questionCandidate(let candidate), .questionStable(let candidate):
      return Input(
        eventID: candidate.id,
        streamID: candidate.streamID,
        revisionSequence: candidate.revisionSequence,
        sourceText: candidate.sourceText,
        isProvisional: candidate.status == .provisional,
        question: candidate,
        bindings: candidate.bindings.map {
          KnowledgeLiveBinding(key: $0.key, value: $0.value, surfaceText: $0.surfaceText)
        },
        proposedValue: nil
      )
    case .claimCandidate(let candidate), .claimStable(let candidate):
      return Input(
        eventID: candidate.id,
        streamID: candidate.streamID,
        revisionSequence: candidate.revisionSequence,
        sourceText: candidate.sourceText,
        isProvisional: candidate.status == .provisional,
        question: nil,
        bindings: candidate.bindings,
        proposedValue: proposedValue(for: candidate.bindings)
      )
    case .topicShift, .answerSuperseded, .noAction:
      return nil
    }
  }

  private func makeEvidenceQuery(_ input: Input) -> KnowledgeEvidenceQuery? {
    let predicates = Set(
      input.bindings.filter { $0.key == "term" }.map(\.value).filter {
        !$0.hasPrefix("question_family:")
      })
    guard predicates.count == 1, let predicate = predicates.first else { return nil }
    var qualifiers: [String: String] = [:]
    let periods = Set(input.bindings.filter { $0.key == "period" }.map(\.value))
    if periods.count == 1 { qualifiers["period"] = periods.first }
    let subjects = Set(pack.assertions.filter { $0.predicate == predicate }.map(\.subject))
    return KnowledgeEvidenceQuery(
      subject: subjects.count == 1 ? subjects.first : nil,
      predicate: predicate,
      qualifiers: qualifiers,
      proposedValue: input.proposedValue
    )
  }

  private func makeSearchQuery(_ input: Input) -> KnowledgePackSearchQuery {
    var preferredQualifiers: [String: String] = [:]
    let periods = Set(input.bindings.filter { $0.key == "period" }.map(\.value))
    if periods.count == 1 { preferredQualifiers["period"] = periods.first }
    return KnowledgePackSearchQuery(
      text: input.sourceText,
      scope: KnowledgePackSearchScope(
        packID: pack.manifest.packID,
        recordKinds: [.assertion, .calculation, .passage, .responseCard],
        preferredQualifiers: preferredQualifiers
      ),
      limit: 12
    )
  }

  private func hotProposal(
    input: Input,
    resolution: HotResolution,
    timing: KnowledgeAnswerLaneTiming
  ) -> Proposal? {
    if let card = resolution.card, !card.isFallback,
      Self.isCorpusSupported(card.evidenceState)
    {
      return Proposal(
        eventID: input.eventID,
        streamID: input.streamID,
        revisionSequence: input.revisionSequence,
        lane: .hot,
        supportLevel: .reviewed,
        presentationQuality: .reviewedCard,
        evidenceFingerprint: Self.cardFingerprint(card),
        isProvisional: input.isProvisional,
        timing: timing,
        payload: .reviewedCard(card)
      )
    }
    if let evidence = resolution.evidence, Self.isCorpusSupported(evidence.state) {
      return exactProposal(input: input, evidence: evidence, lane: .hot, timing: timing)
    }
    if let card = resolution.card {
      return Proposal(
        eventID: input.eventID,
        streamID: input.streamID,
        revisionSequence: input.revisionSequence,
        lane: .hot,
        supportLevel: .abstention,
        presentationQuality: card.isFallback ? .fallback : .reviewedCard,
        evidenceFingerprint: Self.cardFingerprint(card),
        isProvisional: input.isProvisional,
        timing: timing,
        payload: .reviewedCard(card)
      )
    }
    if let evidence = resolution.evidence {
      return exactProposal(input: input, evidence: evidence, lane: .hot, timing: timing)
    }
    return nil
  }

  private func warmProposal(
    input: Input,
    resolution: WarmResolution,
    timing: KnowledgeAnswerLaneTiming
  ) -> Proposal? {
    if let evidence = resolution.evidence {
      return exactProposal(input: input, evidence: evidence, lane: .warm, timing: timing)
    }
    guard !resolution.results.isEmpty else { return nil }
    return Proposal(
      eventID: input.eventID,
      streamID: input.streamID,
      revisionSequence: input.revisionSequence,
      lane: .warm,
      supportLevel: .retrievedOnly,
      presentationQuality: .evidencePreview,
      evidenceFingerprint: resolution.results.map(\.id).sorted().joined(separator: "|"),
      isProvisional: input.isProvisional,
      timing: timing,
      payload: .retrievedEvidence(resolution.results)
    )
  }

  private func exactProposal(
    input: Input,
    evidence: KnowledgeEvidenceOutcome,
    lane: KnowledgeAnswerLane,
    timing: KnowledgeAnswerLaneTiming
  ) -> Proposal {
    let supported = Self.isCorpusSupported(evidence.state)
    return Proposal(
      eventID: input.eventID,
      streamID: input.streamID,
      revisionSequence: input.revisionSequence,
      lane: lane,
      supportLevel: supported ? .corpusVerified : .abstention,
      presentationQuality: supported ? .exactEvidence : .fallback,
      evidenceFingerprint: Self.evidenceFingerprint(evidence),
      isProvisional: input.isProvisional,
      timing: timing,
      payload: .exactEvidence(evidence)
    )
  }

  private func makeSynthesisRequest(
    input: Input,
    evidence: KnowledgeEvidenceOutcome,
    retrievalResults: [KnowledgePackSearchResult]
  ) -> KnowledgeConstrainedSynthesisRequest {
    var recordsByID: [String: KnowledgeSynthesisEvidenceRecord] = [:]
    var requirements: [KnowledgeSynthesisCitationRequirement] = []
    for claim in evidence.claims {
      let assertionRecordID = "assertion:\(claim.assertionID)"
      recordsByID[assertionRecordID] = KnowledgeSynthesisEvidenceRecord(
        id: assertionRecordID,
        kind: .assertion,
        title: claim.predicate,
        text: Self.claimText(claim),
        sourceIDs: Array(Set(claim.attributions.map(\.sourceID))).sorted(),
        qualifiers: claim.qualifiers
      )
      var citationOptions: Set<String> = [assertionRecordID]
      for attribution in claim.attributions {
        let passageRecordID = "passage:\(attribution.passageID)"
        citationOptions.insert(passageRecordID)
        recordsByID[passageRecordID] = KnowledgeSynthesisEvidenceRecord(
          id: passageRecordID,
          kind: .passage,
          title: attribution.sourceTitle,
          text: attribution.excerpt,
          sourceIDs: [attribution.sourceID],
          qualifiers: claim.qualifiers
        )
      }
      requirements.append(
        KnowledgeSynthesisCitationRequirement(anyOfEvidenceRecordIDs: citationOptions))
    }
    for result in retrievalResults
    where result.packID == evidence.packID
      && result.packContentHash == evidence.packContentHash
    {
      let recordID = "retrieval:\(result.kind.rawValue):\(result.recordID)"
      recordsByID[recordID] = KnowledgeSynthesisEvidenceRecord(
        id: recordID,
        kind: result.kind,
        title: result.title,
        text: result.excerpt,
        sourceIDs: result.sourceIDs,
        qualifiers: result.qualifiers
      )
    }
    return KnowledgeConstrainedSynthesisRequest(
      packID: evidence.packID,
      packContentHash: evidence.packContentHash,
      eventID: input.eventID,
      sourceText: input.sourceText,
      evidenceState: evidence.state,
      evidenceRecords: recordsByID.values.sorted { $0.id < $1.id },
      citationRequirements: requirements
    )
  }

  private func proposedValue(for bindings: [KnowledgeLiveBinding]) -> KnowledgeValue? {
    let predicates = Set(bindings.filter { $0.key == "term" }.map(\.value))
    let literals = Set(bindings.filter { $0.key == "literal" }.map(\.value))
    guard predicates.count == 1, let predicate = predicates.first,
      literals.count == 1, let literal = literals.first
    else { return nil }
    let templates = pack.assertions.filter { $0.predicate == predicate }.map(\.value)
    let signatures = Set(templates.map(Self.valueSignature))
    guard signatures.count == 1, let template = templates.first, template.type == .number,
      let parsed = Self.parseNumber(literal, unit: template.unit)
    else { return nil }
    return KnowledgeValue(
      type: .number,
      number: parsed,
      unit: template.unit,
      scale: 1
    )
  }

  private func runWithinBudget<Value: Sendable>(
    lane: KnowledgeAnswerLane,
    operation: @escaping @Sendable () async -> Value?
  ) async -> Budgeted<Value> {
    let budgetMilliseconds = budgets.milliseconds(for: lane)
    let clock = ContinuousClock()
    let start = clock.now
    guard !Task.isCancelled else {
      return Budgeted(
        value: nil,
        timing: KnowledgeAnswerLaneTiming(
          budgetMilliseconds: budgetMilliseconds,
          elapsedMilliseconds: 0
        )
      )
    }
    // A structured race cannot return before its children finish, so a
    // cancellation-resistant adapter would stall the stream past every
    // budget. Run the operation as an explicit task, resume a continuation
    // exactly once (result or timeout), and forward cancellation to the
    // operation task from both the timeout path and outer cancellation —
    // cooperative adapters still stop promptly; resistant ones leak a
    // discarded background task instead of blocking the answer stream.
    let operationTask = Task { await operation() }
    let resumed = OSAllocatedUnfairLock(initialState: false)
    let value: Value? = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
        Task {
          let result = await operationTask.value
          let claimed = resumed.withLock { state -> Bool in
            if state { return false }
            state = true
            return true
          }
          if claimed { continuation.resume(returning: result) }
        }
        Task {
          try? await Task.sleep(for: .milliseconds(budgetMilliseconds))
          let claimed = resumed.withLock { state -> Bool in
            if state { return false }
            state = true
            return true
          }
          if claimed {
            operationTask.cancel()
            continuation.resume(returning: nil)
          }
        }
      }
    } onCancel: {
      operationTask.cancel()
    }
    let elapsed = start.duration(to: clock.now)
    return Budgeted(
      value: value,
      timing: KnowledgeAnswerLaneTiming(
        budgetMilliseconds: budgetMilliseconds,
        elapsedMilliseconds: Self.milliseconds(elapsed)
      )
    )
  }

  private static func isValid(
    _ output: KnowledgeConstrainedSynthesisOutput,
    for request: KnowledgeConstrainedSynthesisRequest
  ) -> Bool {
    guard !output.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !output.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return false }
    let allowedIDs = Set(request.evidenceRecords.map(\.id))
    let citedIDs = Set(output.citedEvidenceRecordIDs)
    guard !citedIDs.isEmpty, citedIDs.isSubset(of: allowedIDs) else { return false }
    guard
      request.citationRequirements.allSatisfy({
        !citedIDs.isDisjoint(with: $0.anyOfEvidenceRecordIDs)
      })
    else { return false }
    return numericTokensAreSupported(in: output, for: request)
  }

  private static func isCorpusSupported(_ state: KnowledgeEvidenceState) -> Bool {
    switch state {
    case .directlySourced, .calculated, .supportedByCorpus, .contradictedByCorpus, .contested,
      .interpretive:
      return true
    case .notFoundInCorpus, .needsClarification:
      return false
    }
  }

  /// Every number the model writes must match a number present in the
  /// admitted evidence (title, text, or qualifier values), allowing
  /// percent/ratio re-expression (x, x/100, x*100) within the same ULP bound
  /// used for claim fact-checking. A valid citation set cannot smuggle
  /// unsupported figures into the prose; failure discards the synthesis and
  /// leaves the deterministic card visible. Conservative by design: prose
  /// counts ("all 3 sources agree") not present in evidence also reject.
  static func numericTokensAreSupported(
    in output: KnowledgeConstrainedSynthesisOutput,
    for request: KnowledgeConstrainedSynthesisRequest
  ) -> Bool {
    numericTokensAreSupported(in: output, by: request.evidenceRecords)
  }

  static func numericTokensAreSupported(
    in output: KnowledgeConstrainedSynthesisOutput,
    by records: [KnowledgeSynthesisEvidenceRecord]
  ) -> Bool {
    let proseNumbers = numericValues(in: output.title + "\n" + output.answer)
    guard !proseNumbers.isEmpty else { return true }
    let evidenceText = records.map { record in
      ([record.title, record.text] + record.qualifiers.values.sorted()).joined(separator: "\n")
    }.joined(separator: "\n")
    let evidenceNumbers = numericValues(in: evidenceText)
    return proseNumbers.allSatisfy { candidate in
      evidenceNumbers.contains { evidence in
        [1.0, 0.01, 100.0].contains { scale in
          KnowledgeEvidenceOutcomeEvaluator.ulpDistance(candidate * scale, evidence)
            .map { $0 <= KnowledgeEvidenceOutcomeEvaluator.maximumEquivalentULPDistance }
            ?? false
        }
      }
    }
  }

  /// Numeric tokens with optional thousands separators and decimals.
  static func numericValues(in text: String) -> [Double] {
    let pattern = #"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).compactMap { match in
      guard let swiftRange = Range(match.range, in: text) else { return nil }
      return Double(text[swiftRange].replacingOccurrences(of: ",", with: ""))
    }
  }

  private static func evidenceFingerprint(_ evidence: KnowledgeEvidenceOutcome) -> String {
    let claimIDs = evidence.claims.map(\.assertionID).sorted().joined(separator: ",")
    let sourceIDs = evidence.contributingSources.map(\.id).sorted().joined(separator: ",")
    return "\(evidence.packContentHash)|\(evidence.state.rawValue)|\(claimIDs)|\(sourceIDs)"
  }

  private static func cardFingerprint(_ card: KnowledgeAnswerCard) -> String {
    let passageIDs = card.citations.map(\.passageID).sorted().joined(separator: ",")
    return "\(card.responseCardID ?? "fallback")|\(card.evidenceState.rawValue)|\(passageIDs)"
  }

  private static func claimText(_ claim: KnowledgeEvidenceClaim) -> String {
    let qualifierText = claim.qualifiers.keys.sorted().map {
      "\($0)=\(claim.qualifiers[$0] ?? "")"
    }.joined(separator: ", ")
    return "\(claim.subject) — \(claim.predicate): \(claim.displayValue) [\(qualifierText)]"
  }

  private static func valueSignature(_ value: KnowledgeValue) -> String {
    "\(value.type.rawValue)|\(value.unit ?? "")|\(value.scale ?? 1)"
  }

  private static func parseNumber(_ literal: String, unit: String?) -> Double? {
    let isPercent = literal.contains("%")
    let stripped = literal.replacingOccurrences(
      of: "[^0-9+\\-.]",
      with: "",
      options: .regularExpression
    )
    guard var value = Double(stripped) else { return nil }
    if isPercent, unit == "ratio" { value /= 100 }
    return value
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}

private actor KnowledgeTieredAnswerState {
  struct Start: Sendable {
    let accepted: Bool
    let retraction: KnowledgeTieredAnswerUpdate?
  }

  private struct Active: Sendable {
    let eventID: String
    let revisionSequence: Int
  }

  private struct Visible: Sendable {
    let updateID: String
    let eventID: String
    let supportLevel: KnowledgeAnswerSupportLevel
    let presentationQuality: KnowledgeAnswerPresentationQuality
    let evidenceFingerprint: String
  }

  private var activeByStream: [String: Active] = [:]
  private var visibleByStream: [String: Visible] = [:]
  private var supersededEventIDs: Set<String> = []

  func begin(_ input: KnowledgeTieredAnswerResolver.Input) -> Start {
    guard !supersededEventIDs.contains(input.eventID) else {
      return Start(accepted: false, retraction: nil)
    }
    if let active = activeByStream[input.streamID],
      input.revisionSequence < active.revisionSequence
    {
      return Start(accepted: false, retraction: nil)
    }
    var retraction: KnowledgeTieredAnswerUpdate?
    if let active = activeByStream[input.streamID], active.eventID != input.eventID {
      supersededEventIDs.insert(active.eventID)
      if let visible = visibleByStream.removeValue(forKey: input.streamID) {
        retraction = Self.retraction(
          eventID: active.eventID,
          streamID: input.streamID,
          revisionSequence: input.revisionSequence,
          visible: visible
        )
      }
    }
    activeByStream[input.streamID] = Active(
      eventID: input.eventID,
      revisionSequence: input.revisionSequence
    )
    return Start(accepted: true, retraction: retraction)
  }

  func isCurrent(_ input: KnowledgeTieredAnswerResolver.Input) -> Bool {
    guard let active = activeByStream[input.streamID] else { return false }
    return active.eventID == input.eventID && active.revisionSequence == input.revisionSequence
  }

  func hasReviewedAnswer(for input: KnowledgeTieredAnswerResolver.Input) -> Bool {
    guard isCurrent(input), let visible = visibleByStream[input.streamID] else { return false }
    return visible.supportLevel == .reviewed
  }

  func publish(
    _ proposal: KnowledgeTieredAnswerResolver.Proposal
  ) -> KnowledgeTieredAnswerUpdate? {
    guard activeByStream[proposal.streamID]?.eventID == proposal.eventID,
      activeByStream[proposal.streamID]?.revisionSequence == proposal.revisionSequence
    else { return nil }

    let previous = visibleByStream[proposal.streamID]
    let action: KnowledgeTieredAnswerUpdateAction
    if let previous {
      if proposal.supportLevel > previous.supportLevel {
        action = .supersede
      } else if proposal.supportLevel == previous.supportLevel,
        proposal.evidenceFingerprint == previous.evidenceFingerprint,
        proposal.presentationQuality > previous.presentationQuality
      {
        action = .refine
      } else {
        return nil
      }
    } else {
      action = .show
    }

    let updateID = [
      proposal.eventID,
      String(proposal.revisionSequence),
      proposal.lane.rawValue,
      String(proposal.presentationQuality.rawValue),
    ].joined(separator: "#")
    let update = KnowledgeTieredAnswerUpdate(
      id: updateID,
      eventID: proposal.eventID,
      streamID: proposal.streamID,
      revisionSequence: proposal.revisionSequence,
      lane: proposal.lane,
      action: action,
      supersedesUpdateID: previous?.updateID,
      supportLevel: proposal.supportLevel,
      presentationQuality: proposal.presentationQuality,
      isProvisional: proposal.isProvisional,
      timing: proposal.timing,
      payload: proposal.payload
    )
    visibleByStream[proposal.streamID] = Visible(
      updateID: updateID,
      eventID: proposal.eventID,
      supportLevel: proposal.supportLevel,
      presentationQuality: proposal.presentationQuality,
      evidenceFingerprint: proposal.evidenceFingerprint
    )
    return update
  }

  func retract(_ supersession: KnowledgeAnswerSupersession) -> KnowledgeTieredAnswerUpdate? {
    guard
      activeByStream[supersession.previousStreamID]?.eventID
        == supersession.previousEventID
    else { return nil }
    supersededEventIDs.insert(supersession.previousEventID)
    activeByStream.removeValue(forKey: supersession.previousStreamID)
    guard let visible = visibleByStream.removeValue(forKey: supersession.previousStreamID) else {
      return nil
    }
    return Self.retraction(
      eventID: supersession.previousEventID,
      streamID: supersession.previousStreamID,
      revisionSequence: supersession.revisionSequence,
      visible: visible
    )
  }

  private static func retraction(
    eventID: String,
    streamID: String,
    revisionSequence: Int,
    visible: Visible
  ) -> KnowledgeTieredAnswerUpdate {
    KnowledgeTieredAnswerUpdate(
      id: "\(eventID)#\(revisionSequence)#retract",
      eventID: eventID,
      streamID: streamID,
      revisionSequence: revisionSequence,
      lane: nil,
      action: .retract,
      supersedesUpdateID: visible.updateID,
      supportLevel: .abstention,
      presentationQuality: .fallback,
      isProvisional: false,
      timing: nil,
      payload: nil
    )
  }
}
