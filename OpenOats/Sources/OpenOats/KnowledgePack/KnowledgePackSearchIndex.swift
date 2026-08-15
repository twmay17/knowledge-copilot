import Foundation
import SQLite3

public enum KnowledgePackSearchRecordKind: String, CaseIterable, Codable, Sendable {
  case manifest
  case source
  case passage
  case assertion
  case evidenceLink = "evidence_link"
  case calculation
  case responseCard = "response_card"
  case questionFamily = "question_family"
}

public struct KnowledgePackSearchScope: Equatable, Sendable {
  public let packID: String
  public let recordKinds: Set<KnowledgePackSearchRecordKind>
  public let sourceIDs: Set<String>
  public let requiredQualifiers: [String: String]
  public let preferredQualifiers: [String: String]

  public init(
    packID: String,
    recordKinds: Set<KnowledgePackSearchRecordKind> = [],
    sourceIDs: Set<String> = [],
    requiredQualifiers: [String: String] = [:],
    preferredQualifiers: [String: String] = [:]
  ) {
    self.packID = packID
    self.recordKinds = recordKinds
    self.sourceIDs = sourceIDs
    self.requiredQualifiers = requiredQualifiers
    self.preferredQualifiers = preferredQualifiers
  }
}

public struct KnowledgePackSearchQuery: Equatable, Sendable {
  public let text: String
  public let scope: KnowledgePackSearchScope
  public let limit: Int

  public init(text: String, scope: KnowledgePackSearchScope, limit: Int = 10) {
    self.text = text
    self.scope = scope
    self.limit = limit
  }
}

public enum KnowledgePackSearchChannel: String, Codable, Equatable, Hashable, Sendable {
  case exact
  case fullText = "full_text"
  case vector
}

public struct KnowledgePackSearchScore: Codable, Equatable, Sendable {
  public let exact: Double
  public let fullText: Double
  public let qualifier: Double
  public let vector: Double

  public var total: Double {
    min(1, exact + fullText + qualifier + vector)
  }

  public init(exact: Double, fullText: Double, qualifier: Double, vector: Double) {
    self.exact = exact
    self.fullText = fullText
    self.qualifier = qualifier
    self.vector = vector
  }
}

public struct KnowledgePackSearchResult: Codable, Equatable, Sendable, Identifiable {
  public let packID: String
  public let packContentHash: String
  public let kind: KnowledgePackSearchRecordKind
  public let recordID: String
  public let title: String
  public let excerpt: String
  public let qualifiers: [String: String]
  public let sourceIDs: [String]
  public let score: KnowledgePackSearchScore
  public let channels: Set<KnowledgePackSearchChannel>

  public var id: String { "\(kind.rawValue):\(recordID)" }

  public init(
    packID: String,
    packContentHash: String,
    kind: KnowledgePackSearchRecordKind,
    recordID: String,
    title: String,
    excerpt: String,
    qualifiers: [String: String],
    sourceIDs: [String],
    score: KnowledgePackSearchScore,
    channels: Set<KnowledgePackSearchChannel>
  ) {
    self.packID = packID
    self.packContentHash = packContentHash
    self.kind = kind
    self.recordID = recordID
    self.title = title
    self.excerpt = excerpt
    self.qualifiers = qualifiers
    self.sourceIDs = sourceIDs
    self.score = score
    self.channels = channels
  }
}

public struct KnowledgePackVectorCandidate: Equatable, Sendable, Identifiable {
  public let id: String
  public let kind: KnowledgePackSearchRecordKind
  public let recordID: String
  public let title: String
  public let text: String

  public init(
    id: String,
    kind: KnowledgePackSearchRecordKind,
    recordID: String,
    title: String,
    text: String
  ) {
    self.id = id
    self.kind = kind
    self.recordID = recordID
    self.title = title
    self.text = text
  }
}

public struct KnowledgePackVectorSearchRequest: Equatable, Sendable {
  public let packID: String
  public let packContentHash: String
  public let query: String
  public let candidates: [KnowledgePackVectorCandidate]
  public let limit: Int

  public init(
    packID: String,
    packContentHash: String,
    query: String,
    candidates: [KnowledgePackVectorCandidate],
    limit: Int
  ) {
    self.packID = packID
    self.packContentHash = packContentHash
    self.query = query
    self.candidates = candidates
    self.limit = limit
  }
}

public struct KnowledgePackVectorMatch: Equatable, Sendable {
  public let candidateID: String
  public let score: Double

  public init(candidateID: String, score: Double) {
    self.candidateID = candidateID
    self.score = score
  }
}

public protocol KnowledgePackVectorSearchAdapter: Sendable {
  func search(_ request: KnowledgePackVectorSearchRequest) async throws
    -> [KnowledgePackVectorMatch]
}

public enum KnowledgePackSearchError: Error, Equatable, CustomStringConvertible {
  case blankQuery
  case invalidLimit
  case indexUnavailable
  case packMismatch(expected: String, actual: String)
  case sqlite(String)

  public var description: String {
    switch self {
    case .blankQuery:
      return "KnowledgePack search text must not be blank."
    case .invalidLimit:
      return "KnowledgePack search limit must be between 1 and 100."
    case .indexUnavailable:
      return "Load and validate a KnowledgePack before searching it."
    case .packMismatch(let expected, let actual):
      return "Search was scoped to pack '\(actual)', but this index belongs to '\(expected)'."
    case .sqlite(let message):
      return "The local KnowledgePack full-text index failed: \(message)"
    }
  }
}

public struct KnowledgePackArtifactReference: Codable, Equatable, Hashable, Sendable {
  public let kind: KnowledgePackSearchRecordKind
  public let id: String

  public init(kind: KnowledgePackSearchRecordKind, id: String) {
    self.kind = kind
    self.id = id
  }
}

public struct KnowledgePackDependencyInvalidationPlan: Equatable, Sendable {
  public let packID: String
  public let previousPackContentHash: String
  public let currentPackContentHash: String
  public let directlyChanged: Set<KnowledgePackArtifactReference>
  public let invalidated: Set<KnowledgePackArtifactReference>

  public var requiresRebuild: Bool {
    previousPackContentHash != currentPackContentHash
  }

  public init(
    packID: String,
    previousPackContentHash: String,
    currentPackContentHash: String,
    directlyChanged: Set<KnowledgePackArtifactReference>,
    invalidated: Set<KnowledgePackArtifactReference>
  ) {
    self.packID = packID
    self.previousPackContentHash = previousPackContentHash
    self.currentPackContentHash = currentPackContentHash
    self.directlyChanged = directlyChanged
    self.invalidated = invalidated
  }
}

public struct KnowledgePackSearchRebuildReport: Equatable, Sendable {
  public let packID: String
  public let packContentHash: String
  public let indexedDocumentCount: Int
  public let invalidationPlan: KnowledgePackDependencyInvalidationPlan?
  public let reusedExistingIndex: Bool

  public init(
    packID: String,
    packContentHash: String,
    indexedDocumentCount: Int,
    invalidationPlan: KnowledgePackDependencyInvalidationPlan?,
    reusedExistingIndex: Bool
  ) {
    self.packID = packID
    self.packContentHash = packContentHash
    self.indexedDocumentCount = indexedDocumentCount
    self.invalidationPlan = invalidationPlan
    self.reusedExistingIndex = reusedExistingIndex
  }
}

public struct KnowledgePackSearchIndexBuild: Sendable {
  public let index: KnowledgePackSearchIndex
  public let report: KnowledgePackSearchRebuildReport

  public init(index: KnowledgePackSearchIndex, report: KnowledgePackSearchRebuildReport) {
    self.index = index
    self.report = report
  }
}

public enum KnowledgePackSearchIndexer {
  public static func build(
    pack: KnowledgePack,
    previousPack: KnowledgePack? = nil,
    previousIndex: KnowledgePackSearchIndex? = nil
  ) throws -> KnowledgePackSearchIndexBuild {
    let contentHash = try KnowledgeStudyBundleBuilder().build(from: pack).packContentHash
    let invalidationPlan: KnowledgePackDependencyInvalidationPlan?
    if let previousPack, previousPack.manifest.packID == pack.manifest.packID {
      invalidationPlan = try KnowledgePackDependencyInvalidator().plan(
        from: previousPack,
        to: pack
      )
    } else {
      invalidationPlan = nil
    }
    let canReuse =
      previousPack != nil
      && previousIndex?.packID == pack.manifest.packID
      && previousIndex?.packContentHash == contentHash
      && invalidationPlan?.requiresRebuild != true
    let index =
      try canReuse
      ? previousIndex!
      : KnowledgePackSearchIndex(pack: pack, packContentHash: contentHash)
    return KnowledgePackSearchIndexBuild(
      index: index,
      report: KnowledgePackSearchRebuildReport(
        packID: index.packID,
        packContentHash: index.packContentHash,
        indexedDocumentCount: index.documentCount,
        invalidationPlan: invalidationPlan,
        reusedExistingIndex: canReuse
      )
    )
  }
}

public final class KnowledgePackSearchIndex: @unchecked Sendable {
  public let packID: String
  public let packContentHash: String
  public let documentCount: Int

  private let documentsByID: [String: SearchDocument]
  private let exactIDsByAlias: [String: Set<String>]
  private let fullTextIndex: KnowledgePackSQLiteFullTextIndex

  public convenience init(pack: KnowledgePack) throws {
    let contentHash = try KnowledgeStudyBundleBuilder().build(from: pack).packContentHash
    try self.init(pack: pack, packContentHash: contentHash)
  }

  fileprivate init(pack: KnowledgePack, packContentHash: String) throws {
    packID = pack.manifest.packID
    self.packContentHash = packContentHash
    let documents = SearchDocument.makeDocuments(from: pack)
    documentsByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
    documentCount = documents.count
    exactIDsByAlias = Self.makeExactLookup(documents: documents)
    fullTextIndex = try KnowledgePackSQLiteFullTextIndex(documents: documents)
  }

  public func search(_ query: KnowledgePackSearchQuery) throws -> [KnowledgePackSearchResult] {
    let prepared = try prepare(query)
    return makeResults(
      prepared: prepared,
      vectorScores: [:]
    )
  }

  public func search(
    _ query: KnowledgePackSearchQuery,
    vectorAdapter: any KnowledgePackVectorSearchAdapter
  ) async throws -> [KnowledgePackSearchResult] {
    let prepared = try prepare(query)
    let candidates = prepared.scopedDocuments.map {
      KnowledgePackVectorCandidate(
        id: $0.id,
        kind: $0.kind,
        recordID: $0.recordID,
        title: $0.title,
        text: $0.searchableText
      )
    }
    let vectorMatches: [KnowledgePackVectorMatch]
    do {
      vectorMatches = try await vectorAdapter.search(
        KnowledgePackVectorSearchRequest(
          packID: packID,
          packContentHash: packContentHash,
          query: prepared.text,
          candidates: candidates,
          limit: prepared.limit
        )
      )
    } catch {
      vectorMatches = []
    }
    let allowedIDs = Set(candidates.map(\.id))
    let vectorScores = Dictionary(
      vectorMatches.compactMap { match -> (String, Double)? in
        guard allowedIDs.contains(match.candidateID), match.score.isFinite else { return nil }
        return (match.candidateID, min(max(match.score, 0), 1))
      },
      uniquingKeysWith: max
    )
    return makeResults(prepared: prepared, vectorScores: vectorScores)
  }

  private struct PreparedSearch {
    let text: String
    let normalizedText: String
    let limit: Int
    let scope: KnowledgePackSearchScope
    let scopedDocuments: [SearchDocument]
    let exactDocumentIDs: Set<String>
    let fullTextScores: [String: Double]
  }

  private func prepare(_ query: KnowledgePackSearchQuery) throws -> PreparedSearch {
    let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw KnowledgePackSearchError.blankQuery }
    guard (1...100).contains(query.limit) else { throw KnowledgePackSearchError.invalidLimit }
    guard query.scope.packID == packID else {
      throw KnowledgePackSearchError.packMismatch(expected: packID, actual: query.scope.packID)
    }

    let scopedDocuments = documentsByID.values.filter {
      Self.isInScope($0, scope: query.scope)
    }.sorted { $0.id < $1.id }
    let scopedIDs = Set(scopedDocuments.map(\.id))
    let normalizedText = Self.normalize(text)
    let exactDocumentIDs = (exactIDsByAlias[normalizedText] ?? []).intersection(scopedIDs)
    let fullTextScores = try fullTextIndex.search(
      text,
      limit: min(max(query.limit * 6, 30), 300)
    ).filter { scopedIDs.contains($0.key) }

    return PreparedSearch(
      text: text,
      normalizedText: normalizedText,
      limit: query.limit,
      scope: query.scope,
      scopedDocuments: scopedDocuments,
      exactDocumentIDs: exactDocumentIDs,
      fullTextScores: fullTextScores
    )
  }

  private func makeResults(
    prepared: PreparedSearch,
    vectorScores: [String: Double]
  ) -> [KnowledgePackSearchResult] {
    let candidateIDs = prepared.exactDocumentIDs
      .union(prepared.fullTextScores.keys)
      .union(vectorScores.keys)

    return candidateIDs.compactMap { documentID -> KnowledgePackSearchResult? in
      guard let document = documentsByID[documentID] else { return nil }
      let exactScore = prepared.exactDocumentIDs.contains(documentID) ? 0.7 : 0
      let fullTextScore = 0.25 * (prepared.fullTextScores[documentID] ?? 0)
      let qualifierScore = Self.qualifierScore(
        document.qualifiers,
        preferred: prepared.scope.preferredQualifiers
      )
      let vectorScore = 0.35 * (vectorScores[documentID] ?? 0)
      var channels: Set<KnowledgePackSearchChannel> = []
      if exactScore > 0 { channels.insert(.exact) }
      if fullTextScore > 0 { channels.insert(.fullText) }
      if vectorScore > 0 { channels.insert(.vector) }
      return KnowledgePackSearchResult(
        packID: packID,
        packContentHash: packContentHash,
        kind: document.kind,
        recordID: document.recordID,
        title: document.title,
        excerpt: document.excerpt,
        qualifiers: document.qualifiers,
        sourceIDs: document.sourceIDs.sorted(),
        score: KnowledgePackSearchScore(
          exact: exactScore,
          fullText: fullTextScore,
          qualifier: qualifierScore,
          vector: vectorScore
        ),
        channels: channels
      )
    }.sorted {
      if $0.score.total != $1.score.total { return $0.score.total > $1.score.total }
      if $0.score.exact != $1.score.exact { return $0.score.exact > $1.score.exact }
      return ($0.kind.rawValue, $0.recordID) < ($1.kind.rawValue, $1.recordID)
    }.prefix(prepared.limit).map { $0 }
  }

  private static func isInScope(
    _ document: SearchDocument,
    scope: KnowledgePackSearchScope
  ) -> Bool {
    if !scope.recordKinds.isEmpty, !scope.recordKinds.contains(document.kind) { return false }
    if !scope.sourceIDs.isEmpty, scope.sourceIDs.isDisjoint(with: document.sourceIDs) {
      return false
    }
    return scope.requiredQualifiers.allSatisfy {
      document.qualifiers[$0.key] == $0.value
    }
  }

  private static func qualifierScore(
    _ qualifiers: [String: String],
    preferred: [String: String]
  ) -> Double {
    guard !preferred.isEmpty else { return 0 }
    let matches = preferred.reduce(into: 0) { count, item in
      if qualifiers[item.key] == item.value { count += 1 }
    }
    return 0.1 * Double(matches) / Double(preferred.count)
  }

  private static func makeExactLookup(
    documents: [SearchDocument]
  ) -> [String: Set<String>] {
    var result: [String: Set<String>] = [:]
    for document in documents {
      for alias in document.exactAliases {
        let normalized = normalize(alias)
        guard !normalized.isEmpty else { continue }
        result[normalized, default: []].insert(document.id)
      }
    }
    return result
  }

  private static func normalize(_ value: String) -> String {
    let folded = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .current
    )
    .lowercased()
    let normalizedCharacters = folded.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) ? String($0) : " "
    }.joined()
    return
      normalizedCharacters
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
      .joined(separator: " ")
  }
}

public struct KnowledgePackDependencyInvalidator: Sendable {
  public init() {}

  public func plan(
    from previousPack: KnowledgePack,
    to currentPack: KnowledgePack
  ) throws -> KnowledgePackDependencyInvalidationPlan {
    guard previousPack.manifest.packID == currentPack.manifest.packID else {
      throw KnowledgePackSearchError.packMismatch(
        expected: previousPack.manifest.packID,
        actual: currentPack.manifest.packID
      )
    }
    let previousHash = try KnowledgeStudyBundleBuilder().build(from: previousPack).packContentHash
    let currentHash = try KnowledgeStudyBundleBuilder().build(from: currentPack).packContentHash
    let directlyChanged = Self.directChanges(from: previousPack, to: currentPack)
    let previousGraph = Self.dependencyGraph(for: previousPack)
    let currentGraph = Self.dependencyGraph(for: currentPack)
    var invalidated = directlyChanged
    var queue = Array(directlyChanged)
    while let reference = queue.popLast() {
      let dependents = (previousGraph[reference] ?? []).union(currentGraph[reference] ?? [])
      for dependent in dependents where invalidated.insert(dependent).inserted {
        queue.append(dependent)
      }
    }
    return KnowledgePackDependencyInvalidationPlan(
      packID: currentPack.manifest.packID,
      previousPackContentHash: previousHash,
      currentPackContentHash: currentHash,
      directlyChanged: directlyChanged,
      invalidated: invalidated
    )
  }

  private static func directChanges(
    from previous: KnowledgePack,
    to current: KnowledgePack
  ) -> Set<KnowledgePackArtifactReference> {
    var changes: Set<KnowledgePackArtifactReference> = []
    if previous.manifest != current.manifest {
      changes.insert(.init(kind: .manifest, id: current.manifest.packID))
    }
    changes.formUnion(changed(previous.sources, current.sources, kind: .source))
    changes.formUnion(changed(previous.passages, current.passages, kind: .passage))
    changes.formUnion(changed(previous.assertions, current.assertions, kind: .assertion))
    changes.formUnion(changed(previous.evidenceLinks, current.evidenceLinks, kind: .evidenceLink))
    changes.formUnion(changed(previous.calculations, current.calculations, kind: .calculation))
    changes.formUnion(changed(previous.responseCards, current.responseCards, kind: .responseCard))
    changes.formUnion(
      changed(previous.questionFamilies, current.questionFamilies, kind: .questionFamily)
    )
    return changes
  }

  private static func changed<Record: Equatable & Identifiable>(
    _ previous: [Record],
    _ current: [Record],
    kind: KnowledgePackSearchRecordKind
  ) -> Set<KnowledgePackArtifactReference> where Record.ID == String {
    let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
    let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    return Set(previousByID.keys).union(currentByID.keys).reduce(into: []) { result, id in
      if previousByID[id] != currentByID[id] {
        result.insert(KnowledgePackArtifactReference(kind: kind, id: id))
      }
    }
  }

  private static func dependencyGraph(
    for pack: KnowledgePack
  ) -> [KnowledgePackArtifactReference: Set<KnowledgePackArtifactReference>] {
    var graph: [KnowledgePackArtifactReference: Set<KnowledgePackArtifactReference>] = [:]
    func link(
      _ dependency: KnowledgePackArtifactReference,
      _ dependent: KnowledgePackArtifactReference
    ) {
      graph[dependency, default: []].insert(dependent)
    }

    let manifestReference = KnowledgePackArtifactReference(
      kind: .manifest,
      id: pack.manifest.packID
    )
    for source in pack.sources {
      link(manifestReference, .init(kind: .source, id: source.id))
    }
    for questionFamily in pack.questionFamilies {
      link(manifestReference, .init(kind: .questionFamily, id: questionFamily.id))
    }

    for passage in pack.passages {
      link(.init(kind: .source, id: passage.sourceID), .init(kind: .passage, id: passage.id))
    }
    for evidenceLink in pack.evidenceLinks {
      let evidenceReference = KnowledgePackArtifactReference(
        kind: .evidenceLink, id: evidenceLink.id)
      link(.init(kind: .passage, id: evidenceLink.passageID), evidenceReference)
      link(evidenceReference, .init(kind: .assertion, id: evidenceLink.assertionID))
    }
    for assertion in pack.assertions {
      for evidenceLinkID in assertion.evidenceLinkIDs {
        link(
          .init(kind: .evidenceLink, id: evidenceLinkID),
          .init(kind: .assertion, id: assertion.id)
        )
      }
    }
    for calculation in pack.calculations {
      let calculationReference = KnowledgePackArtifactReference(
        kind: .calculation,
        id: calculation.id
      )
      for assertionID in calculation.inputAssertionIDs + [calculation.outputAssertionID] {
        link(.init(kind: .assertion, id: assertionID), calculationReference)
      }
    }
    for card in pack.responseCards {
      let cardReference = KnowledgePackArtifactReference(kind: .responseCard, id: card.id)
      for assertionID in card.assertionIDs {
        link(.init(kind: .assertion, id: assertionID), cardReference)
      }
      for passageID in card.citationPassageIDs {
        link(.init(kind: .passage, id: passageID), cardReference)
      }
      for calculationID in card.calculationIDs {
        link(.init(kind: .calculation, id: calculationID), cardReference)
      }
      for questionFamilyID in card.questionFamilyIDs {
        link(.init(kind: .questionFamily, id: questionFamilyID), cardReference)
      }
    }
    return graph
  }
}

private struct SearchDocument: Sendable {
  let kind: KnowledgePackSearchRecordKind
  let recordID: String
  let title: String
  let body: String
  let aliases: [String]
  let qualifiers: [String: String]
  let sourceIDs: Set<String>

  var id: String { "\(kind.rawValue):\(recordID)" }
  var excerpt: String { body }
  var exactAliases: [String] { [recordID, title] + aliases }
  var searchableText: String { ([title, body] + aliases).joined(separator: "\n") }

  static func makeDocuments(from pack: KnowledgePack) -> [SearchDocument] {
    let sourcesByID = Dictionary(uniqueKeysWithValues: pack.sources.map { ($0.id, $0) })
    let passagesByID = Dictionary(uniqueKeysWithValues: pack.passages.map { ($0.id, $0) })
    let evidenceLinksByID = Dictionary(uniqueKeysWithValues: pack.evidenceLinks.map { ($0.id, $0) })
    let assertionsByID = Dictionary(uniqueKeysWithValues: pack.assertions.map { ($0.id, $0) })
    let questionFamiliesByID = Dictionary(
      uniqueKeysWithValues: pack.questionFamilies.map { ($0.id, $0) }
    )

    func sourceIDs(for assertion: KnowledgeAssertion) -> Set<String> {
      Set(
        assertion.evidenceLinkIDs.compactMap { evidenceLinkID in
          guard let passageID = evidenceLinksByID[evidenceLinkID]?.passageID else { return nil }
          return passagesByID[passageID]?.sourceID
        })
    }

    func sourceIDs(for assertionIDs: [String]) -> Set<String> {
      assertionIDs.reduce(into: []) { result, assertionID in
        guard let assertion = assertionsByID[assertionID] else { return }
        result.formUnion(sourceIDs(for: assertion))
      }
    }

    func mergedQualifiers(for assertionIDs: [String]) -> [String: String] {
      var merged: [String: String] = [:]
      var conflicts: Set<String> = []
      for assertionID in assertionIDs {
        guard let assertion = assertionsByID[assertionID] else { continue }
        for (key, value) in assertion.qualifiers {
          if let existing = merged[key], existing != value {
            conflicts.insert(key)
          } else {
            merged[key] = value
          }
        }
      }
      for key in conflicts { merged.removeValue(forKey: key) }
      return merged
    }

    var documents: [SearchDocument] = []
    documents += pack.sources.map { source in
      SearchDocument(
        kind: .source,
        recordID: source.id,
        title: source.title,
        body: "\(source.kind.rawValue) \(source.relativePath)",
        aliases: [
          source.relativePath,
          source.relativePath.split(separator: "/").last.map(String.init) ?? "",
        ],
        qualifiers: [:],
        sourceIDs: [source.id]
      )
    }
    documents += pack.passages.map { passage in
      let source = sourcesByID[passage.sourceID]
      var qualifiers: [String: String] = [:]
      if let period = passage.spreadsheet?.period { qualifiers["period"] = period }
      if let unit = passage.spreadsheet?.unit { qualifiers["unit"] = unit }
      return SearchDocument(
        kind: .passage,
        recordID: passage.id,
        title: source?.title ?? passage.id,
        body: passage.text,
        aliases: passage.locator.sectionPath + [source?.relativePath ?? ""],
        qualifiers: qualifiers,
        sourceIDs: [passage.sourceID]
      )
    }
    documents += pack.assertions.map { assertion in
      let predicateAlias = assertion.predicate.split(separator: ".").last.map(String.init) ?? ""
      return SearchDocument(
        kind: .assertion,
        recordID: assertion.id,
        title: assertion.predicate,
        body: [
          assertion.subject,
          displayValue(assertion.value),
          assertion.qualifiers.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
            .joined(separator: " "),
          assertion.kind.rawValue,
        ].joined(separator: " "),
        aliases: [assertion.subject, predicateAlias],
        qualifiers: assertion.qualifiers,
        sourceIDs: sourceIDs(for: assertion)
      )
    }
    documents += pack.evidenceLinks.map { evidenceLink in
      let passage = passagesByID[evidenceLink.passageID]
      return SearchDocument(
        kind: .evidenceLink,
        recordID: evidenceLink.id,
        title: evidenceLink.relation.rawValue,
        body: [evidenceLink.assertionID, evidenceLink.passageID, evidenceLink.note ?? ""]
          .joined(separator: " "),
        aliases: [evidenceLink.assertionID, evidenceLink.passageID],
        qualifiers: assertionsByID[evidenceLink.assertionID]?.qualifiers ?? [:],
        sourceIDs: passage.map { [$0.sourceID] } ?? []
      )
    }
    documents += pack.calculations.map { calculation in
      let assertionIDs = calculation.inputAssertionIDs + [calculation.outputAssertionID]
      return SearchDocument(
        kind: .calculation,
        recordID: calculation.id,
        title: calculation.name,
        body: "\(calculation.expression) version \(calculation.version)",
        aliases: [calculation.outputAssertionID],
        qualifiers: mergedQualifiers(for: assertionIDs),
        sourceIDs: sourceIDs(for: assertionIDs)
      )
    }
    documents += pack.responseCards.filter { $0.reviewStatus == .reviewed }.map { card in
      let questionAliases = card.questionFamilyIDs.compactMap { questionFamiliesByID[$0] }
        .flatMap {
          [$0.canonicalQuestion] + $0.variants + $0.aliases + $0.partialPrefixes + $0.tags
        }
      return SearchDocument(
        kind: .responseCard,
        recordID: card.id,
        title: card.title,
        body: "\(card.answer) \(card.evidenceState.rawValue)",
        aliases: card.questionFamilyIDs + questionAliases,
        qualifiers: mergedQualifiers(for: card.assertionIDs),
        sourceIDs: Set(card.citationPassageIDs.compactMap { passagesByID[$0]?.sourceID })
          .union(sourceIDs(for: card.assertionIDs))
      )
    }
    documents += pack.questionFamilies.map { question in
      let relatedCards = pack.responseCards.filter {
        $0.reviewStatus == .reviewed && $0.questionFamilyIDs.contains(question.id)
      }
      return SearchDocument(
        kind: .questionFamily,
        recordID: question.id,
        title: question.canonicalQuestion,
        body: (question.variants + question.partialPrefixes + question.tags).joined(separator: " "),
        aliases: question.aliases + question.variants + question.partialPrefixes + question.tags,
        qualifiers: mergedQualifiers(for: relatedCards.flatMap(\.assertionIDs)),
        sourceIDs: relatedCards.reduce(into: []) { result, card in
          result.formUnion(sourceIDs(for: card.assertionIDs))
          result.formUnion(card.citationPassageIDs.compactMap { passagesByID[$0]?.sourceID })
        }
      )
    }
    return documents.sorted { $0.id < $1.id }
  }

  private static func displayValue(_ value: KnowledgeValue) -> String {
    switch value.type {
    case .text: return value.text ?? ""
    case .number:
      guard let number = value.number, let scale = value.scale else { return "" }
      return "\(number * scale) \(value.unit ?? "")"
    case .boolean: return value.boolean.map(String.init) ?? ""
    case .date: return value.date ?? ""
    case .reference: return value.referenceID ?? ""
    }
  }
}

private final class KnowledgePackSQLiteFullTextIndex: @unchecked Sendable {
  private let lock = NSLock()
  private var database: OpaquePointer?

  init(documents: [SearchDocument]) throws {
    guard sqlite3_open(":memory:", &database) == SQLITE_OK, database != nil else {
      throw KnowledgePackSearchError.sqlite("Could not open the in-memory SQLite database.")
    }
    do {
      try execute(
        """
        CREATE VIRTUAL TABLE documents USING fts5(
          document_id UNINDEXED,
          kind UNINDEXED,
          title,
          body,
          aliases,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        """
      )
      try insert(documents)
    } catch {
      sqlite3_close(database)
      database = nil
      throw error
    }
  }

  deinit {
    sqlite3_close(database)
  }

  func search(_ text: String, limit: Int) throws -> [String: Double] {
    lock.lock()
    defer { lock.unlock() }
    let expression = Self.matchExpression(text)
    guard !expression.isEmpty else { return [:] }
    let sql =
      "SELECT document_id, bm25(documents, 0.0, 0.0, 5.0, 1.0, 2.0) "
      + "FROM documents WHERE documents MATCH ? ORDER BY 2 LIMIT ?;"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw sqliteError()
    }
    defer { sqlite3_finalize(statement) }
    bind(expression, at: 1, to: statement)
    sqlite3_bind_int(statement, 2, Int32(limit))
    var ordered: [(String, Double)] = []
    var stepResult = sqlite3_step(statement)
    while stepResult == SQLITE_ROW {
      if let idText = sqlite3_column_text(statement, 0) {
        ordered.append((String(cString: idText), sqlite3_column_double(statement, 1)))
      }
      stepResult = sqlite3_step(statement)
    }
    guard stepResult == SQLITE_DONE else { throw sqliteError() }
    let count = max(ordered.count, 1)
    return Dictionary(
      uniqueKeysWithValues: ordered.enumerated().map { index, item in
        (item.0, 1 - (Double(index) / Double(count + 1)))
      }
    )
  }

  private func insert(_ documents: [SearchDocument]) throws {
    let sql =
      "INSERT INTO documents(document_id, kind, title, body, aliases) VALUES (?, ?, ?, ?, ?);"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw sqliteError()
    }
    defer { sqlite3_finalize(statement) }
    for document in documents {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      bind(document.id, at: 1, to: statement)
      bind(document.kind.rawValue, at: 2, to: statement)
      bind(document.title, at: 3, to: statement)
      bind(document.body, at: 4, to: statement)
      bind(document.aliases.joined(separator: " "), at: 5, to: statement)
      guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw sqliteError() }
  }

  private func bind(_ value: String, at index: Int32, to statement: OpaquePointer?) {
    sqlite3_bind_text(
      statement,
      index,
      value,
      -1,
      unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    )
  }

  private func sqliteError() -> KnowledgePackSearchError {
    guard let database, let message = sqlite3_errmsg(database) else {
      return .sqlite("Unknown SQLite error.")
    }
    return .sqlite(String(cString: message))
  }

  private static func matchExpression(_ value: String) -> String {
    let terms = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
    return terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
      .joined(separator: " OR ")
  }
}
