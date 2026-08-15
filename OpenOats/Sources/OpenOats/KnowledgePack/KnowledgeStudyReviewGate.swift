import CryptoKit
import Foundation

public enum KnowledgeStudyProposalKind: String, Codable, Equatable, Sendable {
  case questionFamily = "question_family"
  case responseCard = "response_card"
}

public enum KnowledgeStudyReviewDisposition: String, Codable, Equatable, Sendable {
  case approve
  case reject
}

public struct KnowledgeStudyReviewDecision: Codable, Equatable, Sendable {
  public let proposalKind: KnowledgeStudyProposalKind
  public let proposalID: String
  public let disposition: KnowledgeStudyReviewDisposition
  public let note: String?

  public init(
    proposalKind: KnowledgeStudyProposalKind,
    proposalID: String,
    disposition: KnowledgeStudyReviewDisposition,
    note: String? = nil
  ) {
    self.proposalKind = proposalKind
    self.proposalID = proposalID
    self.disposition = disposition
    self.note = note
  }
}

public struct KnowledgeStudyReviewDecisionSet: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let queueID: String
  public let analysisID: String
  public let bundleID: String
  public let reviewer: String
  public let reviewedAt: Date
  public let decisions: [KnowledgeStudyReviewDecision]

  public init(
    schemaVersion: Int,
    queueID: String,
    analysisID: String,
    bundleID: String,
    reviewer: String,
    reviewedAt: Date,
    decisions: [KnowledgeStudyReviewDecision]
  ) {
    self.schemaVersion = schemaVersion
    self.queueID = queueID
    self.analysisID = analysisID
    self.bundleID = bundleID
    self.reviewer = reviewer
    self.reviewedAt = reviewedAt
    self.decisions = decisions
  }
}

public struct KnowledgeStudyApprovedImport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let importID: String
  public let packID: String
  public let basePackContentHash: String
  public let resultingPackContentHash: String
  public let sourceBundleID: String
  public let sourceAnalysisID: String
  public let sourceQueueID: String
  public let reviewer: String
  public let reviewedAt: Date
  public let approvedQuestionFamilies: [KnowledgeQuestionFamily]
  public let approvedResponseCards: [KnowledgeResponseCard]
  public let reviewDecisions: [KnowledgeStudyReviewDecision]
  public let rejectedDecisions: [KnowledgeStudyReviewDecision]

  public init(
    schemaVersion: Int,
    importID: String,
    packID: String,
    basePackContentHash: String,
    resultingPackContentHash: String,
    sourceBundleID: String,
    sourceAnalysisID: String,
    sourceQueueID: String,
    reviewer: String,
    reviewedAt: Date,
    approvedQuestionFamilies: [KnowledgeQuestionFamily],
    approvedResponseCards: [KnowledgeResponseCard],
    reviewDecisions: [KnowledgeStudyReviewDecision],
    rejectedDecisions: [KnowledgeStudyReviewDecision]
  ) {
    self.schemaVersion = schemaVersion
    self.importID = importID
    self.packID = packID
    self.basePackContentHash = basePackContentHash
    self.resultingPackContentHash = resultingPackContentHash
    self.sourceBundleID = sourceBundleID
    self.sourceAnalysisID = sourceAnalysisID
    self.sourceQueueID = sourceQueueID
    self.reviewer = reviewer
    self.reviewedAt = reviewedAt
    self.approvedQuestionFamilies = approvedQuestionFamilies
    self.approvedResponseCards = approvedResponseCards
    self.reviewDecisions = reviewDecisions
    self.rejectedDecisions = rejectedDecisions
  }
}

public enum KnowledgeStudyReviewGateError: Error, CustomStringConvertible {
  case unsupportedSchema(actual: Int, expected: Int)
  case queueDoesNotMatchCurrentBundle
  case queueTampered
  case identityMismatch(field: String, expected: String, actual: String)
  case invalidReviewer
  case invalidDecisionNote(proposalID: String)
  case tooManyDecisions(limit: Int)
  case duplicateDecision(kind: KnowledgeStudyProposalKind, id: String)
  case unknownDecision(kind: KnowledgeStudyProposalKind, id: String)
  case missingDecision(kind: KnowledgeStudyProposalKind, id: String)
  case mergedPackInvalid(KnowledgePackValidationReport)

  public var description: String {
    switch self {
    case .unsupportedSchema(let actual, let expected):
      return "Study review schema \(actual) is unsupported; expected \(expected)."
    case .queueDoesNotMatchCurrentBundle:
      return "Study review queue does not match the active KnowledgePack content."
    case .queueTampered:
      return "Study review queue content does not match its validated analysis and current bundle."
    case .identityMismatch(let field, let expected, let actual):
      return "Study review \(field) '\(actual)' does not match expected '\(expected)'."
    case .invalidReviewer:
      return
        "Study review requires a normalized, non-empty reviewer name of at most 200 characters."
    case .invalidDecisionNote(let proposalID):
      return
        "Study review decision note for '\(proposalID)' must be normalized text of at most 1,000 characters."
    case .tooManyDecisions(let limit):
      return "Study review contains more than \(limit) decisions."
    case .duplicateDecision(let kind, let id):
      return "Study review contains more than one decision for \(kind.rawValue) '\(id)'."
    case .unknownDecision(let kind, let id):
      return "Study review contains a decision for unknown \(kind.rawValue) '\(id)'."
    case .missingDecision(let kind, let id):
      return "Study review is missing an explicit decision for \(kind.rawValue) '\(id)'."
    case .mergedPackInvalid(let report):
      return report.errors.map(\.description).joined(separator: "\n")
    }
  }
}

public struct KnowledgeStudyReviewGate: Sendable {
  public static let schemaVersion = 1

  private let profileRegistry: KnowledgeDomainProfileRegistry

  public init(profileRegistry: KnowledgeDomainProfileRegistry = .empty) {
    self.profileRegistry = profileRegistry
  }

  public func approve(
    queue: KnowledgeStudyReviewQueue,
    decisions: KnowledgeStudyReviewDecisionSet,
    pack: KnowledgePack
  ) throws -> KnowledgeStudyApprovedImport {
    guard decisions.schemaVersion == Self.schemaVersion else {
      throw KnowledgeStudyReviewGateError.unsupportedSchema(
        actual: decisions.schemaVersion,
        expected: Self.schemaVersion
      )
    }
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    guard queue.analysis.bundleID == bundle.bundleID,
      queue.analysis.packID == bundle.packID,
      queue.analysis.packContentHash == bundle.packContentHash
    else {
      throw KnowledgeStudyReviewGateError.queueDoesNotMatchCurrentBundle
    }
    let expectedQueue = try KnowledgeStudyAnalysisValidator().makeReviewQueue(
      analysis: queue.analysis,
      bundle: bundle
    )
    guard expectedQueue == queue else {
      throw KnowledgeStudyReviewGateError.queueTampered
    }

    try requireIdentity("queueID", actual: decisions.queueID, expected: queue.queueID)
    try requireIdentity(
      "analysisID",
      actual: decisions.analysisID,
      expected: queue.analysis.analysisID
    )
    try requireIdentity("bundleID", actual: decisions.bundleID, expected: queue.analysis.bundleID)
    try validateReviewer(decisions.reviewer)
    guard decisions.decisions.count <= KnowledgeStudyAnalysisValidator.maximumProposalCount * 2
    else {
      throw KnowledgeStudyReviewGateError.tooManyDecisions(
        limit: KnowledgeStudyAnalysisValidator.maximumProposalCount * 2
      )
    }

    let questionProposals = Dictionary(
      uniqueKeysWithValues: queue.analysis.questionFamilyProposals.map { ($0.id, $0) }
    )
    let cardProposals = Dictionary(
      uniqueKeysWithValues: queue.analysis.responseCardProposals.map { ($0.id, $0) }
    )
    var decisionsByKey: [DecisionKey: KnowledgeStudyReviewDecision] = [:]
    for decision in decisions.decisions {
      try validateNote(decision.note, proposalID: decision.proposalID)
      let key = DecisionKey(kind: decision.proposalKind, id: decision.proposalID)
      guard decisionsByKey[key] == nil else {
        throw KnowledgeStudyReviewGateError.duplicateDecision(
          kind: decision.proposalKind,
          id: decision.proposalID
        )
      }
      switch decision.proposalKind {
      case .questionFamily:
        guard questionProposals[decision.proposalID] != nil else {
          throw KnowledgeStudyReviewGateError.unknownDecision(
            kind: decision.proposalKind,
            id: decision.proposalID
          )
        }
      case .responseCard:
        guard cardProposals[decision.proposalID] != nil else {
          throw KnowledgeStudyReviewGateError.unknownDecision(
            kind: decision.proposalKind,
            id: decision.proposalID
          )
        }
      }
      decisionsByKey[key] = decision
    }

    for id in questionProposals.keys.sorted() {
      let key = DecisionKey(kind: .questionFamily, id: id)
      guard decisionsByKey[key] != nil else {
        throw KnowledgeStudyReviewGateError.missingDecision(kind: .questionFamily, id: id)
      }
    }
    for id in cardProposals.keys.sorted() {
      let key = DecisionKey(kind: .responseCard, id: id)
      guard decisionsByKey[key] != nil else {
        throw KnowledgeStudyReviewGateError.missingDecision(kind: .responseCard, id: id)
      }
    }

    let approvedQuestions: [KnowledgeQuestionFamily] = questionProposals.values.compactMap {
      proposal -> KnowledgeQuestionFamily? in
      guard
        decisionsByKey[DecisionKey(kind: .questionFamily, id: proposal.id)]?.disposition
          == .approve
      else { return nil }
      return KnowledgeQuestionFamily(
        id: proposal.id,
        canonicalQuestion: proposal.canonicalQuestion,
        variants: proposal.variants,
        partialPrefixes: proposal.partialPrefixes,
        aliases: proposal.aliases,
        tags: proposal.tags
      )
    }.sorted { $0.id < $1.id }

    let approvedCards: [KnowledgeResponseCard] = cardProposals.values.compactMap {
      proposal -> KnowledgeResponseCard? in
      guard
        decisionsByKey[DecisionKey(kind: .responseCard, id: proposal.id)]?.disposition == .approve
      else { return nil }
      return KnowledgeResponseCard(
        id: proposal.id,
        title: proposal.title,
        answer: proposal.answer,
        evidenceState: proposal.evidenceState,
        questionFamilyIDs: proposal.questionFamilyIDs,
        assertionIDs: proposal.assertionIDs,
        citationPassageIDs: proposal.citationPassageIDs,
        calculationIDs: proposal.calculationIDs,
        reviewStatus: .reviewed
      )
    }.sorted { $0.id < $1.id }

    let mergedPack = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards + approvedCards,
      questionFamilies: pack.questionFamilies + approvedQuestions
    )
    let report = KnowledgePackLoader(profileRegistry: profileRegistry).validate(mergedPack)
    guard report.isValid else {
      throw KnowledgeStudyReviewGateError.mergedPackInvalid(report)
    }

    let resultingBundle = try KnowledgeStudyBundleBuilder().build(from: mergedPack)
    let sortedDecisions = decisions.decisions.sorted {
      ($0.proposalKind.rawValue, $0.proposalID) < ($1.proposalKind.rawValue, $1.proposalID)
    }
    let rejected = sortedDecisions.filter { $0.disposition == .reject }
    let importID = try Self.importID(
      queueID: queue.queueID,
      reviewer: decisions.reviewer,
      reviewedAt: decisions.reviewedAt,
      decisions: decisions.decisions
    )
    return KnowledgeStudyApprovedImport(
      schemaVersion: Self.schemaVersion,
      importID: importID,
      packID: pack.manifest.packID,
      basePackContentHash: bundle.packContentHash,
      resultingPackContentHash: resultingBundle.packContentHash,
      sourceBundleID: bundle.bundleID,
      sourceAnalysisID: queue.analysis.analysisID,
      sourceQueueID: queue.queueID,
      reviewer: decisions.reviewer,
      reviewedAt: decisions.reviewedAt,
      approvedQuestionFamilies: approvedQuestions,
      approvedResponseCards: approvedCards,
      reviewDecisions: sortedDecisions,
      rejectedDecisions: rejected
    )
  }

  private func requireIdentity(_ field: String, actual: String, expected: String) throws {
    guard actual == expected else {
      throw KnowledgeStudyReviewGateError.identityMismatch(
        field: field,
        expected: expected,
        actual: actual
      )
    }
  }

  private func validateReviewer(_ reviewer: String) throws {
    let trimmed = reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed == reviewer, reviewer.count <= 200 else {
      throw KnowledgeStudyReviewGateError.invalidReviewer
    }
  }

  private func validateNote(_ note: String?, proposalID: String) throws {
    guard let note else { return }
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed == note, note.count <= 1_000 else {
      throw KnowledgeStudyReviewGateError.invalidDecisionNote(proposalID: proposalID)
    }
  }

  private static func importID(
    queueID: String,
    reviewer: String,
    reviewedAt: Date,
    decisions: [KnowledgeStudyReviewDecision]
  ) throws -> String {
    let content = CanonicalReviewDecisionContent(
      queueID: queueID,
      reviewer: reviewer,
      reviewedAt: reviewedAt,
      decisions: decisions.sorted {
        ($0.proposalKind.rawValue, $0.proposalID) < ($1.proposalKind.rawValue, $1.proposalID)
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(content)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return "import-\(digest.prefix(24))"
  }
}

private struct DecisionKey: Hashable {
  let kind: KnowledgeStudyProposalKind
  let id: String
}

private struct CanonicalReviewDecisionContent: Encodable {
  let queueID: String
  let reviewer: String
  let reviewedAt: Date
  let decisions: [KnowledgeStudyReviewDecision]
}
