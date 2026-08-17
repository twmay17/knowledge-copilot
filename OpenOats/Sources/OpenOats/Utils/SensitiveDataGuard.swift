import Foundation

public enum SensitiveDataKind: String, CaseIterable, Equatable, Sendable {
  case privateKey = "private_key"
  case providerCredential = "provider_credential"
  case bearerToken = "bearer_token"
  case credentialAssignment = "credential_assignment"
}

public struct SensitiveDataFinding: Equatable, Sendable {
  public let kind: SensitiveDataKind

  public init(kind: SensitiveDataKind) {
    self.kind = kind
  }
}

/// Detects common credential material without retaining or reporting the matched value.
public enum SensitiveDataGuard {
  private struct Pattern {
    let kind: SensitiveDataKind
    let expression: String
    let options: NSRegularExpression.Options
  }

  public static func findings(in text: String) -> [SensitiveDataFinding] {
    patterns.flatMap { pattern in
      matches(pattern, in: text).map { _ in SensitiveDataFinding(kind: pattern.kind) }
    }
  }

  public static func redacted(_ text: String) -> String {
    var result = text
    for pattern in patterns {
      let ranges = matches(pattern, in: result).map(\.range).sorted { $0.location > $1.location }
      for range in ranges {
        guard let swiftRange = Range(range, in: result) else { continue }
        result.replaceSubrange(swiftRange, with: "<redacted:\(pattern.kind.rawValue)>")
      }
    }
    return result
  }

  private static var patterns: [Pattern] {
    [
      Pattern(
        kind: .privateKey,
        expression:
          #"-----BEGIN(?: [A-Z0-9]+)* PRIVATE KEY-----[\s\S]*?-----END(?: [A-Z0-9]+)* PRIVATE KEY-----"#,
        options: []
      ),
      Pattern(
        kind: .providerCredential,
        expression:
          #"\b(?:AKIA[0-9A-Z]{16}|(?:sk-(?:proj-|or-v1-)?|gh[pousr]_|github_pat_|xox[baprs]-)[A-Za-z0-9_-]{12,})\b"#,
        options: []
      ),
      Pattern(
        kind: .bearerToken,
        expression: #"\b(?:authorization\s*:\s*)?bearer\s+[A-Za-z0-9._~+/=-]{8,}"#,
        options: [.caseInsensitive]
      ),
      Pattern(
        kind: .credentialAssignment,
        expression:
          #"\b(?:api[_ -]?key|access[_ -]?token|client[_ -]?secret|webhook[_ -]?secret|password)\b\s*[:=]\s*[\"']?[A-Za-z0-9_./+=-]{8,}"#,
        options: [.caseInsensitive]
      ),
    ]
  }

  private static func matches(_ pattern: Pattern, in text: String) -> [NSTextCheckingResult] {
    guard
      let expression = try? NSRegularExpression(
        pattern: pattern.expression,
        options: pattern.options
      )
    else { return [] }
    return expression.matches(
      in: text,
      range: NSRange(text.startIndex..<text.endIndex, in: text)
    )
  }
}
