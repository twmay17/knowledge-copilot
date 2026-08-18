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

  /// Free-form pack-controlled text echoed into validation/error messages is
  /// redacted and length-bounded before display: a field that fails one rule
  /// may still contain credential material, and messages travel to UI, CLI
  /// output, and reports. Bounded on UTF-8 bytes, not Character count — one
  /// Character can carry unbounded combining scalars, so a Character-based
  /// bound would pass an arbitrarily large string through untruncated.
  public static func echoSafe(_ value: String) -> String {
    let redacted = redacted(value)
    let limit = 80
    guard redacted.utf8.count > limit else { return redacted }
    // Truncate on a scalar boundary within the byte budget, then mark elision.
    var scalars = String.UnicodeScalarView()
    var bytes = 0
    for scalar in redacted.unicodeScalars {
      let width = String(scalar).utf8.count
      if bytes + width > limit { break }
      scalars.append(scalar)
      bytes += width
    }
    return String(scalars) + "…"
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
        kind: .providerCredential,
        expression: #"\bAIza[0-9A-Za-z_-]{35}"#,
        options: []
      ),
      Pattern(
        kind: .bearerToken,
        expression: #"\b(?:authorization\s*:\s*)?bearer\s+[A-Za-z0-9._~+/=-]{8,}"#,
        options: [.caseInsensitive]
      ),
      Pattern(
        kind: .bearerToken,
        expression: #"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
        options: []
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
