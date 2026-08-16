# KC-24 supervised Teams alpha-review harness — 2026-08-16

## Status

The deterministic review harness and operator protocol are implemented and verified locally. The
required consented 31-minute Microsoft Teams session has **not** yet been run, so KC-24 remains in
progress and no private-alpha `GO` decision has been claimed.

Baseline under test: `b4f7ffe6cb60caeb66f419571624934b651d2a21` (published KC-23).

## Implemented

- Added the `teams-alpha-review` executable and versioned submission schema.
- Bound human observations to the same audio session ID and exact session window as the strict
  `audio-capture-verify` report.
- Added 14 fail-closed gates covering consent, recording visibility, non-confidential/share-safe
  operation, the no-admin Microsoft path, remote transcription, automatic question detection,
  grounded answers, source inspection, correction replacement, notes, finalization, and strict
  two-track audio evidence.
- Added severity-aware issue handling:
  - any failed gate or unresolved critical/high issue produces `NO_GO`;
  - an unresolved medium issue produces `CONDITIONAL_GO`; and
  - only a clean required-gate result with no unresolved critical/high/medium issue produces `GO`.
- Kept operator notes and the private audio session ID out of the shareable report.
- Added a false-by-default submission template and a synthetic hospitality meeting script based on
  the redistributable `synthetic-hotel-2020-v1` KnowledgePack.
- Documented the privacy boundary and confirmed that the workflow requires macOS microphone/System
  Audio Recording permissions, not Microsoft 365 administrator consent, Graph, Entra, or a Teams
  bot.

## Verification

Run from `OpenOats/` on 2026-08-16:

```bash
swift format lint --strict \
  Sources/OpenOats/Alpha/TeamsAlphaReview.swift \
  Sources/TeamsAlphaReviewTool/main.swift \
  Tests/OpenOatsTests/TeamsAlphaReviewTests.swift
git diff --check
jq empty ../fixtures/teams-alpha-review/submission-template.json
swift test --filter TeamsAlphaReviewTests
swift test --skip MeetingDetectorTests
swift build -c release --product teams-alpha-review
.build/release/teams-alpha-review --help
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
```

Results:

- strict Swift format lint: pass;
- Git whitespace check: pass;
- submission JSON syntax: pass;
- focused evaluator/privacy/template tests: 11 passed, 0 failed;
- broad regression suite: 877 passed, 0 failed (`MeetingDetectorTests` excluded because those
  operating-system interaction tests are outside this change's deterministic suite);
- release `teams-alpha-review` build and CLI help path: pass; and
- synthetic KnowledgePack validation: pass (3 sources, 3 passages, 18 assertions, 9 cards).

The release build emitted only pre-existing warnings in unrelated audio, transcription, batch-text,
and suggestion-engine code.

## Remaining human gate

Follow [`docs/supervised-teams-alpha-review.md`](../supervised-teams-alpha-review.md) in a consented
real Teams call. The operator must capture the strict audio report, record every observed issue by
severity, evaluate the paired submission, and document the resulting private-alpha decision. Unit
tests and synthetic replay are not substitutes for that session.
