import Foundation

/// Product-level targets measured from a sufficient transcript revision entering the live event
/// detector until an answer update is ready for presentation.
public struct KnowledgeAnswerLiveLatencyTargets: Equatable, Sendable {
  public let hotMilliseconds: Double
  public let warmMilliseconds: Double

  public init(
    hotMilliseconds: Double = 1_000,
    warmMilliseconds: Double = 2_500
  ) {
    self.hotMilliseconds = max(1, hotMilliseconds)
    self.warmMilliseconds = max(1, warmMilliseconds)
  }

  public func milliseconds(for lane: KnowledgeAnswerLane) -> Double? {
    switch lane {
    case .hot: hotMilliseconds
    case .warm: warmMilliseconds
    case .cold: nil
    }
  }
}

/// One privacy-safe timing observation. It contains no transcript text, answer text, or source data.
public struct KnowledgeAnswerLatencySample: Equatable, Sendable {
  public let lane: KnowledgeAnswerLane
  public let endToEndMilliseconds: Double
  public let resolverMilliseconds: Double

  public init(
    lane: KnowledgeAnswerLane,
    endToEndMilliseconds: Double,
    resolverMilliseconds: Double
  ) {
    self.lane = lane
    self.endToEndMilliseconds = max(0, endToEndMilliseconds)
    self.resolverMilliseconds = max(0, resolverMilliseconds)
  }
}

public struct KnowledgeAnswerLaneLatencySummary: Equatable, Sendable {
  public let lane: KnowledgeAnswerLane
  public let sampleCount: Int
  public let targetMilliseconds: Double?
  public let endToEndP50Milliseconds: Double
  public let endToEndP95Milliseconds: Double
  public let endToEndMaximumMilliseconds: Double
  public let resolverP50Milliseconds: Double
  public let meetsP50Target: Bool?
}

/// Deterministic nearest-rank latency aggregation for replay, tests, and operator diagnostics.
public struct KnowledgeAnswerLatencyReport: Equatable, Sendable {
  public let summaries: [KnowledgeAnswerLaneLatencySummary]

  public init(
    samples: [KnowledgeAnswerLatencySample],
    targets: KnowledgeAnswerLiveLatencyTargets = KnowledgeAnswerLiveLatencyTargets()
  ) {
    summaries = KnowledgeAnswerLane.allCases.compactMap { lane in
      let laneSamples = samples.filter { $0.lane == lane }
      guard !laneSamples.isEmpty else { return nil }
      let endToEnd = laneSamples.map(\.endToEndMilliseconds).sorted()
      let resolver = laneSamples.map(\.resolverMilliseconds).sorted()
      let target = targets.milliseconds(for: lane)
      let p50 = Self.percentile(0.50, values: endToEnd)
      return KnowledgeAnswerLaneLatencySummary(
        lane: lane,
        sampleCount: laneSamples.count,
        targetMilliseconds: target,
        endToEndP50Milliseconds: p50,
        endToEndP95Milliseconds: Self.percentile(0.95, values: endToEnd),
        endToEndMaximumMilliseconds: endToEnd.last ?? 0,
        resolverP50Milliseconds: Self.percentile(0.50, values: resolver),
        meetsP50Target: target.map { p50 <= $0 }
      )
    }
  }

  public func summary(for lane: KnowledgeAnswerLane) -> KnowledgeAnswerLaneLatencySummary? {
    summaries.first { $0.lane == lane }
  }

  /// True only when both release-gated lanes have samples and meet their product targets.
  public var meetsLiveP50Targets: Bool {
    guard let hot = summary(for: .hot), let warm = summary(for: .warm) else { return false }
    return hot.meetsP50Target == true && warm.meetsP50Target == true
  }

  private static func percentile(_ percentile: Double, values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let rank = Int(ceil(percentile * Double(values.count)))
    return values[min(max(rank - 1, 0), values.count - 1)]
  }
}
