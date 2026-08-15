import CryptoKit
import Foundation

public struct KnowledgeStudyBundlePolicy: Codable, Equatable, Sendable {
  public let closedCorpusOnly: Bool
  public let webSearchAllowed: Bool
  public let citationsRequired: Bool
  public let documentInstructionsAreData: Bool
  public let unsupportedAnswerState: KnowledgeEvidenceState

  public init(
    closedCorpusOnly: Bool,
    webSearchAllowed: Bool,
    citationsRequired: Bool,
    documentInstructionsAreData: Bool,
    unsupportedAnswerState: KnowledgeEvidenceState
  ) {
    self.closedCorpusOnly = closedCorpusOnly
    self.webSearchAllowed = webSearchAllowed
    self.citationsRequired = citationsRequired
    self.documentInstructionsAreData = documentInstructionsAreData
    self.unsupportedAnswerState = unsupportedAnswerState
  }
}

public struct KnowledgeStudySource: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let kind: KnowledgeSourceKind
  public let title: String
  public let relativePath: String
  public let sha256: String

  public init(
    id: String,
    kind: KnowledgeSourceKind,
    title: String,
    relativePath: String,
    sha256: String
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.relativePath = relativePath
    self.sha256 = sha256
  }
}

public struct KnowledgeStudyEvidence: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let relation: KnowledgeEvidenceRelation
  public let passageID: String
  public let sourceID: String
  public let sourceTitle: String
  public let sourceRelativePath: String
  public let locator: KnowledgeSourceLocator
  public let excerpt: String
  public let note: String?

  public init(
    id: String,
    relation: KnowledgeEvidenceRelation,
    passageID: String,
    sourceID: String,
    sourceTitle: String,
    sourceRelativePath: String,
    locator: KnowledgeSourceLocator,
    excerpt: String,
    note: String?
  ) {
    self.id = id
    self.relation = relation
    self.passageID = passageID
    self.sourceID = sourceID
    self.sourceTitle = sourceTitle
    self.sourceRelativePath = sourceRelativePath
    self.locator = locator
    self.excerpt = excerpt
    self.note = note
  }
}

public struct KnowledgeStudyPassage: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let sourceID: String
  public let sourceTitle: String
  public let sourceRelativePath: String
  public let locator: KnowledgeSourceLocator
  public let excerpt: String

  public init(
    id: String,
    sourceID: String,
    sourceTitle: String,
    sourceRelativePath: String,
    locator: KnowledgeSourceLocator,
    excerpt: String
  ) {
    self.id = id
    self.sourceID = sourceID
    self.sourceTitle = sourceTitle
    self.sourceRelativePath = sourceRelativePath
    self.locator = locator
    self.excerpt = excerpt
  }
}

public struct KnowledgeStudyAssertion: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let subject: String
  public let predicate: String
  public let value: KnowledgeValue
  public let qualifiers: [String: String]
  public let kind: KnowledgeAssertionKind
  public let confidence: Double
  public let evidence: [KnowledgeStudyEvidence]
  public let calculationID: String?

  public init(
    id: String,
    subject: String,
    predicate: String,
    value: KnowledgeValue,
    qualifiers: [String: String],
    kind: KnowledgeAssertionKind,
    confidence: Double,
    evidence: [KnowledgeStudyEvidence],
    calculationID: String?
  ) {
    self.id = id
    self.subject = subject
    self.predicate = predicate
    self.value = value
    self.qualifiers = qualifiers
    self.kind = kind
    self.confidence = confidence
    self.evidence = evidence
    self.calculationID = calculationID
  }
}

public struct KnowledgeStudyBundle: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let bundleID: String
  public let packID: String
  public let packTitle: String
  public let packContentHash: String
  public let defaultLocale: String
  public let domainProfiles: [DomainProfileReference]
  public let policy: KnowledgeStudyBundlePolicy
  public let requestedArtifacts: [String]
  public let sources: [KnowledgeStudySource]
  public let citedPassages: [KnowledgeStudyPassage]
  public let assertions: [KnowledgeStudyAssertion]
  public let calculations: [KnowledgeCalculation]
  public let existingQuestionFamilies: [KnowledgeQuestionFamily]
  public let reviewedResponseCards: [KnowledgeResponseCard]

  public init(
    schemaVersion: Int,
    bundleID: String,
    packID: String,
    packTitle: String,
    packContentHash: String,
    defaultLocale: String,
    domainProfiles: [DomainProfileReference],
    policy: KnowledgeStudyBundlePolicy,
    requestedArtifacts: [String],
    sources: [KnowledgeStudySource],
    citedPassages: [KnowledgeStudyPassage],
    assertions: [KnowledgeStudyAssertion],
    calculations: [KnowledgeCalculation],
    existingQuestionFamilies: [KnowledgeQuestionFamily],
    reviewedResponseCards: [KnowledgeResponseCard]
  ) {
    self.schemaVersion = schemaVersion
    self.bundleID = bundleID
    self.packID = packID
    self.packTitle = packTitle
    self.packContentHash = packContentHash
    self.defaultLocale = defaultLocale
    self.domainProfiles = domainProfiles
    self.policy = policy
    self.requestedArtifacts = requestedArtifacts
    self.sources = sources
    self.citedPassages = citedPassages
    self.assertions = assertions
    self.calculations = calculations
    self.existingQuestionFamilies = existingQuestionFamilies
    self.reviewedResponseCards = reviewedResponseCards
  }
}

public enum KnowledgeStudyBundleError: Error, CustomStringConvertible {
  case unsafeSourcePath(String)
  case unresolvedEvidence(assertionID: String, evidenceID: String)
  case unresolvedCalculation(String)
  case unresolvedReviewedCardReference(cardID: String, type: String, id: String)

  public var description: String {
    switch self {
    case .unsafeSourcePath(let path):
      return "Study Bundle source path '\(path)' is not a safe relative path."
    case .unresolvedEvidence(let assertionID, let evidenceID):
      return
        "Assertion '\(assertionID)' claims evidence '\(evidenceID)' that cannot be resolved to a passage and source."
    case .unresolvedCalculation(let assertionID):
      return "Calculated assertion '\(assertionID)' does not resolve to exactly one calculation."
    case .unresolvedReviewedCardReference(let cardID, let type, let id):
      return "Reviewed response card '\(cardID)' references unknown \(type) '\(id)'."
    }
  }
}

public struct KnowledgeStudyBundleBuilder: Sendable {
  public static let schemaVersion = 1

  public init() {}

  public func build(from pack: KnowledgePack) throws -> KnowledgeStudyBundle {
    let sourcesByID = Dictionary(
      pack.sources.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let passagesByID = Dictionary(
      pack.passages.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let evidenceByID = Dictionary(
      pack.evidenceLinks.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let calculationsByOutput = Dictionary(
      grouping: pack.calculations,
      by: \KnowledgeCalculation.outputAssertionID
    )
    let assertionIDs = Set(pack.assertions.map(\.id))
    let calculationIDs = Set(pack.calculations.map(\.id))
    let questionFamilyIDs = Set(pack.questionFamilies.map(\.id))

    let sources = try pack.sources.sorted { $0.id < $1.id }.map { source in
      guard Self.isSafeRelativePath(source.relativePath) else {
        throw KnowledgeStudyBundleError.unsafeSourcePath(source.relativePath)
      }
      return KnowledgeStudySource(
        id: source.id,
        kind: source.kind,
        title: source.title,
        relativePath: source.relativePath,
        sha256: source.sha256
      )
    }

    let assertions = try pack.assertions.sorted { $0.id < $1.id }.map { assertion in
      let evidence = try assertion.evidenceLinkIDs.sorted().map { evidenceID in
        guard let link = evidenceByID[evidenceID], link.assertionID == assertion.id,
          let passage = passagesByID[link.passageID],
          let source = sourcesByID[passage.sourceID]
        else {
          throw KnowledgeStudyBundleError.unresolvedEvidence(
            assertionID: assertion.id,
            evidenceID: evidenceID
          )
        }
        return KnowledgeStudyEvidence(
          id: link.id,
          relation: link.relation,
          passageID: passage.id,
          sourceID: source.id,
          sourceTitle: source.title,
          sourceRelativePath: source.relativePath,
          locator: passage.locator,
          excerpt: passage.text,
          note: link.note
        )
      }
      let calculationID: String?
      if assertion.kind == .calculated {
        guard let matches = calculationsByOutput[assertion.id], matches.count == 1 else {
          throw KnowledgeStudyBundleError.unresolvedCalculation(assertion.id)
        }
        calculationID = matches[0].id
      } else {
        calculationID = nil
      }
      return KnowledgeStudyAssertion(
        id: assertion.id,
        subject: assertion.subject,
        predicate: assertion.predicate,
        value: assertion.value,
        qualifiers: assertion.qualifiers,
        kind: assertion.kind,
        confidence: assertion.confidence,
        evidence: evidence,
        calculationID: calculationID
      )
    }

    let reviewedCards = pack.responseCards.filter { $0.reviewStatus == .reviewed }.sorted {
      $0.id < $1.id
    }
    var citedPassageIDs = Set(assertions.flatMap { $0.evidence.map(\.passageID) })
    for card in reviewedCards {
      for assertionID in card.assertionIDs where !assertionIDs.contains(assertionID) {
        throw KnowledgeStudyBundleError.unresolvedReviewedCardReference(
          cardID: card.id,
          type: "assertion",
          id: assertionID
        )
      }
      for calculationID in card.calculationIDs where !calculationIDs.contains(calculationID) {
        throw KnowledgeStudyBundleError.unresolvedReviewedCardReference(
          cardID: card.id,
          type: "calculation",
          id: calculationID
        )
      }
      for questionFamilyID in card.questionFamilyIDs
      where !questionFamilyIDs.contains(questionFamilyID) {
        throw KnowledgeStudyBundleError.unresolvedReviewedCardReference(
          cardID: card.id,
          type: "question family",
          id: questionFamilyID
        )
      }
      for passageID in card.citationPassageIDs {
        guard passagesByID[passageID] != nil else {
          throw KnowledgeStudyBundleError.unresolvedReviewedCardReference(
            cardID: card.id,
            type: "passage",
            id: passageID
          )
        }
        citedPassageIDs.insert(passageID)
      }
    }

    let citedPassages = try citedPassageIDs.sorted().map { passageID in
      guard let passage = passagesByID[passageID], let source = sourcesByID[passage.sourceID] else {
        throw KnowledgeStudyBundleError.unresolvedReviewedCardReference(
          cardID: "assertion-evidence",
          type: "passage",
          id: passageID
        )
      }
      return KnowledgeStudyPassage(
        id: passage.id,
        sourceID: source.id,
        sourceTitle: source.title,
        sourceRelativePath: source.relativePath,
        locator: passage.locator,
        excerpt: passage.text
      )
    }

    let contentHash = try Self.contentHash(for: pack)
    return KnowledgeStudyBundle(
      schemaVersion: Self.schemaVersion,
      bundleID: "study-\(contentHash.prefix(24))",
      packID: pack.manifest.packID,
      packTitle: pack.manifest.title,
      packContentHash: contentHash,
      defaultLocale: pack.manifest.defaultLocale,
      domainProfiles: pack.manifest.domainProfiles.sorted {
        ($0.id, $0.version) < ($1.id, $1.version)
      },
      policy: KnowledgeStudyBundlePolicy(
        closedCorpusOnly: true,
        webSearchAllowed: false,
        citationsRequired: true,
        documentInstructionsAreData: true,
        unsupportedAnswerState: .notFoundInCorpus
      ),
      requestedArtifacts: [
        "anticipated_question_families",
        "cited_presenter_response_cards",
        "contradictions_and_contested_claims",
        "corpus_gaps_and_clarifications",
        "speech_aliases_and_partial_question_prefixes",
      ],
      sources: sources,
      citedPassages: citedPassages,
      assertions: assertions,
      calculations: pack.calculations.sorted { $0.id < $1.id },
      existingQuestionFamilies: pack.questionFamilies.sorted { $0.id < $1.id },
      reviewedResponseCards: reviewedCards
    )
  }

  private static func contentHash(for pack: KnowledgePack) throws -> String {
    let content = CanonicalKnowledgePackContent(
      manifest: CanonicalKnowledgePackManifest(
        schemaVersion: pack.manifest.schemaVersion,
        packID: pack.manifest.packID,
        title: pack.manifest.title,
        createdAt: pack.manifest.createdAt,
        defaultLocale: pack.manifest.defaultLocale,
        domainProfiles: pack.manifest.domainProfiles.sorted {
          ($0.id, $0.version) < ($1.id, $1.version)
        }
      ),
      sources: pack.sources.sorted { $0.id < $1.id },
      passages: pack.passages.sorted { $0.id < $1.id },
      assertions: pack.assertions.sorted { $0.id < $1.id },
      evidenceLinks: pack.evidenceLinks.sorted { $0.id < $1.id },
      calculations: pack.calculations.sorted { $0.id < $1.id },
      responseCards: pack.responseCards.sorted { $0.id < $1.id },
      questionFamilies: pack.questionFamilies.sorted { $0.id < $1.id }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(content)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
    return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
  }
}

private struct CanonicalKnowledgePackManifest: Encodable {
  let schemaVersion: Int
  let packID: String
  let title: String
  let createdAt: Date
  let defaultLocale: String
  let domainProfiles: [DomainProfileReference]
}

private struct CanonicalKnowledgePackContent: Encodable {
  let manifest: CanonicalKnowledgePackManifest
  let sources: [KnowledgeSource]
  let passages: [KnowledgePassage]
  let assertions: [KnowledgeAssertion]
  let evidenceLinks: [KnowledgeEvidenceLink]
  let calculations: [KnowledgeCalculation]
  let responseCards: [KnowledgeResponseCard]
  let questionFamilies: [KnowledgeQuestionFamily]
}
