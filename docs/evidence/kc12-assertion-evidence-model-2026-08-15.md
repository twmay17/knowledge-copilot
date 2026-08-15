# KC-12 Assertion and Evidence Model Evidence — August 15, 2026

## Result

The KC-12 acceptance slice passes locally with a backward-compatible JSON contract and no
domain-specific predicate in the core model.

- All five typed values validate: text, number, boolean, ISO-8601 date, and reference.
- Numeric values require explicit normalized unit and positive finite scale.
- `period`, `version`, and `scope` are exposed through a normalized context view.
- Calculations fail closed when an output context is missing or differs on any input.
- Stated, calculated, inferred, and interpretive assertions remain distinct.
- Every assertion requires supporting source evidence or exactly one recorded derivation.
- Evidence ownership is bidirectional and `derives` is limited to calculated assertions.
- Hospitality adds `status` as a protected context dimension and requires room scope without
  changing the generic assertion shape.

## Verification

```bash
swift test --filter KnowledgeAssertionEvidenceModelTests
swift test --filter \
  'KnowledgeAssertionEvidenceModelTests|KnowledgePackLoaderTests|KnowledgeAnswerCardResolverTests|KnowledgeProofReplayTests|KnowledgeSpreadsheetIngestorTests|KnowledgeDocumentIngestorTests|QuestionCandidateDetectorTests'
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <six changed Swift files>
git diff --check
```

The focused KC-12 suite passed 7 of 7 tests. The combined KnowledgePack ingestion, loader,
detection, resolution, replay, and assertion/evidence regression run passed 48 of 48 tests.
The synthetic hospitality fixture validated with 3 sources, 3 passages, 18 assertions, and 9
answer cards. Both release products built successfully. All six changed Swift files passed strict
Swift-format lint, the assertion JSONL parsed successfully, and the diff passed whitespace
validation.

This evidence contains no real meeting transcript, audio, business document, customer identity,
tenant detail, or proprietary figure.
