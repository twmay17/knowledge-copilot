import XCTest

@testable import OpenOatsKit

final class KnowledgeNumericEquivalenceTests: XCTestCase {
  private func ratio(_ number: Double, scale: Double = 1) -> KnowledgeValue {
    KnowledgeValue(type: .number, number: number, unit: "ratio", scale: scale)
  }

  func testParsePathRoundingIsEquivalentToStoredRatio() {
    // "0.07%" spoken -> 0.07 / 100 differs from the decoded literal 0.0007 by 1 ULP.
    XCTAssertTrue(
      KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(0.0007), ratio(0.07 / 100.0)))
    XCTAssertTrue(
      KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(0.0805), ratio(8.05 / 100.0)))
  }

  func testBoundaryValues() {
    // Zero: only zero matches zero — including the value exactly 1 ULP away.
    XCTAssertTrue(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(0), ratio(0)))
    XCTAssertTrue(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(0), ratio(-0.0)))
    XCTAssertFalse(
      KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(
        ratio(0), ratio(Double.leastNonzeroMagnitude)))
    XCTAssertFalse(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(0), ratio(1e-300)))
    // Sign difference is never equivalent.
    XCTAssertFalse(
      KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(0.0007), ratio(-0.0007)))
    // Negative values tolerate the same parse rounding.
    XCTAssertTrue(
      KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(-0.0007), ratio(-0.07 / 100.0)))
    // Large financial magnitudes stay tight: $1 at $1B is ~4e12 ULPs, far above the bound.
    let billion = KnowledgeValue(type: .number, number: 1_000_000_000, unit: "usd", scale: 1)
    let billionPlusOne = KnowledgeValue(type: .number, number: 1_000_000_001, unit: "usd", scale: 1)
    XCTAssertFalse(
      KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(billion, billionPlusOne))
    // Non-finite never matches.
    XCTAssertFalse(
      KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(
        ratio(.infinity), ratio(.infinity)))
    XCTAssertFalse(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(.nan), ratio(.nan)))
  }

  func testScaleNormalizationComparesEffectiveValues() {
    let scaled = KnowledgeValue(type: .number, number: 89.5, unit: "usd", scale: 1_000_000)
    let flat = KnowledgeValue(type: .number, number: 89_500_000, unit: "usd", scale: 1)
    XCTAssertTrue(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(scaled, flat))
  }

  func testUnitMismatchStaysInequivalent() {
    let usd = KnowledgeValue(type: .number, number: 0.0007, unit: "usd", scale: 1)
    XCTAssertFalse(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(ratio(0.0007), usd))
  }

  func testNonNumericValuesStillCompareByFingerprint() {
    let text = KnowledgeValue(type: .text, text: "north tower")
    let sameText = KnowledgeValue(type: .text, text: "north tower")
    let otherText = KnowledgeValue(type: .text, text: "south tower")
    XCTAssertTrue(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(text, sameText))
    XCTAssertFalse(KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(text, otherText))
  }

  func testTwoDecimalPercentSweepHasNoFalseOutcomes() {
    // Every value 0.01% ... 99.99%: the parse-path double must match the stored
    // 4-decimal literal, and must NOT match its 0.01-percentage-point neighbor.
    for i in 1...9_999 {
      let spoken = Double(i) / 100.0
      let stored = Double(String(format: "%.4f", spoken / 100.0))!
      XCTAssertTrue(
        KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(
          ratio(stored), ratio(spoken / 100.0)),
        "false contradiction at \(spoken)%"
      )
      let neighbor = Double(String(format: "%.4f", (spoken + 0.01) / 100.0))!
      XCTAssertFalse(
        KnowledgeEvidenceOutcomeEvaluator.valuesAreEquivalent(
          ratio(neighbor), ratio(spoken / 100.0)),
        "missed real difference at \(spoken)%"
      )
    }
  }
}
