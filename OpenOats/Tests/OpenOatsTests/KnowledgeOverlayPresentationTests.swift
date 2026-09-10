import HospitalityDomainProfile
import SwiftUI
import XCTest

@testable import OpenOatsKit

final class KnowledgeOverlayPresentationTests: XCTestCase {
  func testKeyboardShortcutsMapEveryCoreControlAndRejectExtraModifiers() {
    let expected: [String: KnowledgeOverlayCommand] = [
      "p": .togglePin,
      "c": .copyAnswer,
      "e": .openSource,
      "w": .requestCorrection,
      "x": .dismiss,
      "k": .toggleCompactMode,
    ]

    for (key, command) in expected {
      XCTAssertEqual(
        KnowledgeOverlayKeyboardShortcuts.command(
          forKey: key,
          commandPressed: true,
          shiftPressed: true,
          optionPressed: true
        ),
        command
      )
    }

    XCTAssertNil(
      KnowledgeOverlayKeyboardShortcuts.command(
        forKey: "c",
        commandPressed: true,
        shiftPressed: true,
        optionPressed: false
      ))
    XCTAssertNil(
      KnowledgeOverlayKeyboardShortcuts.command(
        forKey: "c",
        commandPressed: true,
        shiftPressed: false,
        optionPressed: true
      ))
    XCTAssertNil(
      KnowledgeOverlayKeyboardShortcuts.command(
        forKey: "c",
        commandPressed: true,
        shiftPressed: true,
        optionPressed: true,
        controlPressed: true
      ))
  }

  func testShareSafetyNoticeAlwaysWarnsAboutFullDisplaySharing() {
    let protectedNotice = KnowledgeOverlayShareSafetyNotice.make(hideFromScreenShare: true)
    let visibleNotice = KnowledgeOverlayShareSafetyNotice.make(hideFromScreenShare: false)

    XCTAssertEqual(protectedNotice.severity, .caution)
    XCTAssertTrue(protectedNotice.title.lowercased().contains("full-display"))
    XCTAssertTrue(protectedNotice.message.contains("single app window"))
    XCTAssertEqual(visibleNotice.severity, .warning)
    XCTAssertTrue(visibleNotice.message.lowercased().contains("full-display"))
  }

  @MainActor
  func testPanelsHideFromCaptureAndFreshPanelsAreCapturable() {
    let overlay = OverlayPanel(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
      hideFromScreenShare: false
    )
    let miniBar = MiniBarPanel(
      contentRect: NSRect(x: 0, y: 0, width: 40, height: 18),
      hideFromScreenShare: false
    )
    XCTAssertEqual(overlay.sharingType, .readOnly)
    XCTAssertEqual(miniBar.sharingType, .readOnly)

    overlay.applyHideFromScreenShare(true)
    miniBar.applyHideFromScreenShare(true)
    XCTAssertEqual(overlay.sharingType, .none)
    XCTAssertEqual(miniBar.sharingType, .none)
    // Managers restore the setting in place or rebuild when readback refuses it.
    // Neither path establishes actual screen-capture behavior.
    overlay.close()
    miniBar.close()
  }

  @MainActor
  func testOverlayManagerRestoresCaptureSettingAndPreservesPresentation() {
    let manager = OverlayManager()
    manager.showSidePanel(content: Text("panel"))
    manager.showSidecastSidebar(content: Text("sidecast"))
    manager.updateHideFromScreenShare(true)
    XCTAssertEqual(manager.panel?.sharingType, NSWindow.SharingType.none)
    XCTAssertEqual(manager.sidecastPanel?.sharingType, NSWindow.SharingType.none)
    let hiddenPanel = manager.panel
    let hiddenSidecast = manager.sidecastPanel
    let panelContent = hiddenPanel?.contentView
    let sidecastContent = hiddenSidecast?.contentView
    let panelFrame = hiddenPanel?.frame

    manager.updateHideFromScreenShare(false)

    XCTAssertEqual(manager.panel?.sharingType, .readOnly)
    XCTAssertEqual(manager.sidecastPanel?.sharingType, .readOnly)
    XCTAssertTrue(manager.panel?.contentView === panelContent)
    XCTAssertTrue(manager.sidecastPanel?.contentView === sidecastContent)
    XCTAssertEqual(manager.panel?.frame, panelFrame)
    manager.hide()
    manager.panel?.close()
    manager.sidecastPanel?.close()
  }

  @MainActor
  func testMiniBarManagerRestoresCaptureSettingAndPreservesPresentation() {
    let manager = MiniBarManager()
    manager.show()
    manager.updateHideFromScreenShare(true)
    XCTAssertEqual(manager.panel?.sharingType, NSWindow.SharingType.none)
    let hidden = manager.panel
    let content = hidden?.contentView

    manager.updateHideFromScreenShare(false)

    XCTAssertEqual(manager.panel?.sharingType, .readOnly)
    XCTAssertTrue(manager.panel?.contentView === content)
    manager.hide()
    manager.panel?.close()
  }

  @MainActor
  func testOverlayManagerRebuildsWhenCaptureReadbackRefusesRestore() {
    let manager = OverlayManager()
    manager.showSidePanel(content: Text("panel"))
    manager.showSidecastSidebar(content: Text("sidecast"))
    manager.updateHideFromScreenShare(true)
    let hidden = manager.panel
    let hiddenSidebar = manager.sidecastPanel
    let content = hidden?.contentView
    let sidebarContent = hiddenSidebar?.contentView
    manager.captureSharingType = { _ in .none }
    manager.updateHideFromScreenShare(false)
    XCTAssertTrue(manager.panel !== hidden)
    XCTAssertTrue(manager.sidecastPanel !== hiddenSidebar)
    XCTAssertEqual(manager.panel?.sharingType, .readOnly)
    XCTAssertEqual(manager.sidecastPanel?.sharingType, .readOnly)
    XCTAssertTrue(manager.panel?.contentView === content)
    XCTAssertTrue(manager.sidecastPanel?.contentView === sidebarContent)
    XCTAssertEqual(manager.panel?.frame, hidden?.frame)
    manager.hide()
    manager.panel?.close()
    manager.sidecastPanel?.close()
  }

  @MainActor
  func testMiniBarManagerRebuildsWhenCaptureReadbackRefusesRestore() {
    let manager = MiniBarManager()
    manager.show()
    manager.updateHideFromScreenShare(true)
    let hidden = manager.panel
    let content = hidden?.contentView
    manager.captureSharingType = { _ in .none }
    manager.updateHideFromScreenShare(false)
    XCTAssertTrue(manager.panel !== hidden)
    XCTAssertEqual(manager.panel?.sharingType, .readOnly)
    XCTAssertTrue(manager.panel?.contentView === content)
    XCTAssertEqual(manager.panel?.frame, hidden?.frame)
    manager.hide()
    manager.panel?.close()
  }

  func testEveryEvidenceStateHasExplicitLanguageIndependentOfColor() {
    XCTAssertEqual(
      KnowledgeEvidenceState.allCases.map(\.overlayLabel),
      [
        "Directly Sourced",
        "Calculated",
        "Supported by Corpus",
        "Contradicted by Corpus",
        "Contested",
        "Interpretive",
        "Not Found in Corpus",
        "Needs Clarification",
      ]
    )
    XCTAssertTrue(KnowledgeEvidenceState.allCases.allSatisfy { !$0.overlayExplanation.isEmpty })
  }

  func testContestedEvidencePreservesEveryClaimAndAttribution() throws {
    let first = attribution(assertionID: "a-1", sourceID: "source-1", title: "Plan A")
    let second = attribution(assertionID: "a-2", sourceID: "source-2", title: "Plan B")
    let evidence = outcome(
      state: .contested,
      reason: .contestedEvidence,
      claims: [
        claim(id: "a-1", value: "100 room", attribution: first),
        claim(id: "a-2", value: "120 room", attribution: second),
      ],
      sources: [first, second]
    )

    let card = try XCTUnwrap(
      KnowledgeOverlayCard.make(from: update(payload: .exactEvidence(evidence))))

    XCTAssertEqual(card.evidenceState, .contested)
    XCTAssertEqual(card.claims.map(\.value), ["100 room", "120 room"])
    XCTAssertTrue(card.claims[0].attribution.contains("Plan A"))
    XCTAssertTrue(card.claims[1].attribution.contains("Plan B"))
    XCTAssertEqual(card.sources.map(\.title), ["Plan A", "Plan B"])
    XCTAssertTrue(card.answer.contains("2 attributed claims"))
  }

  func testConstrainedSynthesisKeepsCitedClaimAndOpenableSource() throws {
    let first = attribution(assertionID: "a-1", sourceID: "source-1", title: "Plan A")
    let second = attribution(assertionID: "a-2", sourceID: "source-2", title: "Plan B")
    let evidence = outcome(
      state: .supportedByCorpus,
      reason: .supportedClaims,
      claims: [
        claim(id: "a-1", value: "100 room", attribution: first),
        claim(id: "a-2", value: "100 room", attribution: second),
      ],
      sources: [first, second]
    )
    let output = KnowledgeConstrainedSynthesisOutput(
      title: "Room count",
      answer: "The property has 100 rooms.",
      citedEvidenceRecordIDs: ["assertion:a-2"]
    )

    let card = try XCTUnwrap(
      KnowledgeOverlayCard.make(
        from: update(payload: .constrainedSynthesis(output: output, evidence: evidence))))

    XCTAssertEqual(card.answer, output.answer)
    XCTAssertEqual(card.claims.map(\.id), ["a-2"])
    XCTAssertEqual(card.sources.map(\.title), ["Plan B"])
    XCTAssertNotNil(card.sources.first?.fileURL)
    XCTAssertEqual(card.firstOpenableSourceURL, card.sources.first?.fileURL)
    XCTAssertTrue(card.clipboardText.contains(output.title))
    XCTAssertTrue(card.clipboardText.contains(output.answer))
    XCTAssertTrue(card.clipboardText.contains("Evidence: Supported by Corpus"))
    XCTAssertTrue(card.clipboardText.contains("Plan B — Page 1"))
    XCTAssertTrue(card.why.contains("Drafted from the cited evidence"))
  }

  func testPrimaryActionTargetsTheLiveRemoteAnswerBeforePinnedOrLocalCards() throws {
    var state = KnowledgeOverlayPresentationState()
    state.apply(
      update(
        id: "u-pinned",
        eventID: "event-pinned",
        streamID: "remote",
        payload: .reviewedCard(reviewedCard(id: "event-pinned", answer: "Pinned"))
      ))
    state.togglePin(eventID: "event-pinned")
    state.apply(
      update(
        id: "u-local",
        eventID: "event-local",
        streamID: "local",
        revisionSequence: 2,
        payload: .reviewedCard(reviewedCard(id: "event-local", answer: "Local"))
      ))
    state.apply(
      update(
        id: "u-remote",
        eventID: "event-remote",
        streamID: "remote",
        revisionSequence: 3,
        payload: .reviewedCard(reviewedCard(id: "event-remote", answer: "Remote"))
      ))

    let primary = try XCTUnwrap(state.primaryActionCard)
    XCTAssertEqual(primary.eventID, "event-remote")
    XCTAssertEqual(primary.answer, "Remote")
  }

  func testRefinementReplacesVisibleContentForTheSameEvent() throws {
    var state = KnowledgeOverlayPresentationState()
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard(answer: "Draft"))))
    state.apply(
      update(
        id: "u-2",
        action: .refine,
        supersedesUpdateID: "u-1",
        payload: .reviewedCard(reviewedCard(answer: "Final"))
      ))

    let card = try XCTUnwrap(state.visibleCards.first)
    XCTAssertEqual(state.visibleCards.count, 1)
    XCTAssertEqual(card.updateID, "u-2")
    XCTAssertEqual(card.answer, "Final")
  }

  func testLateSameRevisionUpdateCannotRollBackARefinement() throws {
    var state = KnowledgeOverlayPresentationState()
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard(answer: "Draft"))))
    state.apply(
      update(
        id: "u-2",
        action: .refine,
        supersedesUpdateID: "u-1",
        payload: .reviewedCard(reviewedCard(answer: "Final"))
      ))
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard(answer: "Draft"))))

    let card = try XCTUnwrap(state.visibleCards.first)
    XCTAssertEqual(card.updateID, "u-2")
    XCTAssertEqual(card.answer, "Final")
  }

  func testPinnedCardSurvivesRetractionAsAnExplicitSnapshot() throws {
    var state = KnowledgeOverlayPresentationState()
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard())))
    XCTAssertTrue(state.togglePin(eventID: "event-1"))
    state.apply(
      update(
        id: "u-retract",
        action: .retract,
        supersedesUpdateID: "u-1",
        payload: nil
      ))

    let card = try XCTUnwrap(state.visibleCards.first)
    XCTAssertTrue(card.isPinned)
    XCTAssertTrue(card.isSuperseded)
  }

  func testPinnedAnswerRemainsVisibleWhenTheStreamReceivesANewEvent() {
    var state = KnowledgeOverlayPresentationState()
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard())))
    state.togglePin(eventID: "event-1")
    state.apply(
      update(
        id: "u-2",
        eventID: "event-2",
        revisionSequence: 2,
        payload: .reviewedCard(reviewedCard(id: "event-2", answer: "New answer"))
      ))

    XCTAssertEqual(state.visibleCards.map(\.eventID), ["event-1", "event-2"])
    XCTAssertTrue(state.visibleCards[0].isPinned)
    XCTAssertFalse(state.visibleCards[1].isPinned)
  }

  func testLateUpdateCannotRollBackPinnedRefinement() throws {
    var state = KnowledgeOverlayPresentationState()
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard(answer: "Draft"))))
    state.togglePin(eventID: "event-1")
    state.apply(
      update(
        id: "u-2",
        action: .refine,
        supersedesUpdateID: "u-1",
        payload: .reviewedCard(reviewedCard(answer: "Final"))
      ))
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard(answer: "Draft"))))

    let card = try XCTUnwrap(state.visibleCards.first)
    XCTAssertEqual(card.updateID, "u-2")
    XCTAssertEqual(card.answer, "Final")
    XCTAssertTrue(card.isPinned)
  }

  func testDismissTombstonePreventsLateLaneFromResurrectingAnswer() {
    var state = KnowledgeOverlayPresentationState()
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard())))
    state.dismiss(eventID: "event-1")
    state.apply(
      update(
        id: "u-2",
        action: .refine,
        supersedesUpdateID: "u-1",
        payload: .reviewedCard(reviewedCard(answer: "Late answer"))
      ))

    XCTAssertTrue(state.visibleCards.isEmpty)
    XCTAssertTrue(state.dismissedEventIDs.contains("event-1"))
  }

  func testCorrectionCreatesReviewRequestAndSurvivesRefinement() throws {
    var state = KnowledgeOverlayPresentationState()
    state.apply(update(id: "u-1", payload: .reviewedCard(reviewedCard(answer: "Draft"))))

    let request = try XCTUnwrap(state.requestCorrection(eventID: "event-1"))
    XCTAssertEqual(request.answer, "Draft")
    XCTAssertTrue(state.visibleCards[0].isCorrectionRequested)

    state.apply(
      update(
        id: "u-2",
        action: .refine,
        supersedesUpdateID: "u-1",
        payload: .reviewedCard(reviewedCard(answer: "Refined"))
      ))

    XCTAssertEqual(state.correctionRequests.count, 1)
    XCTAssertTrue(state.visibleCards[0].isCorrectionRequested)
    XCTAssertEqual(state.visibleCards[0].answer, "Refined")
  }

  func testRetrievedMaterialIsNotMisrepresentedAsVerifiedSupport() throws {
    let result = KnowledgePackSearchResult(
      packID: "pack",
      packContentHash: "hash",
      kind: .passage,
      recordID: "passage-1",
      title: "Business plan",
      excerpt: "The proposed launch is in June.",
      qualifiers: [:],
      sourceIDs: [],
      score: KnowledgePackSearchScore(exact: 0.4, fullText: 0.3, qualifier: 0, vector: 0),
      channels: [.fullText]
    )

    let card = try XCTUnwrap(
      KnowledgeOverlayCard.make(from: update(payload: .retrievedEvidence([result]))))

    XCTAssertEqual(card.evidenceState, .needsClarification)
    XCTAssertTrue(card.answer.contains("not been verified"))
    XCTAssertTrue(card.why.contains("Verify the source"))
  }

  func testSourceCatalogDoesNotOpenPathsOutsideTheSelectedPack() throws {
    let root = URL(fileURLWithPath: "/tmp/selected-pack", isDirectory: true)
    let pack = KnowledgePack(
      manifest: KnowledgePackManifest(
        schemaVersion: 1,
        packID: "pack",
        title: "Pack",
        createdAt: Date(timeIntervalSince1970: 0),
        defaultLocale: "en",
        domainProfiles: []
      ),
      sources: [
        KnowledgeSource(
          id: "inside",
          kind: .document,
          title: "Inside",
          relativePath: "sources/inside.pdf",
          sha256: String(repeating: "a", count: 64),
          importedAt: Date(timeIntervalSince1970: 0)
        ),
        KnowledgeSource(
          id: "outside",
          kind: .document,
          title: "Outside",
          relativePath: "../outside.pdf",
          sha256: String(repeating: "b", count: 64),
          importedAt: Date(timeIntervalSince1970: 0)
        ),
      ],
      passages: [],
      assertions: [],
      evidenceLinks: [],
      calculations: [],
      responseCards: [],
      questionFamilies: []
    )

    let catalog = KnowledgeOverlaySourceCatalog(pack: pack, rootDirectory: root)

    XCTAssertNotNil(try XCTUnwrap(catalog.source(for: "inside")).fileURL)
    XCTAssertNil(try XCTUnwrap(catalog.source(for: "outside")).fileURL)
  }

  @MainActor
  func testKnowledgePackStoreFeedsTieredUpdatesIntoOverlayAndClearsThem() async throws {
    let store = KnowledgePackStore(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))
    await store.load(fromPath: fixtureURL().path)

    _ = store.processTranscriptText(
      streamID: "remote",
      text: "What was the rev par for this asset in 2020",
      stability: .partial
    )
    _ = store.processTranscriptText(
      streamID: "remote",
      text: "What was the rev par for this asset in 2020",
      stability: .final
    )

    for _ in 0..<100
    where store.visibleOverlayCards.first?.presentationQuality != .reviewedCard {
      try await Task.sleep(for: .milliseconds(5))
    }
    let card = try XCTUnwrap(store.visibleOverlayCards.first)
    XCTAssertEqual(card.evidenceState, .calculated)
    XCTAssertFalse(card.sources.isEmpty)
    XCTAssertNotNil(store.primaryOverlayCopyText)
    XCTAssertNotNil(store.primaryOverlaySourceURL)
    XCTAssertTrue(store.toggleOverlayCompactMode())
    XCTAssertTrue(store.isOverlayCompact)
    XCTAssertEqual(store.togglePrimaryOverlayPin(), true)
    XCTAssertTrue(try XCTUnwrap(store.primaryOverlayCard).isPinned)
    XCTAssertTrue(store.requestPrimaryOverlayCorrection())
    XCTAssertEqual(store.pendingOverlayCorrections.count, 1)
    XCTAssertTrue(store.dismissPrimaryOverlayCard())
    XCTAssertTrue(store.visibleOverlayCards.isEmpty)

    store.clear()
    XCTAssertTrue(store.visibleOverlayCards.isEmpty)
    XCTAssertTrue(store.pendingOverlayCorrections.isEmpty)
    XCTAssertFalse(store.isOverlayCompact)
  }

  private func update(
    id: String = "u-1",
    eventID: String = "event-1",
    streamID: String = "remote",
    revisionSequence: Int = 1,
    action: KnowledgeTieredAnswerUpdateAction = .show,
    supersedesUpdateID: String? = nil,
    payload: KnowledgeTieredAnswerPayload?
  ) -> KnowledgeTieredAnswerUpdate {
    KnowledgeTieredAnswerUpdate(
      id: id,
      eventID: eventID,
      streamID: streamID,
      revisionSequence: revisionSequence,
      lane: action == .retract ? nil : .hot,
      action: action,
      supersedesUpdateID: supersedesUpdateID,
      supportLevel: action == .retract ? .abstention : .reviewed,
      presentationQuality: action == .retract ? .fallback : .reviewedCard,
      isProvisional: false,
      timing: nil,
      payload: payload
    )
  }

  private func reviewedCard(
    id: String = "event-1",
    answer: String = "100 rooms"
  ) -> KnowledgeAnswerCard {
    KnowledgeAnswerCard(
      id: id,
      candidateID: id,
      responseCardID: "card-1",
      title: "Room count",
      answer: answer,
      evidenceState: .directlySourced,
      citations: [],
      calculations: [],
      isFallback: false
    )
  }

  private func outcome(
    state: KnowledgeEvidenceState,
    reason: KnowledgeEvidenceOutcomeReason,
    claims: [KnowledgeEvidenceClaim],
    sources: [KnowledgeEvidenceAttribution]
  ) -> KnowledgeEvidenceOutcome {
    KnowledgeEvidenceOutcome(
      packID: "pack",
      packContentHash: "hash",
      state: state,
      reason: reason,
      claims: claims,
      contributingSources: sources.map(KnowledgeEvidenceSourceReference.init)
    )
  }

  private func claim(
    id: String,
    value: String,
    attribution: KnowledgeEvidenceAttribution
  ) -> KnowledgeEvidenceClaim {
    KnowledgeEvidenceClaim(
      assertionID: id,
      subject: "asset",
      predicate: "asset.room_count",
      value: KnowledgeValue(type: .number, number: 100, unit: "room", scale: 1),
      displayValue: value,
      qualifiers: ["period": "2020"],
      kind: .stated,
      confidence: 1,
      attributions: [attribution]
    )
  }

  private func attribution(
    assertionID: String,
    sourceID: String,
    title: String
  ) -> KnowledgeEvidenceAttribution {
    KnowledgeEvidenceAttribution(
      assertionID: assertionID,
      evidenceLinkID: "link-\(assertionID)",
      relation: .supports,
      note: nil,
      passageID: "passage-\(assertionID)",
      sourceID: sourceID,
      sourceTitle: title,
      fileURL: URL(fileURLWithPath: "/tmp/\(sourceID).pdf"),
      locatorLabel: "Page 1",
      excerpt: "Source excerpt for \(assertionID)."
    )
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }
}
