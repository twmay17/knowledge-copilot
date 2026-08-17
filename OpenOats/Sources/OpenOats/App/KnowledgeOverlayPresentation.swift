import Foundation

struct KnowledgeOverlaySource: Equatable, Sendable, Identifiable {
  let id: String
  let title: String
  let locator: String
  let excerpt: String
  let fileURL: URL?
  let attribution: String?
}

struct KnowledgeOverlayClaim: Equatable, Sendable, Identifiable {
  let id: String
  let value: String
  let context: String
  let attribution: String
}

struct KnowledgeOverlayCorrectionRequest: Equatable, Sendable, Identifiable {
  let id: String
  let eventID: String
  let updateID: String
  let title: String
  let answer: String
  let evidenceState: KnowledgeEvidenceState
}

struct KnowledgeOverlayCard: Equatable, Sendable, Identifiable {
  let id: String
  let updateID: String
  let eventID: String
  let streamID: String
  let revisionSequence: Int
  let title: String
  let answer: String
  let evidenceState: KnowledgeEvidenceState
  let why: String
  let sources: [KnowledgeOverlaySource]
  let claims: [KnowledgeOverlayClaim]
  let calculations: [KnowledgeCalculationSummary]
  let lane: KnowledgeAnswerLane?
  let supportLevel: KnowledgeAnswerSupportLevel
  let presentationQuality: KnowledgeAnswerPresentationQuality
  let isProvisional: Bool
  var isPinned: Bool
  var isSuperseded: Bool
  var isCorrectionRequested: Bool

  var evidenceLabel: String { evidenceState.overlayLabel }
  var evidenceExplanation: String { evidenceState.overlayExplanation }

  static func make(
    from update: KnowledgeTieredAnswerUpdate,
    sourceCatalog: KnowledgeOverlaySourceCatalog? = nil
  ) -> KnowledgeOverlayCard? {
    guard let payload = update.payload else { return nil }

    let content: Content
    switch payload {
    case .reviewedCard(let card):
      content = reviewedContent(card)
    case .exactEvidence(let evidence):
      content = evidenceContent(evidence)
    case .retrievedEvidence(let results):
      content = retrievalContent(results, sourceCatalog: sourceCatalog)
    case .constrainedSynthesis(let output, let evidence):
      content = synthesisContent(output: output, evidence: evidence)
    }

    return KnowledgeOverlayCard(
      id: update.eventID,
      updateID: update.id,
      eventID: update.eventID,
      streamID: update.streamID,
      revisionSequence: update.revisionSequence,
      title: content.title,
      answer: content.answer,
      evidenceState: content.evidenceState,
      why: content.why,
      sources: content.sources,
      claims: content.claims,
      calculations: content.calculations,
      lane: update.lane,
      supportLevel: update.supportLevel,
      presentationQuality: update.presentationQuality,
      isProvisional: update.isProvisional,
      isPinned: false,
      isSuperseded: false,
      isCorrectionRequested: false
    )
  }

  private struct Content {
    let title: String
    let answer: String
    let evidenceState: KnowledgeEvidenceState
    let why: String
    let sources: [KnowledgeOverlaySource]
    let claims: [KnowledgeOverlayClaim]
    let calculations: [KnowledgeCalculationSummary]
  }

  private static func reviewedContent(_ card: KnowledgeAnswerCard) -> Content {
    Content(
      title: card.title,
      answer: card.answer,
      evidenceState: card.evidenceState,
      why: card.evidenceState.overlayExplanation,
      sources: card.citations.map {
        KnowledgeOverlaySource(
          id: $0.id,
          title: $0.sourceTitle,
          locator: $0.locatorLabel,
          excerpt: $0.excerpt,
          fileURL: $0.fileURL,
          attribution: nil
        )
      },
      claims: [],
      calculations: card.calculations
    )
  }

  private static func evidenceContent(_ evidence: KnowledgeEvidenceOutcome) -> Content {
    Content(
      title: evidenceTitle(evidence),
      answer: evidenceAnswer(evidence),
      evidenceState: evidence.state,
      why: evidenceReason(evidence),
      sources: evidence.contributingSources.map(source),
      claims: evidence.claims.map(claim),
      calculations: []
    )
  }

  private static func retrievalContent(
    _ results: [KnowledgePackSearchResult],
    sourceCatalog: KnowledgeOverlaySourceCatalog?
  ) -> Content {
    let sources = results.flatMap { result in
      let catalogSources = result.sourceIDs.compactMap { sourceCatalog?.source(for: $0) }
      if !catalogSources.isEmpty { return catalogSources }
      return [
        KnowledgeOverlaySource(
          id: result.id,
          title: result.title,
          locator: result.kind.overlayLabel,
          excerpt: result.excerpt,
          fileURL: nil,
          attribution: "Possible match · \(Int((result.score.total * 100).rounded()))%"
        )
      ]
    }
    return Content(
      title: "Possible corpus match",
      answer: "I found potentially relevant material, but it has not been verified as an answer.",
      evidenceState: .needsClarification,
      why: "Retrieval found possible evidence. Verify the source before presenting it as fact.",
      sources: uniqueSources(sources),
      claims: [],
      calculations: []
    )
  }

  private static func synthesisContent(
    output: KnowledgeConstrainedSynthesisOutput,
    evidence: KnowledgeEvidenceOutcome
  ) -> Content {
    let citedIDs = Set(output.citedEvidenceRecordIDs)
    let citedClaims = evidence.claims.filter { citedIDs.contains("assertion:\($0.assertionID)") }
    let citedPassageIDs = Set(
      output.citedEvidenceRecordIDs.compactMap { id in
        id.hasPrefix("passage:") ? String(id.dropFirst("passage:".count)) : nil
      })
    let citedSources = evidence.contributingSources.filter { source in
      citedPassageIDs.contains(source.passageID)
        || citedClaims.contains { claim in
          claim.attributions.contains { $0.passageID == source.passageID }
        }
    }
    return Content(
      title: output.title,
      answer: output.answer,
      evidenceState: evidence.state,
      why:
        "Drafted from the cited evidence — verify wording against the sources below. \(evidenceReason(evidence))",
      sources: (citedSources.isEmpty ? evidence.contributingSources : citedSources).map(source),
      claims: (citedClaims.isEmpty ? evidence.claims : citedClaims).map(claim),
      calculations: []
    )
  }

  private static func evidenceTitle(_ evidence: KnowledgeEvidenceOutcome) -> String {
    switch evidence.state {
    case .contradictedByCorpus: "Corpus fact check"
    case .contested: "Corpus contains competing claims"
    case .notFoundInCorpus: "No answer in corpus"
    case .needsClarification: "Clarification needed"
    case .directlySourced, .calculated, .supportedByCorpus, .interpretive: "Corpus answer"
    }
  }

  private static func evidenceAnswer(_ evidence: KnowledgeEvidenceOutcome) -> String {
    let values = evidence.claims.map(\.displayValue)
    switch evidence.state {
    case .contradictedByCorpus:
      guard !values.isEmpty else {
        return "The statement conflicts with evidence in the selected corpus."
      }
      return
        "The statement conflicts with the corpus. Corpus value: \(values.joined(separator: "; "))."
    case .contested:
      return
        "The corpus contains \(evidence.claims.count) attributed claims. Review each source before answering."
    case .notFoundInCorpus:
      return "The selected corpus does not contain the requested fact."
    case .needsClarification:
      if evidence.missingFields.isEmpty {
        return "The corpus cannot support one unambiguous answer yet."
      }
      return
        "Clarify \(evidence.missingFields.map(\.rawValue).joined(separator: ", ")) before answering."
    case .directlySourced, .calculated, .supportedByCorpus, .interpretive:
      guard !values.isEmpty else { return evidence.state.overlayExplanation }
      return values.joined(separator: "; ")
    }
  }

  private static func evidenceReason(_ evidence: KnowledgeEvidenceOutcome) -> String {
    switch evidence.reason {
    case .insufficientContext:
      return "Required context is missing from the question."
    case .noMatchingAssertions:
      return "No typed assertion matches the requested details."
    case .retrievalIncomplete:
      return "Some eligible assertions were not retrieved, so the system abstained."
    case .evidenceUnavailable:
      return "A claim exists, but its source evidence cannot be opened."
    case .conflictingAssertions:
      return "Comparable corpus assertions disagree."
    case .incompatibleContexts:
      return "The matching claims use contexts that cannot be combined safely."
    case .contestedEvidence:
      return "The sources preserve competing claims instead of choosing one silently."
    case .claimContradicted:
      return "The statement differs from the typed value in the selected corpus."
    case .interpretiveClaims:
      return "This is an attributed interpretation, not a directly stated fact."
    case .calculatedClaims:
      return "The result is derived from cited inputs using a recorded calculation."
    case .supportedClaims:
      return "Multiple corpus records support the same claim."
    case .directlySourcedClaims:
      return "The value is stated directly in an identified corpus source."
    }
  }

  private static func source(
    _ source: KnowledgeEvidenceSourceReference
  ) -> KnowledgeOverlaySource {
    KnowledgeOverlaySource(
      id: source.id,
      title: source.sourceTitle,
      locator: source.locatorLabel,
      excerpt: source.excerpt,
      fileURL: source.fileURL,
      attribution: nil
    )
  }

  private static func claim(_ claim: KnowledgeEvidenceClaim) -> KnowledgeOverlayClaim {
    let context = claim.qualifiers.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: ", ")
    let attribution = claim.attributions.map { attribution in
      let locator = attribution.locatorLabel.isEmpty ? "" : " · \(attribution.locatorLabel)"
      return "\(attribution.sourceTitle)\(locator) · \(attribution.relation.overlayLabel)"
    }.joined(separator: "; ")
    return KnowledgeOverlayClaim(
      id: claim.id,
      value: claim.displayValue,
      context: context,
      attribution: attribution
    )
  }

  private static func uniqueSources(
    _ sources: [KnowledgeOverlaySource]
  ) -> [KnowledgeOverlaySource] {
    var seen: Set<String> = []
    return sources.filter { seen.insert($0.id).inserted }
  }
}

struct KnowledgeOverlaySourceCatalog: Equatable, Sendable {
  private let sourcesByID: [String: KnowledgeOverlaySource]

  init(pack: KnowledgePack, rootDirectory: URL) {
    let root = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
    sourcesByID = Dictionary(
      uniqueKeysWithValues: pack.sources.map { source in
        let candidate = root.appendingPathComponent(source.relativePath).standardizedFileURL
          .resolvingSymlinksInPath()
        let isInsideRoot =
          candidate.path == root.path
          || candidate.path.hasPrefix(root.path + "/")
        return (
          source.id,
          KnowledgeOverlaySource(
            id: source.id,
            title: source.title,
            locator: "Corpus source",
            excerpt: "Retrieved from \(source.title).",
            fileURL: isInsideRoot ? candidate : nil,
            attribution: nil
          )
        )
      })
  }

  func source(for id: String) -> KnowledgeOverlaySource? { sourcesByID[id] }
}

struct KnowledgeOverlayPresentationState: Equatable, Sendable {
  private(set) var activeByStream: [String: KnowledgeOverlayCard] = [:]
  private(set) var pinnedByEvent: [String: KnowledgeOverlayCard] = [:]
  private(set) var dismissedEventIDs: Set<String> = []
  private(set) var correctionRequestsByEvent: [String: KnowledgeOverlayCorrectionRequest] = [:]

  var visibleCards: [KnowledgeOverlayCard] {
    let pinned = pinnedByEvent.values.sorted { $0.eventID < $1.eventID }
    let active = activeByStream.values.sorted { lhs, rhs in
      if lhs.streamID == "remote" { return true }
      if rhs.streamID == "remote" { return false }
      return lhs.streamID < rhs.streamID
    }
    return pinned + active.filter { pinnedByEvent[$0.eventID] == nil }
  }

  var correctionRequests: [KnowledgeOverlayCorrectionRequest] {
    correctionRequestsByEvent.values.sorted { $0.eventID < $1.eventID }
  }

  var primaryActionCard: KnowledgeOverlayCard? {
    if let remoteCard = activeByStream["remote"] { return remoteCard }
    if let activeCard = activeByStream.values.sorted(by: activeCardOrder).first {
      return activeCard
    }
    return pinnedByEvent.values.sorted(by: pinnedCardOrder).first
  }

  mutating func apply(
    _ update: KnowledgeTieredAnswerUpdate,
    sourceCatalog: KnowledgeOverlaySourceCatalog? = nil
  ) {
    if update.action == .retract {
      retract(update)
      return
    }
    guard !dismissedEventIDs.contains(update.eventID),
      var card = KnowledgeOverlayCard.make(from: update, sourceCatalog: sourceCatalog)
    else { return }

    let current = pinnedByEvent[update.eventID] ?? activeByStream[update.streamID]
    if let current,
      current.revisionSequence > update.revisionSequence
    {
      return
    }
    if let current,
      current.revisionSequence == update.revisionSequence
    {
      if current.updateID == update.id { return }
      if let supersedesUpdateID = update.supersedesUpdateID,
        supersedesUpdateID != current.updateID
      {
        return
      }
      if update.supersedesUpdateID == nil,
        update.supportLevel < current.supportLevel
          || (update.supportLevel == current.supportLevel
            && update.presentationQuality <= current.presentationQuality)
      {
        return
      }
    }
    if var pinned = pinnedByEvent[update.eventID] {
      card.isPinned = true
      card.isCorrectionRequested = pinned.isCorrectionRequested
      pinned = card
      pinnedByEvent[update.eventID] = pinned
      activeByStream.removeValue(forKey: update.streamID)
      return
    }
    card.isCorrectionRequested = correctionRequestsByEvent[update.eventID] != nil
    activeByStream[update.streamID] = card
  }

  @discardableResult
  mutating func togglePin(eventID: String) -> Bool {
    if var pinned = pinnedByEvent.removeValue(forKey: eventID) {
      pinned.isPinned = false
      if !pinned.isSuperseded, !dismissedEventIDs.contains(eventID) {
        activeByStream[pinned.streamID] = pinned
      }
      return false
    }
    guard let entry = activeByStream.first(where: { $0.value.eventID == eventID }) else {
      return false
    }
    var pinned = entry.value
    pinned.isPinned = true
    pinnedByEvent[eventID] = pinned
    activeByStream.removeValue(forKey: entry.key)
    return true
  }

  mutating func dismiss(eventID: String) {
    dismissedEventIDs.insert(eventID)
    pinnedByEvent.removeValue(forKey: eventID)
    activeByStream = activeByStream.filter { $0.value.eventID != eventID }
  }

  @discardableResult
  mutating func requestCorrection(eventID: String) -> KnowledgeOverlayCorrectionRequest? {
    guard
      var card = pinnedByEvent[eventID]
        ?? activeByStream.values.first(where: { $0.eventID == eventID })
    else { return nil }
    let request = KnowledgeOverlayCorrectionRequest(
      id: eventID,
      eventID: eventID,
      updateID: card.updateID,
      title: card.title,
      answer: card.answer,
      evidenceState: card.evidenceState
    )
    correctionRequestsByEvent[eventID] = request
    card.isCorrectionRequested = true
    if pinnedByEvent[eventID] != nil {
      pinnedByEvent[eventID] = card
    } else {
      activeByStream[card.streamID] = card
    }
    return request
  }

  mutating func reset() {
    self = KnowledgeOverlayPresentationState()
  }

  private mutating func retract(_ update: KnowledgeTieredAnswerUpdate) {
    if let active = activeByStream[update.streamID],
      active.eventID == update.eventID
        || active.updateID == update.supersedesUpdateID
    {
      activeByStream.removeValue(forKey: update.streamID)
    }
    if var pinned = pinnedByEvent[update.eventID] {
      pinned.isSuperseded = true
      pinnedByEvent[update.eventID] = pinned
    }
  }

  private func activeCardOrder(
    _ lhs: KnowledgeOverlayCard,
    _ rhs: KnowledgeOverlayCard
  ) -> Bool {
    if lhs.revisionSequence != rhs.revisionSequence {
      return lhs.revisionSequence > rhs.revisionSequence
    }
    if lhs.streamID != rhs.streamID { return lhs.streamID < rhs.streamID }
    return lhs.eventID < rhs.eventID
  }

  private func pinnedCardOrder(
    _ lhs: KnowledgeOverlayCard,
    _ rhs: KnowledgeOverlayCard
  ) -> Bool {
    if lhs.isSuperseded != rhs.isSuperseded { return !lhs.isSuperseded }
    if lhs.revisionSequence != rhs.revisionSequence {
      return lhs.revisionSequence > rhs.revisionSequence
    }
    return lhs.eventID < rhs.eventID
  }
}

extension KnowledgeEvidenceState {
  var overlayLabel: String {
    switch self {
    case .directlySourced: "Directly Sourced"
    case .calculated: "Calculated"
    case .supportedByCorpus: "Supported by Corpus"
    case .contradictedByCorpus: "Contradicted by Corpus"
    case .contested: "Contested"
    case .interpretive: "Interpretive"
    case .notFoundInCorpus: "Not Found in Corpus"
    case .needsClarification: "Needs Clarification"
    }
  }

  var overlayExplanation: String {
    switch self {
    case .directlySourced:
      "The answer is stated directly in an identified corpus source."
    case .calculated:
      "The answer is derived from cited inputs using a recorded calculation."
    case .supportedByCorpus:
      "The answer is supported by multiple records in the selected corpus."
    case .contradictedByCorpus:
      "The statement conflicts with evidence in the selected corpus."
    case .contested:
      "The corpus contains competing attributed claims; no side was chosen silently."
    case .interpretive:
      "The answer is an attributed interpretation, not a directly stated fact."
    case .notFoundInCorpus:
      "The requested answer was not found in the selected corpus."
    case .needsClarification:
      "More context or source verification is required before answering."
    }
  }
}

extension KnowledgePackSearchRecordKind {
  fileprivate var overlayLabel: String {
    switch self {
    case .manifest: "Knowledge pack"
    case .source: "Source"
    case .passage: "Passage"
    case .assertion: "Assertion"
    case .evidenceLink: "Evidence link"
    case .calculation: "Calculation"
    case .responseCard: "Reviewed answer"
    case .questionFamily: "Question family"
    }
  }
}

extension KnowledgeEvidenceRelation {
  fileprivate var overlayLabel: String {
    switch self {
    case .supports: "supports"
    case .contradicts: "contradicts"
    case .derives: "derives"
    case .contextualizes: "contextualizes"
    }
  }
}
