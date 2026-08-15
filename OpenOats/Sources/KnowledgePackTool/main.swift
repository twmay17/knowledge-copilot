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
    let options = parseOptions(Array(arguments.dropFirst(2)))
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
    let options = parseOptions(Array(arguments.dropFirst(2)))
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

  private static func parseOptions(_ arguments: [String]) -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    let supported = Set(["--relative-path", "--title", "--output"])
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
    """
}
