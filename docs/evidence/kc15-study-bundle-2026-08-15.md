# KC-15 Study Bundle Evidence — August 15, 2026

## Acceptance slice

KC-15 establishes the provider-neutral preparation boundary between a validated KnowledgePack and
a user-operated frontier-model study session.

Verified behavior:

- a valid pack exports deterministic schema-v1 JSON from the command line;
- the embedded policy requires a closed corpus and citations, disables web authority, treats
  document instructions as data, and makes `not_found_in_corpus` the unsupported-answer state;
- every assertion evidence link carries its exact excerpt, source identity, safe relative path,
  and locator;
- every passage cited by a reviewed presenter card is included with its exact excerpt;
- only reviewed response cards are exported;
- calculated assertions identify their one registered calculation;
- broken evidence, calculation, or reviewed-card references fail closed;
- absolute source paths fail closed;
- the bundle ID derives from a canonical full-content hash and changes when record content changes;
  and
- a generic product-pitch pack exports without any Domain Profile or hospitality dependency.

## Reproducible commands

From `OpenOats/`:

```bash
swift test --filter KnowledgeStudyBundleTests

swift run knowledge-pack export-study-bundle \
  ../fixtures/knowledge-packs/minimal-hospitality \
  --output ../outputs/kc15-study-bundle.json

swift test --skip MeetingDetectorTests
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats

xcrun swift-format lint --strict \
  Sources/OpenOats/KnowledgePack/KnowledgeStudyBundle.swift \
  Sources/KnowledgePackTool/main.swift \
  Tests/OpenOatsTests/KnowledgeStudyBundleTests.swift
git diff --check
```

Results:

- 9 of 9 focused Study Bundle tests passed;
- two independent exports were byte-for-byte identical;
- the synthetic export contained 3 sources, 3 cited passages, 18 assertions, 6 calculations, 9
  question families, and 9 reviewed cards;
- the policy and citation closure checks passed;
- 768 non-environmental tests passed with zero failures when the inherited
  `MeetingDetectorTests` suite was excluded;
- release builds succeeded for both `knowledge-pack` and `OpenOats`;
- all three changed Swift files passed strict Swift-format lint; and
- the diff passed whitespace validation.

## Data and account boundary

The generated file contains exact corpus excerpts, so private exports remain local and ignored by
Git. The subscription-assisted workflow is a deliberate user upload with a closed-corpus prompt;
it does not automate a ChatGPT account or represent generated content as reviewed. Any later direct
model integration must use a separately authorized provider adapter and the same evidence gate.
