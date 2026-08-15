# KC-16 Study Analysis Review Evidence — August 15, 2026

## Acceptance slice

KC-16 closes the trust gap between user-operated frontier-model preparation and the live
KnowledgePack. Model output is untrusted, pack-hash-bound proposal data until an explicit human
decision set passes the review gate.

Verified behavior:

- the analysis must match the exact bundle ID, pack ID, and full pack-content hash;
- question, card, contradiction, and corpus-gap proposals are bounded and normalized;
- unknown assertions, passages, calculations, and question families fail closed;
- card citations must fall inside the evidence closure of claimed assertions and registered
  calculation inputs;
- factual, calculated, contested, and abstention evidence-state rules are enforced;
- a model-supplied `reviewStatus` cannot bypass the queue's forced `generated` state;
- queues are deterministic, content-bound, and rejected after tampering or pack changes;
- every question-family and response-card proposal needs exactly one explicit human decision;
- rejecting a proposed family while approving its dependent card fails merged-pack validation;
- only explicitly approved cards become `reviewed` in the import artifact; and
- no command mutates the active KnowledgePack.

## Reproducible commands

From `OpenOats/`:

```bash
swift test --filter 'KnowledgeStudyReviewTests|KnowledgeStudyBundleTests'

swift run knowledge-pack prepare-study-review \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../fixtures/study-analysis/synthetic-hospitality-analysis.json \
  --output ../outputs/kc16-review-queue.json

swift run knowledge-pack approve-study-review \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../outputs/kc16-review-queue.json \
  ../fixtures/study-analysis/synthetic-hospitality-decisions.json \
  --output ../outputs/kc16-approved-import.json

swift test --skip MeetingDetectorTests
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <four changed Swift files>
git diff --check
```

Results:

- 12 of 12 KC-16 review-gate tests passed;
- all 21 Study Bundle and Study Review focused tests passed;
- repeated review-queue and approved-import CLI runs were byte-for-byte identical;
- the pending queue contained one generated card, one question family, one contradiction, and one
  corpus gap;
- the approved import contained one explicitly reviewed contested card and one question family;
- the base and resulting full-content hashes were different and recorded;
- both public JSON Schemas and both synthetic input fixtures passed JSON syntax validation;
- 780 non-environmental tests passed with zero failures;
- release builds succeeded for both `knowledge-pack` and `OpenOats`;
- all four changed Swift files passed strict Swift-format lint; and
- the diff passed whitespace validation.

## Fixture and privacy boundary

The analysis, decisions, and KnowledgePack are wholly synthetic and redistributable. Generated
queues and import artifacts remain in the Git-ignored `outputs/` directory. The workflow makes no
model, web, Teams, Microsoft Graph, or Microsoft 365 tenant call.
