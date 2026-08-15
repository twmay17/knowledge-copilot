# KC-13 Domain Profile and Calculation Registry Evidence — August 15, 2026

## Result

The KC-13 acceptance slice passes locally with hospitality isolated as a removable Swift package
extension.

- The core exposes a documented, versioned profile schema and registry lookup.
- Profiles register typed qualifiers, vocabulary, aliases, units, context keys, and deterministic
  calculations.
- Registered operations validate input order, units, scales, periods, arithmetic, and stored output.
- Ordered-period growth distinguishes current and prior inputs without weakening same-period rules.
- Calculation answer summaries expose resolved operands, output, qualifiers, and source citations.
- Missing evidence, invalid arithmetic, zero denominators, wrong units, or mismatched periods fail
  closed.
- A generic pack validates with the empty registry and no hospitality dependency.
- Hospitality Reference Profile 1 includes occupancy, ADR, RevPAR, NOI, NOI margin, and revenue
  growth rules.

## Verification

```bash
swift test --filter KnowledgeDomainProfileRegistryTests
swift test --filter \
  'KnowledgeDomainProfileRegistryTests|KnowledgePackLoaderTests|KnowledgeAnswerCardResolverTests|KnowledgeAssertionEvidenceModelTests|QuestionCandidateDetectorTests|KnowledgeProofReplayTests'
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <seven changed Swift files>
git diff --check
```

The focused KC-13 suite passed 7 of 7 tests. The combined registry, KnowledgePack, answer,
assertion/evidence, detection, and replay regression run passed 43 of 43 tests.
The synthetic hospitality fixture validated with 3 sources, 3 passages, 18 assertions, and 9
answer cards. Both release products built successfully. All seven changed Swift files passed
strict Swift-format lint and the diff passed whitespace validation. Release compilation reported
only the repository's existing warnings outside the KC-13 files.

This evidence contains no real meeting transcript, audio, business document, customer identity,
tenant detail, or proprietary figure.
