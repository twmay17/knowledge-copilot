import Foundation

/// A presentation of the KnowledgePack evidence engine, not an independent
/// model/grounding pipeline. There is no provider client or raw-corpus upload
/// here. Lifecycle transitions and final delivery are main-actor isolated.
@MainActor
final class SidecastWhiteboardCoordinator {
  let model: SidecastWhiteboardModel
  let knowledgePackStore: KnowledgePackStore
  private let settings: AppSettings
  private let repository: SessionRepository?
  private var persistenceTask: Task<Void, Never>?
  private var sessionID: String?
  private var generation = UUID()
  private var events: [String: (question: String, timestamp: Date)] = [:]

  init(
    model: SidecastWhiteboardModel = SidecastWhiteboardModel(),
    knowledgePackStore: KnowledgePackStore,
    settings: AppSettings,
    repository: SessionRepository? = nil
  ) {
    self.model = model
    self.knowledgePackStore = knowledgePackStore
    self.settings = settings
    self.repository = repository
    knowledgePackStore.onLiveUpdate = { [weak self] update, card in
      self?.accept(update: update, card: card)
    }
    knowledgePackStore.onContextChange = { [weak self] in self?.contextChanged() }
    refreshReadiness()
  }

  func sessionStarted(at date: Date, sessionID: String = UUID().uuidString) {
    self.sessionID = nil
    invalidateWork()
    model.clear()
    self.sessionID = sessionID
    model.sessionStart = date
    refreshReadiness()
  }

  func sessionEnded() {
    // Stop means no new work or late publication, even if assistance was
    // disabled mid-session. Already accepted notes remain for export.
    sessionID = nil
    invalidateWork()
    model.status = .ended
  }

  func clear() {
    let start = model.sessionStart
    let wasEnded = model.status == .ended
    invalidateWork()
    model.clear()
    model.sessionStart = start
    refreshReadiness()
    if wasEnded { model.status = .ended }
  }

  func flushNotes() async { await persistenceTask?.value }

  func openLastSavedBoard() async {
    guard sessionID == nil else {
      model.storageStatusLine = "Stop the current session before opening saved answers."
      return
    }
    guard let repository else { return }
    await flushNotes()
    do {
      if let archive = try await repository.latestWhiteboard() {
        guard sessionID == nil else { return }
        model.restore(archive)
        model.storageStatusLine = nil
        return
      }
      model.storageStatusLine = "No saved whiteboard answers yet."
    } catch {
      model.storageStatusLine =
        "Saved whiteboard could not be read. Existing session files were left unchanged."
    }
  }

  func settingsChanged() {
    invalidateWork()
    knowledgePackStore.setNetworkMode(settings.knowledgeNetworkMode)
    refreshReadiness()
  }

  func selectPack(_ folder: URL) async {
    settings.knowledgePackFolderPath = folder.path
    await knowledgePackStore.load(fromPath: folder.path)
  }

  func receive(utteranceText: String, speaker: Speaker, at date: Date) {
    receive(text: utteranceText, speaker: speaker, at: date, stability: .final)
  }

  func receivePartial(text: String, speaker: Speaker, at date: Date) {
    receive(text: text, speaker: speaker, at: date, stability: .partial)
  }

  private func receive(
    text: String, speaker: Speaker, at date: Date, stability: TranscriptRevision.Stability
  ) {
    guard settings.sidecastWhiteboardEnabled, let sessionID else { return }
    refreshReadiness()
    guard case .loaded = knowledgePackStore.state else { return }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if stability == .final { model.noteDiagHeard() }
    let stream = "whiteboard-\(sessionID)-\(generation)-\(speaker == .you ? "you" : "remote")"
    knowledgePackStore.processTranscriptText(streamID: stream, text: text, stability: stability)
    model.noteDiagListen()
    for event in knowledgePackStore.latestLiveKnowledgeEvents {
      switch event {
      case .questionCandidate(let candidate), .questionStable(let candidate):
        if events[candidate.id] == nil { model.noteDiagQuestions(1) }
        events[candidate.id] = (candidate.sourceText, date)
      case .claimCandidate(let candidate), .claimStable(let candidate):
        if events[candidate.id] == nil { model.noteDiagQuestions(1) }
        events[candidate.id] = (candidate.sourceText, date)
      case .answerSuperseded, .topicShift, .noAction: break
      }
    }
    if events.count > 200 {
      let newest = events.sorted { $0.value.timestamp > $1.value.timestamp }.prefix(100)
      events = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }
  }

  private func accept(update: KnowledgeTieredAnswerUpdate, card: KnowledgeOverlayCard?) {
    guard settings.sidecastWhiteboardEnabled, let sessionID,
      case .loaded = knowledgePackStore.state,
      update.streamID.hasPrefix("whiteboard-\(sessionID)-\(generation)-"),
      let context = events[update.eventID],
      let pack = knowledgePackStore.selectedPack,
      let hash = knowledgePackStore.searchIndex?.packContentHash
    else { return }
    if update.action == .retract {
      model.supersede(eventID: update.eventID)
      if let note = model.notes.last(where: { $0.evidence?.eventID == update.eventID }) {
        persist(note)
      }
      return
    }
    guard let card else { return }
    model.receive(
      card: card, question: context.question, timestamp: context.timestamp,
      sessionID: sessionID, packID: pack.manifest.packID, packContentHash: hash)
    if let note = model.notes.last(where: { $0.evidence?.eventID == update.eventID }) {
      persist(note)
    }
  }

  private func persist(_ note: SidecastWhiteboardModel.DisplayNote) {
    guard let repository, let sessionID = note.evidence?.sessionID,
      let startedAt = model.sessionStart
    else { return }
    let previous = persistenceTask
    persistenceTask = Task { [weak self] in
      await previous?.value
      do {
        try await repository.saveWhiteboardNote(note, sessionID: sessionID, startedAt: startedAt)
      } catch {
        self?.model.storageStatusLine =
          "Answers could not be saved. Export this board before closing; check available disk space and folder access."
      }
    }
  }

  private func invalidateWork() {
    generation = UUID()
    events = [:]
    knowledgePackStore.resetLiveSession()
  }

  private func contextChanged() {
    generation = UUID()
    events = [:]
    // Preserve provenance on historical notes; never relabel old answers
    // as belonging to a newly selected corpus.
    model.supersedeAll()
    refreshReadiness()
  }

  private func refreshReadiness() {
    guard settings.sidecastWhiteboardEnabled else {
      model.status = .paused
      model.corpusStatusLine =
        "Whiteboard disabled — enable it in Settings → Knowledge Copilot Pack."
      model.corpusStatusLineIsError = false
      return
    }
    switch knowledgePackStore.state {
    case .idle:
      model.status = .error("Choose a validated KnowledgePack before starting assistance.")
      model.corpusStatusLine = "No corpus loaded. General-knowledge answers are disabled."
      model.corpusStatusLineIsError = true
    case .loading:
      model.status = .paused
      model.corpusStatusLine = "Loading and validating the selected KnowledgePack…"
      model.corpusStatusLineIsError = false
    case .failed:
      model.status = .error("KnowledgePack unavailable — assistance is paused.")
      model.corpusStatusLine =
        "Pack validation failed. Check the Knowledge Pack settings for details."
      model.corpusStatusLineIsError = true
    case .loaded(_, let summary):
      if model.status != .ended { model.status = sessionID == nil ? .ready : .live }
      model.corpusStatusLine =
        "\(summary.title) · \(summary.sourceCount) sources · local evidence engine"
      model.corpusStatusLineIsError = false
    }
  }
}
