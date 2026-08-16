import AppKit
import Foundation

enum KnowledgeOverlayCommand: String, CaseIterable, Equatable, Sendable {
  case togglePin
  case copyAnswer
  case openSource
  case requestCorrection
  case dismiss
  case toggleCompactMode

  var shortcutLabel: String {
    switch self {
    case .togglePin: "⌥⇧⌘P"
    case .copyAnswer: "⌥⇧⌘C"
    case .openSource: "⌥⇧⌘E"
    case .requestCorrection: "⌥⇧⌘W"
    case .dismiss: "⌥⇧⌘X"
    case .toggleCompactMode: "⌥⇧⌘K"
    }
  }
}

enum KnowledgeOverlayKeyboardShortcuts {
  static func command(for event: NSEvent) -> KnowledgeOverlayCommand? {
    command(
      forKey: event.charactersIgnoringModifiers ?? "",
      commandPressed: event.modifierFlags.contains(.command),
      shiftPressed: event.modifierFlags.contains(.shift),
      optionPressed: event.modifierFlags.contains(.option),
      controlPressed: event.modifierFlags.contains(.control)
    )
  }

  static func command(
    forKey key: String,
    commandPressed: Bool,
    shiftPressed: Bool,
    optionPressed: Bool = false,
    controlPressed: Bool = false
  ) -> KnowledgeOverlayCommand? {
    guard commandPressed, shiftPressed, optionPressed, !controlPressed else { return nil }

    return switch key.lowercased() {
    case "p": .togglePin
    case "c": .copyAnswer
    case "e": .openSource
    case "w": .requestCorrection
    case "x": .dismiss
    case "k": .toggleCompactMode
    default: nil
    }
  }
}

struct KnowledgeOverlayShareSafetyNotice: Equatable, Sendable {
  enum Severity: Equatable, Sendable {
    case caution
    case warning
  }

  let severity: Severity
  let title: String
  let message: String

  static func make(hideFromScreenShare: Bool) -> KnowledgeOverlayShareSafetyNotice {
    if hideFromScreenShare {
      return KnowledgeOverlayShareSafetyNotice(
        severity: .caution,
        title: "Full-display share warning",
        message:
          "Window-capture exclusion is on, but sharing your entire display may still show this overlay. Share a single app window."
      )
    }

    return KnowledgeOverlayShareSafetyNotice(
      severity: .warning,
      title: "Overlay visible to screen sharing",
      message:
        "Window-capture exclusion is off. Window and full-display sharing may show this overlay."
    )
  }
}

extension KnowledgeOverlayCard {
  var firstOpenableSourceURL: URL? {
    sources.lazy.compactMap(\.fileURL).first
  }

  var clipboardText: String {
    var sections = [
      title,
      answer,
      "Evidence: \(evidenceLabel)",
      "Why: \(why)",
    ]

    if !sources.isEmpty {
      let sourceLines = sources.map { source in
        let locator = source.locator.isEmpty ? "" : " — \(source.locator)"
        return "- \(source.title)\(locator)"
      }
      sections.append("Sources:\n\(sourceLines.joined(separator: "\n"))")
    }

    return sections.joined(separator: "\n\n")
  }
}
