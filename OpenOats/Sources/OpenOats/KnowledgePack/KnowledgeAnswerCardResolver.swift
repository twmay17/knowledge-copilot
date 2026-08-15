import Foundation

public struct KnowledgeEvidenceCitation: Equatable, Sendable, Identifiable {
  public let passageID: String
  public let sourceID: String
  public let sourceTitle: String
  public let fileURL: URL
  public let locatorLabel: String
  public let excerpt: String

  public var id: String { passageID }

  public init(
    passageID: String,
    sourceID: String,
    sourceTitle: String,
    fileURL: URL,
    locatorLabel: String,
    excerpt: String
  ) {
    self.passageID = passageID
    self.sourceID = sourceID
    self.sourceTitle = sourceTitle
    self.fileURL = fileURL
    self.locatorLabel = locatorLabel
    self.excerpt = excerpt
  }
}

public struct KnowledgeCalculationSummary: Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let version: String
  public let expression: String
  public let inputs: [KnowledgeCalculationValueSummary]
  public let output: KnowledgeCalculationValueSummary?

  public init(
    id: String,
    name: String,
    version: String,
    expression: String,
    inputs: [KnowledgeCalculationValueSummary] = [],
    output: KnowledgeCalculationValueSummary? = nil
  ) {
    self.id = id
    self.name = name
    self.version = version
    self.expression = expression
    self.inputs = inputs
    self.output = output
  }
}

public struct KnowledgeCalculationValueSummary: Equatable, Sendable, Identifiable {
  public let assertionID: String
  public let predicate: String
  public let displayValue: String
  public let qualifiers: [String: String]
  public let citations: [KnowledgeEvidenceCitation]

  public var id: String { assertionID }

  public init(
    assertionID: String,
    predicate: String,
    displayValue: String,
    qualifiers: [String: String],
    citations: [KnowledgeEvidenceCitation]
  ) {
    self.assertionID = assertionID
    self.predicate = predicate
    self.displayValue = displayValue
    self.qualifiers = qualifiers
    self.citations = citations
  }
}

public struct KnowledgeAnswerCard: Equatable, Sendable, Identifiable {
  public let id: String
  public let candidateID: String
  public let responseCardID: String?
  public let title: String
  public let answer: String
  public let evidenceState: KnowledgeEvidenceState
  public let citations: [KnowledgeEvidenceCitation]
  public let calculations: [KnowledgeCalculationSummary]
  public let isFallback: Bool

  public init(
    id: String,
    candidateID: String,
    responseCardID: String?,
    title: String,
    answer: String,
    evidenceState: KnowledgeEvidenceState,
    citations: [KnowledgeEvidenceCitation],
    calculations: [KnowledgeCalculationSummary],
    isFallback: Bool
  ) {
    self.id = id
    self.candidateID = candidateID
    self.responseCardID = responseCardID
    self.title = title
    self.answer = answer
    self.evidenceState = evidenceState
    self.citations = citations
    self.calculations = calculations
    self.isFallback = isFallback
  }
}

/// Resolves a stable, domain-neutral question candidate to one reviewed KnowledgePack card.
///
/// The resolver never synthesizes factual content. Missing, ambiguous, unreviewed, or inconsistent
/// material produces an explicit corpus-only fallback card.
public struct KnowledgeAnswerCardResolver: Sendable {
  private let pack: KnowledgePack
  private let rootDirectory: URL

  public init(pack: KnowledgePack, rootDirectory: URL) {
    self.pack = pack
    self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
  }

  public func resolve(_ candidate: QuestionCandidate) -> KnowledgeAnswerCard? {
    guard candidate.status == .stable else { return nil }

    let matches = pack.responseCards.filter { card in
      card.reviewStatus == .reviewed
        && card.questionFamilyIDs.contains(candidate.questionFamilyID)
        && bindings(in: candidate, areCompatibleWith: card)
    }.sorted { $0.id < $1.id }

    guard matches.count == 1, let card = matches.first else {
      let state: KnowledgeEvidenceState = matches.isEmpty ? .notFoundInCorpus : .needsClarification
      let answer =
        matches.isEmpty
        ? "The selected corpus does not contain a reviewed answer for the requested details."
        : "The selected corpus contains more than one reviewed answer for this question. Clarify which one to use."
      return fallback(candidate: candidate, evidenceState: state, answer: answer)
    }

    guard let citations = resolveCitations(for: card),
      let calculations = resolveCalculations(for: card)
    else {
      return fallback(
        candidate: candidate,
        evidenceState: .needsClarification,
        answer: "The selected corpus card is incomplete or its evidence cannot be opened."
      )
    }

    return KnowledgeAnswerCard(
      id: candidate.id,
      candidateID: candidate.id,
      responseCardID: card.id,
      title: card.title,
      answer: card.answer,
      evidenceState: card.evidenceState,
      citations: citations,
      calculations: calculations,
      isFallback: false
    )
  }

  private func bindings(
    in candidate: QuestionCandidate,
    areCompatibleWith card: KnowledgeResponseCard
  ) -> Bool {
    let assertions = card.assertionIDs.compactMap { assertionID in
      pack.assertions.first(where: { $0.id == assertionID })
    }
    guard assertions.count == card.assertionIDs.count else { return false }

    for binding in candidate.bindings {
      switch binding.key {
      case "period":
        guard
          assertions.isEmpty
            || assertions.contains(where: { $0.qualifiers["period"] == binding.value })
        else { return false }
      case "term":
        guard assertions.isEmpty || assertions.contains(where: { $0.predicate == binding.value })
        else { return false }
      default:
        continue
      }
    }
    return true
  }

  private func resolveCitations(
    for card: KnowledgeResponseCard
  ) -> [KnowledgeEvidenceCitation]? {
    let citations = card.citationPassageIDs.compactMap(resolveCitation)
    guard citations.count == card.citationPassageIDs.count else { return nil }

    switch card.evidenceState {
    case .notFoundInCorpus, .needsClarification:
      return citations
    case .directlySourced, .calculated, .supportedByCorpus, .contradictedByCorpus, .contested,
      .interpretive:
      return citations.isEmpty ? nil : citations
    }
  }

  private func resolveCalculations(
    for card: KnowledgeResponseCard
  ) -> [KnowledgeCalculationSummary]? {
    let calculations = card.calculationIDs.compactMap {
      calculationID -> KnowledgeCalculationSummary? in
      guard let calculation = pack.calculations.first(where: { $0.id == calculationID }) else {
        return nil
      }
      let inputs = calculation.inputAssertionIDs.compactMap {
        resolveCalculationValue(assertionID: $0, requiresEvidence: true)
      }
      guard inputs.count == calculation.inputAssertionIDs.count,
        let output = resolveCalculationValue(
          assertionID: calculation.outputAssertionID,
          requiresEvidence: false
        )
      else { return nil }
      return KnowledgeCalculationSummary(
        id: calculation.id,
        name: calculation.name,
        version: calculation.version,
        expression: calculation.expression,
        inputs: inputs,
        output: output
      )
    }
    guard calculations.count == card.calculationIDs.count else { return nil }
    if card.evidenceState == .calculated, calculations.isEmpty { return nil }
    return calculations
  }

  private func resolveCalculationValue(
    assertionID: String,
    requiresEvidence: Bool
  ) -> KnowledgeCalculationValueSummary? {
    guard let assertion = pack.assertions.first(where: { $0.id == assertionID }) else { return nil }
    let citations = assertion.evidenceLinkIDs.compactMap {
      evidenceLinkID -> KnowledgeEvidenceCitation? in
      guard
        let link = pack.evidenceLinks.first(where: {
          $0.id == evidenceLinkID && $0.assertionID == assertion.id
        })
      else { return nil }
      return resolveCitation(link.passageID)
    }
    guard citations.count == assertion.evidenceLinkIDs.count,
      !requiresEvidence || !citations.isEmpty
    else { return nil }

    return KnowledgeCalculationValueSummary(
      assertionID: assertion.id,
      predicate: assertion.predicate,
      displayValue: Self.displayValue(assertion.value),
      qualifiers: assertion.qualifiers,
      citations: citations
    )
  }

  private func resolveCitation(_ passageID: String) -> KnowledgeEvidenceCitation? {
    guard let passage = pack.passages.first(where: { $0.id == passageID }),
      let source = pack.sources.first(where: { $0.id == passage.sourceID })
    else { return nil }

    let fileURL =
      rootDirectory
      .appendingPathComponent(source.relativePath)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    guard Self.isInsideRoot(fileURL, root: rootDirectory),
      FileManager.default.fileExists(atPath: fileURL.path)
    else { return nil }

    return KnowledgeEvidenceCitation(
      passageID: passage.id,
      sourceID: source.id,
      sourceTitle: source.title,
      fileURL: fileURL,
      locatorLabel: Self.locatorLabel(passage.locator),
      excerpt: passage.text
    )
  }

  private func fallback(
    candidate: QuestionCandidate,
    evidenceState: KnowledgeEvidenceState,
    answer: String
  ) -> KnowledgeAnswerCard {
    KnowledgeAnswerCard(
      id: candidate.id,
      candidateID: candidate.id,
      responseCardID: nil,
      title: evidenceState == .notFoundInCorpus ? "Not found in corpus" : "Clarification needed",
      answer: answer,
      evidenceState: evidenceState,
      citations: [],
      calculations: [],
      isFallback: true
    )
  }

  private static func isInsideRoot(_ fileURL: URL, root: URL) -> Bool {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return fileURL.path.hasPrefix(rootPath)
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
