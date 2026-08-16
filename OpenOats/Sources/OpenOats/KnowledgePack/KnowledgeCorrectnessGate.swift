import CryptoKit
import Foundation

public struct KnowledgeCorrectnessGateSpec: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let name: String
  public let benchmarkRelativePath: String
  public let minimumCrossPackScenarioCount: Int
  public let packs: [KnowledgeCorrectnessPackReference]
  public let outcomeProbes: [KnowledgeCorrectnessOutcomeProbe]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    name: String,
    benchmarkRelativePath: String,
    minimumCrossPackScenarioCount: Int,
    packs: [KnowledgeCorrectnessPackReference],
    outcomeProbes: [KnowledgeCorrectnessOutcomeProbe]
  ) {
    self.schemaVersion = schemaVersion
    self.name = name
    self.benchmarkRelativePath = benchmarkRelativePath
    self.minimumCrossPackScenarioCount = minimumCrossPackScenarioCount
    self.packs = packs
    self.outcomeProbes = outcomeProbes
  }
}

public struct KnowledgeCorrectnessPackReference: Codable, Equatable, Sendable {
  public let packID: String
  public let relativePath: String
  public let expectedFingerprints: KnowledgeCorrectnessFingerprints

  public init(
    packID: String,
    relativePath: String,
    expectedFingerprints: KnowledgeCorrectnessFingerprints
  ) {
    self.packID = packID
    self.relativePath = relativePath
    self.expectedFingerprints = expectedFingerprints
  }
}

public struct KnowledgeCorrectnessOutcomeProbe: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let packID: String
  public let query: KnowledgeEvidenceQuery
  public let expectedState: KnowledgeEvidenceState
  public let expectedReason: KnowledgeEvidenceOutcomeReason
  public let expectedAssertionIDs: [String]
  public let expectedPassageIDs: [String]

  public init(
    id: String,
    packID: String,
    query: KnowledgeEvidenceQuery,
    expectedState: KnowledgeEvidenceState,
    expectedReason: KnowledgeEvidenceOutcomeReason,
    expectedAssertionIDs: [String],
    expectedPassageIDs: [String]
  ) {
    self.id = id
    self.packID = packID
    self.query = query
    self.expectedState = expectedState
    self.expectedReason = expectedReason
    self.expectedAssertionIDs = expectedAssertionIDs
    self.expectedPassageIDs = expectedPassageIDs
  }
}

/// Stable category hashes identify whether drift occurred in claims, qualifiers, calculations,
/// evidence links, citations, or presenter-card labels instead of reducing every mismatch to one
/// opaque pack hash.
public struct KnowledgeCorrectnessFingerprints: Codable, Equatable, Sendable {
  public let packContentSHA256: String
  public let sourcesSHA256: String
  public let passagesSHA256: String
  public let assertionsSHA256: String
  public let evidenceLinksSHA256: String
  public let calculationsSHA256: String
  public let responseCardsSHA256: String
  public let questionFamiliesSHA256: String

  public init(
    packContentSHA256: String,
    sourcesSHA256: String,
    passagesSHA256: String,
    assertionsSHA256: String,
    evidenceLinksSHA256: String,
    calculationsSHA256: String,
    responseCardsSHA256: String,
    questionFamiliesSHA256: String
  ) {
    self.packContentSHA256 = packContentSHA256
    self.sourcesSHA256 = sourcesSHA256
    self.passagesSHA256 = passagesSHA256
    self.assertionsSHA256 = assertionsSHA256
    self.evidenceLinksSHA256 = evidenceLinksSHA256
    self.calculationsSHA256 = calculationsSHA256
    self.responseCardsSHA256 = responseCardsSHA256
    self.questionFamiliesSHA256 = questionFamiliesSHA256
  }

  public static func make(for pack: KnowledgePack) throws -> Self {
    Self(
      packContentSHA256: try KnowledgeStudyBundleBuilder().build(from: pack).packContentHash,
      sourcesSHA256: try digest(pack.sources.sorted { $0.id < $1.id }),
      passagesSHA256: try digest(pack.passages.sorted { $0.id < $1.id }),
      assertionsSHA256: try digest(pack.assertions.sorted { $0.id < $1.id }),
      evidenceLinksSHA256: try digest(pack.evidenceLinks.sorted { $0.id < $1.id }),
      calculationsSHA256: try digest(pack.calculations.sorted { $0.id < $1.id }),
      responseCardsSHA256: try digest(pack.responseCards.sorted { $0.id < $1.id }),
      questionFamiliesSHA256: try digest(pack.questionFamilies.sorted { $0.id < $1.id })
    )
  }

  public var isWellFormed: Bool {
    [
      packContentSHA256,
      sourcesSHA256,
      passagesSHA256,
      assertionsSHA256,
      evidenceLinksSHA256,
      calculationsSHA256,
      responseCardsSHA256,
      questionFamiliesSHA256,
    ].allSatisfy(Self.isLowercaseSHA256)
  }

  public func checks(against actual: Self) -> [KnowledgeProofCheck] {
    [
      check("pack_content", expected: packContentSHA256, actual: actual.packContentSHA256),
      check("sources", expected: sourcesSHA256, actual: actual.sourcesSHA256),
      check("passages", expected: passagesSHA256, actual: actual.passagesSHA256),
      check("assertions", expected: assertionsSHA256, actual: actual.assertionsSHA256),
      check(
        "evidence_links", expected: evidenceLinksSHA256, actual: actual.evidenceLinksSHA256),
      check("calculations", expected: calculationsSHA256, actual: actual.calculationsSHA256),
      check(
        "response_cards", expected: responseCardsSHA256, actual: actual.responseCardsSHA256),
      check(
        "question_families", expected: questionFamiliesSHA256,
        actual: actual.questionFamiliesSHA256),
    ]
  }

  private func check(_ name: String, expected: String, actual: String) -> KnowledgeProofCheck {
    KnowledgeProofCheck(
      name: name,
      passed: expected == actual,
      detail: expected == actual
        ? "Golden \(name) SHA-256 matched."
        : "Golden \(name) SHA-256 differed: expected \(expected), observed \(actual)."
    )
  }

  private static func digest<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func isLowercaseSHA256(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }
}

public struct KnowledgeCorrectnessFinding: Codable, Equatable, Sendable {
  public let severity: String
  public let code: String
  public let packID: String
  public let recordID: String?
  public let detail: String

  public init(
    severity: String,
    code: String,
    packID: String,
    recordID: String? = nil,
    detail: String
  ) {
    self.severity = severity
    self.code = code
    self.packID = packID
    self.recordID = recordID
    self.detail = detail
  }
}

public struct KnowledgeCorrectnessPackAudit: Codable, Equatable, Sendable, Identifiable {
  public var id: String { packID }

  public let packID: String
  public let expectedFingerprints: KnowledgeCorrectnessFingerprints
  public let actualFingerprints: KnowledgeCorrectnessFingerprints?
  public let fingerprintChecks: [KnowledgeProofCheck]
  public let findings: [KnowledgeCorrectnessFinding]
  public let sourceCount: Int
  public let passageCount: Int
  public let assertionCount: Int
  public let calculationCount: Int
  public let responseCardCount: Int
  public let citationCount: Int
  public let verdict: KnowledgeProofVerdict

  public init(
    packID: String,
    expectedFingerprints: KnowledgeCorrectnessFingerprints,
    actualFingerprints: KnowledgeCorrectnessFingerprints?,
    fingerprintChecks: [KnowledgeProofCheck],
    findings: [KnowledgeCorrectnessFinding],
    sourceCount: Int,
    passageCount: Int,
    assertionCount: Int,
    calculationCount: Int,
    responseCardCount: Int,
    citationCount: Int,
    verdict: KnowledgeProofVerdict
  ) {
    self.packID = packID
    self.expectedFingerprints = expectedFingerprints
    self.actualFingerprints = actualFingerprints
    self.fingerprintChecks = fingerprintChecks
    self.findings = findings
    self.sourceCount = sourceCount
    self.passageCount = passageCount
    self.assertionCount = assertionCount
    self.calculationCount = calculationCount
    self.responseCardCount = responseCardCount
    self.citationCount = citationCount
    self.verdict = verdict
  }
}

public struct KnowledgeCorrectnessOutcomeAudit: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let packID: String
  public let expectedState: KnowledgeEvidenceState
  public let actualState: KnowledgeEvidenceState?
  public let expectedReason: KnowledgeEvidenceOutcomeReason
  public let actualReason: KnowledgeEvidenceOutcomeReason?
  public let expectedAssertionIDs: [String]
  public let actualAssertionIDs: [String]
  public let expectedPassageIDs: [String]
  public let actualPassageIDs: [String]
  public let detail: String
  public let passed: Bool

  public init(
    id: String,
    packID: String,
    expectedState: KnowledgeEvidenceState,
    actualState: KnowledgeEvidenceState?,
    expectedReason: KnowledgeEvidenceOutcomeReason,
    actualReason: KnowledgeEvidenceOutcomeReason?,
    expectedAssertionIDs: [String],
    actualAssertionIDs: [String],
    expectedPassageIDs: [String],
    actualPassageIDs: [String],
    detail: String,
    passed: Bool
  ) {
    self.id = id
    self.packID = packID
    self.expectedState = expectedState
    self.actualState = actualState
    self.expectedReason = expectedReason
    self.actualReason = actualReason
    self.expectedAssertionIDs = expectedAssertionIDs
    self.actualAssertionIDs = actualAssertionIDs
    self.expectedPassageIDs = expectedPassageIDs
    self.actualPassageIDs = actualPassageIDs
    self.detail = detail
    self.passed = passed
  }
}

public struct KnowledgeCorrectnessReplayAudit: Codable, Equatable, Sendable {
  public let benchmarkName: String
  public let verdict: KnowledgeProofVerdict
  public let scenarioCount: Int
  public let passedScenarioCount: Int
  public let crossPackScenarioCount: Int
  public let passedCrossPackScenarioCount: Int
  public let falseCardCount: Int
  public let failedScenarioIDs: [String]

  public init(
    benchmarkName: String,
    verdict: KnowledgeProofVerdict,
    scenarioCount: Int,
    passedScenarioCount: Int,
    crossPackScenarioCount: Int,
    passedCrossPackScenarioCount: Int,
    falseCardCount: Int,
    failedScenarioIDs: [String]
  ) {
    self.benchmarkName = benchmarkName
    self.verdict = verdict
    self.scenarioCount = scenarioCount
    self.passedScenarioCount = passedScenarioCount
    self.crossPackScenarioCount = crossPackScenarioCount
    self.passedCrossPackScenarioCount = passedCrossPackScenarioCount
    self.falseCardCount = falseCardCount
    self.failedScenarioIDs = failedScenarioIDs
  }
}

public struct KnowledgeCorrectnessGateReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let gateName: String
  public let verdict: KnowledgeProofVerdict
  public let checks: [KnowledgeProofCheck]
  public let packAudits: [KnowledgeCorrectnessPackAudit]
  public let outcomeAudits: [KnowledgeCorrectnessOutcomeAudit]
  public let replayAudit: KnowledgeCorrectnessReplayAudit?

  public init(
    schemaVersion: Int = currentSchemaVersion,
    gateName: String,
    verdict: KnowledgeProofVerdict,
    checks: [KnowledgeProofCheck],
    packAudits: [KnowledgeCorrectnessPackAudit],
    outcomeAudits: [KnowledgeCorrectnessOutcomeAudit],
    replayAudit: KnowledgeCorrectnessReplayAudit?
  ) {
    self.schemaVersion = schemaVersion
    self.gateName = gateName
    self.verdict = verdict
    self.checks = checks
    self.packAudits = packAudits
    self.outcomeAudits = outcomeAudits
    self.replayAudit = replayAudit
  }
}

public enum KnowledgeCorrectnessGateValidationError: Error, Equatable,
  CustomStringConvertible
{
  case unsupportedSchema(Int)
  case emptyName
  case unsafeBenchmarkPath
  case invalidMinimumCrossPackScenarioCount
  case noPacks
  case duplicatePackID(String)
  case unsafePackPath(String)
  case malformedFingerprint(String)
  case emptyProbeID(Int)
  case duplicateProbeID(String)
  case unknownProbePack(probeID: String, packID: String)
  case incompleteEvidenceStateCoverage([KnowledgeEvidenceState])
  case benchmarkPackMismatch
  case missingLoadedPack(String)
  case loadedPackIDMismatch(expected: String, actual: String)

  public var description: String {
    switch self {
    case .unsupportedSchema(let version):
      "Correctness gate schema \(version) is unsupported; expected \(KnowledgeCorrectnessGateSpec.currentSchemaVersion)."
    case .emptyName:
      "Correctness gate name must not be empty."
    case .unsafeBenchmarkPath:
      "Correctness gate benchmark path must be a safe relative path."
    case .invalidMinimumCrossPackScenarioCount:
      "Correctness gate minimum cross-pack scenario count must be greater than zero."
    case .noPacks:
      "Correctness gate requires at least one KnowledgePack."
    case .duplicatePackID(let packID):
      "Correctness gate declares pack ID '\(packID)' more than once."
    case .unsafePackPath(let packID):
      "Correctness gate pack '\(packID)' must use a safe relative path."
    case .malformedFingerprint(let packID):
      "Correctness gate pack '\(packID)' contains a malformed SHA-256 fingerprint."
    case .emptyProbeID(let index):
      "Correctness outcome probe \(index + 1) has an empty ID."
    case .duplicateProbeID(let probeID):
      "Correctness outcome probe ID '\(probeID)' is duplicated."
    case .unknownProbePack(let probeID, let packID):
      "Correctness outcome probe '\(probeID)' references unknown pack '\(packID)'."
    case .incompleteEvidenceStateCoverage(let states):
      "Correctness outcome probes do not cover: \(states.map(\.rawValue).sorted().joined(separator: ", "))."
    case .benchmarkPackMismatch:
      "Correctness gate and replay benchmark must reference the same pack IDs and paths."
    case .missingLoadedPack(let packID):
      "Correctness gate did not receive loaded pack '\(packID)'."
    case .loadedPackIDMismatch(let expected, let actual):
      "Correctness gate expected pack '\(expected)' but loaded '\(actual)'."
    }
  }
}

/// Runs the release-level correctness contract independently of model output. The gate validates
/// immutable pack content, card-to-evidence closure, all evidence outcome labels, and the multi-pack
/// replay corpus before returning PASS.
public struct KnowledgeCorrectnessGateRunner: Sendable {
  private let packs: [String: KnowledgeReplayBenchmarkPack]
  private let loader: KnowledgePackLoader

  public init(
    packs: [String: KnowledgeReplayBenchmarkPack],
    profileRegistry: KnowledgeDomainProfileRegistry = .empty
  ) {
    self.packs = packs
    loader = KnowledgePackLoader(profileRegistry: profileRegistry)
  }

  public func run(
    _ spec: KnowledgeCorrectnessGateSpec,
    benchmark: KnowledgeReplayBenchmarkSpec
  ) throws -> KnowledgeCorrectnessGateReport {
    try validate(spec, benchmark: benchmark)

    let packAudits = try spec.packs.map { reference -> KnowledgeCorrectnessPackAudit in
      guard let configured = packs[reference.packID] else {
        throw KnowledgeCorrectnessGateValidationError.missingLoadedPack(reference.packID)
      }
      guard configured.pack.manifest.packID == reference.packID else {
        throw KnowledgeCorrectnessGateValidationError.loadedPackIDMismatch(
          expected: reference.packID,
          actual: configured.pack.manifest.packID
        )
      }
      return audit(reference, configured: configured)
    }

    let runnablePackIDs = Set(
      zip(spec.packs, packAudits).compactMap { reference, audit in
        audit.findings.contains(where: {
          $0.severity == "error"
            && ($0.code.hasPrefix("loader.") || $0.code.hasPrefix("source."))
        }) ? nil : reference.packID
      })
    let outcomeAudits = spec.outcomeProbes.map { probe in
      guard runnablePackIDs.contains(probe.packID), let configured = packs[probe.packID] else {
        return failedProbe(probe, detail: "Pack validation failed; outcome probe was not run.")
      }
      return audit(probe, configured: configured)
    }

    let replayReport: KnowledgeReplayBenchmarkReport?
    if runnablePackIDs.count == spec.packs.count {
      replayReport = try KnowledgeReplayBenchmarkRunner(packs: packs).run(benchmark)
    } else {
      replayReport = nil
    }
    let replayAudit = replayReport.map(Self.replayAudit)

    let structurePassed = packAudits.allSatisfy {
      !$0.findings.contains {
        $0.severity == "error"
          && ($0.code.hasPrefix("loader.") || $0.code.hasPrefix("source."))
      }
    }
    let fingerprintsPassed = packAudits.allSatisfy {
      $0.actualFingerprints != nil && $0.fingerprintChecks.allSatisfy(\.passed)
    }
    let citationsPassed = packAudits.allSatisfy {
      !$0.findings.contains {
        $0.severity == "error"
          && ($0.code.hasPrefix("citation.") || $0.code.hasPrefix("card.provenance"))
      }
    }
    let calculationsPassed = packAudits.allSatisfy {
      !$0.findings.contains {
        $0.severity == "error"
          && ($0.code.contains("calculation") || $0.code == "fingerprint.calculations")
      }
    }
    let outcomesPassed = outcomeAudits.allSatisfy(\.passed)
    let actualStates = Set(outcomeAudits.compactMap(\.actualState))
    let stateCoveragePassed = actualStates == Set(KnowledgeEvidenceState.allCases) && outcomesPassed
    let replayPassed = replayReport?.verdict == .pass
    let crossPackReports =
      replayReport?.scenarios.filter {
        $0.categories.contains(.crossPack)
      } ?? []
    let crossPackPassed =
      crossPackReports.count >= spec.minimumCrossPackScenarioCount
      && crossPackReports.allSatisfy { $0.verdict == .pass && $0.finalResponseCardID == nil }

    let checks = [
      KnowledgeProofCheck(
        name: "pack_structure",
        passed: structurePassed,
        detail: structurePassed
          ? "Every pack passed structural, profile, source-file, and reference validation."
          : "One or more packs failed structural or profile validation."
      ),
      KnowledgeProofCheck(
        name: "golden_pack_content",
        passed: fingerprintsPassed,
        detail: fingerprintsPassed
          ? "Every category fingerprint matched its reviewed golden pack."
          : "One or more reviewed pack category fingerprints changed."
      ),
      KnowledgeProofCheck(
        name: "citation_resolution",
        passed: citationsPassed,
        detail: citationsPassed
          ? "Every non-abstention card resolved pack-local citations covering its claims."
          : "One or more cards had missing, unsafe, or unrelated claim citations."
      ),
      KnowledgeProofCheck(
        name: "calculation_accuracy",
        passed: calculationsPassed,
        detail: calculationsPassed
          ? "Every registered calculation retained valid inputs, context, units, and output."
          : "One or more deterministic calculations failed closed."
      ),
      KnowledgeProofCheck(
        name: "assertion_and_outcome_fidelity",
        passed: outcomesPassed,
        detail:
          "\(outcomeAudits.filter(\.passed).count) of \(outcomeAudits.count) golden outcome probes passed."
      ),
      KnowledgeProofCheck(
        name: "evidence_state_coverage",
        passed: stateCoveragePassed,
        detail: stateCoveragePassed
          ? "All eight evidence states were produced with their expected reason and evidence."
          : "The outcome probes did not reproduce all eight expected evidence states."
      ),
      KnowledgeProofCheck(
        name: "replay_ground_truth",
        passed: replayPassed,
        detail: replayReport.map {
          "\($0.passedScenarioCount) of \($0.scenarioCount) conversation scenarios passed."
        } ?? "Replay was not run because a pack failed validation."
      ),
      KnowledgeProofCheck(
        name: "cross_pack_isolation",
        passed: crossPackPassed,
        detail:
          "\(crossPackReports.filter { $0.verdict == .pass && $0.finalResponseCardID == nil }.count) of \(crossPackReports.count) cross-pack scenarios abstained without leaking a card; minimum is \(spec.minimumCrossPackScenarioCount)."
      ),
    ]
    return KnowledgeCorrectnessGateReport(
      gateName: spec.name,
      verdict: checks.allSatisfy(\.passed) ? .pass : .fail,
      checks: checks,
      packAudits: packAudits,
      outcomeAudits: outcomeAudits,
      replayAudit: replayAudit
    )
  }

  private func audit(
    _ reference: KnowledgeCorrectnessPackReference,
    configured: KnowledgeReplayBenchmarkPack
  ) -> KnowledgeCorrectnessPackAudit {
    let pack = configured.pack
    let validation = loader.validate(pack)
    var findings = validation.issues.map {
      KnowledgeCorrectnessFinding(
        severity: $0.severity.rawValue,
        code: "loader.\($0.code)",
        packID: reference.packID,
        detail: $0.message
      )
    }
    findings.append(contentsOf: auditSourceFiles(in: configured))
    findings.append(contentsOf: auditCards(in: configured))

    let actualFingerprints = try? KnowledgeCorrectnessFingerprints.make(for: pack)
    let fingerprintChecks: [KnowledgeProofCheck]
    if let actualFingerprints {
      fingerprintChecks = reference.expectedFingerprints.checks(against: actualFingerprints)
      for check in fingerprintChecks where !check.passed {
        findings.append(
          KnowledgeCorrectnessFinding(
            severity: "error",
            code: "fingerprint.\(check.name)",
            packID: reference.packID,
            detail: check.detail
          ))
      }
    } else {
      fingerprintChecks = [
        KnowledgeProofCheck(
          name: "pack_content",
          passed: false,
          detail: "Pack content could not be canonicalized because references were unresolved.")
      ]
      findings.append(
        KnowledgeCorrectnessFinding(
          severity: "error",
          code: "fingerprint.unavailable",
          packID: reference.packID,
          detail: "Pack content could not be canonicalized because references were unresolved."
        ))
    }

    let verdict: KnowledgeProofVerdict =
      findings.contains(where: { $0.severity == "error" }) ? .fail : .pass
    return KnowledgeCorrectnessPackAudit(
      packID: reference.packID,
      expectedFingerprints: reference.expectedFingerprints,
      actualFingerprints: actualFingerprints,
      fingerprintChecks: fingerprintChecks,
      findings: findings,
      sourceCount: pack.sources.count,
      passageCount: pack.passages.count,
      assertionCount: pack.assertions.count,
      calculationCount: pack.calculations.count,
      responseCardCount: pack.responseCards.count,
      citationCount: Set(pack.responseCards.flatMap(\.citationPassageIDs)).count,
      verdict: verdict
    )
  }

  private func auditCards(
    in configured: KnowledgeReplayBenchmarkPack
  ) -> [KnowledgeCorrectnessFinding] {
    let pack = configured.pack
    let assertions = Dictionary(
      pack.assertions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let passages = Dictionary(
      pack.passages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let sources = Dictionary(
      pack.sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let evidence = Dictionary(
      pack.evidenceLinks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let calculations = Dictionary(
      pack.calculations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var findings: [KnowledgeCorrectnessFinding] = []

    for card in pack.responseCards {
      let cited = Set(card.citationPassageIDs)
      let abstains =
        card.evidenceState == .notFoundInCorpus
        || card.evidenceState == .needsClarification
      if abstains && (!card.assertionIDs.isEmpty || !cited.isEmpty || !card.calculationIDs.isEmpty)
      {
        findings.append(
          finding(
            "card.abstention_has_evidence", card: card, packID: pack.manifest.packID,
            "Abstention cards must not carry claims, calculations, or citations."))
      }

      for passageID in cited {
        guard let passage = passages[passageID], let source = sources[passage.sourceID] else {
          findings.append(
            finding(
              "citation.unresolved", card: card, packID: pack.manifest.packID,
              "Citation '\(passageID)' does not resolve inside the active pack."))
          continue
        }
        let fileURL = configured.rootDirectory.appendingPathComponent(source.relativePath)
          .standardizedFileURL.resolvingSymlinksInPath()
        if !Self.isInside(fileURL, root: configured.rootDirectory)
          || !FileManager.default.fileExists(atPath: fileURL.path)
        {
          findings.append(
            finding(
              "citation.unsafe_or_missing_file", card: card, packID: pack.manifest.packID,
              "Citation '\(passageID)' does not resolve to an existing pack-local source file."))
        }
      }

      for assertionID in card.assertionIDs {
        guard assertions[assertionID] != nil else { continue }
        let attributable = attributablePassageIDs(
          assertionID: assertionID,
          assertions: assertions,
          evidence: evidence,
          calculations: calculations,
          visited: []
        )
        let missing = attributable.subtracting(cited)
        if !missing.isEmpty {
          findings.append(
            finding(
              "card.provenance_not_cited", card: card, packID: pack.manifest.packID,
              "Claim '\(assertionID)' omits attributable citation(s): \(missing.sorted().joined(separator: ", "))."
            ))
        }
      }

      let claimedAssertions = card.assertionIDs.compactMap { assertions[$0] }
      switch card.evidenceState {
      case .directlySourced:
        if claimedAssertions.isEmpty || claimedAssertions.contains(where: { $0.kind != .stated })
          || !card.calculationIDs.isEmpty
        {
          findings.append(
            finding(
              "card.evidence_state_mismatch", card: card, packID: pack.manifest.packID,
              "Directly sourced cards must claim only stated assertions and no calculations."))
        }
      case .calculated:
        if card.calculationIDs.isEmpty
          || claimedAssertions.contains(where: { $0.kind != .calculated })
        {
          findings.append(
            finding(
              "card.evidence_state_mismatch", card: card, packID: pack.manifest.packID,
              "Calculated cards must claim calculated outputs with recorded derivations."))
        }
      case .contested:
        let signatures = Set(claimedAssertions.map(Self.assertionSignature))
        if claimedAssertions.count < 2 || signatures.count < 2 {
          findings.append(
            finding(
              "card.evidence_state_mismatch", card: card, packID: pack.manifest.packID,
              "Contested cards must retain at least two distinguishable claims."))
        }
      case .interpretive:
        if !claimedAssertions.contains(where: { $0.kind == .interpretive }) {
          findings.append(
            finding(
              "card.evidence_state_mismatch", card: card, packID: pack.manifest.packID,
              "Interpretive cards must explicitly claim an interpretive assertion."))
        }
      case .contradictedByCorpus, .supportedByCorpus:
        if claimedAssertions.isEmpty {
          findings.append(
            finding(
              "card.evidence_state_mismatch", card: card, packID: pack.manifest.packID,
              "Factual evidence cards must claim at least one typed assertion."))
        }
      case .notFoundInCorpus, .needsClarification:
        break
      }
    }
    return findings
  }

  private func auditSourceFiles(
    in configured: KnowledgeReplayBenchmarkPack
  ) -> [KnowledgeCorrectnessFinding] {
    var findings: [KnowledgeCorrectnessFinding] = []
    for source in configured.pack.sources {
      let fileURL = configured.rootDirectory.appendingPathComponent(source.relativePath)
        .standardizedFileURL.resolvingSymlinksInPath()
      var isDirectory: ObjCBool = false
      guard Self.isInside(fileURL, root: configured.rootDirectory),
        FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      else {
        findings.append(
          KnowledgeCorrectnessFinding(
            severity: "error",
            code: "source.unsafe_or_missing_file",
            packID: configured.pack.manifest.packID,
            recordID: source.id,
            detail: "Source does not resolve to an existing regular file inside the active pack."
          ))
        continue
      }
      do {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if actualHash != source.sha256 {
          findings.append(
            KnowledgeCorrectnessFinding(
              severity: "error",
              code: "source.hash_mismatch",
              packID: configured.pack.manifest.packID,
              recordID: source.id,
              detail: "Source bytes do not match the reviewed SHA-256."
            ))
        }
      } catch {
        findings.append(
          KnowledgeCorrectnessFinding(
            severity: "error",
            code: "source.unreadable_file",
            packID: configured.pack.manifest.packID,
            recordID: source.id,
            detail:
              "Source could not be read for SHA-256 verification: \(error.localizedDescription)"
          ))
      }
    }
    return findings
  }

  private func audit(
    _ probe: KnowledgeCorrectnessOutcomeProbe,
    configured: KnowledgeReplayBenchmarkPack
  ) -> KnowledgeCorrectnessOutcomeAudit {
    do {
      let evaluator = try KnowledgeEvidenceOutcomeEvaluator(
        pack: configured.pack,
        searchIndex: KnowledgePackSearchIndex(pack: configured.pack),
        rootDirectory: configured.rootDirectory
      )
      let outcome = try evaluator.evaluate(probe.query)
      let actualAssertionIDs = outcome.claims.map(\.assertionID).sorted()
      let actualPassageIDs = outcome.contributingSources.map(\.passageID).sorted()
      let passed =
        outcome.packID == probe.packID
        && outcome.state == probe.expectedState
        && outcome.reason == probe.expectedReason
        && actualAssertionIDs == probe.expectedAssertionIDs.sorted()
        && actualPassageIDs == probe.expectedPassageIDs.sorted()
        && outcome.contributingSources.allSatisfy {
          Self.isInside($0.fileURL, root: configured.rootDirectory)
            && FileManager.default.fileExists(atPath: $0.fileURL.path)
        }
      return KnowledgeCorrectnessOutcomeAudit(
        id: probe.id,
        packID: probe.packID,
        expectedState: probe.expectedState,
        actualState: outcome.state,
        expectedReason: probe.expectedReason,
        actualReason: outcome.reason,
        expectedAssertionIDs: probe.expectedAssertionIDs.sorted(),
        actualAssertionIDs: actualAssertionIDs,
        expectedPassageIDs: probe.expectedPassageIDs.sorted(),
        actualPassageIDs: actualPassageIDs,
        detail: passed
          ? "State, reason, assertions, and pack-local citations matched."
          : "State, reason, assertions, or pack-local citations differed.",
        passed: passed
      )
    } catch {
      return failedProbe(probe, detail: "Outcome probe failed closed: \(error)")
    }
  }

  private func failedProbe(
    _ probe: KnowledgeCorrectnessOutcomeProbe,
    detail: String
  ) -> KnowledgeCorrectnessOutcomeAudit {
    KnowledgeCorrectnessOutcomeAudit(
      id: probe.id,
      packID: probe.packID,
      expectedState: probe.expectedState,
      actualState: nil,
      expectedReason: probe.expectedReason,
      actualReason: nil,
      expectedAssertionIDs: probe.expectedAssertionIDs.sorted(),
      actualAssertionIDs: [],
      expectedPassageIDs: probe.expectedPassageIDs.sorted(),
      actualPassageIDs: [],
      detail: detail,
      passed: false
    )
  }

  private func validate(
    _ spec: KnowledgeCorrectnessGateSpec,
    benchmark: KnowledgeReplayBenchmarkSpec
  ) throws {
    guard spec.schemaVersion == KnowledgeCorrectnessGateSpec.currentSchemaVersion else {
      throw KnowledgeCorrectnessGateValidationError.unsupportedSchema(spec.schemaVersion)
    }
    guard !spec.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw KnowledgeCorrectnessGateValidationError.emptyName
    }
    guard Self.isSafeRelativePath(spec.benchmarkRelativePath) else {
      throw KnowledgeCorrectnessGateValidationError.unsafeBenchmarkPath
    }
    guard spec.minimumCrossPackScenarioCount > 0 else {
      throw KnowledgeCorrectnessGateValidationError.invalidMinimumCrossPackScenarioCount
    }
    guard !spec.packs.isEmpty else { throw KnowledgeCorrectnessGateValidationError.noPacks }

    var packIDs: Set<String> = []
    for reference in spec.packs {
      guard packIDs.insert(reference.packID).inserted else {
        throw KnowledgeCorrectnessGateValidationError.duplicatePackID(reference.packID)
      }
      guard Self.isSafeRelativePath(reference.relativePath) else {
        throw KnowledgeCorrectnessGateValidationError.unsafePackPath(reference.packID)
      }
      guard reference.expectedFingerprints.isWellFormed else {
        throw KnowledgeCorrectnessGateValidationError.malformedFingerprint(reference.packID)
      }
    }

    var probeIDs: Set<String> = []
    for (index, probe) in spec.outcomeProbes.enumerated() {
      guard !probe.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw KnowledgeCorrectnessGateValidationError.emptyProbeID(index)
      }
      guard probeIDs.insert(probe.id).inserted else {
        throw KnowledgeCorrectnessGateValidationError.duplicateProbeID(probe.id)
      }
      guard packIDs.contains(probe.packID) else {
        throw KnowledgeCorrectnessGateValidationError.unknownProbePack(
          probeID: probe.id, packID: probe.packID)
      }
    }
    let missingStates = Set(KnowledgeEvidenceState.allCases).subtracting(
      spec.outcomeProbes.map(\.expectedState))
    guard missingStates.isEmpty else {
      throw KnowledgeCorrectnessGateValidationError.incompleteEvidenceStateCoverage(
        Array(missingStates))
    }

    let correctnessPacks = Set(spec.packs.map { "\($0.packID)|\($0.relativePath)" })
    let benchmarkPacks = Set(benchmark.packs.map { "\($0.packID)|\($0.relativePath)" })
    guard correctnessPacks == benchmarkPacks else {
      throw KnowledgeCorrectnessGateValidationError.benchmarkPackMismatch
    }
  }

  private func attributablePassageIDs(
    assertionID: String,
    assertions: [String: KnowledgeAssertion],
    evidence: [String: KnowledgeEvidenceLink],
    calculations: [String: KnowledgeCalculation],
    visited: Set<String>
  ) -> Set<String> {
    guard !visited.contains(assertionID), let assertion = assertions[assertionID] else { return [] }
    let direct = Set(assertion.evidenceLinkIDs.compactMap { evidence[$0]?.passageID })
    let nextVisited = visited.union([assertionID])
    let derived = calculations.values
      .filter { $0.outputAssertionID == assertionID }
      .flatMap(\.inputAssertionIDs)
      .reduce(into: Set<String>()) { result, inputID in
        result.formUnion(
          attributablePassageIDs(
            assertionID: inputID,
            assertions: assertions,
            evidence: evidence,
            calculations: calculations,
            visited: nextVisited
          ))
      }
    return direct.union(derived)
  }

  private func finding(
    _ code: String,
    card: KnowledgeResponseCard,
    packID: String,
    _ detail: String
  ) -> KnowledgeCorrectnessFinding {
    KnowledgeCorrectnessFinding(
      severity: "error",
      code: code,
      packID: packID,
      recordID: card.id,
      detail: detail
    )
  }

  private static func assertionSignature(_ assertion: KnowledgeAssertion) -> String {
    let value: String
    switch assertion.value.type {
    case .text: value = assertion.value.text ?? ""
    case .number:
      value =
        "\(assertion.value.number ?? .nan)|\(assertion.value.unit ?? "")|\(assertion.value.scale ?? .nan)"
    case .boolean: value = assertion.value.boolean.map(String.init) ?? ""
    case .date: value = assertion.value.date ?? ""
    case .reference: value = assertion.value.referenceID ?? ""
    }
    let qualifiers = assertion.qualifiers.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    return "\(assertion.subject)|\(assertion.predicate)|\(value)|\(qualifiers)"
  }

  private static func replayAudit(
    _ report: KnowledgeReplayBenchmarkReport
  ) -> KnowledgeCorrectnessReplayAudit {
    let crossPack = report.scenarios.filter { $0.categories.contains(.crossPack) }
    return KnowledgeCorrectnessReplayAudit(
      benchmarkName: report.benchmarkName,
      verdict: report.verdict,
      scenarioCount: report.scenarioCount,
      passedScenarioCount: report.passedScenarioCount,
      crossPackScenarioCount: crossPack.count,
      passedCrossPackScenarioCount: crossPack.filter { $0.verdict == .pass }.count,
      falseCardCount: report.falseCardCount,
      failedScenarioIDs: report.scenarios.filter { $0.verdict == .fail }.map(\.id)
    )
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
    return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
  }

  private static func isInside(_ fileURL: URL, root: URL) -> Bool {
    let normalizedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
    let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    let rootPath =
      normalizedRoot.path.hasSuffix("/") ? normalizedRoot.path : normalizedRoot.path + "/"
    return normalizedFile.path.hasPrefix(rootPath)
  }
}
