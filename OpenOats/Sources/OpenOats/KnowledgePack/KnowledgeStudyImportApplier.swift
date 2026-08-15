import CryptoKit
import Darwin
import Foundation

public enum KnowledgeStudyImportPlanState: String, Codable, Equatable, Sendable {
  case ready
  case alreadyApplied = "already_applied"
  case noChanges = "no_changes"
}

public struct KnowledgeStudyImportPlan: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let state: KnowledgeStudyImportPlanState
  public let importID: String
  public let packID: String
  public let activePackContentHash: String
  public let basePackContentHash: String
  public let resultingPackContentHash: String
  public let approvedQuestionFamilyIDs: [String]
  public let approvedResponseCardIDs: [String]
  public let rejectedProposalCount: Int

  public init(
    schemaVersion: Int,
    state: KnowledgeStudyImportPlanState,
    importID: String,
    packID: String,
    activePackContentHash: String,
    basePackContentHash: String,
    resultingPackContentHash: String,
    approvedQuestionFamilyIDs: [String],
    approvedResponseCardIDs: [String],
    rejectedProposalCount: Int
  ) {
    self.schemaVersion = schemaVersion
    self.state = state
    self.importID = importID
    self.packID = packID
    self.activePackContentHash = activePackContentHash
    self.basePackContentHash = basePackContentHash
    self.resultingPackContentHash = resultingPackContentHash
    self.approvedQuestionFamilyIDs = approvedQuestionFamilyIDs
    self.approvedResponseCardIDs = approvedResponseCardIDs
    self.rejectedProposalCount = rejectedProposalCount
  }
}

public enum KnowledgeStudyImportOutcome: String, Codable, Equatable, Sendable {
  case applied
  case alreadyApplied = "already_applied"
  case noChanges = "no_changes"
}

public struct KnowledgeStudyImportReceipt: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let outcome: KnowledgeStudyImportOutcome
  public let importID: String
  public let packID: String
  public let previousPackContentHash: String
  public let resultingPackContentHash: String
  public let appliedAt: Date
  public let approvedQuestionFamilyIDs: [String]
  public let approvedResponseCardIDs: [String]
  public let reviewer: String
  public let reviewedAt: Date
  public let recoveredInterruptedTransaction: Bool

  public init(
    schemaVersion: Int,
    outcome: KnowledgeStudyImportOutcome,
    importID: String,
    packID: String,
    previousPackContentHash: String,
    resultingPackContentHash: String,
    appliedAt: Date,
    approvedQuestionFamilyIDs: [String],
    approvedResponseCardIDs: [String],
    reviewer: String,
    reviewedAt: Date,
    recoveredInterruptedTransaction: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.outcome = outcome
    self.importID = importID
    self.packID = packID
    self.previousPackContentHash = previousPackContentHash
    self.resultingPackContentHash = resultingPackContentHash
    self.appliedAt = appliedAt
    self.approvedQuestionFamilyIDs = approvedQuestionFamilyIDs
    self.approvedResponseCardIDs = approvedResponseCardIDs
    self.reviewer = reviewer
    self.reviewedAt = reviewedAt
    self.recoveredInterruptedTransaction = recoveredInterruptedTransaction
  }
}

public enum KnowledgeStudyImportApplicationError: Error, CustomStringConvertible {
  case unsupportedSchema(actual: Int, expected: Int)
  case identityMismatch(field: String, expected: String, actual: String)
  case invalidIdentity(field: String)
  case invalidContentHash(field: String)
  case invalidReviewer
  case invalidDecision(proposalID: String, reason: String)
  case duplicateDecision(kind: KnowledgeStudyProposalKind, id: String)
  case approvedRecordsDoNotMatchDecisions(kind: KnowledgeStudyProposalKind)
  case rejectedDecisionsDoNotMatch
  case responseCardNotReviewed(id: String)
  case nonCanonicalArtifact(field: String)
  case stalePack(expected: String, actual: String)
  case resultingHashMismatch(expected: String, actual: String)
  case mergedPackInvalid(KnowledgePackValidationReport)
  case packBusy
  case lockUnavailable(String)
  case transactionRecoveryFailed(String)
  case transactionFailed(String)

  public var description: String {
    switch self {
    case .unsupportedSchema(let actual, let expected):
      return "Approved import schema \(actual) is unsupported; expected \(expected)."
    case .identityMismatch(let field, let expected, let actual):
      return "Approved import \(field) '\(actual)' does not match expected '\(expected)'."
    case .invalidIdentity(let field):
      return "Approved import \(field) must be normalized, non-empty text."
    case .invalidContentHash(let field):
      return "Approved import \(field) must be a lowercase SHA-256 hash."
    case .invalidReviewer:
      return
        "Approved import reviewer must be normalized, non-empty text of at most 200 characters."
    case .invalidDecision(let proposalID, let reason):
      return "Approved import decision for '\(proposalID)' is invalid: \(reason)"
    case .duplicateDecision(let kind, let id):
      return "Approved import repeats the \(kind.rawValue) decision for '\(id)'."
    case .approvedRecordsDoNotMatchDecisions(let kind):
      return
        "Approved \(kind.rawValue) records do not exactly match the explicit approval decisions."
    case .rejectedDecisionsDoNotMatch:
      return "Rejected decisions do not exactly match the rejected subset of all review decisions."
    case .responseCardNotReviewed(let id):
      return "Approved response card '\(id)' is not marked reviewed."
    case .nonCanonicalArtifact(let field):
      return "Approved import \(field) is not in deterministic canonical order."
    case .stalePack(let expected, let actual):
      return "Approved import is stale: expected active pack hash \(expected), found \(actual)."
    case .resultingHashMismatch(let expected, let actual):
      return "Approved import result hash mismatch: expected \(expected), calculated \(actual)."
    case .mergedPackInvalid(let report):
      return report.errors.map(\.description).joined(separator: "\n")
    case .packBusy:
      return "Another approved-import transaction currently holds the KnowledgePack lock."
    case .lockUnavailable(let message):
      return "The KnowledgePack transaction lock could not be opened: \(message)"
    case .transactionRecoveryFailed(let message):
      return "Approved-import transaction recovery failed: \(message)"
    case .transactionFailed(let message):
      return "Approved-import transaction failed and was rolled back: \(message)"
    }
  }
}

public struct KnowledgeStudyImportApplier: Sendable {
  public static let schemaVersion = 1

  private static let questionFileName = "question-families.jsonl"
  private static let responseFileName = "response-cards.jsonl"
  private static let journalFileName = ".knowledge-copilot-study-import-transaction.json"
  private static let lockFileName = ".knowledge-copilot-study-import.lock"

  private let profileRegistry: KnowledgeDomainProfileRegistry
  private let now: @Sendable () -> Date
  private let mutationHook: @Sendable (KnowledgeStudyImportMutationStep) throws -> Void

  public init(profileRegistry: KnowledgeDomainProfileRegistry = .empty) {
    self.init(profileRegistry: profileRegistry, now: Date.init, mutationHook: { _ in })
  }

  init(
    profileRegistry: KnowledgeDomainProfileRegistry,
    now: @escaping @Sendable () -> Date,
    mutationHook: @escaping @Sendable (KnowledgeStudyImportMutationStep) throws -> Void
  ) {
    self.profileRegistry = profileRegistry
    self.now = now
    self.mutationHook = mutationHook
  }

  public func plan(
    approvedImport: KnowledgeStudyApprovedImport,
    packDirectory: URL
  ) throws -> KnowledgeStudyImportPlan {
    let directory = packDirectory.standardizedFileURL
    guard !FileManager.default.fileExists(atPath: journalURL(in: directory).path) else {
      throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
        "an interrupted transaction journal exists; call apply to recover it while holding the pack lock"
      )
    }
    let pack = try loader.load(from: directory)
    return try makePlan(approvedImport: approvedImport, pack: pack)
  }

  public func apply(
    approvedImport: KnowledgeStudyApprovedImport,
    to packDirectory: URL
  ) throws -> KnowledgeStudyImportReceipt {
    let directory = packDirectory.standardizedFileURL
    let lock = try KnowledgeStudyImportLock(
      url: directory.appendingPathComponent(Self.lockFileName)
    )
    defer { lock.unlock() }

    let recovered = try recoverIfNeeded(in: directory)
    let initialPack = try loader.load(from: directory)
    let plan = try makePlan(approvedImport: approvedImport, pack: initialPack)

    switch plan.state {
    case .alreadyApplied:
      return receipt(
        for: approvedImport,
        plan: plan,
        outcome: .alreadyApplied,
        recovered: recovered
      )
    case .noChanges:
      return receipt(
        for: approvedImport,
        plan: plan,
        outcome: .noChanges,
        recovered: recovered
      )
    case .ready:
      break
    }

    // Re-read under the exclusive lock immediately before staging any mutation.
    let currentPack = try loader.load(from: directory)
    let currentHash = try contentHash(for: currentPack)
    guard currentHash == approvedImport.basePackContentHash else {
      throw KnowledgeStudyImportApplicationError.stalePack(
        expected: approvedImport.basePackContentHash,
        actual: currentHash
      )
    }

    let transaction = KnowledgeStudyImportTransaction.make(
      importID: approvedImport.importID,
      basePackContentHash: approvedImport.basePackContentHash,
      resultingPackContentHash: approvedImport.resultingPackContentHash
    )
    do {
      try writeJournal(transaction, in: directory)
      try stage(
        currentURL: directory.appendingPathComponent(Self.questionFileName),
        stagedURL: directory.appendingPathComponent(transaction.questionStagedFileName),
        additions: approvedImport.approvedQuestionFamilies
      )
      try stage(
        currentURL: directory.appendingPathComponent(Self.responseFileName),
        stagedURL: directory.appendingPathComponent(transaction.responseStagedFileName),
        additions: approvedImport.approvedResponseCards
      )
      try mutationHook(.staged)

      try install(
        currentFileName: Self.questionFileName,
        stagedFileName: transaction.questionStagedFileName,
        backupFileName: transaction.questionBackupFileName,
        in: directory
      )
      try mutationHook(.questionFamiliesInstalled)
      try install(
        currentFileName: Self.responseFileName,
        stagedFileName: transaction.responseStagedFileName,
        backupFileName: transaction.responseBackupFileName,
        in: directory
      )
      try mutationHook(.responseCardsInstalled)

      let installedPack = try loader.load(from: directory)
      let installedHash = try contentHash(for: installedPack)
      guard installedHash == approvedImport.resultingPackContentHash else {
        throw KnowledgeStudyImportApplicationError.resultingHashMismatch(
          expected: approvedImport.resultingPackContentHash,
          actual: installedHash
        )
      }
    } catch {
      do {
        try rollback(transaction, in: directory)
      } catch let recoveryError {
        throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
          "\(error); rollback error: \(recoveryError)"
        )
      }
      throw KnowledgeStudyImportApplicationError.transactionFailed(String(describing: error))
    }

    do {
      try finish(transaction, in: directory)
    } catch {
      throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
        "the import was committed, but transaction cleanup did not finish: \(error)"
      )
    }

    return receipt(for: approvedImport, plan: plan, outcome: .applied, recovered: recovered)
  }

  private var loader: KnowledgePackLoader {
    KnowledgePackLoader(profileRegistry: profileRegistry)
  }

  private func makePlan(
    approvedImport: KnowledgeStudyApprovedImport,
    pack: KnowledgePack
  ) throws -> KnowledgeStudyImportPlan {
    try validateArtifact(approvedImport)
    guard pack.manifest.packID == approvedImport.packID else {
      throw KnowledgeStudyImportApplicationError.identityMismatch(
        field: "packID",
        expected: pack.manifest.packID,
        actual: approvedImport.packID
      )
    }

    let currentHash = try contentHash(for: pack)
    let questionIDs = approvedImport.approvedQuestionFamilies.map(\.id)
    let responseIDs = approvedImport.approvedResponseCards.map(\.id)
    let state: KnowledgeStudyImportPlanState
    if approvedImport.basePackContentHash == approvedImport.resultingPackContentHash,
      questionIDs.isEmpty,
      responseIDs.isEmpty,
      currentHash == approvedImport.basePackContentHash
    {
      state = .noChanges
    } else if currentHash == approvedImport.resultingPackContentHash,
      recordsAlreadyPresent(approvedImport, in: pack)
    {
      state = .alreadyApplied
    } else {
      guard currentHash == approvedImport.basePackContentHash else {
        throw KnowledgeStudyImportApplicationError.stalePack(
          expected: approvedImport.basePackContentHash,
          actual: currentHash
        )
      }
      let mergedPack = merge(approvedImport, into: pack)
      let report = loader.validate(mergedPack)
      guard report.isValid else {
        throw KnowledgeStudyImportApplicationError.mergedPackInvalid(report)
      }
      let calculatedHash = try contentHash(for: mergedPack)
      guard calculatedHash == approvedImport.resultingPackContentHash else {
        throw KnowledgeStudyImportApplicationError.resultingHashMismatch(
          expected: approvedImport.resultingPackContentHash,
          actual: calculatedHash
        )
      }
      state = .ready
    }

    return KnowledgeStudyImportPlan(
      schemaVersion: Self.schemaVersion,
      state: state,
      importID: approvedImport.importID,
      packID: approvedImport.packID,
      activePackContentHash: currentHash,
      basePackContentHash: approvedImport.basePackContentHash,
      resultingPackContentHash: approvedImport.resultingPackContentHash,
      approvedQuestionFamilyIDs: questionIDs,
      approvedResponseCardIDs: responseIDs,
      rejectedProposalCount: approvedImport.rejectedDecisions.count
    )
  }

  private func validateArtifact(_ approvedImport: KnowledgeStudyApprovedImport) throws {
    guard approvedImport.schemaVersion == Self.schemaVersion else {
      throw KnowledgeStudyImportApplicationError.unsupportedSchema(
        actual: approvedImport.schemaVersion,
        expected: Self.schemaVersion
      )
    }
    for (field, value) in [
      ("importID", approvedImport.importID),
      ("packID", approvedImport.packID),
      ("sourceBundleID", approvedImport.sourceBundleID),
      ("sourceAnalysisID", approvedImport.sourceAnalysisID),
      ("sourceQueueID", approvedImport.sourceQueueID),
    ] {
      guard isNormalized(value) else {
        throw KnowledgeStudyImportApplicationError.invalidIdentity(field: field)
      }
    }
    for (field, value) in [
      ("basePackContentHash", approvedImport.basePackContentHash),
      ("resultingPackContentHash", approvedImport.resultingPackContentHash),
    ] {
      guard isLowercaseSHA256(value) else {
        throw KnowledgeStudyImportApplicationError.invalidContentHash(field: field)
      }
    }
    let expectedBundleID = "study-\(approvedImport.basePackContentHash.prefix(24))"
    guard approvedImport.sourceBundleID == expectedBundleID else {
      throw KnowledgeStudyImportApplicationError.identityMismatch(
        field: "sourceBundleID",
        expected: expectedBundleID,
        actual: approvedImport.sourceBundleID
      )
    }
    guard isNormalized(approvedImport.reviewer), approvedImport.reviewer.count <= 200 else {
      throw KnowledgeStudyImportApplicationError.invalidReviewer
    }

    let sortedDecisions = approvedImport.reviewDecisions.sorted(by: decisionComesBefore)
    guard
      approvedImport.reviewDecisions.count
        <= KnowledgeStudyAnalysisValidator.maximumProposalCount * 2
    else {
      throw KnowledgeStudyImportApplicationError.invalidDecision(
        proposalID: "*",
        reason: "decision count exceeds the supported review limit"
      )
    }
    guard sortedDecisions == approvedImport.reviewDecisions else {
      throw KnowledgeStudyImportApplicationError.nonCanonicalArtifact(field: "reviewDecisions")
    }
    var decisionKeys: Set<KnowledgeStudyImportDecisionKey> = []
    for decision in approvedImport.reviewDecisions {
      guard isNormalized(decision.proposalID) else {
        throw KnowledgeStudyImportApplicationError.invalidDecision(
          proposalID: decision.proposalID,
          reason: "proposal ID must be normalized, non-empty text"
        )
      }
      if let note = decision.note,
        !isNormalized(note) || note.count > 1_000
      {
        throw KnowledgeStudyImportApplicationError.invalidDecision(
          proposalID: decision.proposalID,
          reason: "note must be normalized text of at most 1,000 characters"
        )
      }
      let key = KnowledgeStudyImportDecisionKey(
        kind: decision.proposalKind,
        id: decision.proposalID
      )
      guard decisionKeys.insert(key).inserted else {
        throw KnowledgeStudyImportApplicationError.duplicateDecision(
          kind: decision.proposalKind,
          id: decision.proposalID
        )
      }
    }

    let sortedQuestions = approvedImport.approvedQuestionFamilies.sorted { $0.id < $1.id }
    guard sortedQuestions == approvedImport.approvedQuestionFamilies else {
      throw KnowledgeStudyImportApplicationError.nonCanonicalArtifact(
        field: "approvedQuestionFamilies"
      )
    }
    guard Set(sortedQuestions.map(\.id)).count == sortedQuestions.count else {
      throw KnowledgeStudyImportApplicationError.nonCanonicalArtifact(
        field: "approvedQuestionFamilies contains duplicate IDs"
      )
    }
    let sortedCards = approvedImport.approvedResponseCards.sorted { $0.id < $1.id }
    guard sortedCards == approvedImport.approvedResponseCards else {
      throw KnowledgeStudyImportApplicationError.nonCanonicalArtifact(
        field: "approvedResponseCards"
      )
    }
    guard Set(sortedCards.map(\.id)).count == sortedCards.count else {
      throw KnowledgeStudyImportApplicationError.nonCanonicalArtifact(
        field: "approvedResponseCards contains duplicate IDs"
      )
    }
    for card in approvedImport.approvedResponseCards where card.reviewStatus != .reviewed {
      throw KnowledgeStudyImportApplicationError.responseCardNotReviewed(id: card.id)
    }

    let approvedQuestionIDs = Set(
      approvedImport.reviewDecisions.compactMap { decision in
        decision.proposalKind == .questionFamily && decision.disposition == .approve
          ? decision.proposalID : nil
      }
    )
    let approvedCardIDs = Set(
      approvedImport.reviewDecisions.compactMap { decision in
        decision.proposalKind == .responseCard && decision.disposition == .approve
          ? decision.proposalID : nil
      }
    )
    guard approvedQuestionIDs == Set(approvedImport.approvedQuestionFamilies.map(\.id)) else {
      throw KnowledgeStudyImportApplicationError.approvedRecordsDoNotMatchDecisions(
        kind: .questionFamily
      )
    }
    guard approvedCardIDs == Set(approvedImport.approvedResponseCards.map(\.id)) else {
      throw KnowledgeStudyImportApplicationError.approvedRecordsDoNotMatchDecisions(
        kind: .responseCard
      )
    }
    let rejected = approvedImport.reviewDecisions.filter { $0.disposition == .reject }
    guard rejected == approvedImport.rejectedDecisions else {
      throw KnowledgeStudyImportApplicationError.rejectedDecisionsDoNotMatch
    }
    let expectedImportID = try KnowledgeStudyImportIntegrity.importID(
      queueID: approvedImport.sourceQueueID,
      reviewer: approvedImport.reviewer,
      reviewedAt: approvedImport.reviewedAt,
      decisions: approvedImport.reviewDecisions
    )
    guard approvedImport.importID == expectedImportID else {
      throw KnowledgeStudyImportApplicationError.identityMismatch(
        field: "importID",
        expected: expectedImportID,
        actual: approvedImport.importID
      )
    }
  }

  private func merge(
    _ approvedImport: KnowledgeStudyApprovedImport,
    into pack: KnowledgePack
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards + approvedImport.approvedResponseCards,
      questionFamilies: pack.questionFamilies + approvedImport.approvedQuestionFamilies
    )
  }

  private func recordsAlreadyPresent(
    _ approvedImport: KnowledgeStudyApprovedImport,
    in pack: KnowledgePack
  ) -> Bool {
    let questions = Dictionary(uniqueKeysWithValues: pack.questionFamilies.map { ($0.id, $0) })
    let cards = Dictionary(uniqueKeysWithValues: pack.responseCards.map { ($0.id, $0) })
    return approvedImport.approvedQuestionFamilies.allSatisfy { questions[$0.id] == $0 }
      && approvedImport.approvedResponseCards.allSatisfy { cards[$0.id] == $0 }
  }

  private func contentHash(for pack: KnowledgePack) throws -> String {
    try KnowledgeStudyBundleBuilder().build(from: pack).packContentHash
  }

  private func receipt(
    for approvedImport: KnowledgeStudyApprovedImport,
    plan: KnowledgeStudyImportPlan,
    outcome: KnowledgeStudyImportOutcome,
    recovered: Bool
  ) -> KnowledgeStudyImportReceipt {
    KnowledgeStudyImportReceipt(
      schemaVersion: Self.schemaVersion,
      outcome: outcome,
      importID: approvedImport.importID,
      packID: approvedImport.packID,
      previousPackContentHash: plan.activePackContentHash,
      resultingPackContentHash: plan.resultingPackContentHash,
      appliedAt: now(),
      approvedQuestionFamilyIDs: plan.approvedQuestionFamilyIDs,
      approvedResponseCardIDs: plan.approvedResponseCardIDs,
      reviewer: approvedImport.reviewer,
      reviewedAt: approvedImport.reviewedAt,
      recoveredInterruptedTransaction: recovered
    )
  }

  private func recoverIfNeeded(in directory: URL) throws -> Bool {
    let url = journalURL(in: directory)
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    let transaction: KnowledgeStudyImportTransaction
    do {
      let decoder = JSONDecoder()
      transaction = try decoder.decode(
        KnowledgeStudyImportTransaction.self,
        from: Data(contentsOf: url)
      )
      try validateTransaction(transaction)
    } catch {
      throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
        "journal is unreadable or invalid: \(error)"
      )
    }

    if let pack = try? loader.load(from: directory),
      let hash = try? contentHash(for: pack),
      hash == transaction.resultingPackContentHash
    {
      try finish(transaction, in: directory)
      return true
    }
    do {
      try rollback(transaction, in: directory)
      return true
    } catch {
      throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
        String(describing: error))
    }
  }

  private func stage<T: Encodable>(
    currentURL: URL,
    stagedURL: URL,
    additions: [T]
  ) throws {
    var data = try Data(contentsOf: currentURL)
    if !data.isEmpty, data.last != 0x0A {
      data.append(0x0A)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    for addition in additions {
      data.append(try encoder.encode(addition))
      data.append(0x0A)
    }
    try data.write(to: stagedURL, options: .withoutOverwriting)
    let attributes = try FileManager.default.attributesOfItem(atPath: currentURL.path)
    if let permissions = attributes[.posixPermissions] {
      try FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: stagedURL.path)
    }
    try synchronize(stagedURL)
  }

  private func install(
    currentFileName: String,
    stagedFileName: String,
    backupFileName: String,
    in directory: URL
  ) throws {
    let manager = FileManager.default
    let currentURL = directory.appendingPathComponent(currentFileName)
    let stagedURL = directory.appendingPathComponent(stagedFileName)
    let backupURL = directory.appendingPathComponent(backupFileName)
    try manager.moveItem(at: currentURL, to: backupURL)
    try manager.moveItem(at: stagedURL, to: currentURL)
    try synchronizeDirectory(directory)
  }

  private func writeJournal(
    _ transaction: KnowledgeStudyImportTransaction,
    in directory: URL
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(transaction)
    let url = journalURL(in: directory)
    guard !FileManager.default.fileExists(atPath: url.path) else {
      throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
        "a transaction journal appeared while the pack lock was held"
      )
    }
    try data.write(to: url, options: .atomic)
    try synchronize(url)
    try synchronizeDirectory(directory)
  }

  private func rollback(
    _ transaction: KnowledgeStudyImportTransaction,
    in directory: URL
  ) throws {
    let manager = FileManager.default
    for item in transaction.items {
      let currentURL = directory.appendingPathComponent(item.currentFileName)
      let backupURL = directory.appendingPathComponent(item.backupFileName)
      if manager.fileExists(atPath: backupURL.path) {
        if manager.fileExists(atPath: currentURL.path) {
          try manager.removeItem(at: currentURL)
        }
        try manager.moveItem(at: backupURL, to: currentURL)
      }
      let stagedURL = directory.appendingPathComponent(item.stagedFileName)
      if manager.fileExists(atPath: stagedURL.path) {
        try manager.removeItem(at: stagedURL)
      }
    }
    let restoredPack = try loader.load(from: directory)
    let restoredHash = try contentHash(for: restoredPack)
    guard restoredHash == transaction.basePackContentHash else {
      throw KnowledgeStudyImportApplicationError.stalePack(
        expected: transaction.basePackContentHash,
        actual: restoredHash
      )
    }
    let journal = journalURL(in: directory)
    if manager.fileExists(atPath: journal.path) {
      try manager.removeItem(at: journal)
    }
    try synchronizeDirectory(directory)
  }

  private func finish(
    _ transaction: KnowledgeStudyImportTransaction,
    in directory: URL
  ) throws {
    let manager = FileManager.default
    for item in transaction.items {
      for fileName in [item.backupFileName, item.stagedFileName] {
        let url = directory.appendingPathComponent(fileName)
        if manager.fileExists(atPath: url.path) {
          try manager.removeItem(at: url)
        }
      }
    }
    let journal = journalURL(in: directory)
    if manager.fileExists(atPath: journal.path) {
      try manager.removeItem(at: journal)
    }
    try synchronizeDirectory(directory)
  }

  private func validateTransaction(_ transaction: KnowledgeStudyImportTransaction) throws {
    guard transaction.schemaVersion == Self.schemaVersion,
      isNormalized(transaction.importID),
      isLowercaseSHA256(transaction.basePackContentHash),
      isLowercaseSHA256(transaction.resultingPackContentHash)
    else {
      throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
        "journal identity or content hashes are invalid"
      )
    }
    let names = transaction.items.flatMap { [$0.stagedFileName, $0.backupFileName] }
    guard Set(names).count == names.count,
      names.allSatisfy({ name in
        name.hasPrefix(".knowledge-copilot-")
          && !name.contains("/")
          && !name.contains("\\")
          && !name.contains("..")
      })
    else {
      throw KnowledgeStudyImportApplicationError.transactionRecoveryFailed(
        "journal contains unsafe or duplicate transaction file names"
      )
    }
  }

  private func journalURL(in directory: URL) -> URL {
    directory.appendingPathComponent(Self.journalFileName)
  }

  private func synchronize(_ url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
  }

  private func synchronizeDirectory(_ directory: URL) throws {
    let descriptor = Darwin.open(directory.path, O_RDONLY)
    guard descriptor >= 0 else {
      throw CocoaError(.fileReadUnknown)
    }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else {
      throw CocoaError(.fileWriteUnknown)
    }
  }

  private func isNormalized(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed == value
  }

  private func isLowercaseSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (97...102).contains(byte)
      }
  }

  private func decisionComesBefore(
    _ lhs: KnowledgeStudyReviewDecision,
    _ rhs: KnowledgeStudyReviewDecision
  ) -> Bool {
    (lhs.proposalKind.rawValue, lhs.proposalID) < (rhs.proposalKind.rawValue, rhs.proposalID)
  }
}

enum KnowledgeStudyImportMutationStep: Sendable {
  case staged
  case questionFamiliesInstalled
  case responseCardsInstalled
}

enum KnowledgeStudyImportIntegrity {
  static func importID(
    queueID: String,
    reviewer: String,
    reviewedAt: Date,
    decisions: [KnowledgeStudyReviewDecision]
  ) throws -> String {
    let content = CanonicalReviewDecisionContent(
      queueID: queueID,
      reviewer: reviewer,
      reviewedAt: reviewedAt,
      decisions: decisions.sorted {
        ($0.proposalKind.rawValue, $0.proposalID) < ($1.proposalKind.rawValue, $1.proposalID)
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(content)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return "import-\(digest.prefix(24))"
  }
}

private struct KnowledgeStudyImportDecisionKey: Hashable {
  let kind: KnowledgeStudyProposalKind
  let id: String
}

private struct CanonicalReviewDecisionContent: Encodable {
  let queueID: String
  let reviewer: String
  let reviewedAt: Date
  let decisions: [KnowledgeStudyReviewDecision]
}

private struct KnowledgeStudyImportTransaction: Codable {
  let schemaVersion: Int
  let importID: String
  let basePackContentHash: String
  let resultingPackContentHash: String
  let questionStagedFileName: String
  let questionBackupFileName: String
  let responseStagedFileName: String
  let responseBackupFileName: String

  var items: [KnowledgeStudyImportTransactionItem] {
    [
      KnowledgeStudyImportTransactionItem(
        currentFileName: "question-families.jsonl",
        stagedFileName: questionStagedFileName,
        backupFileName: questionBackupFileName
      ),
      KnowledgeStudyImportTransactionItem(
        currentFileName: "response-cards.jsonl",
        stagedFileName: responseStagedFileName,
        backupFileName: responseBackupFileName
      ),
    ]
  }

  static func make(
    importID: String,
    basePackContentHash: String,
    resultingPackContentHash: String
  ) -> KnowledgeStudyImportTransaction {
    let nonce = UUID().uuidString.lowercased()
    return KnowledgeStudyImportTransaction(
      schemaVersion: 1,
      importID: importID,
      basePackContentHash: basePackContentHash,
      resultingPackContentHash: resultingPackContentHash,
      questionStagedFileName: ".knowledge-copilot-\(nonce)-questions.staged",
      questionBackupFileName: ".knowledge-copilot-\(nonce)-questions.backup",
      responseStagedFileName: ".knowledge-copilot-\(nonce)-cards.staged",
      responseBackupFileName: ".knowledge-copilot-\(nonce)-cards.backup"
    )
  }
}

private struct KnowledgeStudyImportTransactionItem {
  let currentFileName: String
  let stagedFileName: String
  let backupFileName: String
}

private final class KnowledgeStudyImportLock {
  private var descriptor: Int32

  init(url: URL) throws {
    descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw KnowledgeStudyImportApplicationError.lockUnavailable(
        String(cString: Darwin.strerror(errno))
      )
    }
    guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
      let lockError = errno
      Darwin.close(descriptor)
      descriptor = -1
      if lockError == EACCES || lockError == EAGAIN {
        throw KnowledgeStudyImportApplicationError.packBusy
      }
      throw KnowledgeStudyImportApplicationError.lockUnavailable(
        String(cString: Darwin.strerror(lockError))
      )
    }
  }

  func unlock() {
    guard descriptor >= 0 else { return }
    _ = Darwin.lockf(descriptor, F_ULOCK, 0)
    Darwin.close(descriptor)
    descriptor = -1
  }

  deinit {
    unlock()
  }
}
