import Darwin
import Foundation
import HospitalityDomainProfile
import OpenOatsKit

@main
struct KnowledgePackTool {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
      fail(usage)
    }

    do {
      let profiles = KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
      switch command {
      case "validate":
        let (pack, _) = try loadPack(arguments: arguments, profiles: profiles)
        validate(pack)
      case "inspect":
        let (pack, _) = try loadPack(arguments: arguments, profiles: profiles)
        inspect(pack)
      case "replay":
        try replay(arguments: arguments, profiles: profiles)
      case "ingest-document":
        try ingestDocument(arguments: arguments)
      case "ingest-spreadsheet":
        try ingestSpreadsheet(arguments: arguments)
      case "import-underwriting-csv":
        try importUnderwritingCSV(arguments: arguments)
      case "export-study-bundle":
        try exportStudyBundle(arguments: arguments, profiles: profiles)
      case "prepare-study-review":
        try prepareStudyReview(arguments: arguments, profiles: profiles)
      case "approve-study-review":
        try approveStudyReview(arguments: arguments, profiles: profiles)
      case "plan-study-import":
        try planStudyImport(arguments: arguments, profiles: profiles)
      case "apply-study-import":
        try applyStudyImport(arguments: arguments, profiles: profiles)
      case "help", "--help", "-h":
        print(usage)
      default:
        fail("Unknown command '\(command)'.\n\n\(usage)")
      }
    } catch {
      fail(String(describing: error))
    }
  }

  private static func loadPack(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws -> (KnowledgePack, URL) {
    guard arguments.count == 2 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    return (try KnowledgePackLoader(profileRegistry: profiles).load(from: directory), directory)
  }

  private static func validate(_ pack: KnowledgePack) {
    print("Valid KnowledgePack: \(pack.manifest.title)")
    print("Pack ID: \(pack.manifest.packID)")
    print("Schema: \(pack.manifest.schemaVersion)")
    print(
      "Sources: \(pack.sources.count); passages: \(pack.passages.count); assertions: \(pack.assertions.count); cards: \(pack.responseCards.count)"
    )
  }

  private static func inspect(_ pack: KnowledgePack) {
    print("\(pack.manifest.title) [\(pack.manifest.packID)]")
    print(
      "Profiles: \(pack.manifest.domainProfiles.map { "\($0.id)@\($0.version)" }.joined(separator: ", "))"
    )
    for card in pack.responseCards {
      print("- [\(card.evidenceState.rawValue)] \(card.title): \(card.answer)")
    }
  }

  private static func replay(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 3 || arguments.count == 5 else { fail(usage) }
    guard arguments.count == 3 || arguments[3] == "--output" else { fail(usage) }

    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let specURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let spec = try JSONDecoder().decode(
      KnowledgeProofReplaySpec.self,
      from: Data(contentsOf: specURL)
    )
    let report = try KnowledgeProofReplayRunner(
      pack: pack,
      rootDirectory: directory,
      termAliases: profiles.termAliases(for: pack.manifest)
    ).run(spec)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let reportData = try encoder.encode(report)

    if arguments.count == 5 {
      let outputURL = URL(fileURLWithPath: arguments[4]).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try reportData.write(to: outputURL, options: .atomic)
      printReplaySummary(report)
      print("Report: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(reportData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }

    if report.verdict == .fail {
      Darwin.exit(EXIT_FAILURE)
    }
  }

  private static func ingestDocument(arguments: [String]) throws {
    guard arguments.count >= 4 else { fail(usage) }
    let documentURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--relative-path", "--title", "--output"]
    )
    guard let relativePath = options["--relative-path"] else { fail(usage) }

    let result = try KnowledgeDocumentIngestor().ingest(
      fileAt: documentURL,
      relativePath: relativePath,
      title: options["--title"]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let resultData = try encoder.encode(result)

    if let outputPath = options["--output"] {
      let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try resultData.write(to: outputURL, options: .atomic)
      printDocumentIngestionSummary(result)
      print("Result: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(resultData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }

  private static func ingestSpreadsheet(arguments: [String]) throws {
    guard arguments.count >= 4 else { fail(usage) }
    let spreadsheetURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--relative-path", "--title", "--output"]
    )
    guard let relativePath = options["--relative-path"] else { fail(usage) }

    let result = try KnowledgeSpreadsheetIngestor().ingest(
      fileAt: spreadsheetURL,
      relativePath: relativePath,
      title: options["--title"]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let resultData = try encoder.encode(result)

    if let outputPath = options["--output"] {
      let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try resultData.write(to: outputURL, options: .atomic)
      printSpreadsheetIngestionSummary(result)
      print("Result: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(resultData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }

  private static func importUnderwritingCSV(arguments: [String]) throws {
    guard arguments.count >= 6 else { fail(usage) }
    let csvURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: [
        "--relative-path", "--asset-id", "--period", "--status", "--title", "--output",
      ]
    )
    guard let relativePath = options["--relative-path"],
      let assetID = options["--asset-id"]
    else { fail(usage) }

    let result = try HospitalityUnderwritingCSVImporter().ingest(
      fileAt: csvURL,
      relativePath: relativePath,
      assetID: assetID,
      period: options["--period"],
      status: options["--status"],
      title: options["--title"]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let resultData = try encoder.encode(result)

    if let outputPath = options["--output"] {
      let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try resultData.write(to: outputURL, options: .atomic)
      printUnderwritingImportSummary(result)
      print("Result: \(outputURL.path)")
    } else {
      FileHandle.standardOutput.write(resultData)
      FileHandle.standardOutput.write(Data("\n".utf8))
    }
  }

  private static func exportStudyBundle(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 4 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(2)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(bundle)
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: outputURL, options: .atomic)

    print("Exported Study Bundle: \(bundle.bundleID)")
    print("Pack: \(bundle.packTitle) [\(bundle.packID)]")
    print(
      "Sources: \(bundle.sources.count); cited passages: \(bundle.citedPassages.count); assertions: \(bundle.assertions.count); calculations: \(bundle.calculations.count); reviewed cards: \(bundle.reviewedResponseCards.count)"
    )
    print("Closed corpus: yes; web search: disabled; citations: required")
    print("Result: \(outputURL.path)")
  }

  private static func prepareStudyReview(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 5 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let analysisURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(3)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
    let analysis = try decodeJSON(KnowledgeStudyAnalysis.self, from: analysisURL)
    let queue = try KnowledgeStudyAnalysisValidator().makeReviewQueue(
      analysis: analysis,
      bundle: bundle
    )
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    try writeJSON(queue, to: outputURL)

    print("Prepared Study Review: \(queue.queueID)")
    print("Analysis: \(queue.analysis.analysisID); generator: \(queue.analysis.generator)")
    print(
      "Pending question families: \(queue.analysis.questionFamilyProposals.count); response cards: \(queue.responseCardItems.count); contradictions: \(queue.analysis.contradictions.count); gaps: \(queue.analysis.corpusGaps.count)"
    )
    print("All model proposals remain generated and require an explicit human decision.")
    print("Result: \(outputURL.path)")
  }

  private static func approveStudyReview(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 6 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let queueURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let decisionsURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(4)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
    let queue = try decodeJSON(KnowledgeStudyReviewQueue.self, from: queueURL)
    let decisions = try decodeJSON(KnowledgeStudyReviewDecisionSet.self, from: decisionsURL)
    let approvedImport = try KnowledgeStudyReviewGate(profileRegistry: profiles).approve(
      queue: queue,
      decisions: decisions,
      pack: pack
    )
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    try writeJSON(approvedImport, to: outputURL)

    print("Approved Study Import: \(approvedImport.importID)")
    print(
      "Reviewer: \(approvedImport.reviewer); question families: \(approvedImport.approvedQuestionFamilies.count); response cards: \(approvedImport.approvedResponseCards.count); rejected: \(approvedImport.rejectedDecisions.count)"
    )
    print("No KnowledgePack files were modified; the output is a reviewed import artifact.")
    print("Result: \(outputURL.path)")
  }

  private static func planStudyImport(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 5 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let importURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(3)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let approvedImport = try decodeJSON(KnowledgeStudyApprovedImport.self, from: importURL)
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    requireOutputOutsidePack(outputURL, packDirectory: directory)
    let plan = try KnowledgeStudyImportApplier(profileRegistry: profiles).plan(
      approvedImport: approvedImport,
      packDirectory: directory
    )
    try writeJSON(plan, to: outputURL)

    print("Study Import Plan: \(plan.state.rawValue)")
    print("Import: \(plan.importID); pack: \(plan.packID)")
    print(
      "Approved question families: \(plan.approvedQuestionFamilyIDs.count); response cards: \(plan.approvedResponseCardIDs.count); rejected: \(plan.rejectedProposalCount)"
    )
    print("No KnowledgePack files were modified.")
    print("Result: \(outputURL.path)")
  }

  private static func applyStudyImport(
    arguments: [String],
    profiles: KnowledgeDomainProfileRegistry
  ) throws {
    guard arguments.count == 5 else { fail(usage) }
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    let importURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let options = parseOptions(
      Array(arguments.dropFirst(3)),
      supported: ["--output"]
    )
    guard let outputPath = options["--output"] else { fail(usage) }

    let approvedImport = try decodeJSON(KnowledgeStudyApprovedImport.self, from: importURL)
    let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
    requireOutputOutsidePack(outputURL, packDirectory: directory)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    guard FileManager.default.isWritableFile(atPath: outputURL.deletingLastPathComponent().path)
    else {
      throw CocoaError(.fileWriteNoPermission)
    }
    let receipt = try KnowledgeStudyImportApplier(profileRegistry: profiles).apply(
      approvedImport: approvedImport,
      to: directory
    )
    try writeJSON(receipt, to: outputURL)

    print("Study Import: \(receipt.outcome.rawValue)")
    print("Import: \(receipt.importID); reviewer: \(receipt.reviewer)")
    print(
      "Question families: \(receipt.approvedQuestionFamilyIDs.count); response cards: \(receipt.approvedResponseCardIDs.count)"
    )
    print("Pack hash: \(receipt.resultingPackContentHash)")
    print("Receipt: \(outputURL.path)")
  }

  private static func decodeJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(contentsOf: url))
  }

  private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
  }

  private static func requireOutputOutsidePack(_ outputURL: URL, packDirectory: URL) {
    let root = packDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let target = outputURL.standardizedFileURL.resolvingSymlinksInPath()
    guard target.path != root.path, !target.path.hasPrefix(root.path + "/") else {
      fail(
        "Output must be outside the KnowledgePack directory so a plan or receipt cannot overwrite corpus files."
      )
    }
  }

  private static func parseOptions(
    _ arguments: [String],
    supported: Set<String>
  ) -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      let key = arguments[index]
      guard supported.contains(key), index + 1 < arguments.count else { fail(usage) }
      options[key] = arguments[index + 1]
      index += 2
    }
    return options
  }

  private static func printDocumentIngestionSummary(_ result: KnowledgeDocumentIngestionResult) {
    let tableCount = Set(result.passages.compactMap(\.locator.table)).count
    print("Ingested: \(result.source.title)")
    print(
      "Passages: \(result.passages.count); tables: \(tableCount); warnings: \(result.warnings.count)"
    )
    for warning in result.warnings {
      print("Warning [\(warning.flag.rawValue)]: \(warning.message)")
    }
  }

  private static func printUnderwritingImportSummary(
    _ result: HospitalityUnderwritingImportResult
  ) {
    print("Imported: \(result.source.title)")
    print(
      "Profile: \(result.profileID)@\(result.profileVersion); role: \(result.labels.role.rawValue); type: \(result.labels.documentType.rawValue)"
    )
    print(
      "Passages: \(result.passages.count); assertions: \(result.assertions.count); warnings: \(result.warnings.count)"
    )
    for warning in result.warnings {
      let row = warning.row.map { " row \($0)" } ?? ""
      print("Warning [\(warning.code)]\(row): \(warning.message)")
    }
  }

  private static func printSpreadsheetIngestionSummary(
    _ result: KnowledgeSpreadsheetIngestionResult
  ) {
    let sheets = Set(result.passages.compactMap(\.locator.sheet)).count
    let formulaCells = result.passages.reduce(0) { count, passage in
      count + (passage.spreadsheet?.cells.filter { $0.formula != nil }.count ?? 0)
    }
    print("Ingested: \(result.source.title)")
    print(
      "Passages: \(result.passages.count); sheets: \(sheets); formula cells: \(formulaCells); warnings: \(result.warnings.count)"
    )
    for warning in result.warnings {
      print("Warning [\(warning.code)]: \(warning.message)")
    }
  }

  private static func printReplaySummary(_ report: KnowledgeProofReport) {
    print("\(report.verdict.rawValue): \(report.replayName)")
    print(
      "Answer: \(report.answerAppearedAtMilliseconds.map(formatted) ?? "never") ms; deadline: \(report.responseDeadlineMilliseconds) ms; headroom: \(report.deadlineHeadroomMilliseconds.map(formatted) ?? "n/a") ms"
    )
    print(
      "Processing latency: median \(formatted(report.latency.medianMilliseconds)) ms; p95 \(formatted(report.latency.p95Milliseconds)) ms; max \(formatted(report.latency.maximumMilliseconds)) ms"
    )
    for check in report.checks where !check.passed {
      print("Failed \(check.name): \(check.detail)")
    }
  }

  private static func formatted(_ value: Double) -> String {
    String(format: "%.3f", value)
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("knowledge-pack: \(message)\n".utf8))
    Darwin.exit(EXIT_FAILURE)
  }

  private static let usage = """
    Usage:
      knowledge-pack validate <pack-directory>
      knowledge-pack inspect <pack-directory>
      knowledge-pack replay <pack-directory> <replay-spec.json> [--output <report.json>]
      knowledge-pack ingest-document <document.pdf|document.docx> --relative-path <pack-relative-path> [--title <title>] [--output <result.json>]
      knowledge-pack ingest-spreadsheet <spreadsheet.xlsx|spreadsheet.csv> --relative-path <pack-relative-path> [--title <title>] [--output <result.json>]
      knowledge-pack import-underwriting-csv <pl-or-star.csv> --relative-path <pack-relative-path> --asset-id <stable-asset-id> [--period <YYYY|YYYY-MM|TTM:YYYY-MM|YTD:YYYY-MM>] [--status <actual|budget|forecast>] [--title <title>] [--output <result.json>]
      knowledge-pack export-study-bundle <pack-directory> --output <study-bundle.json>
      knowledge-pack prepare-study-review <pack-directory> <study-analysis.json> --output <review-queue.json>
      knowledge-pack approve-study-review <pack-directory> <review-queue.json> <review-decisions.json> --output <approved-import.json>
      knowledge-pack plan-study-import <pack-directory> <approved-import.json> --output <plan.json>
      knowledge-pack apply-study-import <pack-directory> <approved-import.json> --output <receipt.json>
    """
}
