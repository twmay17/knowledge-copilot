import Foundation

public enum KnowledgeEvidenceRequiredField: String, Codable, CaseIterable, Hashable, Sendable {
  case entity
  case period
  case scope
  case version
}

public struct KnowledgeEvidenceQuery: Codable, Equatable, Sendable {
  public let subject: String?
  public let predicate: String
  public let qualifiers: [String: String]
  public let sourceIDs: Set<String>
  public let requiredFields: Set<KnowledgeEvidenceRequiredField>
  public let proposedValue: KnowledgeValue?

  public init(
    subject: String? = nil,
    predicate: String,
    qualifiers: [String: String] = [:],
    sourceIDs: Set<String> = [],
    requiredFields: Set<KnowledgeEvidenceRequiredField> = [],
    proposedValue: KnowledgeValue? = nil
  ) {
    self.subject = subject
    self.predicate = predicate
    self.qualifiers = qualifiers
    self.sourceIDs = sourceIDs
    self.requiredFields = requiredFields
    self.proposedValue = proposedValue
  }
}

public enum KnowledgeEvidenceOutcomeReason: String, Codable, Equatable, Sendable {
  case insufficientContext = "insufficient_context"
  case noMatchingAssertions = "no_matching_assertions"
  case retrievalIncomplete = "retrieval_incomplete"
  case evidenceUnavailable = "evidence_unavailable"
  case conflictingAssertions = "conflicting_assertions"
  case incompatibleContexts = "incompatible_contexts"
  case contestedEvidence = "contested_evidence"
  case claimContradicted = "claim_contradicted"
  case interpretiveClaims = "interpretive_claims"
  case calculatedClaims = "calculated_claims"
  case supportedClaims = "supported_claims"
  case directlySourcedClaims = "directly_sourced_claims"
}

public struct KnowledgeEvidenceAttribution: Codable, Equatable, Sendable, Identifiable {
  public let assertionID: String
  public let evidenceLinkID: String
  public let relation: KnowledgeEvidenceRelation
  public let note: String?
  public let passageID: String
  public let sourceID: String
  public let sourceTitle: String
  public let fileURL: URL
  public let locatorLabel: String
  public let excerpt: String

  public var id: String { "\(assertionID):\(evidenceLinkID)" }

  public init(
    assertionID: String,
    evidenceLinkID: String,
    relation: KnowledgeEvidenceRelation,
    note: String?,
    passageID: String,
    sourceID: String,
    sourceTitle: String,
    fileURL: URL,
    locatorLabel: String,
    excerpt: String
  ) {
    self.assertionID = assertionID
    self.evidenceLinkID = evidenceLinkID
    self.relation = relation
    self.note = note
    self.passageID = passageID
    self.sourceID = sourceID
    self.sourceTitle = sourceTitle
    self.fileURL = fileURL
    self.locatorLabel = locatorLabel
    self.excerpt = excerpt
  }
}

public struct KnowledgeEvidenceClaim: Codable, Equatable, Sendable, Identifiable {
  public let assertionID: String
  public let subject: String
  public let predicate: String
  public let value: KnowledgeValue
  public let displayValue: String
  public let qualifiers: [String: String]
  public let kind: KnowledgeAssertionKind
  public let confidence: Double
  public let attributions: [KnowledgeEvidenceAttribution]

  public var id: String { assertionID }

  public init(
    assertionID: String,
    subject: String,
    predicate: String,
    value: KnowledgeValue,
    displayValue: String,
    qualifiers: [String: String],
    kind: KnowledgeAssertionKind,
    confidence: Double,
    attributions: [KnowledgeEvidenceAttribution]
  ) {
    self.assertionID = assertionID
    self.subject = subject
    self.predicate = predicate
    self.value = value
    self.displayValue = displayValue
    self.qualifiers = qualifiers
    self.kind = kind
    self.confidence = confidence
    self.attributions = attributions
  }
}

public struct KnowledgeEvidenceSourceReference: Codable, Equatable, Sendable, Identifiable {
  public let passageID: String
  public let sourceID: String
  public let sourceTitle: String
  public let fileURL: URL
  public let locatorLabel: String
  public let excerpt: String

  public var id: String { "\(sourceID):\(passageID)" }

  public init(attribution: KnowledgeEvidenceAttribution) {
    passageID = attribution.passageID
    sourceID = attribution.sourceID
    sourceTitle = attribution.sourceTitle
    fileURL = attribution.fileURL
    locatorLabel = attribution.locatorLabel
    excerpt = attribution.excerpt
  }
}

public struct KnowledgeEvidenceOutcome: Codable, Equatable, Sendable {
  public let packID: String
  public let packContentHash: String
  public let state: KnowledgeEvidenceState
  public let reason: KnowledgeEvidenceOutcomeReason
  public let claims: [KnowledgeEvidenceClaim]
  public let contributingSources: [KnowledgeEvidenceSourceReference]
  public let missingFields: [KnowledgeEvidenceRequiredField]
  public let unresolvedAssertionIDs: [String]

  public init(
    packID: String,
    packContentHash: String,
    state: KnowledgeEvidenceState,
    reason: KnowledgeEvidenceOutcomeReason,
    claims: [KnowledgeEvidenceClaim],
    contributingSources: [KnowledgeEvidenceSourceReference],
    missingFields: [KnowledgeEvidenceRequiredField] = [],
    unresolvedAssertionIDs: [String] = []
  ) {
    self.packID = packID
    self.packContentHash = packContentHash
    self.state = state
    self.reason = reason
    self.claims = claims
    self.contributingSources = contributingSources
    self.missingFields = missingFields
    self.unresolvedAssertionIDs = unresolvedAssertionIDs
  }
}

public enum KnowledgeEvidenceOutcomeError: Error, Equatable, CustomStringConvertible {
  case blankPredicate
  case staleIndex

  public var description: String {
    switch self {
    case .blankPredicate:
      return "An evidence query requires a canonical predicate."
    case .staleIndex:
      return "The evidence evaluator requires an index for the exact active KnowledgePack content."
    }
  }
}

/// Classifies retrieved, typed assertions without synthesizing a factual answer.
///
/// Retrieval remains pack-bound. The evaluator then preserves every comparable assertion and its
/// source attribution before returning a factual, contested, interpretive, clarification, or
/// corpus-missing outcome.
public struct KnowledgeEvidenceOutcomeEvaluator: Sendable {
  public let packID: String
  public let packContentHash: String

  private struct AttributionResolution {
    let attributions: [KnowledgeEvidenceAttribution]
    let isComplete: Bool
  }

  private let pack: KnowledgePack
  private let searchIndex: KnowledgePackSearchIndex
  private let rootDirectory: URL
  private let assertionsByID: [String: KnowledgeAssertion]
  private let evidenceLinksByID: [String: KnowledgeEvidenceLink]
  private let passagesByID: [String: KnowledgePassage]
  private let sourcesByID: [String: KnowledgeSource]
  private let calculationsByOutputID: [String: [KnowledgeCalculation]]

  public init(
    pack: KnowledgePack,
    searchIndex: KnowledgePackSearchIndex,
    rootDirectory: URL
  ) throws {
    let contentHash = try KnowledgeStudyBundleBuilder().build(from: pack).packContentHash
    guard searchIndex.packID == pack.manifest.packID,
      searchIndex.packContentHash == contentHash
    else { throw KnowledgeEvidenceOutcomeError.staleIndex }

    self.pack = pack
    self.searchIndex = searchIndex
    self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
    packID = pack.manifest.packID
    packContentHash = contentHash
    assertionsByID = Dictionary(uniqueKeysWithValues: pack.assertions.map { ($0.id, $0) })
    evidenceLinksByID = Dictionary(uniqueKeysWithValues: pack.evidenceLinks.map { ($0.id, $0) })
    passagesByID = Dictionary(uniqueKeysWithValues: pack.passages.map { ($0.id, $0) })
    sourcesByID = Dictionary(uniqueKeysWithValues: pack.sources.map { ($0.id, $0) })
    calculationsByOutputID = Dictionary(grouping: pack.calculations, by: \.outputAssertionID)
  }

  public func evaluate(_ query: KnowledgeEvidenceQuery) throws -> KnowledgeEvidenceOutcome {
    let predicate = query.predicate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !predicate.isEmpty else { throw KnowledgeEvidenceOutcomeError.blankPredicate }

    let missingFields = Self.missingFields(in: query)
    guard missingFields.isEmpty else {
      return outcome(
        state: .needsClarification,
        reason: .insufficientContext,
        claims: [],
        missingFields: missingFields
      )
    }

    let normalizedQualifiers = Self.normalizedQualifiers(query.qualifiers)
    let results = try searchIndex.search(
      KnowledgePackSearchQuery(
        text: predicate,
        scope: KnowledgePackSearchScope(
          packID: pack.manifest.packID,
          recordKinds: [.assertion],
          sourceIDs: query.sourceIDs,
          requiredQualifiers: normalizedQualifiers
        ),
        limit: 100
      )
    )
    let subject = Self.normalizedOptional(query.subject)
    let retrievedAssertionIDs = Set(
      results.compactMap { result -> String? in
        guard result.packID == pack.manifest.packID,
          result.packContentHash == searchIndex.packContentHash,
          result.kind == .assertion
        else { return nil }
        return result.recordID
      })
    let eligibleAssertions = pack.assertions.filter { assertion in
      assertion.predicate == predicate
        && (subject == nil || assertion.subject == subject)
        && normalizedQualifiers.allSatisfy { assertion.qualifiers[$0.key] == $0.value }
        && (query.sourceIDs.isEmpty
          || !query.sourceIDs.isDisjoint(with: sourceIDs(for: assertion.id, visited: [])))
    }.sorted { $0.id < $1.id }

    guard !eligibleAssertions.isEmpty else {
      return outcome(state: .notFoundInCorpus, reason: .noMatchingAssertions, claims: [])
    }
    let omittedAssertionIDs = eligibleAssertions.map(\.id).filter {
      !retrievedAssertionIDs.contains($0)
    }
    guard omittedAssertionIDs.isEmpty else {
      return outcome(
        state: .needsClarification,
        reason: .retrievalIncomplete,
        claims: [],
        unresolvedAssertionIDs: omittedAssertionIDs
      )
    }
    let assertions = eligibleAssertions

    var unresolvedAssertionIDs: [String] = []
    let claims = assertions.map { assertion in
      let resolution = resolveAttributions(for: assertion.id, visited: [])
      if !resolution.isComplete || resolution.attributions.isEmpty {
        unresolvedAssertionIDs.append(assertion.id)
      }
      return KnowledgeEvidenceClaim(
        assertionID: assertion.id,
        subject: assertion.subject,
        predicate: assertion.predicate,
        value: assertion.value,
        displayValue: Self.displayValue(assertion.value),
        qualifiers: assertion.qualifiers,
        kind: assertion.kind,
        confidence: assertion.confidence,
        attributions: resolution.attributions
      )
    }
    let sources = Self.contributingSources(from: claims)

    guard unresolvedAssertionIDs.isEmpty else {
      return outcome(
        state: .needsClarification,
        reason: .evidenceUnavailable,
        claims: claims,
        sources: sources,
        unresolvedAssertionIDs: unresolvedAssertionIDs.sorted()
      )
    }

    let unresolvedContextKeys = Self.incompatibleContextKeys(
      claims: claims,
      boundQualifiers: Set(normalizedQualifiers.keys)
    )
    if !unresolvedContextKeys.isEmpty {
      return outcome(
        state: .contested,
        reason: .incompatibleContexts,
        claims: claims,
        sources: sources
      )
    }

    let fingerprints = Set(claims.map { Self.fingerprint($0.value) })
    if fingerprints.count > 1 {
      return outcome(
        state: .contested,
        reason: .conflictingAssertions,
        claims: claims,
        sources: sources
      )
    }

    if claims.contains(where: { claim in
      claim.attributions.contains(where: { $0.relation == .contradicts })
    }) {
      return outcome(
        state: .contested,
        reason: .contestedEvidence,
        claims: claims,
        sources: sources
      )
    }

    if let proposedValue = query.proposedValue,
      !claims.contains(where: { Self.valuesAreEquivalent($0.value, proposedValue) })
    {
      return outcome(
        state: .contradictedByCorpus,
        reason: .claimContradicted,
        claims: claims,
        sources: sources
      )
    }

    if claims.contains(where: { $0.kind == .interpretive }) {
      return outcome(
        state: .interpretive,
        reason: .interpretiveClaims,
        claims: claims,
        sources: sources
      )
    }
    if claims.allSatisfy({ $0.kind == .calculated }) {
      return outcome(
        state: .calculated,
        reason: .calculatedClaims,
        claims: claims,
        sources: sources
      )
    }
    if claims.allSatisfy({ $0.kind == .stated }) {
      return outcome(
        state: .directlySourced,
        reason: .directlySourcedClaims,
        claims: claims,
        sources: sources
      )
    }
    return outcome(
      state: .supportedByCorpus,
      reason: .supportedClaims,
      claims: claims,
      sources: sources
    )
  }

  private func outcome(
    state: KnowledgeEvidenceState,
    reason: KnowledgeEvidenceOutcomeReason,
    claims: [KnowledgeEvidenceClaim],
    sources: [KnowledgeEvidenceSourceReference] = [],
    missingFields: [KnowledgeEvidenceRequiredField] = [],
    unresolvedAssertionIDs: [String] = []
  ) -> KnowledgeEvidenceOutcome {
    KnowledgeEvidenceOutcome(
      packID: pack.manifest.packID,
      packContentHash: searchIndex.packContentHash,
      state: state,
      reason: reason,
      claims: claims,
      contributingSources: sources,
      missingFields: missingFields,
      unresolvedAssertionIDs: unresolvedAssertionIDs
    )
  }

  private func resolveAttributions(
    for assertionID: String,
    visited: Set<String>
  ) -> AttributionResolution {
    guard !visited.contains(assertionID), let assertion = assertionsByID[assertionID] else {
      return AttributionResolution(attributions: [], isComplete: false)
    }
    let nextVisited = visited.union([assertionID])
    var isComplete = true
    let direct = assertion.evidenceLinkIDs.compactMap {
      evidenceLinkID -> KnowledgeEvidenceAttribution? in
      guard let link = evidenceLinksByID[evidenceLinkID], link.assertionID == assertion.id,
        let attribution = resolveAttribution(link, assertionID: assertion.id)
      else {
        isComplete = false
        return nil
      }
      return attribution
    }
    if !direct.isEmpty || !assertion.evidenceLinkIDs.isEmpty {
      return AttributionResolution(
        attributions: Self.uniqueAttributions(direct),
        isComplete: isComplete && direct.count == assertion.evidenceLinkIDs.count
      )
    }

    guard assertion.kind == .calculated,
      let calculations = calculationsByOutputID[assertion.id],
      calculations.count == 1,
      let calculation = calculations.first
    else { return AttributionResolution(attributions: [], isComplete: false) }

    var derived: [KnowledgeEvidenceAttribution] = []
    for inputAssertionID in calculation.inputAssertionIDs {
      let resolution = resolveAttributions(for: inputAssertionID, visited: nextVisited)
      isComplete = isComplete && resolution.isComplete
      derived.append(contentsOf: resolution.attributions)
    }
    return AttributionResolution(
      attributions: Self.uniqueAttributions(derived),
      isComplete: isComplete && !derived.isEmpty
    )
  }

  private func resolveAttribution(
    _ link: KnowledgeEvidenceLink,
    assertionID: String
  ) -> KnowledgeEvidenceAttribution? {
    guard let passage = passagesByID[link.passageID],
      let source = sourcesByID[passage.sourceID]
    else { return nil }
    let fileURL = rootDirectory.appendingPathComponent(source.relativePath)
      .standardizedFileURL.resolvingSymlinksInPath()
    guard Self.isInsideRoot(fileURL, root: rootDirectory),
      FileManager.default.fileExists(atPath: fileURL.path)
    else { return nil }

    return KnowledgeEvidenceAttribution(
      assertionID: assertionID,
      evidenceLinkID: link.id,
      relation: link.relation,
      note: link.note,
      passageID: passage.id,
      sourceID: source.id,
      sourceTitle: source.title,
      fileURL: fileURL,
      locatorLabel: Self.locatorLabel(passage.locator),
      excerpt: passage.text
    )
  }

  private func sourceIDs(for assertionID: String, visited: Set<String>) -> Set<String> {
    guard !visited.contains(assertionID), let assertion = assertionsByID[assertionID] else {
      return []
    }
    let nextVisited = visited.union([assertionID])
    let direct = Set(
      assertion.evidenceLinkIDs.compactMap { evidenceLinkID -> String? in
        guard let passageID = evidenceLinksByID[evidenceLinkID]?.passageID else { return nil }
        return passagesByID[passageID]?.sourceID
      })
    if !direct.isEmpty { return direct }
    guard assertion.kind == .calculated,
      let calculations = calculationsByOutputID[assertionID],
      calculations.count == 1,
      let calculation = calculations.first
    else { return [] }
    return calculation.inputAssertionIDs.reduce(into: []) { result, inputAssertionID in
      result.formUnion(sourceIDs(for: inputAssertionID, visited: nextVisited))
    }
  }

  private static func missingFields(
    in query: KnowledgeEvidenceQuery
  ) -> [KnowledgeEvidenceRequiredField] {
    query.requiredFields.filter { field in
      switch field {
      case .entity:
        return normalizedOptional(query.subject) == nil
      case .period, .scope, .version:
        let value = query.qualifiers[field.rawValue]
        return normalizedOptional(value) == nil
      }
    }.sorted { $0.rawValue < $1.rawValue }
  }

  private static func incompatibleContextKeys(
    claims: [KnowledgeEvidenceClaim],
    boundQualifiers: Set<String>
  ) -> [String] {
    let allKeys = claims.reduce(into: Set<String>()) { keys, claim in
      keys.formUnion(claim.qualifiers.keys)
    }.subtracting(boundQualifiers)
    return allKeys.filter { key in
      Set(claims.map { $0.qualifiers[key] ?? "<missing>" }).count > 1
    }.sorted()
  }

  private static func contributingSources(
    from claims: [KnowledgeEvidenceClaim]
  ) -> [KnowledgeEvidenceSourceReference] {
    let references = claims.flatMap(\.attributions).map(KnowledgeEvidenceSourceReference.init)
    return Dictionary(grouping: references, by: \.id).compactMap { $0.value.first }
      .sorted { $0.id < $1.id }
  }

  private static func uniqueAttributions(
    _ attributions: [KnowledgeEvidenceAttribution]
  ) -> [KnowledgeEvidenceAttribution] {
    Dictionary(grouping: attributions, by: \.id).compactMap { $0.value.first }
      .sorted { $0.id < $1.id }
  }

  /// Live claim literals travel a different parse path than pack-authored
  /// decimals (for example "8.05%" -> 8.05 / 100), so numeric comparison
  /// tolerates a tightly bounded rounding difference instead of requiring
  /// bit-identical doubles. The demonstrated discrepancy is ≤ ~4 ULPs
  /// (literal decode + divide + scale multiply per side); 8 ULPs covers it
  /// with margin while staying ~1.8e-15 relative — far below any
  /// semantically distinct corpus value at every magnitude.
  static let maximumEquivalentULPDistance: UInt64 = 8

  static func valuesAreEquivalent(_ lhs: KnowledgeValue, _ rhs: KnowledgeValue) -> Bool {
    if lhs.type == .number || rhs.type == .number {
      guard lhs.type == .number, rhs.type == .number,
        let lhsNumber = lhs.number, let lhsScale = lhs.scale,
        let rhsNumber = rhs.number, let rhsScale = rhs.scale
      else { return false }
      guard (lhs.unit ?? "") == (rhs.unit ?? "") else { return false }
      guard let distance = ulpDistance(lhsNumber * lhsScale, rhsNumber * rhsScale) else {
        return false
      }
      return distance <= Self.maximumEquivalentULPDistance
    }
    return fingerprint(lhs) == fingerprint(rhs)
  }

  /// Distance in representable doubles between two finite, nonzero values of
  /// the same sign; nil when either value is non-finite, either is zero after
  /// exact equality has been ruled out (±0 counts as equal), or the signs
  /// differ.
  static func ulpDistance(_ lhs: Double, _ rhs: Double) -> UInt64? {
    guard lhs.isFinite, rhs.isFinite else { return nil }
    if lhs == rhs { return 0 }
    // Zero is exactly 1 ULP from Double.leastNonzeroMagnitude; "only zero
    // matches zero" requires excluding zero operands past this point.
    guard lhs != 0, rhs != 0 else { return nil }
    guard (lhs < 0) == (rhs < 0) else { return nil }
    let lhsBits = abs(lhs).bitPattern
    let rhsBits = abs(rhs).bitPattern
    return lhsBits > rhsBits ? lhsBits - rhsBits : rhsBits - lhsBits
  }

  private static func fingerprint(_ value: KnowledgeValue) -> String {
    switch value.type {
    case .text:
      return "text:\(value.text ?? "")"
    case .number:
      guard let number = value.number, let scale = value.scale else { return "number:invalid" }
      return "number:\(String(format: "%.17g", number * scale)):\(value.unit ?? "")"
    case .boolean:
      return "boolean:\(value.boolean.map(String.init) ?? "invalid")"
    case .date:
      return "date:\(value.date ?? "")"
    case .reference:
      return "reference:\(value.referenceID ?? "")"
    }
  }

  private static func displayValue(_ value: KnowledgeValue) -> String {
    switch value.type {
    case .text:
      return value.text ?? ""
    case .number:
      guard let number = value.number, let scale = value.scale else { return "" }
      let formatted = String(format: "%.12g", number * scale)
      return value.unit.map { "\(formatted) \($0)" } ?? formatted
    case .boolean:
      return value.boolean.map(String.init) ?? ""
    case .date:
      return value.date ?? ""
    case .reference:
      return value.referenceID ?? ""
    }
  }

  private static func normalizedOptional(_ value: String?) -> String? {
    guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !normalized.isEmpty
    else { return nil }
    return normalized
  }

  private static func normalizedQualifiers(
    _ qualifiers: [String: String]
  ) -> [String: String] {
    qualifiers.keys.sorted().reduce(into: [:]) { result, key in
      let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedValue = qualifiers[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      result[normalizedKey] = normalizedValue
    }
  }

  private static func isInsideRoot(_ fileURL: URL, root: URL) -> Bool {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return fileURL.path.hasPrefix(rootPath)
  }

  private static func locatorLabel(_ locator: KnowledgeSourceLocator) -> String {
    var parts: [String] = []
    if let page = locator.page { parts.append("Page \(page)") }
    if let sheet = locator.sheet { parts.append(sheet) }
    if let cellRange = locator.cellRange { parts.append(cellRange) }
    if !locator.sectionPath.isEmpty { parts.append(locator.sectionPath.joined(separator: " › ")) }
    if locator.cellRange == nil, let start = locator.rowStart {
      let rows =
        locator.rowEnd.map { $0 == start ? "Row \(start)" : "Rows \(start)–\($0)" }
        ?? "Row \(start)"
      parts.append(rows)
    }
    return parts.joined(separator: " · ")
  }
}
