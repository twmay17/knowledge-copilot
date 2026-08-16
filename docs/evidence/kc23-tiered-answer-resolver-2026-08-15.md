# KC-23 Tiered Answer Resolver Evidence — August 15, 2026

This public-safe record covers repository milestone KC-23, corresponding to Notion task KC-20,
`Build the hot, warm, and cold answer resolver`.

## Implemented contract

- Added hot, warm, and cold lanes with configurable 40 ms, 250 ms, and 2,000 ms defaults.
- Preferred reviewed corpus-supported cards, then exact typed evidence, before retrieval previews or
  abstentions.
- Added live `show`, `supersede`, `refine`, and `retract` updates with support and presentation ranks.
- Allowed a stable reviewed card to visibly supersede provisional exact evidence.
- Prevented a slower result from replacing stronger evidence merely because it completed later.
- Added pack-bound hybrid retrieval for questions that do not expose a canonical predicate.
- Added typed numeric claim checking without guessing an ambiguous type or unit.
- Added a capability-poor optional synthesis protocol whose input is only admitted evidence.
- Required synthesis citations to stay inside the request allow-list and cover every admitted claim.
- Skipped synthesis when a reviewed card already answers the event.
- Enforced lane cancellation at the configured budget and suppressed stale post-supersession output.
- Tombstoned superseded event IDs so late ASR revisions cannot resurrect a retracted answer.
- Integrated resolver construction, access, and cleanup into `KnowledgePackStore`.

## Focused verification

The resolver test suite covers:

- reviewed-card hot-lane preference;
- exact-value preference over retrieval;
- warm pack-bound evidence previews;
- same-evidence cold refinement;
- unknown and incomplete citation rejection;
- cold-lane timeout behavior;
- typed claim contradiction;
- reviewed missing-data abstention;
- visible provisional-to-reviewed supersession;
- retraction and late-revision suppression; and
- application-store lifecycle integration.
- stale evaluator/index rejection across pack hashes.

Passing command:

```bash
swift test --filter KnowledgeTieredAnswerResolverTests
swift test --filter \
  'KnowledgeTieredAnswerResolverTests|KnowledgeEvidenceOutcomeEvaluatorTests|KnowledgePackSearchIndexTests|KnowledgeAnswerCardResolverTests|KnowledgeLiveEventDetectorTests'
swift test --skip MeetingDetectorTests
swift build -c release --product OpenOats
swift build -c release --product knowledge-pack
swift format lint --strict \
  Sources/OpenOats/KnowledgePack/KnowledgeEvidenceOutcomeEvaluator.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeTieredAnswerResolver.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Tests/OpenOatsTests/KnowledgeTieredAnswerResolverTests.swift
git diff --check
```

Results:

- 12 of 12 focused resolver tests passed;
- all 50 detector, card, search, evidence-gate, and tier-resolver tests passed;
- all 847 non-environmental package tests passed;
- both production products built successfully;
- strict Swift formatting passed; and
- whitespace checks passed.

The release compiler emitted only pre-existing warnings in unrelated audio, text-cleaning,
suggestion, and transcription sources.

## Scope boundary

No cloud model, web search, external account, Microsoft 365 administrator permission, private
document, meeting audio, or customer data was used. The cold-lane test adapter is deterministic and
local. A production model adapter, overlay presentation, real-meeting latency study, and semantic
answer-quality evaluation remain separate milestones.
