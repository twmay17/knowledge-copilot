import Darwin
import Foundation
import HospitalityDomainProfile
import OpenOatsKit

@main
struct KnowledgePackTool {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 2 else {
      fail("Usage: knowledge-pack <validate|inspect> <pack-directory>")
    }

    let command = arguments[0]
    let directory = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL

    do {
      let profiles = KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
      let pack = try KnowledgePackLoader(profileRegistry: profiles).load(from: directory)
      switch command {
      case "validate":
        print("Valid KnowledgePack: \(pack.manifest.title)")
        print("Pack ID: \(pack.manifest.packID)")
        print("Schema: \(pack.manifest.schemaVersion)")
        print(
          "Sources: \(pack.sources.count); passages: \(pack.passages.count); assertions: \(pack.assertions.count); cards: \(pack.responseCards.count)"
        )
      case "inspect":
        print("\(pack.manifest.title) [\(pack.manifest.packID)]")
        print(
          "Profiles: \(pack.manifest.domainProfiles.map { "\($0.id)@\($0.version)" }.joined(separator: ", "))"
        )
        for card in pack.responseCards {
          print("- [\(card.evidenceState.rawValue)] \(card.title): \(card.answer)")
        }
      default:
        fail("Unknown command '\(command)'. Use 'validate' or 'inspect'.")
      }
    } catch {
      fail(String(describing: error))
    }
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("knowledge-pack: \(message)\n".utf8))
    Darwin.exit(EXIT_FAILURE)
  }
}
