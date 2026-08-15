import Foundation
import Observation

enum KnowledgeStudyReviewWorkspaceActivity: Equatable, Sendable {
  case idle
  case loading
  case preparing
  case applying
}

enum KnowledgeStudyReviewWorkspaceSelection: Hashable, Identifiable, Sendable {
  case questionFamily(String)
  case responseCard(String)
  case contradiction(String)
  case corpusGap(String)

  var id: String {
    switch self {
    case .questionFamily(let id): return "question-family:\(id)"
    case .responseCard(let id): return "response-card:\(id)"
    case .contradiction(let id): return "contradiction:\(id)"
    case .corpusGap(let id): return "corpus-gap:\(id)"
    }
  }
}

struct KnowledgeStudyReviewDecisionDraft: Equatable, Sendable {
  var disposition: KnowledgeStudyReviewDisposition?
  var note: String

  init(disposition: KnowledgeStudyReviewDisposition? = nil, note: String = "") {
    self.disposition = disposition
    self.note = note
  }
}

enum KnowledgeStudyReviewWorkspaceError: Error, CustomStringConvertible {
  case queueTampered
  case queueNotLoaded
  case invalidReviewer
  case incompleteDecisions(remaining: Int)
  case invalidDecisionNote(proposalID: String)
  case importNotPrepared

  var description: String {
    switch self {
    case .queueTampered:
      return "The review queue does not exactly match its analysis and the active KnowledgePack."
    case .queueNotLoaded:
      return "Load a review queue for the active KnowledgePack first."
    case .invalidReviewer:
      return "Enter a normalized reviewer name of at most 200 characters."
    case .incompleteDecisions(let remaining):
      return "Approve or reject every proposal. \(remaining) decision(s) remain."
    case .invalidDecisionNote(let proposalID):
      return
        "The note for '\(proposalID)' must be empty or normalized text of at most 1,000 characters."
    case .importNotPrepared:
      return "Preview and validate the reviewed import before applying it."
    }
  }
}

@MainActor
@Observable
final class KnowledgeStudyReviewWorkspaceModel {
  private let profileRegistry: KnowledgeDomainProfileRegistry
  private let now: @Sendable () -> Date
  private var drafts: [KnowledgeStudyReviewProposalKey: KnowledgeStudyReviewDecisionDraft] = [:]

  private(set) var queue: KnowledgeStudyReviewQueue?
  private(set) var bundle: KnowledgeStudyBundle?
  private(set) var queueURL: URL?
  private(set) var packDirectory: URL?
  private(set) var packTitle = ""
  private(set) var reviewer: String
  private(set) var activity: KnowledgeStudyReviewWorkspaceActivity = .idle
  private(set) var errorMessage: String?
  private(set) var approvedImport: KnowledgeStudyApprovedImport?
  private(set) var importPlan: KnowledgeStudyImportPlan?
  private(set) var receipt: KnowledgeStudyImportReceipt?
  var selection: KnowledgeStudyReviewWorkspaceSelection?

  init(
    profileRegistry: KnowledgeDomainProfileRegistry,
    reviewer: String = "",
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.profileRegistry = profileRegistry
    self.reviewer = reviewer
    self.now = now
  }

  var isLoaded: Bool {
    queue != nil && packDirectory != nil
  }

  var questionSelections: [KnowledgeStudyReviewWorkspaceSelection] {
    queue?.analysis.questionFamilyProposals.map {
      .questionFamily($0.id)
    } ?? []
  }

  var responseCardSelections: [KnowledgeStudyReviewWorkspaceSelection] {
    queue?.analysis.responseCardProposals.map {
      .responseCard($0.id)
    } ?? []
  }

  var contradictionSelections: [KnowledgeStudyReviewWorkspaceSelection] {
    queue?.analysis.contradictions.map {
      .contradiction($0.id)
    } ?? []
  }

  var corpusGapSelections: [KnowledgeStudyReviewWorkspaceSelection] {
    queue?.analysis.corpusGaps.map {
      .corpusGap($0.id)
    } ?? []
  }

  var proposalCount: Int {
    drafts.count
  }

  var approvedCount: Int {
    drafts.values.filter { $0.disposition == .approve }.count
  }

  var rejectedCount: Int {
    drafts.values.filter { $0.disposition == .reject }.count
  }

  var pendingCount: Int {
    drafts.values.filter { $0.disposition == nil }.count
  }

  var preparationBlocker: String? {
    guard isLoaded else { return KnowledgeStudyReviewWorkspaceError.queueNotLoaded.description }
    guard receipt == nil else { return "This reviewed import has already been applied." }
    guard activity == .idle else { return "Wait for the current review operation to finish." }
    guard isNormalizedReviewer(reviewer) else {
      return KnowledgeStudyReviewWorkspaceError.invalidReviewer.description
    }
    guard pendingCount == 0 else {
      return KnowledgeStudyReviewWorkspaceError.incompleteDecisions(
        remaining: pendingCount
      ).description
    }
    for (key, draft) in drafts where !isValidNote(draft.note) {
      return KnowledgeStudyReviewWorkspaceError.invalidDecisionNote(
        proposalID: key.id
      ).description
    }
    return nil
  }

  var canPrepareImport: Bool {
    preparationBlocker == nil
  }

  var canApplyImport: Bool {
    approvedImport != nil && importPlan != nil && receipt == nil && activity == .idle
  }

  func load(queueURL: URL, packDirectory: URL) async -> Bool {
    activity = .loading
    errorMessage = nil
    clearLoadedReview()
    let registry = profileRegistry
    let normalizedQueueURL = queueURL.standardizedFileURL
    let normalizedPackDirectory = packDirectory.standardizedFileURL

    do {
      let result = try await Task.detached(priority: .userInitiated) {
        let pack = try KnowledgePackLoader(profileRegistry: registry).load(
          from: normalizedPackDirectory
        )
        let queue = try JSONDecoder().decode(
          KnowledgeStudyReviewQueue.self,
          from: Data(contentsOf: normalizedQueueURL)
        )
        let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)
        let expectedQueue = try KnowledgeStudyAnalysisValidator().makeReviewQueue(
          analysis: queue.analysis,
          bundle: bundle
        )
        guard expectedQueue == queue else {
          throw KnowledgeStudyReviewWorkspaceError.queueTampered
        }
        return (pack, queue, bundle)
      }.value

      self.queue = result.1
      bundle = result.2
      self.queueURL = normalizedQueueURL
      self.packDirectory = normalizedPackDirectory
      packTitle = result.0.manifest.title
      drafts = Self.makeDrafts(for: result.1)
      selection =
        responseCardSelections.first ?? questionSelections.first
        ?? contradictionSelections.first ?? corpusGapSelections.first
      activity = .idle
      return true
    } catch {
      activity = .idle
      errorMessage = String(describing: error)
      return false
    }
  }

  func clear() {
    clearLoadedReview()
    errorMessage = nil
    activity = .idle
  }

  func dismissError() {
    errorMessage = nil
  }

  func updateReviewer(_ value: String) {
    guard receipt == nil else { return }
    reviewer = value
    invalidatePreparedImport()
  }

  func draft(
    for selection: KnowledgeStudyReviewWorkspaceSelection
  ) -> KnowledgeStudyReviewDecisionDraft? {
    guard let key = KnowledgeStudyReviewProposalKey(selection: selection) else { return nil }
    return drafts[key]
  }

  func setDisposition(
    _ disposition: KnowledgeStudyReviewDisposition,
    for selection: KnowledgeStudyReviewWorkspaceSelection
  ) {
    guard receipt == nil,
      let key = KnowledgeStudyReviewProposalKey(selection: selection),
      var draft = drafts[key]
    else { return }
    draft.disposition = disposition
    drafts[key] = draft
    invalidatePreparedImport()
  }

  func setNote(_ note: String, for selection: KnowledgeStudyReviewWorkspaceSelection) {
    guard receipt == nil,
      let key = KnowledgeStudyReviewProposalKey(selection: selection),
      var draft = drafts[key]
    else { return }
    draft.note = note
    drafts[key] = draft
    invalidatePreparedImport()
  }

  func prepareImport() async -> Bool {
    guard let queue, let packDirectory else {
      errorMessage = KnowledgeStudyReviewWorkspaceError.queueNotLoaded.description
      return false
    }
    if let blocker = preparationBlocker {
      errorMessage = blocker
      return false
    }

    let decisionSet: KnowledgeStudyReviewDecisionSet
    do {
      decisionSet = try makeDecisionSet(queue: queue)
    } catch {
      errorMessage = String(describing: error)
      return false
    }

    activity = .preparing
    errorMessage = nil
    let registry = profileRegistry
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        let pack = try KnowledgePackLoader(profileRegistry: registry).load(from: packDirectory)
        let approvedImport = try KnowledgeStudyReviewGate(profileRegistry: registry).approve(
          queue: queue,
          decisions: decisionSet,
          pack: pack
        )
        let plan = try KnowledgeStudyImportApplier(profileRegistry: registry).plan(
          approvedImport: approvedImport,
          packDirectory: packDirectory
        )
        return (approvedImport, plan)
      }.value
      approvedImport = result.0
      importPlan = result.1
      activity = .idle
      return true
    } catch {
      approvedImport = nil
      importPlan = nil
      activity = .idle
      errorMessage = String(describing: error)
      return false
    }
  }

  func applyImport() async -> Bool {
    guard let approvedImport, let packDirectory, importPlan != nil else {
      errorMessage = KnowledgeStudyReviewWorkspaceError.importNotPrepared.description
      return false
    }
    guard receipt == nil, activity == .idle else { return false }

    activity = .applying
    errorMessage = nil
    let registry = profileRegistry
    do {
      receipt = try await Task.detached(priority: .userInitiated) {
        try KnowledgeStudyImportApplier(profileRegistry: registry).apply(
          approvedImport: approvedImport,
          to: packDirectory
        )
      }.value
      activity = .idle
      return true
    } catch {
      activity = .idle
      errorMessage = String(describing: error)
      return false
    }
  }

  private func makeDecisionSet(
    queue: KnowledgeStudyReviewQueue
  ) throws -> KnowledgeStudyReviewDecisionSet {
    guard isNormalizedReviewer(reviewer) else {
      throw KnowledgeStudyReviewWorkspaceError.invalidReviewer
    }
    guard pendingCount == 0 else {
      throw KnowledgeStudyReviewWorkspaceError.incompleteDecisions(remaining: pendingCount)
    }
    let decisions = try drafts.keys.sorted(by: KnowledgeStudyReviewProposalKey.comesBefore).map {
      key in
      guard let draft = drafts[key], let disposition = draft.disposition else {
        throw KnowledgeStudyReviewWorkspaceError.incompleteDecisions(remaining: pendingCount)
      }
      guard isValidNote(draft.note) else {
        throw KnowledgeStudyReviewWorkspaceError.invalidDecisionNote(proposalID: key.id)
      }
      return KnowledgeStudyReviewDecision(
        proposalKind: key.kind,
        proposalID: key.id,
        disposition: disposition,
        note: draft.note.isEmpty ? nil : draft.note
      )
    }
    return KnowledgeStudyReviewDecisionSet(
      schemaVersion: KnowledgeStudyReviewGate.schemaVersion,
      queueID: queue.queueID,
      analysisID: queue.analysis.analysisID,
      bundleID: queue.analysis.bundleID,
      reviewer: reviewer,
      reviewedAt: now(),
      decisions: decisions
    )
  }

  private func invalidatePreparedImport() {
    approvedImport = nil
    importPlan = nil
    errorMessage = nil
  }

  private func clearLoadedReview() {
    queue = nil
    bundle = nil
    queueURL = nil
    packDirectory = nil
    packTitle = ""
    drafts = [:]
    approvedImport = nil
    importPlan = nil
    receipt = nil
    selection = nil
  }

  private func isNormalizedReviewer(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed == value && value.count <= 200
  }

  private func isValidNote(_ value: String) -> Bool {
    guard !value.isEmpty else { return true }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed == value && value.count <= 1_000
  }

  private static func makeDrafts(
    for queue: KnowledgeStudyReviewQueue
  ) -> [KnowledgeStudyReviewProposalKey: KnowledgeStudyReviewDecisionDraft] {
    var result: [KnowledgeStudyReviewProposalKey: KnowledgeStudyReviewDecisionDraft] = [:]
    for proposal in queue.analysis.questionFamilyProposals {
      result[KnowledgeStudyReviewProposalKey(kind: .questionFamily, id: proposal.id)] = .init()
    }
    for proposal in queue.analysis.responseCardProposals {
      result[KnowledgeStudyReviewProposalKey(kind: .responseCard, id: proposal.id)] = .init()
    }
    return result
  }
}

private struct KnowledgeStudyReviewProposalKey: Hashable, Sendable {
  let kind: KnowledgeStudyProposalKind
  let id: String

  init(kind: KnowledgeStudyProposalKind, id: String) {
    self.kind = kind
    self.id = id
  }

  init?(selection: KnowledgeStudyReviewWorkspaceSelection) {
    switch selection {
    case .questionFamily(let id): self.init(kind: .questionFamily, id: id)
    case .responseCard(let id): self.init(kind: .responseCard, id: id)
    case .contradiction, .corpusGap: return nil
    }
  }

  static func comesBefore(
    _ lhs: KnowledgeStudyReviewProposalKey,
    _ rhs: KnowledgeStudyReviewProposalKey
  ) -> Bool {
    (lhs.kind.rawValue, lhs.id) < (rhs.kind.rawValue, rhs.id)
  }
}
