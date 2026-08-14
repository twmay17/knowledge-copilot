import CryptoKit
import Foundation

public struct KnowledgePackValidationIssue: Equatable, Sendable, CustomStringConvertible {
  public enum Severity: String, Equatable, Sendable {
    case error
    case warning
  }

  public let severity: Severity
  public let code: String
  public let message: String

  public init(severity: Severity, code: String, message: String) {
    self.severity = severity
    self.code = code
    self.message = message
  }

  public var description: String {
    "[\(severity.rawValue.uppercased())] \(code): \(message)"
  }
}

public struct KnowledgePackValidationReport: Equatable, Sendable {
  public let issues: [KnowledgePackValidationIssue]

  public init(issues: [KnowledgePackValidationIssue]) {
    self.issues = issues
  }

  public var errors: [KnowledgePackValidationIssue] {
    issues.filter { $0.severity == .error }
  }

  public var warnings: [KnowledgePackValidationIssue] {
    issues.filter { $0.severity == .warning }
  }

  public var isValid: Bool {
    errors.isEmpty
  }
}

public enum KnowledgePackLoadingError: Error, CustomStringConvertible {
  case missingFile(String)
  case unreadableFile(String, Error)
  case invalidJSON(file: String, line: Int?, underlying: Error)
  case validationFailed(KnowledgePackValidationReport)

  public var description: String {
    switch self {
    case .missingFile(let name):
      return "KnowledgePack is missing required file '\(name)'."
    case .unreadableFile(let name, let error):
      return "KnowledgePack file '\(name)' could not be read: \(error.localizedDescription)"
    case .invalidJSON(let file, let line, let error):
      let location = line.map { " line \($0)" } ?? ""
      return "KnowledgePack file '\(file)'\(location) is invalid: \(error.localizedDescription)"
    case .validationFailed(let report):
      return report.errors.map(\.description).joined(separator: "\n")
    }
  }
}

public struct KnowledgePackLoader: Sendable {
  private let profileRegistry: KnowledgeDomainProfileRegistry

  public init(profileRegistry: KnowledgeDomainProfileRegistry = .empty) {
    self.profileRegistry = profileRegistry
  }

  public func load(from directory: URL) throws -> KnowledgePack {
    let decoder = Self.makeDecoder()
    let manifest: KnowledgePackManifest = try decodeJSON(
      KnowledgePackManifest.self,
      fileName: "manifest.json",
      directory: directory,
      decoder: decoder
    )

    let pack = KnowledgePack(
      manifest: manifest,
      sources: try decodeJSONLines(
        KnowledgeSource.self, fileName: "sources.jsonl", directory: directory, decoder: decoder),
      passages: try decodeJSONLines(
        KnowledgePassage.self, fileName: "passages.jsonl", directory: directory, decoder: decoder),
      assertions: try decodeJSONLines(
        KnowledgeAssertion.self, fileName: "assertions.jsonl", directory: directory,
        decoder: decoder),
      evidenceLinks: try decodeJSONLines(
        KnowledgeEvidenceLink.self, fileName: "evidence-links.jsonl", directory: directory,
        decoder: decoder),
      calculations: try decodeJSONLines(
        KnowledgeCalculation.self, fileName: "calculations.jsonl", directory: directory,
        decoder: decoder),
      responseCards: try decodeJSONLines(
        KnowledgeResponseCard.self, fileName: "response-cards.jsonl", directory: directory,
        decoder: decoder),
      questionFamilies: try decodeJSONLines(
        KnowledgeQuestionFamily.self, fileName: "question-families.jsonl", directory: directory,
        decoder: decoder)
    )

    var issues = validate(pack).issues
    issues.append(contentsOf: validateSourceFiles(pack.sources, in: directory))
    let report = KnowledgePackValidationReport(issues: issues)
    guard report.isValid else {
      throw KnowledgePackLoadingError.validationFailed(report)
    }
    return pack
  }

  public func validate(_ pack: KnowledgePack) -> KnowledgePackValidationReport {
    var issues: [KnowledgePackValidationIssue] = []

    if pack.manifest.schemaVersion != KnowledgePackSchema.currentVersion {
      issues.append(
        error(
          "manifest.unsupported_schema",
          "Schema version \(pack.manifest.schemaVersion) is not supported; expected \(KnowledgePackSchema.currentVersion)."
        ))
    }
    if pack.manifest.packID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(error("manifest.missing_pack_id", "Manifest packID must not be empty."))
    }
    if pack.manifest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(error("manifest.missing_title", "Manifest title must not be empty."))
    }
    issues.append(contentsOf: profileRegistry.validate(pack))

    issues.append(contentsOf: duplicateIssues(pack.sources.map(\.id), recordType: "source"))
    issues.append(contentsOf: duplicateIssues(pack.passages.map(\.id), recordType: "passage"))
    issues.append(contentsOf: duplicateIssues(pack.assertions.map(\.id), recordType: "assertion"))
    issues.append(
      contentsOf: duplicateIssues(pack.evidenceLinks.map(\.id), recordType: "evidence_link"))
    issues.append(
      contentsOf: duplicateIssues(pack.calculations.map(\.id), recordType: "calculation"))
    issues.append(
      contentsOf: duplicateIssues(pack.responseCards.map(\.id), recordType: "response_card"))
    issues.append(
      contentsOf: duplicateIssues(pack.questionFamilies.map(\.id), recordType: "question_family"))
    issues.append(contentsOf: emptyIDIssues(pack.sources.map(\.id), recordType: "source"))
    issues.append(contentsOf: emptyIDIssues(pack.passages.map(\.id), recordType: "passage"))
    issues.append(contentsOf: emptyIDIssues(pack.assertions.map(\.id), recordType: "assertion"))
    issues.append(
      contentsOf: emptyIDIssues(pack.evidenceLinks.map(\.id), recordType: "evidence_link"))
    issues.append(contentsOf: emptyIDIssues(pack.calculations.map(\.id), recordType: "calculation"))
    issues.append(
      contentsOf: emptyIDIssues(pack.responseCards.map(\.id), recordType: "response_card"))
    issues.append(
      contentsOf: emptyIDIssues(pack.questionFamilies.map(\.id), recordType: "question_family"))

    let sourceIDs = Set(pack.sources.map(\.id))
    let passageIDs = Set(pack.passages.map(\.id))
    let assertionIDs = Set(pack.assertions.map(\.id))
    let evidenceLinkIDs = Set(pack.evidenceLinks.map(\.id))
    let evidenceLinksByID = Dictionary(
      pack.evidenceLinks.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let calculationIDs = Set(pack.calculations.map(\.id))
    let questionFamilyIDs = Set(pack.questionFamilies.map(\.id))

    for source in pack.sources {
      if !Self.isSHA256(source.sha256) {
        issues.append(
          error(
            "source.invalid_sha256",
            "Source '\(source.id)' must have a lowercase 64-character SHA-256 hash."))
      }
      let pathComponents = source.relativePath.split(
        separator: "/", omittingEmptySubsequences: false)
      if source.relativePath.hasPrefix("/") || source.relativePath.contains("\\")
        || pathComponents.contains("..")
      {
        issues.append(
          error("source.unsafe_path", "Source '\(source.id)' must use a safe relative path."))
      }
    }

    for passage in pack.passages {
      if !sourceIDs.contains(passage.sourceID) {
        issues.append(
          error(
            "passage.unknown_source",
            "Passage '\(passage.id)' references unknown source '\(passage.sourceID)'."))
      }
      if passage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(error("passage.empty_text", "Passage '\(passage.id)' must not be empty."))
      }
    }

    for assertion in pack.assertions {
      if !(0...1).contains(assertion.confidence) {
        issues.append(
          error(
            "assertion.invalid_confidence",
            "Assertion '\(assertion.id)' confidence must be between 0 and 1."))
      }
      for evidenceID in assertion.evidenceLinkIDs where !evidenceLinkIDs.contains(evidenceID) {
        issues.append(
          error(
            "assertion.unknown_evidence",
            "Assertion '\(assertion.id)' references unknown evidence link '\(evidenceID)'."))
      }
      for evidenceID in assertion.evidenceLinkIDs {
        if let link = evidenceLinksByID[evidenceID], link.assertionID != assertion.id {
          issues.append(
            error(
              "assertion.mismatched_evidence",
              "Assertion '\(assertion.id)' references evidence link '\(evidenceID)' owned by assertion '\(link.assertionID)'."
            ))
        }
      }
      issues.append(contentsOf: validateValue(assertion.value, assertionID: assertion.id))
    }

    for link in pack.evidenceLinks {
      if !assertionIDs.contains(link.assertionID) {
        issues.append(
          error(
            "evidence.unknown_assertion",
            "Evidence link '\(link.id)' references unknown assertion '\(link.assertionID)'."))
      }
      if !passageIDs.contains(link.passageID) {
        issues.append(
          error(
            "evidence.unknown_passage",
            "Evidence link '\(link.id)' references unknown passage '\(link.passageID)'."))
      }
    }

    for calculation in pack.calculations {
      for assertionID in calculation.inputAssertionIDs where !assertionIDs.contains(assertionID) {
        issues.append(
          error(
            "calculation.unknown_input",
            "Calculation '\(calculation.id)' references unknown input assertion '\(assertionID)'."))
      }
      for assertionID in calculation.inputAssertionIDs {
        if let input = pack.assertions.first(where: { $0.id == assertionID }),
          input.evidenceLinkIDs.isEmpty
        {
          issues.append(
            error(
              "calculation.input_missing_evidence",
              "Calculation '\(calculation.id)' input assertion '\(assertionID)' has no evidence link."
            ))
        }
      }
      if !assertionIDs.contains(calculation.outputAssertionID) {
        issues.append(
          error(
            "calculation.unknown_output",
            "Calculation '\(calculation.id)' references unknown output assertion '\(calculation.outputAssertionID)'."
          ))
      } else if let output = pack.assertions.first(where: { $0.id == calculation.outputAssertionID }
      ), output.kind != .calculated {
        issues.append(
          error(
            "calculation.output_not_calculated",
            "Calculation '\(calculation.id)' output assertion must have kind 'calculated'."))
      }
      if calculation.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(
          error(
            "calculation.empty_expression",
            "Calculation '\(calculation.id)' must record its deterministic expression."))
      }
    }

    for card in pack.responseCards {
      for familyID in card.questionFamilyIDs where !questionFamilyIDs.contains(familyID) {
        issues.append(
          error(
            "card.unknown_question_family",
            "Response card '\(card.id)' references unknown question family '\(familyID)'."))
      }
      for assertionID in card.assertionIDs where !assertionIDs.contains(assertionID) {
        issues.append(
          error(
            "card.unknown_assertion",
            "Response card '\(card.id)' references unknown assertion '\(assertionID)'."))
      }
      for passageID in card.citationPassageIDs where !passageIDs.contains(passageID) {
        issues.append(
          error(
            "card.unknown_passage",
            "Response card '\(card.id)' references unknown citation passage '\(passageID)'."))
      }
      for calculationID in card.calculationIDs where !calculationIDs.contains(calculationID) {
        issues.append(
          error(
            "card.unknown_calculation",
            "Response card '\(card.id)' references unknown calculation '\(calculationID)'."))
      }
      issues.append(contentsOf: validateEvidenceContract(card))
    }

    if pack.sources.isEmpty {
      issues.append(warning("pack.no_sources", "Pack contains no sources."))
    }
    if pack.questionFamilies.isEmpty {
      issues.append(
        warning("pack.no_question_families", "Pack contains no anticipated question families."))
    }

    return KnowledgePackValidationReport(issues: issues)
  }

  private func validateValue(_ value: KnowledgeValue, assertionID: String)
    -> [KnowledgePackValidationIssue]
  {
    let populated = [
      value.text != nil,
      value.number != nil,
      value.boolean != nil,
      value.date != nil,
      value.referenceID != nil,
    ].filter { $0 }.count

    guard populated == 1 else {
      return [
        error(
          "assertion.invalid_value",
          "Assertion '\(assertionID)' must populate exactly one typed value field.")
      ]
    }

    let matchesType: Bool
    switch value.type {
    case .text: matchesType = value.text != nil
    case .number: matchesType = value.number != nil
    case .boolean: matchesType = value.boolean != nil
    case .date: matchesType = value.date != nil
    case .reference: matchesType = value.referenceID != nil
    }
    guard matchesType else {
      return [
        error(
          "assertion.value_type_mismatch",
          "Assertion '\(assertionID)' value does not match declared type '\(value.type.rawValue)'.")
      ]
    }
    if value.type != .number, value.unit != nil || value.scale != nil {
      return [
        error(
          "assertion.non_numeric_unit",
          "Assertion '\(assertionID)' may only set unit or scale on a numeric value.")
      ]
    }
    return []
  }

  private func validateEvidenceContract(_ card: KnowledgeResponseCard)
    -> [KnowledgePackValidationIssue]
  {
    let hasEvidence =
      !card.assertionIDs.isEmpty || !card.citationPassageIDs.isEmpty || !card.calculationIDs.isEmpty
    switch card.evidenceState {
    case .notFoundInCorpus, .needsClarification:
      if hasEvidence {
        return [
          warning(
            "card.abstention_has_evidence",
            "Abstention card '\(card.id)' carries evidence references; verify that it does not imply an answer."
          )
        ]
      }
    case .calculated:
      if card.calculationIDs.isEmpty || card.assertionIDs.isEmpty
        || card.citationPassageIDs.isEmpty
      {
        return [
          error(
            "card.calculation_missing_derivation",
            "Calculated card '\(card.id)' requires a calculation, output assertion, and source citation."
          )
        ]
      }
    default:
      if card.citationPassageIDs.isEmpty {
        return [
          error(
            "card.missing_citation",
            "Card '\(card.id)' with state '\(card.evidenceState.rawValue)' requires a citation passage."
          )
        ]
      }
    }
    return []
  }

  private func duplicateIssues(_ ids: [String], recordType: String)
    -> [KnowledgePackValidationIssue]
  {
    let duplicates = Dictionary(grouping: ids, by: { $0 })
      .filter { !$0.key.isEmpty && $0.value.count > 1 }
      .keys
      .sorted()
    return duplicates.map {
      error("\(recordType).duplicate_id", "Duplicate \(recordType) ID '\($0)'.")
    }
  }

  private func emptyIDIssues(_ ids: [String], recordType: String) -> [KnowledgePackValidationIssue]
  {
    let count = ids.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    guard count > 0 else { return [] }
    return [
      error("\(recordType).empty_id", "Found \(count) \(recordType) record(s) with an empty ID.")
    ]
  }

  private func validateSourceFiles(_ sources: [KnowledgeSource], in directory: URL)
    -> [KnowledgePackValidationIssue]
  {
    var issues: [KnowledgePackValidationIssue] = []
    let root = directory.standardizedFileURL.resolvingSymlinksInPath()

    for source in sources {
      let fileURL =
        root
        .appendingPathComponent(source.relativePath)
        .standardizedFileURL
        .resolvingSymlinksInPath()
      guard fileURL.path.hasPrefix(root.path + "/") else {
        issues.append(
          error(
            "source.path_escape",
            "Source '\(source.id)' resolves outside the KnowledgePack directory."))
        continue
      }
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        issues.append(
          error(
            "source.file_missing",
            "Source '\(source.id)' file '\(source.relativePath)' does not exist."))
        continue
      }
      do {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if digest != source.sha256 {
          issues.append(
            error(
              "source.hash_mismatch",
              "Source '\(source.id)' SHA-256 does not match its manifest record."))
        }
      } catch let readError {
        issues.append(
          error(
            "source.file_unreadable",
            "Source '\(source.id)' file could not be read: \(readError.localizedDescription)"))
      }
    }
    return issues
  }

  private func decodeJSON<T: Decodable>(
    _ type: T.Type,
    fileName: String,
    directory: URL,
    decoder: JSONDecoder
  ) throws -> T {
    let fileURL = directory.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw KnowledgePackLoadingError.missingFile(fileName)
    }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw KnowledgePackLoadingError.unreadableFile(fileName, error)
    }
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw KnowledgePackLoadingError.invalidJSON(file: fileName, line: nil, underlying: error)
    }
  }

  private func decodeJSONLines<T: Decodable>(
    _ type: T.Type,
    fileName: String,
    directory: URL,
    decoder: JSONDecoder
  ) throws -> [T] {
    let fileURL = directory.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw KnowledgePackLoadingError.missingFile(fileName)
    }

    let text: String
    do {
      text = try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
      throw KnowledgePackLoadingError.unreadableFile(fileName, error)
    }

    var records: [T] = []
    for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      do {
        records.append(try decoder.decode(type, from: Data(line.utf8)))
      } catch {
        throw KnowledgePackLoadingError.invalidJSON(
          file: fileName, line: offset + 1, underlying: error)
      }
    }
    return records
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) {
        return date
      }
      let standard = ISO8601DateFormatter()
      standard.formatOptions = [.withInternetDateTime]
      if let date = standard.date(from: value) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected an ISO-8601 date.")
    }
    return decoder
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
  }

  private func error(_ code: String, _ message: String) -> KnowledgePackValidationIssue {
    KnowledgePackValidationIssue(severity: .error, code: code, message: message)
  }

  private func warning(_ code: String, _ message: String) -> KnowledgePackValidationIssue {
    KnowledgePackValidationIssue(severity: .warning, code: code, message: message)
  }
}
