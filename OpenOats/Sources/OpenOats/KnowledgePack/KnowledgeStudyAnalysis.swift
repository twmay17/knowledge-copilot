import CryptoKit
import Foundation

public struct KnowledgeStudyQuestionFamilyProposal: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let canonicalQuestion: String
  public let variants: [String]
  public let partialPrefixes: [String]
  public let aliases: [String]
  public let tags: [String]

  public init(
    id: String,
    canonicalQuestion: String,
    variants: [String],
    partialPrefixes: [String],
    aliases: [String],
    tags: [String]
  ) {
    self.id = id
    self.canonicalQuestion = canonicalQuestion
    self.variants = variants
    self.partialPrefixes = partialPrefixes
    self.aliases = aliases
    self.tags = tags
  }
}

public struct KnowledgeStudyResponseCardProposal: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let answer: String
  public let evidenceState: KnowledgeEvidenceState
  public let questionFamilyIDs: [String]
  public let assertionIDs: [String]
  public let citationPassageIDs: [String]
  public let calculationIDs: [String]
  public let caveat: String?

  public init(
    id: String,
    title: String,
    answer: String,
    evidenceState: KnowledgeEvidenceState,
    questionFamilyIDs: [String],
    assertionIDs: [String],
    citationPassageIDs: [String],
    calculationIDs: [String],
    caveat: String? = nil
  ) {
    self.id = id
    self.title = title
    self.answer = answer
    self.evidenceState = evidenceState
    self.questionFamilyIDs = questionFamilyIDs
    self.assertionIDs = assertionIDs
    self.citationPassageIDs = citationPassageIDs
    self.calculationIDs = calculationIDs
    self.caveat = caveat
  }
}

public struct KnowledgeStudyContradictionProposal: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let summary: String
  public let assertionIDs: [String]
  public let citationPassageIDs: [String]

  public init(
    id: String,
    summary: String,
    assertionIDs: [String],
    citationPassageIDs: [String]
  ) {
    self.id = id
    self.summary = summary
    self.assertionIDs = assertionIDs
    self.citationPassageIDs = citationPassageIDs
  }
}

public struct KnowledgeStudyCorpusGapProposal: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let question: String
  public let detail: String

  public init(id: String, question: String, detail: String) {
    self.id = id
    self.question = question
    self.detail = detail
  }
}

public struct KnowledgeStudyAnalysis: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let analysisID: String
  public let bundleID: String
  public let packID: String
  public let packContentHash: String
  public let generator: String
  public let questionFamilyProposals: [KnowledgeStudyQuestionFamilyProposal]
  public let responseCardProposals: [KnowledgeStudyResponseCardProposal]
  public let contradictions: [KnowledgeStudyContradictionProposal]
  public let corpusGaps: [KnowledgeStudyCorpusGapProposal]

  public init(
    schemaVersion: Int,
    analysisID: String,
    bundleID: String,
    packID: String,
    packContentHash: String,
    generator: String,
    questionFamilyProposals: [KnowledgeStudyQuestionFamilyProposal],
    responseCardProposals: [KnowledgeStudyResponseCardProposal],
    contradictions: [KnowledgeStudyContradictionProposal],
    corpusGaps: [KnowledgeStudyCorpusGapProposal]
  ) {
    self.schemaVersion = schemaVersion
    self.analysisID = analysisID
    self.bundleID = bundleID
    self.packID = packID
    self.packContentHash = packContentHash
    self.generator = generator
    self.questionFamilyProposals = questionFamilyProposals
    self.responseCardProposals = responseCardProposals
    self.contradictions = contradictions
    self.corpusGaps = corpusGaps
  }
}

public enum KnowledgeStudyReviewState: String, Codable, Equatable, Sendable {
  case pendingHumanReview = "pending_human_review"
}

public struct KnowledgeStudyResponseCardReviewItem: Codable, Equatable, Sendable, Identifiable {
  public var id: String { proposal.id }

  public let proposal: KnowledgeStudyResponseCardProposal
  public let referencedAssertions: [KnowledgeStudyAssertion]
  public let citedPassages: [KnowledgeStudyPassage]
  public let referencedCalculations: [KnowledgeCalculation]
  public let reviewStatus: KnowledgeReviewStatus

  public init(
    proposal: KnowledgeStudyResponseCardProposal,
    referencedAssertions: [KnowledgeStudyAssertion],
    citedPassages: [KnowledgeStudyPassage],
    referencedCalculations: [KnowledgeCalculation],
    reviewStatus: KnowledgeReviewStatus
  ) {
    self.proposal = proposal
    self.referencedAssertions = referencedAssertions
    self.citedPassages = citedPassages
    self.referencedCalculations = referencedCalculations
    self.reviewStatus = reviewStatus
  }
}

public struct KnowledgeStudyReviewQueue: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let queueID: String
  public let state: KnowledgeStudyReviewState
  public let analysis: KnowledgeStudyAnalysis
  public let responseCardItems: [KnowledgeStudyResponseCardReviewItem]

  public init(
    schemaVersion: Int,
    queueID: String,
    state: KnowledgeStudyReviewState,
    analysis: KnowledgeStudyAnalysis,
    responseCardItems: [KnowledgeStudyResponseCardReviewItem]
  ) {
    self.schemaVersion = schemaVersion
    self.queueID = queueID
    self.state = state
    self.analysis = analysis
    self.responseCardItems = responseCardItems
  }
}

public enum KnowledgeStudyAnalysisError: Error, CustomStringConvertible {
  case unsupportedSchema(actual: Int, expected: Int)
  case identityMismatch(field: String, expected: String, actual: String)
  case invalidField(recordID: String, field: String, reason: String)
  case tooManyRecords(type: String, limit: Int)
  case duplicateID(type: String, id: String)
  case existingIDCollision(type: String, id: String)
  case unknownReference(recordID: String, type: String, id: String)
  case incompatibleEvidence(recordID: String, reason: String)
  case citationOutsideEvidence(recordID: String, passageID: String)

  public var description: String {
    switch self {
    case .unsupportedSchema(let actual, let expected):
      return "Study analysis schema \(actual) is unsupported; expected \(expected)."
    case .identityMismatch(let field, let expected, let actual):
      return "Study analysis \(field) '\(actual)' does not match expected '\(expected)'."
    case .invalidField(let recordID, let field, let reason):
      return "Study analysis record '\(recordID)' has invalid \(field): \(reason)"
    case .tooManyRecords(let type, let limit):
      return "Study analysis contains more than \(limit) \(type) records."
    case .duplicateID(let type, let id):
      return "Study analysis contains duplicate \(type) ID '\(id)'."
    case .existingIDCollision(let type, let id):
      return "Study analysis \(type) ID '\(id)' already exists in the active pack."
    case .unknownReference(let recordID, let type, let id):
      return "Study analysis record '\(recordID)' references unknown \(type) '\(id)'."
    case .incompatibleEvidence(let recordID, let reason):
      return "Study response proposal '\(recordID)' has incompatible evidence: \(reason)"
    case .citationOutsideEvidence(let recordID, let passageID):
      return
        "Study record '\(recordID)' cites passage '\(passageID)' outside its assertion and calculation evidence closure."
    }
  }
}

public struct KnowledgeStudyAnalysisValidator: Sendable {
  public static let schemaVersion = 1
  public static let maximumProposalCount = 200

  public init() {}

  public func makeReviewQueue(
    analysis: KnowledgeStudyAnalysis,
    bundle: KnowledgeStudyBundle
  ) throws -> KnowledgeStudyReviewQueue {
    guard analysis.schemaVersion == Self.schemaVersion else {
      throw KnowledgeStudyAnalysisError.unsupportedSchema(
        actual: analysis.schemaVersion,
        expected: Self.schemaVersion
      )
    }
    try requireIdentity("bundleID", actual: analysis.bundleID, expected: bundle.bundleID)
    try requireIdentity("packID", actual: analysis.packID, expected: bundle.packID)
    try requireIdentity(
      "packContentHash",
      actual: analysis.packContentHash,
      expected: bundle.packContentHash
    )
    try validateID(analysis.analysisID, recordID: "analysis", field: "analysisID")
    try validateText(
      analysis.generator, recordID: analysis.analysisID, field: "generator", max: 200)

    try enforceCount(analysis.questionFamilyProposals.count, type: "question family proposal")
    try enforceCount(analysis.responseCardProposals.count, type: "response card proposal")
    try enforceCount(analysis.contradictions.count, type: "contradiction")
    try enforceCount(analysis.corpusGaps.count, type: "corpus gap")

    try validateUniqueIDs(analysis.questionFamilyProposals.map(\.id), type: "question family")
    try validateUniqueIDs(analysis.responseCardProposals.map(\.id), type: "response card")
    try validateUniqueIDs(analysis.contradictions.map(\.id), type: "contradiction")
    try validateUniqueIDs(analysis.corpusGaps.map(\.id), type: "corpus gap")

    let existingQuestionIDs = Set(bundle.existingQuestionFamilies.map(\.id))
    let existingCardIDs = Set(bundle.reviewedResponseCards.map(\.id))
    let proposedQuestionIDs = Set(analysis.questionFamilyProposals.map(\.id))
    let allowedQuestionIDs = existingQuestionIDs.union(proposedQuestionIDs)
    let assertionsByID = Dictionary(uniqueKeysWithValues: bundle.assertions.map { ($0.id, $0) })
    let passagesByID = Dictionary(uniqueKeysWithValues: bundle.citedPassages.map { ($0.id, $0) })
    let calculationsByID = Dictionary(uniqueKeysWithValues: bundle.calculations.map { ($0.id, $0) })

    for proposal in analysis.questionFamilyProposals {
      if existingQuestionIDs.contains(proposal.id) {
        throw KnowledgeStudyAnalysisError.existingIDCollision(
          type: "question family",
          id: proposal.id
        )
      }
      try validateQuestionFamily(proposal)
    }

    var reviewItems: [KnowledgeStudyResponseCardReviewItem] = []
    for proposal in analysis.responseCardProposals {
      if existingCardIDs.contains(proposal.id) {
        throw KnowledgeStudyAnalysisError.existingIDCollision(
          type: "response card",
          id: proposal.id
        )
      }
      try validateResponseCard(
        proposal,
        allowedQuestionIDs: allowedQuestionIDs,
        assertionsByID: assertionsByID,
        passagesByID: passagesByID,
        calculationsByID: calculationsByID
      )
      reviewItems.append(
        KnowledgeStudyResponseCardReviewItem(
          proposal: canonical(proposal),
          referencedAssertions: try proposal.assertionIDs.sorted().map {
            try requireReference($0, in: assertionsByID, recordID: proposal.id, type: "assertion")
          },
          citedPassages: try proposal.citationPassageIDs.sorted().map {
            try requireReference($0, in: passagesByID, recordID: proposal.id, type: "passage")
          },
          referencedCalculations: try proposal.calculationIDs.sorted().map {
            try requireReference(
              $0,
              in: calculationsByID,
              recordID: proposal.id,
              type: "calculation"
            )
          },
          reviewStatus: .generated
        ))
    }

    for contradiction in analysis.contradictions {
      try validateContradiction(
        contradiction,
        assertionsByID: assertionsByID,
        passagesByID: passagesByID,
        calculationsByID: calculationsByID
      )
    }
    for gap in analysis.corpusGaps {
      try validateID(gap.id, recordID: gap.id, field: "id")
      try validateText(gap.question, recordID: gap.id, field: "question", max: 500)
      try validateText(gap.detail, recordID: gap.id, field: "detail", max: 2_000)
    }

    let canonicalAnalysis = KnowledgeStudyAnalysis(
      schemaVersion: analysis.schemaVersion,
      analysisID: analysis.analysisID,
      bundleID: analysis.bundleID,
      packID: analysis.packID,
      packContentHash: analysis.packContentHash,
      generator: analysis.generator,
      questionFamilyProposals: analysis.questionFamilyProposals.map(canonical).sorted {
        $0.id < $1.id
      },
      responseCardProposals: analysis.responseCardProposals.map(canonical).sorted {
        $0.id < $1.id
      },
      contradictions: analysis.contradictions.map(canonical).sorted { $0.id < $1.id },
      corpusGaps: analysis.corpusGaps.sorted { $0.id < $1.id }
    )
    let queueID = try Self.queueID(for: canonicalAnalysis)
    return KnowledgeStudyReviewQueue(
      schemaVersion: Self.schemaVersion,
      queueID: queueID,
      state: .pendingHumanReview,
      analysis: canonicalAnalysis,
      responseCardItems: reviewItems.sorted { $0.id < $1.id }
    )
  }

  private func validateQuestionFamily(_ proposal: KnowledgeStudyQuestionFamilyProposal) throws {
    try validateID(proposal.id, recordID: proposal.id, field: "id")
    try validateText(
      proposal.canonicalQuestion,
      recordID: proposal.id,
      field: "canonicalQuestion",
      max: 500
    )
    try validateStringArray(
      proposal.variants,
      recordID: proposal.id,
      field: "variants",
      maxItemLength: 500
    )
    try validateStringArray(
      proposal.partialPrefixes,
      recordID: proposal.id,
      field: "partialPrefixes",
      maxItemLength: 300,
      mustNotBeEmpty: true
    )
    try validateStringArray(
      proposal.aliases,
      recordID: proposal.id,
      field: "aliases",
      maxItemLength: 200
    )
    try validateStringArray(
      proposal.tags,
      recordID: proposal.id,
      field: "tags",
      maxItemLength: 100
    )
  }

  private func validateResponseCard(
    _ proposal: KnowledgeStudyResponseCardProposal,
    allowedQuestionIDs: Set<String>,
    assertionsByID: [String: KnowledgeStudyAssertion],
    passagesByID: [String: KnowledgeStudyPassage],
    calculationsByID: [String: KnowledgeCalculation]
  ) throws {
    try validateID(proposal.id, recordID: proposal.id, field: "id")
    try validateText(proposal.title, recordID: proposal.id, field: "title", max: 300)
    try validateText(proposal.answer, recordID: proposal.id, field: "answer", max: 2_000)
    if let caveat = proposal.caveat {
      try validateText(caveat, recordID: proposal.id, field: "caveat", max: 1_000)
    }
    try validateReferenceArray(
      proposal.questionFamilyIDs,
      recordID: proposal.id,
      field: "questionFamilyIDs",
      mustNotBeEmpty: true
    )
    try validateReferenceArray(
      proposal.assertionIDs,
      recordID: proposal.id,
      field: "assertionIDs"
    )
    try validateReferenceArray(
      proposal.citationPassageIDs,
      recordID: proposal.id,
      field: "citationPassageIDs"
    )
    try validateReferenceArray(
      proposal.calculationIDs,
      recordID: proposal.id,
      field: "calculationIDs"
    )

    for id in proposal.questionFamilyIDs where !allowedQuestionIDs.contains(id) {
      throw KnowledgeStudyAnalysisError.unknownReference(
        recordID: proposal.id,
        type: "question family",
        id: id
      )
    }
    for id in proposal.assertionIDs {
      _ = try requireReference(id, in: assertionsByID, recordID: proposal.id, type: "assertion")
    }
    for id in proposal.citationPassageIDs {
      _ = try requireReference(id, in: passagesByID, recordID: proposal.id, type: "passage")
    }
    for id in proposal.calculationIDs {
      _ = try requireReference(
        id,
        in: calculationsByID,
        recordID: proposal.id,
        type: "calculation"
      )
    }

    let hasEvidence =
      !proposal.assertionIDs.isEmpty || !proposal.citationPassageIDs.isEmpty
      || !proposal.calculationIDs.isEmpty
    switch proposal.evidenceState {
    case .notFoundInCorpus, .needsClarification:
      guard !hasEvidence else {
        throw KnowledgeStudyAnalysisError.incompatibleEvidence(
          recordID: proposal.id,
          reason: "abstention proposals may not carry factual evidence references"
        )
      }
    case .calculated:
      guard !proposal.assertionIDs.isEmpty, !proposal.citationPassageIDs.isEmpty,
        !proposal.calculationIDs.isEmpty
      else {
        throw KnowledgeStudyAnalysisError.incompatibleEvidence(
          recordID: proposal.id,
          reason: "calculated proposals require assertions, citations, and a registered calculation"
        )
      }
    case .contested, .contradictedByCorpus:
      guard proposal.assertionIDs.count >= 2, proposal.citationPassageIDs.count >= 2 else {
        throw KnowledgeStudyAnalysisError.incompatibleEvidence(
          recordID: proposal.id,
          reason:
            "contested or contradicted proposals require at least two assertions and citations"
        )
      }
    default:
      guard !proposal.assertionIDs.isEmpty, !proposal.citationPassageIDs.isEmpty else {
        throw KnowledgeStudyAnalysisError.incompatibleEvidence(
          recordID: proposal.id,
          reason: "factual proposals require an assertion and citation"
        )
      }
    }

    var evidenceAssertionIDs = Set(proposal.assertionIDs)
    for calculationID in proposal.calculationIDs {
      let calculation = try requireReference(
        calculationID,
        in: calculationsByID,
        recordID: proposal.id,
        type: "calculation"
      )
      guard evidenceAssertionIDs.contains(calculation.outputAssertionID) else {
        throw KnowledgeStudyAnalysisError.incompatibleEvidence(
          recordID: proposal.id,
          reason:
            "calculation '\(calculation.id)' output assertion '\(calculation.outputAssertionID)' is not claimed"
        )
      }
      evidenceAssertionIDs.formUnion(calculation.inputAssertionIDs)
    }
    let evidencePassageIDs = Set(
      evidenceAssertionIDs.compactMap { assertionsByID[$0] }.flatMap { assertion in
        assertion.evidence.map(\.passageID)
      })
    for passageID in proposal.citationPassageIDs where !evidencePassageIDs.contains(passageID) {
      throw KnowledgeStudyAnalysisError.citationOutsideEvidence(
        recordID: proposal.id,
        passageID: passageID
      )
    }
  }

  private func validateContradiction(
    _ contradiction: KnowledgeStudyContradictionProposal,
    assertionsByID: [String: KnowledgeStudyAssertion],
    passagesByID: [String: KnowledgeStudyPassage],
    calculationsByID: [String: KnowledgeCalculation]
  ) throws {
    try validateID(contradiction.id, recordID: contradiction.id, field: "id")
    try validateText(
      contradiction.summary,
      recordID: contradiction.id,
      field: "summary",
      max: 2_000
    )
    guard contradiction.assertionIDs.count >= 2, contradiction.citationPassageIDs.count >= 2 else {
      throw KnowledgeStudyAnalysisError.invalidField(
        recordID: contradiction.id,
        field: "evidence",
        reason: "contradictions require at least two assertion IDs and citation passage IDs"
      )
    }
    let shadowCard = KnowledgeStudyResponseCardProposal(
      id: contradiction.id,
      title: "Contradiction",
      answer: contradiction.summary,
      evidenceState: .contested,
      questionFamilyIDs: ["internal-validation"],
      assertionIDs: contradiction.assertionIDs,
      citationPassageIDs: contradiction.citationPassageIDs,
      calculationIDs: []
    )
    try validateResponseCard(
      shadowCard,
      allowedQuestionIDs: ["internal-validation"],
      assertionsByID: assertionsByID,
      passagesByID: passagesByID,
      calculationsByID: calculationsByID
    )
  }

  private func requireIdentity(_ field: String, actual: String, expected: String) throws {
    guard actual == expected else {
      throw KnowledgeStudyAnalysisError.identityMismatch(
        field: field,
        expected: expected,
        actual: actual
      )
    }
  }

  private func enforceCount(_ count: Int, type: String) throws {
    guard count <= Self.maximumProposalCount else {
      throw KnowledgeStudyAnalysisError.tooManyRecords(
        type: type,
        limit: Self.maximumProposalCount
      )
    }
  }

  private func validateUniqueIDs(_ ids: [String], type: String) throws {
    let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }
    if let id = duplicates.keys.sorted().first {
      throw KnowledgeStudyAnalysisError.duplicateID(type: type, id: id)
    }
  }

  private func validateID(_ id: String, recordID: String, field: String) throws {
    guard id.count <= 128,
      id.range(of: "^[a-z][a-z0-9._-]*$", options: .regularExpression) != nil
    else {
      throw KnowledgeStudyAnalysisError.invalidField(
        recordID: recordID,
        field: field,
        reason: "must be 1-128 normalized lowercase letters, numbers, dots, underscores, or hyphens"
      )
    }
  }

  private func validateText(_ text: String, recordID: String, field: String, max: Int) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed == text, text.count <= max else {
      throw KnowledgeStudyAnalysisError.invalidField(
        recordID: recordID,
        field: field,
        reason: "must be normalized non-empty text no longer than \(max) characters"
      )
    }
  }

  private func validateStringArray(
    _ values: [String],
    recordID: String,
    field: String,
    maxItemLength: Int,
    mustNotBeEmpty: Bool = false
  ) throws {
    guard values.count <= 50, !mustNotBeEmpty || !values.isEmpty else {
      throw KnowledgeStudyAnalysisError.invalidField(
        recordID: recordID,
        field: field,
        reason: mustNotBeEmpty ? "must contain 1-50 items" : "may contain at most 50 items"
      )
    }
    guard Set(values).count == values.count else {
      throw KnowledgeStudyAnalysisError.invalidField(
        recordID: recordID,
        field: field,
        reason: "must not contain duplicates"
      )
    }
    for value in values {
      try validateText(value, recordID: recordID, field: field, max: maxItemLength)
    }
  }

  private func validateReferenceArray(
    _ values: [String],
    recordID: String,
    field: String,
    mustNotBeEmpty: Bool = false
  ) throws {
    try validateStringArray(
      values,
      recordID: recordID,
      field: field,
      maxItemLength: 128,
      mustNotBeEmpty: mustNotBeEmpty
    )
    for value in values {
      try validateID(value, recordID: recordID, field: field)
    }
  }

  private func requireReference<T>(
    _ id: String,
    in records: [String: T],
    recordID: String,
    type: String
  ) throws -> T {
    guard let record = records[id] else {
      throw KnowledgeStudyAnalysisError.unknownReference(
        recordID: recordID,
        type: type,
        id: id
      )
    }
    return record
  }

  private func canonical(_ proposal: KnowledgeStudyQuestionFamilyProposal)
    -> KnowledgeStudyQuestionFamilyProposal
  {
    KnowledgeStudyQuestionFamilyProposal(
      id: proposal.id,
      canonicalQuestion: proposal.canonicalQuestion,
      variants: proposal.variants.sorted(),
      partialPrefixes: proposal.partialPrefixes.sorted(),
      aliases: proposal.aliases.sorted(),
      tags: proposal.tags.sorted()
    )
  }

  private func canonical(_ proposal: KnowledgeStudyResponseCardProposal)
    -> KnowledgeStudyResponseCardProposal
  {
    KnowledgeStudyResponseCardProposal(
      id: proposal.id,
      title: proposal.title,
      answer: proposal.answer,
      evidenceState: proposal.evidenceState,
      questionFamilyIDs: proposal.questionFamilyIDs.sorted(),
      assertionIDs: proposal.assertionIDs.sorted(),
      citationPassageIDs: proposal.citationPassageIDs.sorted(),
      calculationIDs: proposal.calculationIDs.sorted(),
      caveat: proposal.caveat
    )
  }

  private func canonical(_ proposal: KnowledgeStudyContradictionProposal)
    -> KnowledgeStudyContradictionProposal
  {
    KnowledgeStudyContradictionProposal(
      id: proposal.id,
      summary: proposal.summary,
      assertionIDs: proposal.assertionIDs.sorted(),
      citationPassageIDs: proposal.citationPassageIDs.sorted()
    )
  }

  private static func queueID(for analysis: KnowledgeStudyAnalysis) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(analysis)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return "review-\(digest.prefix(24))"
  }
}
