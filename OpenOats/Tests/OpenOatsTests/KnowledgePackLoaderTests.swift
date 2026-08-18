import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgePackLoaderTests: XCTestCase {
  func testValidKnowledgePackPassesStructuralValidation() {
    let report = makeLoader().validate(makeValidPack())

    XCTAssertTrue(report.isValid)
    XCTAssertTrue(report.errors.isEmpty)
  }

  func testCredentialLikeMaterialInPackRecordsFailsClosedWithoutEchoingSecret() {
    let valid = makeValidPack()
    let secret = "sk-proj-abcdefghijklmnopqrstuvwxyz123456"
    let original = valid.passages[0]
    let taintedPassage = KnowledgePassage(
      id: original.id,
      sourceID: original.sourceID,
      text: "Internal API key: \(secret)",
      locator: original.locator,
      extraction: original.extraction,
      spreadsheet: original.spreadsheet
    )
    let tainted = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: [taintedPassage],
      assertions: valid.assertions,
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(tainted)
    let securityIssues = report.errors.filter { $0.code == "security.secret_detected" }

    XCTAssertFalse(report.isValid)
    XCTAssertFalse(securityIssues.isEmpty)
    XCTAssertTrue(securityIssues.allSatisfy { !$0.message.contains(secret) })
    XCTAssertTrue(securityIssues.contains { $0.message.contains("passages.jsonl record 1 text") })
  }

  func testCalculatedCardRequiresRecordedCalculation() {
    let valid = makeValidPack()
    let invalidCard = KnowledgeResponseCard(
      id: "card-revpar",
      title: "2020 RevPAR",
      answer: "$89.50",
      evidenceState: .calculated,
      questionFamilyIDs: ["question-revpar"],
      assertionIDs: ["assertion-revpar"],
      citationPassageIDs: ["passage-revpar"],
      calculationIDs: [],
      reviewStatus: .reviewed
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions,
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: [invalidCard],
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "card.calculation_missing_derivation" })
  }

  func testCalculatedCardMustClaimItsCalculationOutput() {
    let valid = makeValidPack()
    let card = valid.responseCards[0]
    let invalidCard = KnowledgeResponseCard(
      id: card.id,
      title: card.title,
      answer: card.answer,
      evidenceState: card.evidenceState,
      questionFamilyIDs: card.questionFamilyIDs,
      assertionIDs: [],
      citationPassageIDs: card.citationPassageIDs,
      calculationIDs: card.calculationIDs,
      reviewStatus: card.reviewStatus
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions,
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: [invalidCard],
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertTrue(
      report.errors.contains { $0.code == "card.calculation_output_not_claimed" })
  }

  func testAssertionCannotBorrowAnotherAssertionsEvidence() {
    let valid = makeValidPack()
    let mismatched = KnowledgeAssertion(
      id: "assertion-other",
      subject: "synthetic-hotel",
      predicate: "hospitality.occupancy",
      value: KnowledgeValue(type: .number, number: 0.75, unit: "ratio", scale: 1),
      qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: ["evidence-revpar"]
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions + [mismatched],
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "assertion.mismatched_evidence" })
  }

  func testUnknownDomainProfileFailsClosed() {
    let valid = makeValidPack()
    let manifest = KnowledgePackManifest(
      schemaVersion: valid.manifest.schemaVersion,
      packID: valid.manifest.packID,
      title: valid.manifest.title,
      createdAt: valid.manifest.createdAt,
      defaultLocale: valid.manifest.defaultLocale,
      domainProfiles: [DomainProfileReference(id: "unregistered-domain", version: "1.0.0")]
    )
    let invalid = KnowledgePack(
      manifest: manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions,
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "profile.unknown" })
  }

  func testHospitalityProfileRejectsUnregisteredPredicate() {
    let valid = makeValidPack()
    let unknown = KnowledgeAssertion(
      id: "assertion-unregistered-metric",
      subject: "synthetic-hotel",
      predicate: "hospitality.unregistered_metric",
      value: KnowledgeValue(type: .number, number: 1, unit: "USD", scale: 1),
      qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: []
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions + [unknown],
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "profile.unknown_predicate" })
  }

  func testHospitalityProfileRejectsUnitMismatch() {
    let valid = makeValidPack()
    let roomRevenue = KnowledgeAssertion(
      id: "assertion-room-revenue",
      subject: "synthetic-hotel",
      predicate: "hospitality.room_revenue",
      value: KnowledgeValue(type: .number, number: 3_266_750, unit: "EUR", scale: 1),
      qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: ["evidence-room-revenue"]
    )
    let invalid = KnowledgePack(
      manifest: valid.manifest,
      sources: valid.sources,
      passages: valid.passages,
      assertions: valid.assertions.map {
        $0.id == roomRevenue.id ? roomRevenue : $0
      },
      evidenceLinks: valid.evidenceLinks,
      calculations: valid.calculations,
      responseCards: valid.responseCards,
      questionFamilies: valid.questionFamilies
    )

    let report = makeLoader().validate(invalid)

    XCTAssertFalse(report.isValid)
    XCTAssertTrue(report.errors.contains { $0.code == "profile.invalid_unit" })
  }

  func testExpandedHospitalityFixtureAndGoldenCasesLoad() throws {
    let fixture = fixtureURL()
    let pack = try makeLoader().load(from: fixture)

    XCTAssertEqual(pack.sources.count, 3)
    XCTAssertEqual(pack.passages.count, 3)
    XCTAssertEqual(pack.assertions.count, 18)
    XCTAssertEqual(pack.calculations.count, 6)
    XCTAssertEqual(pack.responseCards.count, 9)
    XCTAssertEqual(pack.questionFamilies.count, 9)

    let goldenURL = fixture.appendingPathComponent("evaluation/golden-cases.jsonl")
    let contents = try String(contentsOf: goldenURL, encoding: .utf8)
    let cases = try contents.split(whereSeparator: \.isNewline).map {
      try JSONDecoder().decode(GoldenCase.self, from: Data($0.utf8))
    }
    let cards = Dictionary(uniqueKeysWithValues: pack.responseCards.map { ($0.id, $0) })

    XCTAssertEqual(cases.count, 7)
    XCTAssertEqual(
      Set(cases.map(\.expectedEvidenceState)),
      [
        .calculated,
        .contested,
        .directlySourced,
        .notFoundInCorpus,
      ])
    for golden in cases {
      let card = try XCTUnwrap(cards[golden.expectedCardID], golden.id)
      XCTAssertEqual(card.evidenceState, golden.expectedEvidenceState, golden.id)
      XCTAssertEqual(card.reviewStatus, .reviewed, golden.id)
      for fragment in golden.expectedAnswerContains {
        XCTAssertTrue(card.answer.contains(fragment), "\(golden.id) missing '\(fragment)'")
      }
    }
  }

  @MainActor
  func testAppStoreLoadsInPlaceWithoutMutatingOrCopyingFixture() async throws {
    let fixture = fixtureURL()
    let contentsBeforeLoad = try directoryContents(at: fixture)
    let store = KnowledgePackStore(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))

    await store.load(fromPath: fixture.path)

    guard case .loaded(_, let summary) = store.state else {
      return XCTFail("Expected the app KnowledgePack store to load the fixture; got \(store.state)")
    }
    XCTAssertEqual(summary.title, "Synthetic Hotel 2020 Reference Pack")
    XCTAssertEqual(summary.sourceCount, 3)
    XCTAssertEqual(summary.assertionCount, 18)
    XCTAssertEqual(summary.responseCardCount, 9)
    XCTAssertEqual(store.selectedPackDirectory?.standardizedFileURL, fixture.standardizedFileURL)
    XCTAssertEqual(try directoryContents(at: fixture), contentsBeforeLoad)
  }

  func testSourceFileContainingCredentialFailsClosedWithoutEchoingIt() throws {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent("pack-secret-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.copyItem(at: fixtureURL(), to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let secret = "AIza" + String(repeating: "B", count: 35)
    let target = temporary.appendingPathComponent("sources/demo-room-inventory.csv")
    let existing = try String(contentsOf: target, encoding: .utf8)
    try (existing + "\nnotes,\(secret)\n").write(to: target, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(try makeLoader().load(from: temporary)) { error in
      let description = String(describing: error)
      XCTAssertTrue(description.contains("security.secret_in_source_file"))
      XCTAssertTrue(description.contains("source.hash_mismatch"), "edited file also fails its hash")
      XCTAssertFalse(description.contains(secret), "the secret value must never be echoed")
    }
  }

  func testOversizedRecordFileFailsClosedWithExplicitError() {
    let tiny = KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]),
      limits: KnowledgePackLoader.Limits(recordFileBytes: 16)
    )
    XCTAssertThrowsError(try tiny.load(from: fixtureURL())) { error in
      guard case KnowledgePackLoadingError.fileTooLarge(let name, _, let limit) = error else {
        return XCTFail("expected fileTooLarge, got \(error)")
      }
      XCTAssertTrue(name.hasSuffix(".jsonl"))
      XCTAssertEqual(limit, 16)
    }
  }

  func testSymlinkToOversizedRecordFileIsRejected() throws {
    // FileManager.attributesOfItem(atPath:) (the old size-check mechanism)
    // does NOT follow symlinks, while the actual content read
    // (String(contentsOf:)) does — a symlink to a huge file bypassed the
    // ceiling. The fix must read the size through the same follow-the-link
    // path the content read uses.
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent("pack-symlink-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.copyItem(at: fixtureURL(), to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }

    // sources.jsonl (772 B) and passages.jsonl (1,247 B) decode before
    // assertions.jsonl and must stay under the limit untouched, so only the
    // symlinked file is what trips the ceiling below.
    let recordFile = temporary.appendingPathComponent("assertions.jsonl")
    try FileManager.default.removeItem(at: recordFile)

    let oversizedBacking = temporary.appendingPathComponent("oversized-backing.txt")
    let payload = String(repeating: "x", count: 5_000)
    try payload.write(to: oversizedBacking, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: recordFile, withDestinationURL: oversizedBacking)

    let tiny = KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]),
      limits: KnowledgePackLoader.Limits(recordFileBytes: 2_000)
    )
    XCTAssertThrowsError(try tiny.load(from: temporary)) { error in
      guard
        case KnowledgePackLoadingError.fileTooLarge(let name, let byteCount, let limit) = error
      else {
        return XCTFail("expected fileTooLarge, got \(error)")
      }
      XCTAssertEqual(name, "assertions.jsonl")
      XCTAssertEqual(limit, 2_000)
      XCTAssertEqual(
        byteCount, 5_000, "size must be read through the symlink, not the link entry itself")
    }
  }

  func testOversizedSourceFileSkipsSecretScanWithWarning() throws {
    let scanCapped = KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]),
      limits: KnowledgePackLoader.Limits(sourceScanBytes: 4)
    )
    // Loading must still succeed — the scan skip is a warning, not an error —
    // and the warning must surface through the full load-path validation.
    let issues = try issuesFromLoad(scanCapped, expectSuccess: true)
    XCTAssertTrue(issues.contains { $0.code == "security.source_scan_skipped" })
    XCTAssertTrue(
      issues.first { $0.code == "security.source_scan_skipped" }?.severity == .warning)
  }

  func testNearIdenticalNumericAssertionsProduceAuthorWarning() throws {
    let pack = try makeLoader().load(from: fixtureURL())
    guard let template = pack.assertions.first(where: { $0.value.type == .number }) else {
      return XCTFail("fixture has numeric assertions")
    }
    // Two assertions for the same fact whose stored doubles differ by 1 ULP.
    let base = 0.0905
    let twin = 9.05 / 100.0
    XCTAssertNotEqual(base, twin, "pair must genuinely drift for this test to mean anything")

    let report = makeLoader().validate(
      copyReplacingAssertionValues(pack, template: template, numbers: [base, twin])
    )
    XCTAssertTrue(report.issues.contains { $0.code == "assertion.near_identical_value" })
    XCTAssertTrue(
      report.issues.first { $0.code == "assertion.near_identical_value" }?
        .severity == .warning)
  }

  /// Clones `template` once per entry in `numbers`, giving each clone a new
  /// ID and the replacement number but otherwise copying every field
  /// verbatim (subject/predicate/qualifiers/kind/confidence/evidenceLinkIDs,
  /// and the value's unit/scale/text/boolean/date/referenceID), then appends
  /// the clones to `pack.assertions`. The clones intentionally keep the
  /// template's evidenceLinkIDs even though those links still point back at
  /// the template's own ID: the resulting mismatched-evidence/missing-derivation
  /// errors are unrelated to the near-twin check under test and are expected.
  private func copyReplacingAssertionValues(
    _ pack: KnowledgePack,
    template: KnowledgeAssertion,
    numbers: [Double]
  ) -> KnowledgePack {
    let clones = numbers.enumerated().map { offset, number in
      KnowledgeAssertion(
        id: "\(template.id)-near-twin-\(offset)",
        subject: template.subject,
        predicate: template.predicate,
        value: KnowledgeValue(
          type: template.value.type,
          text: template.value.text,
          number: number,
          boolean: template.value.boolean,
          date: template.value.date,
          referenceID: template.value.referenceID,
          unit: template.value.unit,
          scale: template.value.scale
        ),
        qualifiers: template.qualifiers,
        kind: template.kind,
        confidence: template.confidence,
        evidenceLinkIDs: template.evidenceLinkIDs
      )
    }
    return KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions + clones,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
  }

  func testQualifierValidationMessagesTruncateAndRedactEchoedValues() throws {
    let pack = try makeLoader().load(from: fixtureURL())
    guard let template = pack.assertions.first else { return XCTFail("fixture has assertions") }
    let secret = "api_key = " + String(repeating: "Z", count: 300)
    let poisoned = KnowledgeAssertion(
      id: "assertion-echo-probe",
      subject: template.subject,
      predicate: template.predicate,
      value: template.value,
      qualifiers: [secret: "x"],
      kind: template.kind,
      confidence: template.confidence,
      evidenceLinkIDs: template.evidenceLinkIDs
    )
    let mutated = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions + [poisoned],
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
    let report = makeLoader().validate(mutated)
    let echoing = report.issues.filter { $0.code == "assertion.invalid_qualifier_key" }
    XCTAssertFalse(echoing.isEmpty)
    for issue in echoing {
      XCTAssertFalse(issue.message.contains(String(repeating: "Z", count: 100)))
      XCTAssertTrue(issue.message.contains("<redacted:") || issue.message.count < 250)
    }
  }

  func testEchoSafeBoundsCombiningScalarRuns() throws {
    let pack = try makeLoader().load(from: fixtureURL())
    guard let template = pack.assertions.first else { return XCTFail("fixture has assertions") }
    // A single Character can carry unbounded combining scalars: Swift's
    // Character-based `.count`/`.prefix(80)` sees this whole run as ONE
    // extended grapheme cluster (.count == 1), so a naive bound would pass
    // the entire ~10KB string through untruncated. This key is
    // SensitiveDataGuard-inert (no secret-shaped substring), isolating the
    // truncation bound from redaction behavior.
    let combiningBomb = "a" + String(repeating: "\u{0301}", count: 5_000)
    let poisoned = KnowledgeAssertion(
      id: "assertion-echo-scalar-probe",
      subject: template.subject,
      predicate: template.predicate,
      value: template.value,
      qualifiers: [combiningBomb: "x"],
      kind: template.kind,
      confidence: template.confidence,
      evidenceLinkIDs: template.evidenceLinkIDs
    )
    let mutated = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions + [poisoned],
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )
    let report = makeLoader().validate(mutated)
    let echoing = report.issues.filter { $0.code == "assertion.invalid_qualifier_key" }
    XCTAssertFalse(echoing.isEmpty)
    for issue in echoing {
      XCTAssertLessThanOrEqual(
        issue.message.utf8.count, 200,
        "echoed qualifier key must be bounded on UTF-8 bytes, not Character count")
    }
  }

  private func directoryContents(at root: URL) throws -> [String: Data] {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles]
      )
    else { return [:] }

    var result: [String: Data] = [:]
    for case let fileURL as URL in enumerator {
      let values = try fileURL.resourceValues(forKeys: Set(keys))
      guard values.isRegularFile == true else { continue }
      let relativePath = String(fileURL.path.dropFirst(root.path.count + 1))
      result[relativePath] = try Data(contentsOf: fileURL)
    }
    return result
  }

  private func issuesFromLoad(
    _ loader: KnowledgePackLoader, expectSuccess: Bool
  ) throws -> [KnowledgePackValidationIssue] {
    let result = try loader.loadWithReport(from: fixtureURL())
    if expectSuccess { XCTAssertTrue(result.report.isValid) }
    return result.report.issues
  }

  private func makeLoader() -> KnowledgePackLoader {
    KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()]))
  }

  private func fixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("fixtures/knowledge-packs/minimal-hospitality", isDirectory: true)
  }

  private struct GoldenCase: Decodable {
    let id: String
    let expectedCardID: String
    let expectedEvidenceState: KnowledgeEvidenceState
    let expectedAnswerContains: [String]
  }

  private func makeValidPack() -> KnowledgePack {
    let manifest = KnowledgePackManifest(
      schemaVersion: 1,
      packID: "test-pack",
      title: "Test Pack",
      createdAt: Date(timeIntervalSince1970: 0),
      defaultLocale: "en-US",
      domainProfiles: [DomainProfileReference(id: "hospitality", version: "0.1.0")]
    )
    let source = KnowledgeSource(
      id: "source-operating-statement",
      kind: .spreadsheet,
      title: "Operating Statement",
      relativePath: "sources/operating-statement.csv",
      sha256: String(repeating: "a", count: 64),
      importedAt: Date(timeIntervalSince1970: 0)
    )
    let passage = KnowledgePassage(
      id: "passage-revpar",
      sourceID: source.id,
      text: "2020 RevPAR was $89.50.",
      locator: KnowledgeSourceLocator(sheet: "Operating Statement", cellRange: "D2")
    )
    let roomRevenueEvidence = KnowledgeEvidenceLink(
      id: "evidence-room-revenue",
      assertionID: "assertion-room-revenue",
      passageID: passage.id,
      relation: .supports
    )
    let availableRoomNightsEvidence = KnowledgeEvidenceLink(
      id: "evidence-available-room-nights",
      assertionID: "assertion-available-room-nights",
      passageID: passage.id,
      relation: .supports
    )
    let evidence = KnowledgeEvidenceLink(
      id: "evidence-revpar",
      assertionID: "assertion-revpar",
      passageID: passage.id,
      relation: .derives
    )
    let roomRevenue = KnowledgeAssertion(
      id: "assertion-room-revenue",
      subject: "synthetic-hotel",
      predicate: "hospitality.room_revenue",
      value: KnowledgeValue(type: .number, number: 3_266_750, unit: "USD", scale: 1),
      qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: [roomRevenueEvidence.id]
    )
    let availableRoomNights = KnowledgeAssertion(
      id: "assertion-available-room-nights",
      subject: "synthetic-hotel",
      predicate: "hospitality.available_room_nights",
      value: KnowledgeValue(type: .number, number: 36_500, unit: "room_night", scale: 1),
      qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
      kind: .stated,
      confidence: 1,
      evidenceLinkIDs: [availableRoomNightsEvidence.id]
    )
    let assertion = KnowledgeAssertion(
      id: "assertion-revpar",
      subject: "synthetic-hotel",
      predicate: "hospitality.revpar",
      value: KnowledgeValue(type: .number, number: 89.5, unit: "USD_per_available_room", scale: 1),
      qualifiers: ["period": "2020", "scope": "rooms", "status": "actual"],
      kind: .calculated,
      confidence: 1,
      evidenceLinkIDs: [evidence.id]
    )
    let calculation = KnowledgeCalculation(
      id: "calculation-revpar",
      name: "RevPAR",
      version: "1.0.0",
      expression: "room_revenue / available_room_nights",
      inputAssertionIDs: [roomRevenue.id, availableRoomNights.id],
      outputAssertionID: assertion.id
    )
    let question = KnowledgeQuestionFamily(
      id: "question-revpar",
      canonicalQuestion: "What was RevPAR in 2020?",
      variants: ["What was revenue per available room in 2020?"]
    )
    let card = KnowledgeResponseCard(
      id: "card-revpar",
      title: "2020 RevPAR",
      answer: "$89.50",
      evidenceState: .calculated,
      questionFamilyIDs: [question.id],
      assertionIDs: [assertion.id],
      citationPassageIDs: [passage.id],
      calculationIDs: [calculation.id],
      reviewStatus: .reviewed
    )

    return KnowledgePack(
      manifest: manifest,
      sources: [source],
      passages: [passage],
      assertions: [roomRevenue, availableRoomNights, assertion],
      evidenceLinks: [roomRevenueEvidence, availableRoomNightsEvidence, evidence],
      calculations: [calculation],
      responseCards: [card],
      questionFamilies: [question]
    )
  }
}
