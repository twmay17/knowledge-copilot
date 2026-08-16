# KC-34 non-financial product-pitch portability — 2026-08-16

## Acceptance slice

KC-34 proves that the same KnowledgePack core used by the hospitality demonstration can support a
non-financial product pitch without adding a product-specific Domain Profile or modifying the
generic loader, detector, resolver, evidence gate, or replay runner.

The checked-in `nestarc-go-product-pitch-v1` fixture contains only fictional, redistributable
material authored for this repository:

- 4 source documents;
- 10 source passages;
- 23 generic typed assertions;
- 17 anticipated question families and reviewed response cards; and
- one partial-speech materials replay.

The response set covers product definition, materials, dimensions, weight, price, launch timing,
launch contents, durability testing, caregiver research, pricing objections, wash-instruction
conflict, market-size conflict, roadmap status, the modular-design rationale, unsupported
contamination and infant-sleep claims, and version clarification.

## Boundary and safety results

- `domainProfiles` is empty and the pack loads through `KnowledgePackLoader()` with the empty
  registry.
- No assertion uses the `hospitality.*` predicate namespace and the portability tests import no
  hospitality target.
- Conflicting pilot and launch wash instructions remain `contested`.
- Incompatible market definitions remain `contested`; neither estimate is promoted as authoritative.
- Product-design and price-objection conclusions remain `interpretive` and retain their directional
  research limitations.
- Contamination-prevention and infant-sleep questions return `not_found_in_corpus`.
- A version-dependent care question returns `needs_clarification`.
- Every non-abstention answer opens only source files inside the selected pack.

## Reproducible verification

From `OpenOats/`:

```bash
swift run knowledge-pack validate ../fixtures/knowledge-packs/nestarc-product-pitch
swift run knowledge-pack inspect ../fixtures/knowledge-packs/nestarc-product-pitch
swift run knowledge-pack replay \
  ../fixtures/knowledge-packs/nestarc-product-pitch \
  ../fixtures/knowledge-packs/nestarc-product-pitch/evaluation/live-proof-materials.json
swift test --filter KnowledgeProductPitchPortabilityTests
swift test --filter \
  'KnowledgeProductPitchPortabilityTests|KnowledgePackLoaderTests|QuestionCandidateDetectorTests|KnowledgeAnswerCardResolverTests|KnowledgeProofReplayTests|KnowledgePackSearchIndexTests|KnowledgeEvidenceOutcomeEvaluatorTests|KnowledgeDomainProfileRegistryTests'
swift test --skip MeetingDetectorTests
swift format lint --strict \
  Tests/OpenOatsTests/KnowledgeProductPitchPortabilityTests.swift
git diff --check
```

Current results:

- pack validation and source-hash verification: pass;
- all 17 golden utterances detect and resolve the expected reviewed response: pass;
- focused portability tests: 4 passed, 0 failed;
- cross-pack loader, search-isolation, evidence, detector, resolver, and replay regressions: 61
  passed, 0 failed;
- broad deterministic package suite: 881 passed, 0 failed (`MeetingDetectorTests` excluded as the
  existing operating-system interaction suite);
- materials replay: `PASS`, answer triggered on the second partial at 420 ms and before final speech
  at 900 ms;
- replay citations: present and confined to the selected pack;
- strict Swift formatting, JSON parsing, and Git whitespace validation: pass.

Synthetic replay proves deterministic software behavior, not real consumer demand, product safety,
regulatory compliance, or ASR performance in an uncontrolled meeting.
