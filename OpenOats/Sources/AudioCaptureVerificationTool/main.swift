import Darwin
import Foundation
import OpenOatsKit

@main
struct AudioCaptureVerificationTool {
  static func main() {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      if arguments == ["--help"] || arguments == ["-h"] {
        print(Options.usage)
        Darwin.exit(EXIT_SUCCESS)
      }
      let options = try Options(arguments: arguments)
      let policy = AudioCaptureVerificationPolicy(
        minimumSessionDurationSeconds: options.minimumSeconds,
        minimumTrackCoverageRatio: options.minimumCoverage,
        maximumUnrecoveredGapSeconds: options.maximumGapSeconds,
        minimumAudiblePeak: options.minimumPeak
      )
      let attestations = AudioCaptureVerificationAttestations(
        teamsSessionConfirmed: options.teamsSessionConfirmed,
        participantConsentConfirmed: options.participantConsentConfirmed,
        recordingIndicatorConfirmed: options.recordingIndicatorConfirmed,
        verifiedBy: options.verifiedBy
      )
      let report = try AudioCaptureVerifier.verify(
        sessionDirectory: options.sessionDirectory,
        policy: policy,
        attestations: attestations
      )

      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let json = try encoder.encode(report)

      if let outputURL = options.outputURL {
        try json.write(to: outputURL, options: .atomic)
        FileHandle.standardError.write(
          Data("Wrote verification report to \(outputURL.path)\n".utf8)
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
      Data("audio-capture-verify: \(message)\n\n\(Options.usage)\n".utf8))
    Darwin.exit(EXIT_FAILURE)
  }
}

private struct Options {
  static let usage = """
    Usage:
      audio-capture-verify verify <session-directory> [options]

    Required operator attestations for a passing report:
      --teams-session-confirmed
      --participant-consent-confirmed
      --recording-indicator-confirmed

    Threshold options:
      --minimum-seconds <seconds>          Default: 1800
      --minimum-coverage <ratio>           Default: 0.98
      --maximum-gap-seconds <seconds>      Default: 2
      --minimum-peak <amplitude>           Default: 0.002

    Output options:
      --verified-by <name>
      --json
      --output <report.json>
    """

  let sessionDirectory: URL
  var minimumSeconds = 1_800.0
  var minimumCoverage = 0.98
  var maximumGapSeconds = 2.0
  var minimumPeak: Float = 0.002
  var teamsSessionConfirmed = false
  var participantConsentConfirmed = false
  var recordingIndicatorConfirmed = false
  var verifiedBy: String?
  var printJSON = false
  var outputURL: URL?

  init(arguments: [String]) throws {
    guard arguments.count >= 2, arguments[0] == "verify" else {
      throw ArgumentError("Expected the verify command and a session directory.")
    }

    sessionDirectory =
      URL(fileURLWithPath: arguments[1], isDirectory: true)
      .standardizedFileURL
    var index = 2
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--minimum-seconds":
        minimumSeconds = try Self.doubleValue(after: argument, arguments: arguments, index: &index)
      case "--minimum-coverage":
        minimumCoverage = try Self.doubleValue(after: argument, arguments: arguments, index: &index)
      case "--maximum-gap-seconds":
        maximumGapSeconds = try Self.doubleValue(
          after: argument, arguments: arguments, index: &index)
      case "--minimum-peak":
        let value = try Self.doubleValue(after: argument, arguments: arguments, index: &index)
        minimumPeak = Float(value)
      case "--teams-session-confirmed":
        teamsSessionConfirmed = true
      case "--participant-consent-confirmed":
        participantConsentConfirmed = true
      case "--recording-indicator-confirmed":
        recordingIndicatorConfirmed = true
      case "--verified-by":
        verifiedBy = try Self.stringValue(after: argument, arguments: arguments, index: &index)
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

    guard minimumSeconds > 0 else { throw ArgumentError("--minimum-seconds must be positive.") }
    guard (0...1).contains(minimumCoverage) else {
      throw ArgumentError("--minimum-coverage must be between 0 and 1.")
    }
    guard maximumGapSeconds >= 0 else {
      throw ArgumentError("--maximum-gap-seconds cannot be negative.")
    }
    guard minimumPeak >= 0, minimumPeak <= 1 else {
      throw ArgumentError("--minimum-peak must be between 0 and 1.")
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

  private static func doubleValue(
    after option: String,
    arguments: [String],
    index: inout Int
  ) throws -> Double {
    let raw = try stringValue(after: option, arguments: arguments, index: &index)
    guard let value = Double(raw) else {
      throw ArgumentError("Invalid number for \(option): \(raw)")
    }
    return value
  }
}

private struct ArgumentError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
