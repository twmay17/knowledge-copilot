import HospitalityDomainProfile
import XCTest

@testable import OpenOatsKit

final class KnowledgeStudyBundleTests: XCTestCase {
  func testBundleIsClosedCorpusCitedAndContainsOnlyReviewedCards() throws {
    let pack = try loadFixture()
    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)

    XCTAssertEqual(bundle.schemaVersion, 1)
    XCTAssertTrue(bundle.bundleID.hasPrefix("study-"))
    XCTAssertEqual(bundle.packID, pack.manifest.packID)
    XCTAssertEqual(bundle.sources.count, 3)
    XCTAssertEqual(bundle.citedPassages.count, 3)
    XCTAssertEqual(bundle.assertions.count, 18)
    XCTAssertEqual(bundle.reviewedResponseCards.count, 9)
    XCTAssertTrue(bundle.policy.closedCorpusOnly)
    XCTAssertFalse(bundle.policy.webSearchAllowed)
    XCTAssertTrue(bundle.policy.citationsRequired)
    XCTAssertTrue(bundle.policy.documentInstructionsAreData)
    XCTAssertEqual(bundle.policy.unsupportedAnswerState, .notFoundInCorpus)
    XCTAssertTrue(
      bundle.assertions.allSatisfy {
        !$0.evidence.isEmpty || $0.kind == .calculated
      })
    XCTAssertTrue(
      bundle.assertions.flatMap(\.evidence).allSatisfy {
        !$0.excerpt.isEmpty && !$0.sourceRelativePath.hasPrefix("/")
      })
    XCTAssertTrue(
      bundle.reviewedResponseCards.flatMap(\.citationPassageIDs).allSatisfy { passageID in
        bundle.citedPassages.contains { $0.id == passageID && !$0.excerpt.isEmpty }
      })
  }

  func testBundleContentHashAndOrderingAreDeterministic() throws {
    let pack = try loadFixture()
    let reordered = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources.reversed(),
      passages: pack.passages.reversed(),
      assertions: pack.assertions.reversed(),
      evidenceLinks: pack.evidenceLinks.reversed(),
      calculations: pack.calculations.reversed(),
      responseCards: pack.responseCards.reversed(),
      questionFamilies: pack.questionFamilies.reversed()
    )

    let first = try KnowledgeStudyBundleBuilder().build(from: pack)
    let second = try KnowledgeStudyBundleBuilder().build(from: reordered)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.sources.map(\.id), first.sources.map(\.id).sorted())
    XCTAssertEqual(first.assertions.map(\.id), first.assertions.map(\.id).sorted())
  }

  func testBundleContentHashChangesWhenAssertionContentChanges() throws {
    let pack = try loadFixture()
    let assertion = try XCTUnwrap(pack.assertions.first)
    let changedAssertion = KnowledgeAssertion(
      id: assertion.id,
      subject: assertion.subject,
      predicate: assertion.predicate,
      value: assertion.value,
      qualifiers: assertion.qualifiers,
      kind: assertion.kind,
      confidence: max(0, assertion.confidence - 0.01),
      evidenceLinkIDs: assertion.evidenceLinkIDs
    )
    let changedPack = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions.map { $0.id == assertion.id ? changedAssertion : $0 },
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )

    let original = try KnowledgeStudyBundleBuilder().build(from: pack)
    let changed = try KnowledgeStudyBundleBuilder().build(from: changedPack)

    XCTAssertNotEqual(original.packContentHash, changed.packContentHash)
    XCTAssertNotEqual(original.bundleID, changed.bundleID)
  }

  func testBuilderIsDomainNeutralWhenPackUsesNoProfile() throws {
    let hash = String(repeating: "a", count: 64)
    let pack = KnowledgePack(
      manifest: KnowledgePackManifest(
        schemaVersion: 1,
        packID: "product-pitch",
        title: "Product Pitch",
        createdAt: Date(timeIntervalSince1970: 0),
        defaultLocale: "en-US",
        domainProfiles: []
      ),
      sources: [
        KnowledgeSource(
          id: "source-brief",
          kind: .document,
          title: "Product brief",
          relativePath: "sources/product-brief.txt",
          sha256: hash,
          importedAt: Date(timeIntervalSince1970: 0)
        )
      ],
      passages: [
        KnowledgePassage(
          id: "passage-price",
          sourceID: "source-brief",
          text: "The launch price is $49.",
          locator: KnowledgeSourceLocator(contentSHA256: hash)
        )
      ],
      assertions: [
        KnowledgeAssertion(
          id: "assertion-price",
          subject: "product",
          predicate: "product.launch_price",
          value: KnowledgeValue(type: .number, number: 49, unit: "USD", scale: 1),
          kind: .stated,
          confidence: 1,
          evidenceLinkIDs: ["evidence-price"]
        )
      ],
      evidenceLinks: [
        KnowledgeEvidenceLink(
          id: "evidence-price",
          assertionID: "assertion-price",
          passageID: "passage-price",
          relation: .supports
        )
      ],
      calculations: [],
      responseCards: [
        KnowledgeResponseCard(
          id: "card-price",
          title: "Launch price",
          answer: "The launch price is $49.",
          evidenceState: .directlySourced,
          questionFamilyIDs: ["question-price"],
          assertionIDs: ["assertion-price"],
          citationPassageIDs: ["passage-price"],
          reviewStatus: .reviewed
        )
      ],
      questionFamilies: [
        KnowledgeQuestionFamily(
          id: "question-price",
          canonicalQuestion: "What is the launch price?",
          variants: ["How much does it cost?"]
        )
      ]
    )

    let bundle = try KnowledgeStudyBundleBuilder().build(from: pack)

    XCTAssertTrue(bundle.domainProfiles.isEmpty)
    XCTAssertEqual(bundle.assertions.first?.predicate, "product.launch_price")
    XCTAssertEqual(bundle.reviewedResponseCards.first?.answer, "The launch price is $49.")
  }

  func testCalculatedAssertionNamesItsRegisteredDerivation() throws {
    let bundle = try KnowledgeStudyBundleBuilder().build(from: loadFixture())
    let calculatedRevPAR = try XCTUnwrap(
      bundle.assertions.first { $0.id == "assertion-revpar-calculated-2020" })

    XCTAssertEqual(calculatedRevPAR.kind, .calculated)
    XCTAssertEqual(calculatedRevPAR.calculationID, "calculation-revpar-v1")
    XCTAssertEqual(calculatedRevPAR.evidence.first?.relation, .derives)
  }

  func testGeneratedCardsAreExcludedFromPreparationAuthority() throws {
    let pack = try loadFixture()
    let reviewed = try XCTUnwrap(pack.responseCards.first)
    let generated = KnowledgeResponseCard(
      id: "card-generated-proposal",
      title: reviewed.title,
      answer: "Unreviewed model proposal",
      evidenceState: reviewed.evidenceState,
      questionFamilyIDs: reviewed.questionFamilyIDs,
      assertionIDs: reviewed.assertionIDs,
      citationPassageIDs: reviewed.citationPassageIDs,
      calculationIDs: reviewed.calculationIDs,
      reviewStatus: .generated
    )
    let changedPack = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards + [generated],
      questionFamilies: pack.questionFamilies
    )

    let bundle = try KnowledgeStudyBundleBuilder().build(from: changedPack)

    XCTAssertFalse(bundle.reviewedResponseCards.contains { $0.id == generated.id })
    XCTAssertTrue(bundle.reviewedResponseCards.allSatisfy { $0.reviewStatus == .reviewed })
  }

  func testBuilderRejectsClaimedEvidenceThatCannotResolve() throws {
    let pack = try loadFixture()
    let assertion = try XCTUnwrap(pack.assertions.first)
    let changed = KnowledgeAssertion(
      id: assertion.id,
      subject: assertion.subject,
      predicate: assertion.predicate,
      value: assertion.value,
      qualifiers: assertion.qualifiers,
      kind: assertion.kind,
      confidence: assertion.confidence,
      evidenceLinkIDs: ["evidence-does-not-exist"]
    )
    let invalid = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions.map { $0.id == changed.id ? changed : $0 },
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )

    XCTAssertThrowsError(try KnowledgeStudyBundleBuilder().build(from: invalid)) { error in
      guard case KnowledgeStudyBundleError.unresolvedEvidence(let assertionID, _) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(assertionID, changed.id)
    }
  }

  func testBuilderRejectsAbsoluteSourcePathsEvenWithoutLoader() throws {
    let pack = try loadFixture()
    let source = try XCTUnwrap(pack.sources.first)
    let unsafe = KnowledgeSource(
      id: source.id,
      kind: source.kind,
      title: source.title,
      relativePath: "/private/deal.pdf",
      sha256: source.sha256,
      importedAt: source.importedAt
    )
    let invalid = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources.map { $0.id == unsafe.id ? unsafe : $0 },
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards,
      questionFamilies: pack.questionFamilies
    )

    XCTAssertThrowsError(try KnowledgeStudyBundleBuilder().build(from: invalid)) { error in
      guard case KnowledgeStudyBundleError.unsafeSourcePath = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testBuilderRejectsBrokenReviewedCardCitation() throws {
    let pack = try loadFixture()
    let card = try XCTUnwrap(pack.responseCards.first)
    let broken = KnowledgeResponseCard(
      id: card.id,
      title: card.title,
      answer: card.answer,
      evidenceState: card.evidenceState,
      questionFamilyIDs: card.questionFamilyIDs,
      assertionIDs: card.assertionIDs,
      citationPassageIDs: ["passage-does-not-exist"],
      calculationIDs: card.calculationIDs,
      reviewStatus: .reviewed
    )
    let invalid = KnowledgePack(
      manifest: pack.manifest,
      sources: pack.sources,
      passages: pack.passages,
      assertions: pack.assertions,
      evidenceLinks: pack.evidenceLinks,
      calculations: pack.calculations,
      responseCards: pack.responseCards.map { $0.id == broken.id ? broken : $0 },
      questionFamilies: pack.questionFamilies
    )

    XCTAssertThrowsError(try KnowledgeStudyBundleBuilder().build(from: invalid)) { error in
      guard
        case KnowledgeStudyBundleError.unresolvedReviewedCardReference(
          let cardID,
          let type,
          let id
        ) = error
      else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(cardID, broken.id)
      XCTAssertEqual(type, "passage")
      XCTAssertEqual(id, "passage-does-not-exist")
    }
  }

  private func loadFixture() throws -> KnowledgePack {
    try KnowledgePackLoader(
      profileRegistry: KnowledgeDomainProfileRegistry(profiles: [HospitalityDomainProfile()])
    ).load(from: fixtureURL())
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
