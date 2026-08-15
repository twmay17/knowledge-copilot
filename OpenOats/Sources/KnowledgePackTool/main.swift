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
    """
}
