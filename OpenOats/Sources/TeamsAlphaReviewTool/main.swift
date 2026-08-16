import Darwin
import Foundation
import OpenOatsKit

@main
struct TeamsAlphaReviewTool {
  static func main() {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      if arguments == ["--help"] || arguments == ["-h"] {
        print(Options.usage)
        Darwin.exit(EXIT_SUCCESS)
      }
      let options = try Options(arguments: arguments)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let submission = try decoder.decode(
        TeamsAlphaReviewSubmission.self,
        from: Data(contentsOf: options.submissionURL)
      )
      let audioReport = try decoder.decode(
        AudioCaptureVerificationReport.self,
        from: Data(contentsOf: options.audioReportURL)
      )
      let report = try TeamsAlphaReviewEvaluator.evaluate(
        submission: submission,
        audioReport: audioReport
      )

      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let json = try encoder.encode(report)

      if let outputURL = options.outputURL {
        try FileManager.default.createDirectory(
          at: outputURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try json.write(to: outputURL, options: .atomic)
        FileHandle.standardError.write(
          Data("Wrote Teams alpha review report to \(outputURL.path)\n".utf8)
        )
      }

      if options.printJSON {
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
      } else {
        print(report.textSummary)
      }

      Darwin.exit(report.passed ? EXIT_SUCCESS : EXIT_FAILURE)
    } catch {
      fail(error.localizedDescription)
    }
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(
      Data("teams-alpha-review: \(message)\n\n\(Options.usage)\n".utf8)
    )
    Darwin.exit(EXIT_FAILURE)
  }
}

private struct Options {
  static let usage = """
    Usage:
      teams-alpha-review evaluate <submission.json> --audio-report <audio-verification.json> [options]

    Required input:
      --audio-report <report.json>   Passing report from audio-capture-verify

    Output options:
      --json
      --output <alpha-review-report.json>

    The command exits successfully only for an unconditional GO decision.
    CONDITIONAL_GO and NO_GO reports exit nonzero.
    """

  let submissionURL: URL
  let audioReportURL: URL
  var printJSON = false
  var outputURL: URL?

  init(arguments: [String]) throws {
    guard arguments.count >= 4, arguments[0] == "evaluate" else {
      throw ArgumentError("Expected the evaluate command and a submission JSON file.")
    }
    submissionURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL

    var parsedAudioReportURL: URL?
    var index = 2
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--audio-report":
        let path = try Self.stringValue(after: argument, arguments: arguments, index: &index)
        parsedAudioReportURL = URL(fileURLWithPath: path).standardizedFileURL
      case "--json":
        printJSON = true
      case "--output":
        let path = try Self.stringValue(after: argument, arguments: arguments, index: &index)
        outputURL = URL(fileURLWithPath: path).standardizedFileURL
      case "--help", "-h":
        print(Self.usage)
        Darwin.exit(EXIT_SUCCESS)
      default:
        throw ArgumentError("Unknown option: \(argument)")
      }
      index += 1
    }

    guard let parsedAudioReportURL else {
      throw ArgumentError("--audio-report is required.")
    }
    audioReportURL = parsedAudioReportURL
    guard FileManager.default.fileExists(atPath: submissionURL.path) else {
      throw ArgumentError("Submission file does not exist: \(submissionURL.path)")
    }
    guard FileManager.default.fileExists(atPath: audioReportURL.path) else {
      throw ArgumentError("Audio report does not exist: \(audioReportURL.path)")
    }
    if let outputURL,
      outputURL == submissionURL || outputURL == audioReportURL
    {
      throw ArgumentError("Output must not overwrite an input file.")
    }
  }

  private static func stringValue(
    after option: String,
    arguments: [String],
    index: inout Int
  ) throws -> String {
    index += 1
    guard index < arguments.count else { throw ArgumentError("Missing value after \(option).") }
    return arguments[index]
  }
}

private struct ArgumentError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
