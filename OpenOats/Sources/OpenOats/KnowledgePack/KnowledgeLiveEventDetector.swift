import Foundation

public enum KnowledgeLiveEventKind: String, Codable, CaseIterable, Equatable, Sendable {
  case questionCandidate = "QuestionCandidate"
  case questionStable = "QuestionStable"
  case claimCandidate = "ClaimCandidate"
  case claimStable = "ClaimStable"
  case topicShift = "TopicShift"
  case answerSuperseded = "AnswerSuperseded"
  case noAction = "NoAction"

  public var isActionable: Bool { self != .noAction }
}

public enum KnowledgeClaimCandidateStatus: String, Codable, Equatable, Sendable {
  case provisional
  case stable
}

public struct KnowledgeLiveBinding: Codable, Equatable, Hashable, Sendable {
  public let key: String
  public let value: String
  public let surfaceText: String

  public init(key: String, value: String, surfaceText: String) {
    self.key = key
    self.value = value
    self.surfaceText = surfaceText
  }
}

public struct KnowledgeClaimCandidate: Equatable, Sendable, Identifiable {
  public let id: String
  public let streamID: String
  public let revisionSequence: Int
  public let sourceText: String
  public let confidence: Double
  public let status: KnowledgeClaimCandidateStatus
  public let bindings: [KnowledgeLiveBinding]

  public init(
    id: String,
    streamID: String,
    revisionSequence: Int,
    sourceText: String,
    confidence: Double,
    status: KnowledgeClaimCandidateStatus,
    bindings: [KnowledgeLiveBinding]
  ) {
    self.id = id
    self.streamID = streamID
    self.revisionSequence = revisionSequence
    self.sourceText = sourceText
    self.confidence = confidence
    self.status = status
    self.bindings = bindings
  }
}

public enum KnowledgeAnswerSupersessionReason: String, Codable, Equatable, Sendable {
  case cleared
  case corrected
  case followUp = "follow_up"
  case interrupted
  case packChanged = "pack_changed"
}

public struct KnowledgeAnswerSupersession: Equatable, Sendable {
  public let previousEventID: String
  public let previousStreamID: String
  public let revisionSequence: Int
  public let reason: KnowledgeAnswerSupersessionReason
  public let replacementEventID: String?

  public init(
    previousEventID: String,
    previousStreamID: String,
    revisionSequence: Int,
    reason: KnowledgeAnswerSupersessionReason,
    replacementEventID: String? = nil
  ) {
    self.previousEventID = previousEventID
    self.previousStreamID = previousStreamID
    self.revisionSequence = revisionSequence
    self.reason = reason
    self.replacementEventID = replacementEventID
  }
}

public struct KnowledgeTopicShift: Equatable, Sendable {
  public let streamID: String
  public let revisionSequence: Int
  public let fromTopicIDs: [String]
  public let toTopicIDs: [String]
  public let triggeredByEventID: String

  public init(
    streamID: String,
    revisionSequence: Int,
    fromTopicIDs: [String],
    toTopicIDs: [String],
    triggeredByEventID: String
  ) {
    self.streamID = streamID
    self.revisionSequence = revisionSequence
    self.fromTopicIDs = fromTopicIDs
    self.toTopicIDs = toTopicIDs
    self.triggeredByEventID = triggeredByEventID
  }
}

public enum KnowledgeLiveNoActionReason: String, Codable, Equatable, Sendable {
  case emptyTranscript = "empty_transcript"
  case staleRevision = "stale_revision"
  case insufficientSignal = "insufficient_signal"
  case unchangedRevision = "unchanged_revision"
  case duplicateSignal = "duplicate_signal"
}

public struct KnowledgeLiveNoAction: Equatable, Sendable {
  public let streamID: String
  public let revisionSequence: Int
  public let reason: KnowledgeLiveNoActionReason

  public init(
    streamID: String,
    revisionSequence: Int,
    reason: KnowledgeLiveNoActionReason
  ) {
    self.streamID = streamID
    self.revisionSequence = revisionSequence
    self.reason = reason
  }
}

public enum KnowledgeLiveEvent: Equatable, Sendable {
  case questionCandidate(QuestionCandidate)
  case questionStable(QuestionCandidate)
  case claimCandidate(KnowledgeClaimCandidate)
  case claimStable(KnowledgeClaimCandidate)
  case topicShift(KnowledgeTopicShift)
  case answerSuperseded(KnowledgeAnswerSupersession)
  case noAction(KnowledgeLiveNoAction)

  public var kind: KnowledgeLiveEventKind {
    switch self {
    case .questionCandidate: .questionCandidate
    case .questionStable: .questionStable
    case .claimCandidate: .claimCandidate
    case .claimStable: .claimStable
    case .topicShift: .topicShift
    case .answerSuperseded: .answerSuperseded
    case .noAction: .noAction
    }
  }
}

/// Converts revisable transcript text into a deterministic, domain-neutral live event stream.
///
/// Prepared question families and opaque term aliases are the only domain inputs. The detector
/// owns revision ordering, early candidates, stable promotion, correction, duplicate suppression,
/// topic transitions, and conservative claim recognition. It performs no retrieval or inference.
public struct KnowledgeLiveEventDetector: Sendable {
  private struct IndexedTerm: Sendable {
    let id: String
    let forms: [String]
  }

  private struct TermMatch: Sendable {
    let id: String
    let surfaceText: String
  }

  private struct ClaimMatch: Sendable {
    let confidence: Double
    let bindings: [KnowledgeLiveBinding]
    let topicIDs: [String]
  }

  private struct TrackedClaim: Sendable {
    let id: String
    let streamID: String
    var matchingRevisionCount: Int
    var status: KnowledgeClaimCandidateStatus
    var bindings: [KnowledgeLiveBinding]
    var topicIDs: [String]
  }

  private enum ActiveSignalKind: Equatable, Sendable {
    case question
    case claim
  }

  private struct ActiveSignal: Sendable {
    let id: String
    let streamID: String
    let kind: ActiveSignalKind
    let questionFamilyID: String?
    let bindings: [KnowledgeLiveBinding]
    let topicIDs: [String]
  }

  private var questionDetector: QuestionCandidateDetector
  private let terms: [IndexedTerm]
  private let stableRevisionCount: Int
  private var lastSequenceByStream: [String: Int] = [:]
  private var claimGenerationByStream: [String: Int] = [:]
  private var trackedClaimsByStream: [String: TrackedClaim] = [:]
  private var emittedQuestionIDs: Set<String> = []
  private var suppressedQuestionIDs: Set<String> = []
  private var emittedClaimIDs: Set<String> = []
  private var suppressedClaimIDs: Set<String> = []
  private var knownQuestionsByID: [String: QuestionCandidate] = [:]
  private var supersededEventIDs: Set<String> = []
  private var activeSignal: ActiveSignal?
  private var lastStableTopicIDs: [String] = []

  public init(
    questionFamilies: [KnowledgeQuestionFamily],
    termAliases: [KnowledgeTermAlias] = [],
    stableRevisionCount: Int = 2,
    minimumQuestionConfidence: Double = 0.62
  ) {
    questionDetector = QuestionCandidateDetector(
      questionFamilies: questionFamilies,
      termAliases: termAliases,
      stableRevisionCount: stableRevisionCount,
      minimumConfidence: minimumQuestionConfidence
    )
    terms = Self.indexTerms(questionFamilies: questionFamilies, termAliases: termAliases)
    self.stableRevisionCount = max(1, stableRevisionCount)
  }

  public mutating func process(_ revision: TranscriptRevision) -> [KnowledgeLiveEvent] {
    let previousSequence = lastSequenceByStream[revision.streamID] ?? Int.min
    guard revision.sequence > previousSequence else {
      return [noAction(for: revision, reason: .staleRevision)]
    }
    lastSequenceByStream[revision.streamID] = revision.sequence

    let normalizedText = Self.normalize(revision.text)
    let questionEvents = questionDetector.process(revision)
    let replacementQuestionID = questionEvents.compactMap { event -> String? in
      guard case .upsert(let candidate) = event else { return nil }
      return candidate.id
    }.first

    var events: [KnowledgeLiveEvent] = []
    let hasQuestionUpsert = replacementQuestionID != nil
    if hasQuestionUpsert, let claim = trackedClaimsByStream.removeValue(forKey: revision.streamID) {
      if suppressedClaimIDs.remove(claim.id) == nil, emittedClaimIDs.contains(claim.id) {
        appendSupersession(
          for: claim.id,
          streamID: claim.streamID,
          sequence: revision.sequence,
          reason: .corrected,
          replacementEventID: replacementQuestionID,
          to: &events
        )
      }
    }

    for questionEvent in questionEvents {
      switch questionEvent {
      case .cancel(let cancellation):
        knownQuestionsByID.removeValue(forKey: cancellation.candidateID)
        if suppressedQuestionIDs.remove(cancellation.candidateID) != nil { continue }
        guard emittedQuestionIDs.contains(cancellation.candidateID) else { continue }
        appendSupersession(
          for: cancellation.candidateID,
          streamID: cancellation.streamID,
          sequence: cancellation.revisionSequence,
          reason: Self.supersessionReason(for: cancellation.reason),
          replacementEventID: replacementQuestionID,
          to: &events
        )
      case .upsert(let candidate):
        appendQuestion(candidate, to: &events)
      }
    }

    if !hasQuestionUpsert {
      appendClaimEvents(for: revision, normalizedText: normalizedText, to: &events)
    }

    guard events.isEmpty else { return events }
    let reason: KnowledgeLiveNoActionReason
    if normalizedText.isEmpty {
      reason = .emptyTranscript
    } else if suppressedQuestionIDs.contains(where: {
      knownQuestionsByID[$0]?.streamID == revision.streamID
    }) || suppressedClaimIDs.contains(where: { $0.hasPrefix("\(revision.streamID)#claim#") }) {
      reason = .duplicateSignal
    } else if questionEvents.isEmpty, trackedClaimsByStream[revision.streamID] != nil {
      reason = .unchangedRevision
    } else if questionEvents.isEmpty,
      emittedQuestionIDs.contains(where: {
        knownQuestionsByID[$0]?.streamID == revision.streamID
      })
    {
      reason = .unchangedRevision
    } else {
      reason = .insufficientSignal
    }
    return [noAction(for: revision, reason: reason)]
  }

  public mutating func cancelAll(
    sequence: Int,
    reason: KnowledgeAnswerSupersessionReason = .packChanged
  ) -> [KnowledgeLiveEvent] {
    var events: [KnowledgeLiveEvent] = []
    let questionCancellations = questionDetector.cancelAll(
      sequence: sequence,
      reason: reason == .packChanged ? .packChanged : .cleared
    )
    for event in questionCancellations {
      guard case .cancel(let cancellation) = event else { continue }
      guard emittedQuestionIDs.contains(cancellation.candidateID) else { continue }
      appendSupersession(
        for: cancellation.candidateID,
        streamID: cancellation.streamID,
        sequence: sequence,
        reason: reason,
        replacementEventID: nil,
        to: &events
      )
    }
    for claim in trackedClaimsByStream.values.sorted(by: { $0.id < $1.id }) {
      guard emittedClaimIDs.contains(claim.id), !suppressedClaimIDs.contains(claim.id) else {
        continue
      }
      appendSupersession(
        for: claim.id,
        streamID: claim.streamID,
        sequence: sequence,
        reason: reason,
        replacementEventID: nil,
        to: &events
      )
    }
    trackedClaimsByStream.removeAll()
    emittedQuestionIDs.removeAll()
    suppressedQuestionIDs.removeAll()
    emittedClaimIDs.removeAll()
    suppressedClaimIDs.removeAll()
    knownQuestionsByID.removeAll()
    activeSignal = nil
    lastStableTopicIDs = []
    return events
  }

  private mutating func appendQuestion(
    _ candidate: QuestionCandidate,
    to events: inout [KnowledgeLiveEvent]
  ) {
    knownQuestionsByID[candidate.id] = candidate
    guard !supersededEventIDs.contains(candidate.id) else { return }
    let signal = questionSignal(candidate)

    if suppressedQuestionIDs.contains(candidate.id) {
      if let activeSignal, isDuplicateQuestion(candidate, of: activeSignal) { return }
      suppressedQuestionIDs.remove(candidate.id)
    } else if !emittedQuestionIDs.contains(candidate.id),
      let activeSignal,
      isDuplicateQuestion(candidate, of: activeSignal)
    {
      suppressedQuestionIDs.insert(candidate.id)
      return
    }

    if let activeSignal, activeSignal.id != candidate.id,
      !isSameSemanticSignal(signal, activeSignal)
    {
      appendSupersession(
        for: activeSignal.id,
        streamID: activeSignal.streamID,
        sequence: candidate.revisionSequence,
        reason: activeSignal.streamID == candidate.streamID ? .corrected : .interrupted,
        replacementEventID: candidate.id,
        to: &events
      )
    }

    emittedQuestionIDs.insert(candidate.id)
    activeSignal = signal
    if candidate.status == .stable {
      appendTopicShiftIfNeeded(for: signal, sequence: candidate.revisionSequence, to: &events)
      events.append(.questionStable(candidate))
    } else {
      events.append(.questionCandidate(candidate))
    }
  }

  private mutating func appendClaimEvents(
    for revision: TranscriptRevision,
    normalizedText: String,
    to events: inout [KnowledgeLiveEvent]
  ) {
    guard let match = claimMatch(for: revision, normalizedText: normalizedText) else {
      if let tracked = trackedClaimsByStream.removeValue(forKey: revision.streamID) {
        if suppressedClaimIDs.remove(tracked.id) == nil, emittedClaimIDs.contains(tracked.id) {
          appendSupersession(
            for: tracked.id,
            streamID: tracked.streamID,
            sequence: revision.sequence,
            reason: normalizedText.isEmpty ? .cleared : .corrected,
            replacementEventID: nil,
            to: &events
          )
        }
      }
      return
    }

    if var tracked = trackedClaimsByStream[revision.streamID] {
      if Self.hasConflictingBindings(existing: tracked.bindings, incoming: match.bindings)
        || tracked.topicIDs != match.topicIDs
      {
        trackedClaimsByStream.removeValue(forKey: revision.streamID)
        if suppressedClaimIDs.remove(tracked.id) == nil, emittedClaimIDs.contains(tracked.id) {
          appendSupersession(
            for: tracked.id,
            streamID: tracked.streamID,
            sequence: revision.sequence,
            reason: .corrected,
            replacementEventID: nil,
            to: &events
          )
        }
        appendNewClaim(for: revision, match: match, to: &events)
        return
      }

      tracked.matchingRevisionCount += 1
      let mergedBindings = Self.mergeBindings(existing: tracked.bindings, incoming: match.bindings)
      let nextStatus: KnowledgeClaimCandidateStatus =
        revision.stability == .final || tracked.matchingRevisionCount >= stableRevisionCount
        ? .stable : .provisional
      let shouldEmit = tracked.status != nextStatus || tracked.bindings != mergedBindings
      tracked.status = nextStatus
      tracked.bindings = mergedBindings
      trackedClaimsByStream[revision.streamID] = tracked
      guard shouldEmit else { return }
      appendClaim(
        candidate(from: tracked, revision: revision, confidence: match.confidence), to: &events)
      return
    }

    appendNewClaim(for: revision, match: match, to: &events)
  }

  private mutating func appendNewClaim(
    for revision: TranscriptRevision,
    match: ClaimMatch,
    to events: inout [KnowledgeLiveEvent]
  ) {
    let generation = (claimGenerationByStream[revision.streamID] ?? 0) + 1
    claimGenerationByStream[revision.streamID] = generation
    let status: KnowledgeClaimCandidateStatus =
      revision.stability == .final || stableRevisionCount == 1 ? .stable : .provisional
    let tracked = TrackedClaim(
      id: "\(revision.streamID)#claim#\(generation)",
      streamID: revision.streamID,
      matchingRevisionCount: 1,
      status: status,
      bindings: match.bindings,
      topicIDs: match.topicIDs
    )
    trackedClaimsByStream[revision.streamID] = tracked
    appendClaim(
      candidate(from: tracked, revision: revision, confidence: match.confidence), to: &events)
  }

  private mutating func appendClaim(
    _ candidate: KnowledgeClaimCandidate,
    to events: inout [KnowledgeLiveEvent]
  ) {
    guard !supersededEventIDs.contains(candidate.id) else { return }
    let signal = claimSignal(candidate)
    if suppressedClaimIDs.contains(candidate.id) {
      if let activeSignal, isSameSemanticSignal(signal, activeSignal) { return }
      suppressedClaimIDs.remove(candidate.id)
    } else if !emittedClaimIDs.contains(candidate.id),
      let activeSignal,
      activeSignal.id != candidate.id,
      isSameSemanticSignal(signal, activeSignal)
    {
      suppressedClaimIDs.insert(candidate.id)
      return
    }
    if let activeSignal, activeSignal.id != candidate.id {
      appendSupersession(
        for: activeSignal.id,
        streamID: activeSignal.streamID,
        sequence: candidate.revisionSequence,
        reason: activeSignal.streamID == candidate.streamID ? .corrected : .interrupted,
        replacementEventID: candidate.id,
        to: &events
      )
    }
    emittedClaimIDs.insert(candidate.id)
    activeSignal = signal
    if candidate.status == .stable {
      appendTopicShiftIfNeeded(for: signal, sequence: candidate.revisionSequence, to: &events)
      events.append(.claimStable(candidate))
    } else {
      events.append(.claimCandidate(candidate))
    }
  }

  private mutating func appendSupersession(
    for eventID: String,
    streamID: String,
    sequence: Int,
    reason: KnowledgeAnswerSupersessionReason,
    replacementEventID: String?,
    to events: inout [KnowledgeLiveEvent]
  ) {
    guard supersededEventIDs.insert(eventID).inserted else { return }
    events.append(
      .answerSuperseded(
        KnowledgeAnswerSupersession(
          previousEventID: eventID,
          previousStreamID: streamID,
          revisionSequence: sequence,
          reason: reason,
          replacementEventID: replacementEventID
        )))
    if activeSignal?.id == eventID { activeSignal = nil }
  }

  private mutating func appendTopicShiftIfNeeded(
    for signal: ActiveSignal,
    sequence: Int,
    to events: inout [KnowledgeLiveEvent]
  ) {
    defer { lastStableTopicIDs = signal.topicIDs }
    guard !lastStableTopicIDs.isEmpty, lastStableTopicIDs != signal.topicIDs else { return }
    events.append(
      .topicShift(
        KnowledgeTopicShift(
          streamID: signal.streamID,
          revisionSequence: sequence,
          fromTopicIDs: lastStableTopicIDs,
          toTopicIDs: signal.topicIDs,
          triggeredByEventID: signal.id
        )))
  }

  private func claimMatch(
    for revision: TranscriptRevision,
    normalizedText: String
  ) -> ClaimMatch? {
    let words = normalizedText.split(separator: " ").map(String.init)
    guard words.count >= 3, !Self.looksLikeQuestion(revision.text, normalizedWords: words) else {
      return nil
    }
    let termMatches = matchingTerms(in: normalizedText)
    guard !termMatches.isEmpty else { return nil }
    let wordSet = Set(words)
    let hasClaimCue = !wordSet.isDisjoint(with: Self.claimCueWords)
    let literals = Self.literalBindings(in: revision.text)
    guard hasClaimCue || !literals.isEmpty else { return nil }

    var bindings = termMatches.map {
      KnowledgeLiveBinding(key: "term", value: $0.id, surfaceText: $0.surfaceText)
    }
    bindings.append(
      contentsOf: Self.years(in: normalizedText).sorted().map {
        KnowledgeLiveBinding(key: "period", value: $0, surfaceText: $0)
      })
    bindings.append(contentsOf: literals)
    bindings = Array(Set(bindings)).sorted(by: Self.bindingOrder)
    var confidence = 0.64
    if hasClaimCue { confidence += 0.10 }
    if !literals.isEmpty { confidence += 0.12 }
    if revision.stability == .final { confidence += 0.05 }
    return ClaimMatch(
      confidence: min(confidence, 1),
      bindings: bindings,
      topicIDs: termMatches.map(\.id).sorted()
    )
  }

  private func matchingTerms(in text: String) -> [TermMatch] {
    terms.compactMap { term in
      let matches = term.forms.filter { Self.containsPhrase(text, phrase: $0) }
      guard let surface = matches.max(by: { $0.count < $1.count }) else { return nil }
      return TermMatch(id: term.id, surfaceText: surface)
    }.sorted { $0.id < $1.id }
  }

  private func questionSignal(_ candidate: QuestionCandidate) -> ActiveSignal {
    let bindings = candidate.bindings.map {
      KnowledgeLiveBinding(key: $0.key, value: $0.value, surfaceText: $0.surfaceText)
    }
    let termIDs = bindings.filter { $0.key == "term" }.map(\.value).sorted()
    return ActiveSignal(
      id: candidate.id,
      streamID: candidate.streamID,
      kind: .question,
      questionFamilyID: candidate.questionFamilyID,
      bindings: bindings,
      topicIDs: termIDs.isEmpty ? ["question:\(candidate.questionFamilyID)"] : termIDs
    )
  }

  private func claimSignal(_ candidate: KnowledgeClaimCandidate) -> ActiveSignal {
    let topicIDs = candidate.bindings.filter { $0.key == "term" }.map(\.value).sorted()
    return ActiveSignal(
      id: candidate.id,
      streamID: candidate.streamID,
      kind: .claim,
      questionFamilyID: nil,
      bindings: candidate.bindings,
      topicIDs: topicIDs
    )
  }

  private func isDuplicateQuestion(
    _ candidate: QuestionCandidate,
    of signal: ActiveSignal
  ) -> Bool {
    guard signal.kind == .question, signal.questionFamilyID == candidate.questionFamilyID else {
      return false
    }
    let incoming = candidate.bindings.map {
      KnowledgeLiveBinding(key: $0.key, value: $0.value, surfaceText: $0.surfaceText)
    }
    return !Self.hasConflictingBindings(existing: signal.bindings, incoming: incoming)
  }

  private func isSameSemanticSignal(_ lhs: ActiveSignal, _ rhs: ActiveSignal) -> Bool {
    guard lhs.kind == rhs.kind, lhs.questionFamilyID == rhs.questionFamilyID else { return false }
    return Self.semanticBindings(lhs.bindings) == Self.semanticBindings(rhs.bindings)
  }

  private func candidate(
    from tracked: TrackedClaim,
    revision: TranscriptRevision,
    confidence: Double
  ) -> KnowledgeClaimCandidate {
    KnowledgeClaimCandidate(
      id: tracked.id,
      streamID: tracked.streamID,
      revisionSequence: revision.sequence,
      sourceText: revision.text,
      confidence: confidence,
      status: tracked.status,
      bindings: tracked.bindings
    )
  }

  private func noAction(
    for revision: TranscriptRevision,
    reason: KnowledgeLiveNoActionReason
  ) -> KnowledgeLiveEvent {
    .noAction(
      KnowledgeLiveNoAction(
        streamID: revision.streamID,
        revisionSequence: revision.sequence,
        reason: reason
      ))
  }

  private static func supersessionReason(
    for reason: QuestionCandidateCancellationReason
  ) -> KnowledgeAnswerSupersessionReason {
    switch reason {
    case .cleared: .cleared
    case .corrected: .corrected
    case .superseded: .followUp
    case .packChanged: .packChanged
    }
  }

  private static func hasConflictingBindings(
    existing: [KnowledgeLiveBinding],
    incoming: [KnowledgeLiveBinding]
  ) -> Bool {
    for key in ["period", "literal"] {
      let oldValues = Set(existing.filter { $0.key == key }.map(\.value))
      let newValues = Set(incoming.filter { $0.key == key }.map(\.value))
      if !oldValues.isEmpty, !newValues.isEmpty, oldValues != newValues { return true }
    }
    return false
  }

  private static func mergeBindings(
    existing: [KnowledgeLiveBinding],
    incoming: [KnowledgeLiveBinding]
  ) -> [KnowledgeLiveBinding] {
    var result = Set(existing)
    result.formUnion(incoming)
    return result.sorted(by: bindingOrder)
  }

  private static func semanticBindings(_ bindings: [KnowledgeLiveBinding]) -> [String] {
    bindings.map { "\($0.key)=\($0.value)" }.sorted()
  }

  private static func bindingOrder(
    _ lhs: KnowledgeLiveBinding,
    _ rhs: KnowledgeLiveBinding
  ) -> Bool {
    (lhs.key, lhs.value, lhs.surfaceText) < (rhs.key, rhs.value, rhs.surfaceText)
  }

  private static func index(_ alias: KnowledgeTermAlias) -> IndexedTerm {
    let forms = ([alias.canonicalText] + alias.aliases)
      .map(normalize)
      .filter { !$0.isEmpty }
    return IndexedTerm(id: alias.id, forms: Array(Set(forms)).sorted())
  }

  private static func indexTerms(
    questionFamilies: [KnowledgeQuestionFamily],
    termAliases: [KnowledgeTermAlias]
  ) -> [IndexedTerm] {
    let explicit = termAliases.map(index)
    let explicitForms = Set(explicit.flatMap(\.forms))
    let fallbacks = questionFamilies.compactMap { family -> IndexedTerm? in
      let forms = family.aliases.map(normalize).filter { !$0.isEmpty }
      guard !forms.isEmpty, Set(forms).isDisjoint(with: explicitForms) else { return nil }
      return IndexedTerm(
        id: "question_family:\(family.id)",
        forms: Array(Set(forms)).sorted()
      )
    }
    return (explicit + fallbacks).sorted { $0.id < $1.id }
  }

  private static func normalize(_ text: String) -> String {
    let folded = text.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    let scalars = folded.unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
    }
    return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func containsPhrase(_ text: String, phrase: String) -> Bool {
    guard !phrase.isEmpty else { return false }
    return " \(text) ".contains(" \(phrase) ")
  }

  private static func years(in text: String) -> Set<String> {
    Set(
      text.split(separator: " ").compactMap { token in
        guard token.count == 4, let year = Int(token), (1900...2099).contains(year) else {
          return nil
        }
        return String(year)
      })
  }

  private static func looksLikeQuestion(_ text: String, normalizedWords: [String]) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
      || questionLeadingWords.contains(normalizedWords.first ?? "")
  }

  private static func literalBindings(in text: String) -> [KnowledgeLiveBinding] {
    let trimming = CharacterSet(charactersIn: ",.;:!?()[]{}\"'")
    return text.split(whereSeparator: \.isWhitespace).compactMap { rawToken in
      let surface = String(rawToken).trimmingCharacters(in: trimming)
      guard surface.contains(where: \.isNumber) else { return nil }
      let normalized = surface.replacingOccurrences(of: ",", with: "")
      let allowed = CharacterSet(charactersIn: "$€£+-0123456789.%/")
      guard normalized.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
      let yearCandidate = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "$€£+-.%/"))
      if yearCandidate.count == 4, let year = Int(yearCandidate), (1900...2099).contains(year) {
        return nil
      }
      return KnowledgeLiveBinding(key: "literal", value: normalized, surfaceText: surface)
    }
  }

  private static let questionLeadingWords = Set([
    "what", "how", "why", "which", "who", "when", "where", "can", "could", "did", "do",
    "does", "is", "should", "was", "were", "will", "would",
  ])

  private static let claimCueWords = Set([
    "is", "are", "was", "were", "has", "have", "had", "equals", "equaled", "reached",
    "totaled", "remains", "increased", "decreased", "grew", "fell", "rose", "declined",
  ])
}
