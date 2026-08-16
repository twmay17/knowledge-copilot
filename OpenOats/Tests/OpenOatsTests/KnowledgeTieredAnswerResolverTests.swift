import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeTieredAnswerResolverTests: XCTestCase {
  func testStableReviewedCardWinsInHotLaneAndSkipsOptionalSynthesis() async throws {
    let synthesizer = RecordingSynthesizer(behavior: .valid)
    let resolver = try makeResolver()

    let updates = await Self.collect(
      resolver.updates(
        for: .questionStable(revPARCandidate(status: .stable, sequence: 2)),
        synthesizer: synthesizer
      ))

    XCTAssertEqual(updates.count, 1)
    XCTAssertEqual(updates.first?.lane, .hot)
    XCTAssertEqual(updates.first?.action, .show)
    XCTAssertEqual(updates.first?.supportLevel, .reviewed)
    XCTAssertEqual(updates.first?.presentationQuality, .reviewedCard)
    XCTAssertEqual(updates.first?.timing?.budgetMilliseconds, 40)
    guard case .reviewedCard(let card) = updates.first?.payload else {
      return XCTFail("Expected a reviewed card.")
    }
    XCTAssertEqual(card.responseCardID, "card-revpar-2020")
    let synthesisCallCount = await synthesizer.callCount
    XCTAssertEqual(synthesisCallCount, 0)
  }

  func testStableReviewedCardVisiblySupersedesProvisionalExactEvidence() async throws {
    let resolver = try makeResolver()

    let early = await Self.collect(
      resolver.updates(
        for: .questionCandidate(revPARCandidate(status: .provisional, sequence: 1))
      ))
    let stable = await Self.collect(
      resolver.updates(
        for: .questionStable(revPARCandidate(status: .stable, sequence: 2))
      ))

    XCTAssertEqual(early.count, 1)
    XCTAssertEqual(early.first?.supportLevel, .corpusVerified)
    XCTAssertEqual(early.first?.presentationQuality, .exactEvidence)
    XCTAssertTrue(early.first?.isProvisional == true)
    XCTAssertEqual(stable.count, 1)
    XCTAssertEqual(stable.first?.action, .supersede)
    XCTAssertEqual(stable.first?.supersedesUpdateID, early.first?.id)
    XCTAssertEqual(stable.first?.supportLevel, .reviewed)
  }

  func testExactTypedValueIsPreferredToWarmRetrievalWhenNoCardExists() async throws {
    let resolver = try makeResolver(packTransform: removingResponseCards)

    let updates = await Self.collect(
      resolver.updates(for: .questionStable(roomCountCandidate())))

    XCTAssertEqual(updates.count, 1)
    XCTAssertEqual(updates.first?.lane, .hot)
    XCTAssertEqual(updates.first?.supportLevel, .corpusVerified)
    guard case .exactEvidence(let evidence) = updates.first?.payload else {
      return XCTFail("Expected typed evidence.")
    }
    XCTAssertEqual(evidence.state, .directlySourced)
    XCTAssertEqual(evidence.claims.map(\.displayValue), ["100 room"])
  }

  func testWarmLaneSurfacesPackBoundRetrievalWhenNoCanonicalPredicateExists() async throws {
    let resolver = try makeResolver(packTransform: removingResponseCards)
    let candidate = QuestionCandidate(
      id: "remote#generic",
      streamID: "remote",
      revisionSequence: 1,
      questionFamilyID: "question-revpar-period",
      sourceText: "What was RevPAR for this asset in 2020?",
      confidence: 0.7,
      status: .provisional,
      bindings: [
        ResolvedQuestionBinding(
          key: "term",
          value: "question_family:question-revpar-period",
          surfaceText: "RevPAR"
        )
      ]
    )

    let updates = await Self.collect(
      resolver.updates(for: .questionCandidate(candidate)))

    XCTAssertEqual(updates.count, 1)
    XCTAssertEqual(updates.first?.lane, .warm)
    XCTAssertEqual(updates.first?.supportLevel, .retrievedOnly)
    XCTAssertEqual(updates.first?.timing?.budgetMilliseconds, 250)
    guard case .retrievedEvidence(let results) = updates.first?.payload else {
      return XCTFail("Expected a pack-bound evidence preview.")
    }
    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.allSatisfy { $0.packID == "synthetic-hotel-2020-v1" })
  }

  func testReviewedCorpusAbstentionDoesNotClaimVerifiedSupport() async throws {
    let resolver = try makeResolver()
    let candidate = QuestionCandidate(
      id: "remote#2018",
      streamID: "remote",
      revisionSequence: 2,
      questionFamilyID: "question-revpar-2018",
      sourceText: "What was RevPAR in 2018?",
      confidence: 1,
      status: .stable,
      bindings: [
        ResolvedQuestionBinding(key: "period", value: "2018", surfaceText: "2018"),
        ResolvedQuestionBinding(
          key: "term",
          value: "hospitality.revpar",
          surfaceText: "RevPAR"
        ),
      ]
    )

    let updates = await Self.collect(
      resolver.updates(for: .questionStable(candidate)))

    XCTAssertEqual(updates.count, 1)
    XCTAssertEqual(updates.first?.supportLevel, .abstention)
    XCTAssertEqual(updates.first?.presentationQuality, .reviewedCard)
    guard case .reviewedCard(let card) = updates.first?.payload else {
      return XCTFail("Expected the reviewed missing-data card.")
    }
    XCTAssertEqual(card.evidenceState, .notFoundInCorpus)
  }

  func testConstrainedSynthesisReceivesOnlyAdmittedRecordsAndRefinesSameEvidence() async throws {
    let synthesizer = RecordingSynthesizer(behavior: .valid)
    let resolver = try makeResolver(packTransform: removingResponseCards)

    let updates = await Self.collect(
      resolver.updates(
        for: .questionStable(roomCountCandidate()),
        synthesizer: synthesizer
      ))

    XCTAssertEqual(updates.map(\.action), [.show, .refine])
    XCTAssertEqual(updates.map(\.supportLevel), [.corpusVerified, .corpusVerified])
    XCTAssertEqual(updates.last?.lane, .cold)
    XCTAssertEqual(updates.last?.presentationQuality, .constrainedSynthesis)
    XCTAssertEqual(updates.last?.supersedesUpdateID, updates.first?.id)
    XCTAssertEqual(updates.last?.timing?.budgetMilliseconds, 2_000)

    let recordedRequest = await synthesizer.lastRequest
    let request = try XCTUnwrap(recordedRequest)
    XCTAssertEqual(request.packID, "synthetic-hotel-2020-v1")
    XCTAssertEqual(request.eventID, "remote#room-count")
    XCTAssertFalse(request.evidenceRecords.isEmpty)
    XCTAssertTrue(
      request.evidenceRecords.contains { $0.id == "assertion:assertion-room-count-2020" })
    XCTAssertTrue(
      request.citationRequirements.allSatisfy { !$0.anyOfEvidenceRecordIDs.isEmpty })
  }

  func testUnknownOrIncompleteSynthesisCitationsAreRejectedByEvidenceGate() async throws {
    let resolver = try makeResolver(packTransform: removingResponseCards)
    let unknown = RecordingSynthesizer(behavior: .unknownCitation)
    let incomplete = RecordingSynthesizer(behavior: .incompleteCitation)

    let unknownUpdates = await Self.collect(
      resolver.updates(
        for: .questionStable(roomCountCandidate(streamID: "unknown")),
        synthesizer: unknown
      ))
    let incompleteUpdates = await Self.collect(
      resolver.updates(
        for: .questionStable(revPARCandidate(streamID: "incomplete", status: .stable, sequence: 2)),
        synthesizer: incomplete
      ))

    XCTAssertFalse(unknownUpdates.contains { $0.lane == .cold })
    XCTAssertFalse(incompleteUpdates.contains { $0.lane == .cold })
    XCTAssertTrue(unknownUpdates.contains { $0.supportLevel == .corpusVerified })
    XCTAssertTrue(incompleteUpdates.contains { $0.supportLevel == .corpusVerified })
  }

  func testColdLaneBudgetCancelsSlowSynthesisWithoutDelayingStream() async throws {
    let budgets = KnowledgeAnswerLatencyBudgets(
      hotMilliseconds: 40,
      warmMilliseconds: 200,
      coldMilliseconds: 10
    )
    let resolver = try makeResolver(packTransform: removingResponseCards, budgets: budgets)
    let synthesizer = RecordingSynthesizer(behavior: .delayed(milliseconds: 250))
    let clock = ContinuousClock()
    let start = clock.now

    let updates = await Self.collect(
      resolver.updates(
        for: .questionStable(roomCountCandidate()),
        synthesizer: synthesizer
      ))
    let elapsed = start.duration(to: clock.now)

    XCTAssertFalse(updates.contains { $0.lane == .cold })
    XCTAssertLessThan(milliseconds(elapsed), 150)
    let synthesisCallCount = await synthesizer.callCount
    XCTAssertEqual(synthesisCallCount, 1)
  }

  func testHotAndWarmReplayP50MeetComponentAndLiveTargets() async throws {
    let hotResolver = try makeResolver()
    let warmResolver = try makeResolver(packTransform: removingResponseCards)
    var samples: [KnowledgeAnswerLatencySample] = []

    for index in 0..<25 {
      let start = ContinuousClock().now
      let updates = await Self.collect(
        hotResolver.updates(
          for: .questionStable(
            revPARCandidate(streamID: "hot-\(index)", status: .stable, sequence: 1)
          )
        ))
      let update = try XCTUnwrap(updates.first { $0.lane == .hot })
      let timing = try XCTUnwrap(update.timing)
      samples.append(
        KnowledgeAnswerLatencySample(
          lane: .hot,
          endToEndMilliseconds: milliseconds(start.duration(to: ContinuousClock().now)),
          resolverMilliseconds: timing.elapsedMilliseconds
        )
      )
    }

    for index in 0..<25 {
      let start = ContinuousClock().now
      let updates = await Self.collect(
        warmResolver.updates(for: .questionCandidate(warmCandidate(streamID: "warm-\(index)"))))
      let update = try XCTUnwrap(updates.first { $0.lane == .warm })
      let timing = try XCTUnwrap(update.timing)
      samples.append(
        KnowledgeAnswerLatencySample(
          lane: .warm,
          endToEndMilliseconds: milliseconds(start.duration(to: ContinuousClock().now)),
          resolverMilliseconds: timing.elapsedMilliseconds
        )
      )
    }

    let report = KnowledgeAnswerLatencyReport(samples: samples)
    let hot = try XCTUnwrap(report.summary(for: .hot))
    let warm = try XCTUnwrap(report.summary(for: .warm))

    XCTAssertEqual(hot.sampleCount, 25)
    XCTAssertEqual(warm.sampleCount, 25)
    XCTAssertLessThanOrEqual(hot.resolverP50Milliseconds, 40)
    XCTAssertLessThanOrEqual(warm.resolverP50Milliseconds, 250)
    XCTAssertEqual(hot.targetMilliseconds, 1_000)
    XCTAssertEqual(warm.targetMilliseconds, 2_500)
    XCTAssertTrue(report.meetsLiveP50Targets)
  }

  func testStableClaimIsFactCheckedAgainstTypedCorpusValue() async throws {
    let resolver = try makeResolver(packTransform: removingResponseCards)
    let claim = KnowledgeClaimCandidate(
      id: "remote#claim#1",
      streamID: "remote",
      revisionSequence: 3,
      sourceText: "The room count is 120.",
      confidence: 0.9,
      status: .stable,
      bindings: [
        KnowledgeLiveBinding(
          key: "term",
          value: "hospitality.room_count",
          surfaceText: "room count"
        ),
        KnowledgeLiveBinding(key: "literal", value: "120", surfaceText: "120"),
      ]
    )

    let updates = await Self.collect(resolver.updates(for: .claimStable(claim)))

    guard case .exactEvidence(let evidence) = updates.first?.payload else {
      return XCTFail("Expected a typed fact-check outcome.")
    }
    XCTAssertEqual(evidence.state, .contradictedByCorpus)
    XCTAssertEqual(evidence.reason, .claimContradicted)
    XCTAssertEqual(evidence.claims.map(\.displayValue), ["100 room"])
  }

  func testSupersessionRetractsVisibleAnswerAndPreventsResurrection() async throws {
    let resolver = try makeResolver()
    let candidate = revPARCandidate(status: .provisional, sequence: 1)
    let shown = await Self.collect(resolver.updates(for: .questionCandidate(candidate)))
    let supersession = KnowledgeAnswerSupersession(
      previousEventID: candidate.id,
      previousStreamID: candidate.streamID,
      revisionSequence: 2,
      reason: .corrected
    )

    let retracted = await Self.collect(
      resolver.updates(for: .answerSuperseded(supersession)))
    let late = await Self.collect(
      resolver.updates(for: .questionCandidate(candidate)))

    XCTAssertEqual(retracted.count, 1)
    XCTAssertEqual(retracted.first?.action, .retract)
    XCTAssertEqual(retracted.first?.supersedesUpdateID, shown.first?.id)
    XCTAssertNil(retracted.first?.payload)
    XCTAssertTrue(late.isEmpty)
  }

  func testResolverRejectsEvaluatorFromDifferentPackContent() throws {
    let original = try loadFixture()
    let originalIndex = try KnowledgePackSearchIndex(pack: original)
    let originalEvaluator = try KnowledgeEvidenceOutcomeEvaluator(
      pack: original,
      searchIndex: originalIndex,
      rootDirectory: fixtureURL()
    )
    let changed = removingResponseCards(original)
    let changedIndex = try KnowledgePackSearchIndex(pack: changed)

    XCTAssertThrowsError(
      try KnowledgeTieredAnswerResolver(
        pack: changed,
        searchIndex: changedIndex,
        evidenceEvaluator: originalEvaluator,
        rootDirectory: fixtureURL()
      )
    ) { error in
      XCTAssertEqual(error as? KnowledgeEvidenceOutcomeError, .staleIndex)
    }
  }

  @MainActor
  func testStoreBuildsAndClearsTieredResolverWithActivePack() async throws {
    let store = KnowledgePackStore(profileRegistry: registry)

    await store.load(fromPath: fixtureURL().path)
    XCTAssertNotNil(store.tieredAnswerResolver)
    let updates = await Self.collect(
      store.answerUpdates(for: .questionStable(roomCountCandidate())))
    XCTAssertEqual(updates.first?.supportLevel, .reviewed)

    store.clear()
    XCTAssertNil(store.tieredAnswerResolver)
    let clearedUpdates = await Self.collect(
      store.answerUpdates(for: .questionStable(roomCountCandidate())))
    XCTAssertTrue(clearedUpdates.isEmpty)
  }

  @MainActor
  func testStoreCancelsSupersededWarmWorkAndReplacesTheOldCard() async throws {
    let vectorAdapter = CancellationObservingVectorAdapter()
    let store = KnowledgePackStore(
      profileRegistry: registry,
      vectorAdapter: vectorAdapter
    )
    await store.load(fromPath: fixtureURL().path)

    let first = store.processLiveTranscriptRevision(
      TranscriptRevision(
        streamID: "remote",
        sequence: 1,
        text: "What was the rev par",
        stability: .partial
      ))
    XCTAssertEqual(first.map(\.kind), [.questionCandidate])

    for _ in 0..<100 where await vectorAdapter.callCount == 0 {
      try await Task.sleep(for: .milliseconds(5))
    }
    let firstCallCount = await vectorAdapter.callCount
    XCTAssertEqual(firstCallCount, 1)
    XCTAssertEqual(store.visibleOverlayCards.first?.eventID, "remote#1")

    let correction = store.processLiveTranscriptRevision(
      TranscriptRevision(
        streamID: "remote",
        sequence: 2,
        text: "Actually, what was occupancy in 2020?",
        stability: .final
      ))
    XCTAssertEqual(correction.map(\.kind), [.answerSuperseded, .questionStable])

    for _ in 0..<100 where await vectorAdapter.cancellationCount == 0 {
      try await Task.sleep(for: .milliseconds(5))
    }
    for _ in 0..<100 where store.visibleOverlayCards.first?.eventID != "remote#2" {
      try await Task.sleep(for: .milliseconds(5))
    }

    let cancellationCount = await vectorAdapter.cancellationCount
    XCTAssertEqual(cancellationCount, 1)
    XCTAssertGreaterThanOrEqual(store.tieredAnswerTaskCancellationRequestCount, 1)
    XCTAssertEqual(store.visibleOverlayCards.map(\.eventID), ["remote#2"])
    XCTAssertEqual(store.visibleOverlayCards.first?.title, "2020 occupancy")
    let hotLatency = try XCTUnwrap(store.tieredAnswerLatencyReport.summary(for: .hot))
    XCTAssertGreaterThanOrEqual(hotLatency.sampleCount, 2)
    XCTAssertTrue(hotLatency.meetsP50Target == true)
  }

  private var registry: KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func makeResolver(
    packTransform: (KnowledgePack) -> KnowledgePack = { $0 },
    budgets: KnowledgeAnswerLatencyBudgets = KnowledgeAnswerLatencyBudgets()
  ) throws -> KnowledgeTieredAnswerResolver {
    let pack = packTransform(try loadFixture())
    let index = try KnowledgePackSearchIndex(pack: pack)
    let evaluator = try KnowledgeEvidenceOutcomeEvaluator(
      pack: pack,
      searchIndex: index,
      rootDirectory: fixtureURL()
    )
    return try KnowledgeTieredAnswerResolver(
      pack: pack,
      searchIndex: index,
      evidenceEvaluator: evaluator,
      rootDirectory: fixtureURL(),
      budgets: budgets
    )
  }

  private func removingResponseCards(_ pack: KnowledgePack) -> KnowledgePack {
    KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: [],
      questionFamilies: pack.questionFamilies
    )
  }

  private func revPARCandidate(
    streamID: String = "remote",
    status: QuestionCandidateStatus,
    sequence: Int
  ) -> QuestionCandidate {
    QuestionCandidate(
      id: "\(streamID)#1",
      streamID: streamID,
      revisionSequence: sequence,
      questionFamilyID: "question-revpar-period",
      sourceText: "What was RevPAR for this asset in 2020?",
      confidence: 1,
      status: status,
      bindings: [
        ResolvedQuestionBinding(key: "period", value: "2020", surfaceText: "2020"),
        ResolvedQuestionBinding(
          key: "term",
          value: "hospitality.revpar",
          surfaceText: "revpar"
        ),
      ]
    )
  }

  private func roomCountCandidate(streamID: String = "remote") -> QuestionCandidate {
    QuestionCandidate(
      id: "\(streamID)#room-count",
      streamID: streamID,
      revisionSequence: 2,
      questionFamilyID: "question-room-count",
      sourceText: "How many rooms does this hotel have?",
      confidence: 1,
      status: .stable,
      bindings: [
        ResolvedQuestionBinding(
          key: "term",
          value: "hospitality.room_count",
          surfaceText: "rooms"
        )
      ]
    )
  }

  private func warmCandidate(streamID: String) -> QuestionCandidate {
    QuestionCandidate(
      id: "\(streamID)#generic",
      streamID: streamID,
      revisionSequence: 1,
      questionFamilyID: "question-revpar-period",
      sourceText: "What was RevPAR for this asset in 2020?",
      confidence: 0.7,
      status: .provisional,
      bindings: [
        ResolvedQuestionBinding(
          key: "term",
          value: "question_family:question-revpar-period",
          surfaceText: "RevPAR"
        )
      ]
    )
  }

  private static func collect(
    _ stream: AsyncStream<KnowledgeTieredAnswerUpdate>
  ) async -> [KnowledgeTieredAnswerUpdate] {
    var updates: [KnowledgeTieredAnswerUpdate] = []
    for await update in stream { updates.append(update) }
    return updates
  }

  private func loadFixture() throws -> KnowledgePack {
    try KnowledgePackLoader(profileRegistry: registry).load(from: fixtureURL())
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }

  private func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}

private actor CancellationObservingVectorAdapter: KnowledgePackVectorSearchAdapter {
  private(set) var callCount = 0
  private(set) var cancellationCount = 0

  func search(_ request: KnowledgePackVectorSearchRequest) async throws
    -> [KnowledgePackVectorMatch]
  {
    callCount += 1
    guard callCount == 1 else { return [] }
    do {
      try await Task.sleep(for: .seconds(10))
      return []
    } catch {
      if error is CancellationError { cancellationCount += 1 }
      throw error
    }
  }
}

private actor RecordingSynthesizer: KnowledgeConstrainedAnswerSynthesizer {
  enum Behavior: Sendable {
    case valid
    case unknownCitation
    case incompleteCitation
    case delayed(milliseconds: Int)
  }

  private(set) var callCount = 0
  private(set) var lastRequest: KnowledgeConstrainedSynthesisRequest?
  private let behavior: Behavior

  init(behavior: Behavior) {
    self.behavior = behavior
  }

  func synthesize(
    _ request: KnowledgeConstrainedSynthesisRequest
  ) async throws -> KnowledgeConstrainedSynthesisOutput {
    callCount += 1
    lastRequest = request
    if case .delayed(let milliseconds) = behavior {
      try await Task.sleep(for: .milliseconds(milliseconds))
    }
    let validCitations = request.citationRequirements.compactMap {
      $0.anyOfEvidenceRecordIDs.sorted().first
    }
    let citations: [String]
    switch behavior {
    case .unknownCitation:
      citations = ["web:invented-result"]
    case .incompleteCitation:
      citations = Array(validCitations.prefix(1))
    case .valid, .delayed:
      citations = validCitations
    }
    return KnowledgeConstrainedSynthesisOutput(
      title: "Corpus answer",
      answer: "The admitted corpus evidence provides the answer.",
      citedEvidenceRecordIDs: citations
    )
  }
}
