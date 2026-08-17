import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgePackSearchIndexTests: XCTestCase {
  func testExactAliasSearchIsPackBoundAndQualifierScoped() throws {
    let pack = try loadFixture()
    let index = try KnowledgePackSearchIndex(pack: pack)

    let results = try index.search(
      KnowledgePackSearchQuery(
        text: "rev par",
        scope: KnowledgePackSearchScope(
          packID: pack.manifest.packID,
          recordKinds: [.questionFamily, .assertion, .responseCard],
          requiredQualifiers: ["period": "2020"],
          preferredQualifiers: ["scope": "rooms", "status": "actual"]
        )
      )
    )

    XCTAssertFalse(results.isEmpty)
    XCTAssertTrue(results.allSatisfy { $0.packID == pack.manifest.packID })
    XCTAssertTrue(results.allSatisfy { $0.qualifiers["period"] == "2020" })
    XCTAssertTrue(results.contains { $0.channels.contains(.exact) })
    XCTAssertTrue(results.contains { $0.recordID == "question-revpar-period" })
  }

  func testFullTextSearchFindsExactPassageAndRespectsSourceScope() throws {
    let pack = try loadFixture()
    let index = try KnowledgePackSearchIndex(pack: pack)

    let results = try index.search(
      KnowledgePackSearchQuery(
        text: "fictional investment memo inconsistent",
        scope: KnowledgePackSearchScope(
          packID: pack.manifest.packID,
          recordKinds: [.passage],
          sourceIDs: ["source-investment-memo"]
        )
      )
    )

    XCTAssertEqual(results.first?.recordID, "passage-memo-revpar-2020")
    XCTAssertEqual(results.first?.sourceIDs, ["source-investment-memo"])
    XCTAssertEqual(results.first?.channels, [.fullText])
    XCTAssertTrue(results.first?.excerpt.contains("intentionally inconsistent") == true)
  }

  func testMismatchedPackScopeFailsClosed() throws {
    let pack = try loadFixture()
    let index = try KnowledgePackSearchIndex(pack: pack)

    XCTAssertThrowsError(
      try index.search(
        KnowledgePackSearchQuery(
          text: "RevPAR",
          scope: KnowledgePackSearchScope(packID: "another-deal")
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? KnowledgePackSearchError,
        .packMismatch(expected: pack.manifest.packID, actual: "another-deal")
      )
    }
  }

  func testOptionalVectorAdapterCanAddOnlyCurrentScopedCandidates() async throws {
    let pack = try loadFixture()
    let index = try KnowledgePackSearchIndex(pack: pack)
    let adapter = SyntheticVectorAdapter(
      requestedRecordID: "assertion-revpar-calculated-2020",
      maliciousCandidateID: "assertion:other-pack-secret"
    )

    let results = try await index.search(
      KnowledgePackSearchQuery(
        text: "nightly pricing efficiency",
        scope: KnowledgePackSearchScope(
          packID: pack.manifest.packID,
          recordKinds: [.assertion],
          requiredQualifiers: ["period": "2020", "scope": "rooms"]
        )
      ),
      vectorAdapter: adapter
    )

    XCTAssertEqual(results.first?.recordID, "assertion-revpar-calculated-2020")
    XCTAssertTrue(results.first?.channels.contains(.vector) == true)
    XCTAssertFalse(results.contains { $0.recordID == "other-pack-secret" })
    let request = await adapter.lastRequest
    XCTAssertEqual(request?.packID, pack.manifest.packID)
    XCTAssertTrue(request?.candidates.allSatisfy { $0.kind == .assertion } == true)
    XCTAssertEqual(request?.disclosure.destination, .externalProvider)
    XCTAssertEqual(request?.disclosure.candidateRecordCount, request?.candidates.count)
    XCTAssertEqual(
      Set(request?.disclosure.dataClasses ?? []),
      [.queryText, .candidateSearchText, .candidateTitles, .corpusIdentifiers]
    )
    XCTAssertTrue(request?.disclosure.leavesDevice == true)
  }

  func testSourceHashChangeInvalidatesEveryTransitiveDependent() throws {
    let original = try loadFixture()
    let changedSource = try XCTUnwrap(
      original.sources.first { $0.id == "source-operating-statement" }
    )
    let changed = copy(
      original,
      sources: original.sources.map { source in
        guard source.id == changedSource.id else { return source }
        return KnowledgeSource(
          id: source.id,
          kind: source.kind,
          title: source.title,
          relativePath: source.relativePath,
          sha256: String(repeating: "f", count: 64),
          importedAt: source.importedAt
        )
      }
    )

    let plan = try KnowledgePackDependencyInvalidator().plan(from: original, to: changed)

    XCTAssertTrue(plan.requiresRebuild)
    XCTAssertEqual(
      plan.directlyChanged,
      [.init(kind: .source, id: "source-operating-statement")]
    )
    for expected in [
      KnowledgePackArtifactReference(kind: .passage, id: "passage-operating-2020-actual"),
      .init(kind: .evidenceLink, id: "evidence-room-revenue-2020"),
      .init(kind: .assertion, id: "assertion-room-revenue-2020"),
      .init(kind: .calculation, id: "calculation-revpar-v1"),
      .init(kind: .responseCard, id: "card-revpar-2020"),
    ] {
      XCTAssertTrue(plan.invalidated.contains(expected), "Missing invalidation: \(expected)")
    }
  }

  func testUnchangedPackProducesNoInvalidations() throws {
    let pack = try loadFixture()

    let plan = try KnowledgePackDependencyInvalidator().plan(from: pack, to: pack)

    XCTAssertFalse(plan.requiresRebuild)
    XCTAssertTrue(plan.directlyChanged.isEmpty)
    XCTAssertTrue(plan.invalidated.isEmpty)
  }

  func testIndexerReusesContentIdenticalIndex() throws {
    let pack = try loadFixture()
    let first = try KnowledgePackSearchIndexer.build(pack: pack)

    let second = try KnowledgePackSearchIndexer.build(
      pack: pack,
      previousPack: pack,
      previousIndex: first.index
    )

    XCTAssertTrue(first.index === second.index)
    XCTAssertTrue(second.report.reusedExistingIndex)
    XCTAssertFalse(second.report.invalidationPlan?.requiresRebuild == true)
  }

  func testIndexerDoesNotCompareOrReuseAcrossPackIDs() throws {
    let firstPack = try loadFixture()
    let first = try KnowledgePackSearchIndexer.build(pack: firstPack)
    let secondManifest = KnowledgePackManifest(
      schemaVersion: firstPack.manifest.schemaVersion,
      packID: "a-separate-pack",
      title: firstPack.manifest.title,
      createdAt: firstPack.manifest.createdAt,
      defaultLocale: firstPack.manifest.defaultLocale,
      domainProfiles: firstPack.manifest.domainProfiles
    )
    let secondPack = copy(firstPack, manifest: secondManifest)

    let second = try KnowledgePackSearchIndexer.build(
      pack: secondPack,
      previousPack: firstPack,
      previousIndex: first.index
    )

    XCTAssertEqual(second.index.packID, "a-separate-pack")
    XCTAssertFalse(first.index === second.index)
    XCTAssertFalse(second.report.reusedExistingIndex)
    XCTAssertNil(second.report.invalidationPlan)
  }

  func testManifestChangeInvalidatesTheWholePackGraph() throws {
    let original = try loadFixture()
    let changedManifest = KnowledgePackManifest(
      schemaVersion: original.manifest.schemaVersion,
      packID: original.manifest.packID,
      title: "Retitled Search Pack",
      createdAt: original.manifest.createdAt,
      defaultLocale: original.manifest.defaultLocale,
      domainProfiles: original.manifest.domainProfiles
    )

    let plan = try KnowledgePackDependencyInvalidator().plan(
      from: original,
      to: copy(original, manifest: changedManifest)
    )

    XCTAssertTrue(
      plan.directlyChanged.contains(.init(kind: .manifest, id: original.manifest.packID))
    )
    XCTAssertTrue(
      plan.invalidated.contains(.init(kind: .source, id: "source-operating-statement"))
    )
    XCTAssertTrue(
      plan.invalidated.contains(.init(kind: .responseCard, id: "card-revpar-2020"))
    )
  }

  func testIndexerReportsContentBoundRebuild() throws {
    let original = try loadFixture()
    let changed = copy(
      original,
      questionFamilies: original.questionFamilies + [
        KnowledgeQuestionFamily(
          id: "question-new-search-case",
          canonicalQuestion: "What changed in the search corpus?",
          variants: []
        )
      ]
    )

    let build = try KnowledgePackSearchIndexer.build(pack: changed, previousPack: original)

    XCTAssertEqual(build.report.packID, original.manifest.packID)
    XCTAssertEqual(build.report.packContentHash, build.index.packContentHash)
    XCTAssertTrue(build.report.invalidationPlan?.requiresRebuild == true)
    XCTAssertFalse(build.report.reusedExistingIndex)
    XCTAssertTrue(
      build.report.invalidationPlan?.directlyChanged.contains(
        .init(kind: .questionFamily, id: "question-new-search-case")
      ) == true
    )
    XCTAssertGreaterThan(build.report.indexedDocumentCount, 0)
  }

  @MainActor
  func testStoreBuildsAndRefreshesPackBoundIndex() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "knowledge-pack-search-store-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.copyItem(at: fixtureURL(), to: root)
    let store = KnowledgePackStore(profileRegistry: registry)

    await store.load(fromPath: root.path)
    let originalIndex = try XCTUnwrap(store.searchIndex)
    XCTAssertGreaterThan(originalIndex.documentCount, 0)
    let searchResults = try store.searchKnowledgePack(
      KnowledgePackSearchQuery(
        text: "revpar",
        scope: KnowledgePackSearchScope(
          packID: originalIndex.packID,
          recordKinds: [.questionFamily]
        )
      )
    )
    XCTAssertTrue(searchResults.contains { $0.recordID == "question-revpar-period" })

    await store.reload()
    XCTAssertTrue(originalIndex === store.searchIndex)
    XCTAssertTrue(store.searchRebuildReport?.reusedExistingIndex == true)

    try appendJSONLine(
      KnowledgeQuestionFamily(
        id: "question-added-for-store-rebuild",
        canonicalQuestion: "Did the active corpus index rebuild?",
        variants: []
      ),
      to: root.appendingPathComponent("question-families.jsonl")
    )
    await store.reload()

    XCTAssertFalse(originalIndex === store.searchIndex)
    XCTAssertTrue(store.searchRebuildReport?.invalidationPlan?.requiresRebuild == true)
    XCTAssertTrue(
      store.searchRebuildReport?.invalidationPlan?.directlyChanged.contains(
        .init(kind: .questionFamily, id: "question-added-for-store-rebuild")
      ) == true
    )
  }

  private actor SyntheticVectorAdapter: KnowledgePackVectorSearchAdapter {
    let requestedRecordID: String
    let maliciousCandidateID: String
    private(set) var lastRequest: KnowledgePackVectorSearchRequest?

    init(requestedRecordID: String, maliciousCandidateID: String) {
      self.requestedRecordID = requestedRecordID
      self.maliciousCandidateID = maliciousCandidateID
    }

    func search(_ request: KnowledgePackVectorSearchRequest) async throws
      -> [KnowledgePackVectorMatch]
    {
      lastRequest = request
      let requestedCandidate = try XCTUnwrap(
        request.candidates.first { $0.recordID == requestedRecordID }
      )
      return [
        KnowledgePackVectorMatch(candidateID: requestedCandidate.id, score: 0.98),
        KnowledgePackVectorMatch(candidateID: maliciousCandidateID, score: 1),
      ]
    }
  }

  private func loadFixture() throws -> KnowledgePack {
    try KnowledgePackLoader(profileRegistry: registry).load(from: fixtureURL())
  }

  private var registry: KnowledgeDomainProfileRegistry {
    KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }

  private func copy(
    _ pack: KnowledgePack,
    manifest: KnowledgePackManifest? = nil,
    sources: [KnowledgeSource]? = nil,
    questionFamilies: [KnowledgeQuestionFamily]? = nil
  ) -> KnowledgePack {
    KnowledgePack(
      manifest: manifest ?? pack.manifest,
      sources: sources ?? pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: questionFamilies ?? pack.questionFamilies
    )
  }

  private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: encoder.encode(value))
    try handle.write(contentsOf: Data("\n".utf8))
  }
}
