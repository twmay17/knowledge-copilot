import Foundation

public struct KnowledgeTermAlias: Equatable, Sendable {
  public let id: String
  public let canonicalText: String
  public let aliases: [String]

  public init(id: String, canonicalText: String, aliases: [String]) {
    self.id = id
    self.canonicalText = canonicalText
    self.aliases = aliases
  }
}

public struct TranscriptRevision: Equatable, Sendable {
  public enum Stability: Equatable, Sendable {
    case partial
    case final
  }

  public let streamID: String
  public let sequence: Int
  public let text: String
  public let stability: Stability

  public init(streamID: String, sequence: Int, text: String, stability: Stability) {
    self.streamID = streamID
    self.sequence = sequence
    self.text = text
    self.stability = stability
  }
}

public enum QuestionCandidateStatus: String, Codable, Equatable, Sendable {
  case provisional
  case stable
}

public struct ResolvedQuestionBinding: Equatable, Sendable {
  public let key: String
  public let value: String
  public let surfaceText: String

  public init(key: String, value: String, surfaceText: String) {
    self.key = key
    self.value = value
    self.surfaceText = surfaceText
  }
}

public struct QuestionCandidate: Equatable, Sendable, Identifiable {
  public let id: String
  public let streamID: String
  public let revisionSequence: Int
  public let questionFamilyID: String
  public let sourceText: String
  public let confidence: Double
  public let status: QuestionCandidateStatus
  public let bindings: [ResolvedQuestionBinding]

  public init(
    id: String,
    streamID: String,
    revisionSequence: Int,
    questionFamilyID: String,
    sourceText: String,
    confidence: Double,
    status: QuestionCandidateStatus,
    bindings: [ResolvedQuestionBinding]
  ) {
    self.id = id
    self.streamID = streamID
    self.revisionSequence = revisionSequence
    self.questionFamilyID = questionFamilyID
    self.sourceText = sourceText
    self.confidence = confidence
    self.status = status
    self.bindings = bindings
  }
}

public enum QuestionCandidateCancellationReason: String, Equatable, Sendable {
  case cleared
  case corrected
  case superseded
  case packChanged = "pack_changed"
}

public struct QuestionCandidateCancellation: Equatable, Sendable {
  public let candidateID: String
  public let streamID: String
  public let revisionSequence: Int
  public let reason: QuestionCandidateCancellationReason

  public init(
    candidateID: String,
    streamID: String,
    revisionSequence: Int,
    reason: QuestionCandidateCancellationReason
  ) {
    self.candidateID = candidateID
    self.streamID = streamID
    self.revisionSequence = revisionSequence
    self.reason = reason
  }
}

public enum QuestionCandidateEvent: Equatable, Sendable {
  case upsert(QuestionCandidate)
  case cancel(QuestionCandidateCancellation)
}

/// Converts revisable transcript text into stable, domain-neutral question events.
///
/// The detector treats question-family and term IDs as opaque strings. Domain profiles provide
/// aliases, while the core owns matching, revision ordering, promotion, and cancellation.
public struct QuestionCandidateDetector: Sendable {
  private struct IndexedTerm: Sendable {
    let id: String
    let forms: [String]
  }

  private struct IndexedFamily: Sendable {
    let id: String
    let references: [String]
    let prefixes: [String]
    let aliases: [String]
    let vocabulary: String
    let years: Set<String>
  }

  private struct TermMatch: Sendable {
    let id: String
    let surfaceText: String
  }

  private struct Match: Sendable {
    let familyID: String
    let confidence: Double
    let bindings: [ResolvedQuestionBinding]
  }

  private struct TrackedCandidate: Sendable {
    let id: String
    let familyID: String
    var matchingRevisionCount: Int
    var status: QuestionCandidateStatus
    var bindings: [ResolvedQuestionBinding]
    var lastSequence: Int
  }

  private let families: [IndexedFamily]
  private let terms: [IndexedTerm]
  private let stableRevisionCount: Int
  private let minimumConfidence: Double
  private var trackedByStream: [String: TrackedCandidate] = [:]
  private var lastSequenceByStream: [String: Int] = [:]
  private var generationByStream: [String: Int] = [:]

  public init(
    questionFamilies: [KnowledgeQuestionFamily],
    termAliases: [KnowledgeTermAlias] = [],
    stableRevisionCount: Int = 2,
    minimumConfidence: Double = 0.62
  ) {
    families = questionFamilies.map(Self.index)
    terms = termAliases.map(Self.index)
    self.stableRevisionCount = max(1, stableRevisionCount)
    self.minimumConfidence = min(max(minimumConfidence, 0), 1)
  }

  public mutating func process(_ revision: TranscriptRevision) -> [QuestionCandidateEvent] {
    let previousSequence = lastSequenceByStream[revision.streamID] ?? Int.min
    guard revision.sequence > previousSequence else { return [] }
    lastSequenceByStream[revision.streamID] = revision.sequence

    let normalizedText = Self.normalize(revision.text)
    guard !normalizedText.isEmpty else {
      return cancelTracked(
        streamID: revision.streamID,
        sequence: revision.sequence,
        reason: .cleared
      )
    }

    guard let match = bestMatch(for: normalizedText) else {
      return cancelTracked(
        streamID: revision.streamID,
        sequence: revision.sequence,
        reason: .corrected
      )
    }

    guard var tracked = trackedByStream[revision.streamID] else {
      return [createCandidate(for: revision, match: match)]
    }

    if tracked.familyID != match.familyID {
      let cancellation = cancellationEvent(
        tracked,
        streamID: revision.streamID,
        sequence: revision.sequence,
        reason: .superseded
      )
      trackedByStream.removeValue(forKey: revision.streamID)
      return [cancellation, createCandidate(for: revision, match: match)]
    }

    if Self.hasConflictingMaterialBinding(existing: tracked.bindings, incoming: match.bindings) {
      let cancellation = cancellationEvent(
        tracked,
        streamID: revision.streamID,
        sequence: revision.sequence,
        reason: .corrected
      )
      trackedByStream.removeValue(forKey: revision.streamID)
      return [cancellation, createCandidate(for: revision, match: match)]
    }

    tracked.matchingRevisionCount += 1
    tracked.lastSequence = revision.sequence
    let mergedBindings = Self.mergeBindings(existing: tracked.bindings, incoming: match.bindings)
    let nextStatus: QuestionCandidateStatus =
      revision.stability == .final || tracked.matchingRevisionCount >= stableRevisionCount
      ? .stable : .provisional
    let shouldEmit = tracked.status != nextStatus || tracked.bindings != mergedBindings
    tracked.status = nextStatus
    tracked.bindings = mergedBindings
    trackedByStream[revision.streamID] = tracked

    guard shouldEmit else { return [] }
    return [
      .upsert(
        candidate(
          tracked: tracked,
          revision: revision,
          confidence: match.confidence
        ))
    ]
  }

  public mutating func cancelAll(
    sequence: Int,
    reason: QuestionCandidateCancellationReason = .packChanged
  ) -> [QuestionCandidateEvent] {
    let events = trackedByStream.sorted(by: { $0.key < $1.key }).map { streamID, tracked in
      cancellationEvent(tracked, streamID: streamID, sequence: sequence, reason: reason)
    }
    trackedByStream.removeAll()
    return events
  }

  private mutating func createCandidate(
    for revision: TranscriptRevision,
    match: Match
  ) -> QuestionCandidateEvent {
    let generation = (generationByStream[revision.streamID] ?? 0) + 1
    generationByStream[revision.streamID] = generation
    let status: QuestionCandidateStatus =
      revision.stability == .final || stableRevisionCount == 1
      ? .stable : .provisional
    let tracked = TrackedCandidate(
      id: "\(revision.streamID)#\(generation)",
      familyID: match.familyID,
      matchingRevisionCount: 1,
      status: status,
      bindings: match.bindings,
      lastSequence: revision.sequence
    )
    trackedByStream[revision.streamID] = tracked
    return .upsert(candidate(tracked: tracked, revision: revision, confidence: match.confidence))
  }

  private mutating func cancelTracked(
    streamID: String,
    sequence: Int,
    reason: QuestionCandidateCancellationReason
  ) -> [QuestionCandidateEvent] {
    guard let tracked = trackedByStream.removeValue(forKey: streamID) else { return [] }
    return [cancellationEvent(tracked, streamID: streamID, sequence: sequence, reason: reason)]
  }

  private func cancellationEvent(
    _ tracked: TrackedCandidate,
    streamID: String,
    sequence: Int,
    reason: QuestionCandidateCancellationReason
  ) -> QuestionCandidateEvent {
    .cancel(
      QuestionCandidateCancellation(
        candidateID: tracked.id,
        streamID: streamID,
        revisionSequence: sequence,
        reason: reason
      ))
  }

  private func candidate(
    tracked: TrackedCandidate,
    revision: TranscriptRevision,
    confidence: Double
  ) -> QuestionCandidate {
    QuestionCandidate(
      id: tracked.id,
      streamID: revision.streamID,
      revisionSequence: revision.sequence,
      questionFamilyID: tracked.familyID,
      sourceText: revision.text,
      confidence: confidence,
      status: tracked.status,
      bindings: tracked.bindings
    )
  }

  private func bestMatch(for text: String) -> Match? {
    let orderedInputTokens = text.split(separator: " ").map(String.init)
    let inputTokens = Set(orderedInputTokens)
    let termMatches = matchingTerms(in: text)
    let inputYears = Self.years(in: text)
    let isQuestionLead = Self.questionLeadingWords.contains(orderedInputTokens.first ?? "")

    let matches = families.compactMap { family -> Match? in
      let familyAliasMatch = family.aliases.contains { Self.containsPhrase(text, phrase: $0) }
      let prefixMatch = family.prefixes.contains { Self.containsPhrase(text, phrase: $0) }
      let alignedTerms = termMatches.filter { termMatch in
        terms.first(where: { $0.id == termMatch.id })?.forms.contains(where: {
          Self.containsPhrase(family.vocabulary, phrase: $0)
        }) == true
      }
      let hasSpecificSignal = familyAliasMatch || prefixMatch || !alignedTerms.isEmpty
      let hasQuestionShape = isQuestionLead || prefixMatch
      guard hasSpecificSignal, hasQuestionShape else { return nil }

      let referenceScore =
        family.references.map { reference -> Double in
          let referenceTokens = Set(reference.split(separator: " ").map(String.init))
          guard !referenceTokens.isEmpty, !inputTokens.isEmpty else { return 0 }
          let overlap = Double(referenceTokens.intersection(inputTokens).count)
          let referenceCoverage = overlap / Double(referenceTokens.count)
          let inputCoverage = overlap / Double(inputTokens.count)
          return (referenceCoverage * 0.42) + (inputCoverage * 0.25)
        }.max() ?? 0

      var score = prefixMatch ? max(referenceScore, 0.80) : referenceScore
      if familyAliasMatch { score += 0.14 }
      if !alignedTerms.isEmpty { score += 0.12 }
      if isQuestionLead { score += 0.04 }
      if !inputYears.isDisjoint(with: family.years) { score += 0.07 }
      if !inputYears.isEmpty, !family.years.isEmpty, inputYears.isDisjoint(with: family.years) {
        score -= 0.18
      }
      score = min(max(score, 0), 1)
      guard score >= minimumConfidence else { return nil }

      var bindings = alignedTerms.map {
        ResolvedQuestionBinding(key: "term", value: $0.id, surfaceText: $0.surfaceText)
      }
      bindings.append(
        contentsOf: inputYears.sorted().map {
          ResolvedQuestionBinding(key: "period", value: $0, surfaceText: $0)
        })
      bindings.sort {
        ($0.key, $0.value, $0.surfaceText) < ($1.key, $1.value, $1.surfaceText)
      }
      return Match(familyID: family.id, confidence: score, bindings: bindings)
    }

    return matches.sorted {
      if $0.confidence == $1.confidence { return $0.familyID < $1.familyID }
      return $0.confidence > $1.confidence
    }.first
  }

  private func matchingTerms(in text: String) -> [TermMatch] {
    terms.compactMap { term in
      let matches = term.forms.filter { Self.containsPhrase(text, phrase: $0) }
      guard let surface = matches.max(by: { $0.count < $1.count }) else { return nil }
      return TermMatch(id: term.id, surfaceText: surface)
    }
  }

  private static func hasConflictingMaterialBinding(
    existing: [ResolvedQuestionBinding],
    incoming: [ResolvedQuestionBinding]
  ) -> Bool {
    let materialKeys = Set(["period"])
    for key in materialKeys {
      let oldValues = Set(existing.filter { $0.key == key }.map(\.value))
      let newValues = Set(incoming.filter { $0.key == key }.map(\.value))
      if !oldValues.isEmpty, !newValues.isEmpty, oldValues != newValues { return true }
    }
    return false
  }

  private static func mergeBindings(
    existing: [ResolvedQuestionBinding],
    incoming: [ResolvedQuestionBinding]
  ) -> [ResolvedQuestionBinding] {
    var byIdentity = Dictionary(
      uniqueKeysWithValues: existing.map { ("\($0.key)\u{0}\($0.value)", $0) })
    for binding in incoming {
      let identity = "\(binding.key)\u{0}\(binding.value)"
      if byIdentity[identity] == nil {
        byIdentity[identity] = binding
      }
    }
    return byIdentity.values.sorted {
      ($0.key, $0.value, $0.surfaceText) < ($1.key, $1.value, $1.surfaceText)
    }
  }

  private static func index(_ family: KnowledgeQuestionFamily) -> IndexedFamily {
    let canonical = normalize(family.canonicalQuestion)
    let variants = family.variants.map(normalize).filter { !$0.isEmpty }
    let prefixes = family.partialPrefixes.map(normalize).filter { !$0.isEmpty }
    let aliases = family.aliases.map(normalize).filter { !$0.isEmpty }
    let references = [canonical] + variants + prefixes
    let vocabulary = ([canonical] + variants + prefixes + aliases).joined(separator: " ")
    return IndexedFamily(
      id: family.id,
      references: references,
      prefixes: prefixes,
      aliases: aliases,
      vocabulary: vocabulary,
      years: years(in: vocabulary)
    )
  }

  private static func index(_ alias: KnowledgeTermAlias) -> IndexedTerm {
    let forms = ([alias.canonicalText] + alias.aliases)
      .map(normalize)
      .filter { !$0.isEmpty }
    return IndexedTerm(id: alias.id, forms: Array(Set(forms)).sorted())
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

  private static let questionLeadingWords = Set([
    "what", "how", "why", "which", "who", "when", "where", "can", "could", "did", "do",
    "does", "is", "should", "was", "were", "will", "would",
  ])
}
