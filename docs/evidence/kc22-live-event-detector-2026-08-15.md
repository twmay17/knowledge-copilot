# KC-22 Live Event Detector Evidence — August 15, 2026

This public-safe record covers repository milestone KC-22, corresponding to Notion task KC-19,
`Implement the live event detector`.

## Implemented contract

- Added a domain-neutral event stream for `QuestionCandidate`, `QuestionStable`, `ClaimCandidate`,
  `ClaimStable`, `TopicShift`, `AnswerSuperseded`, and `NoAction`.
- Kept prepared question matching local and able to start retrieval before final punctuation.
- Added conservative claim recognition over opaque aliases, claim cues, periods, and literals without
  deciding claim truth.
- Added question-family alias fallback so a product or other generic pack can detect claims without
  a domain-specific profile.
- Added deterministic correction, clearing, interruption, pack-change, and stale-sequence handling.
- Suppressed equivalent question and claim events across rapid follow-up streams.
- Prevented late final ASR revisions from resurrecting a superseded event.
- Added stable topic-shift events over opaque topic IDs.
- Integrated the event detector into `KnowledgePackStore` while preserving its legacy
  question-upsert/cancel API and reviewed answer-card behavior.
- Added a replay schema, exact ordered traces, actionable false-positive/false-negative counts, and
  a declared maximum false-positive rate.

## Public replay fixtures

The fictional minimal-hospitality corpus now includes:

- `live-events-transitions.json`: 11 revisions covering early and stable questions, a claim,
  supersession, topic changes, duplicate suppression, and an intentionally stale revision; and
- `live-events-negative.json`: 6 expected no-action revisions, including small talk, an unbound year,
  a bare metric name, a future-review statement, and a bare question-family alias.

Both replays matched their complete ordered traces. The negative replay measured 0 actionable false
positives across 6 negative revisions, for a deterministic fixture false-positive rate of 0.0%.
This number describes only these checked-in synthetic text fixtures; it is not a real-meeting or ASR
accuracy claim.

## Verification

Passing checks:

```bash
swift test --filter KnowledgeLiveEventDetectorTests
swift test --filter \
  'KnowledgeLiveEventDetectorTests|QuestionCandidateDetectorTests|KnowledgeAnswerCardResolverTests|KnowledgeProofReplayTests'
swift test --skip MeetingDetectorTests
swift build -c release --product OpenOats
swift build -c release --product knowledge-pack
swift format lint --strict \
  Sources/OpenOats/KnowledgePack/QuestionCandidateDetector.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeLiveEventDetector.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeLiveEventReplay.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Tests/OpenOatsTests/KnowledgeLiveEventDetectorTests.swift
jq empty \
  ../fixtures/knowledge-packs/minimal-hospitality/evaluation/live-events-transitions.json \
  ../fixtures/knowledge-packs/minimal-hospitality/evaluation/live-events-negative.json
git diff --check
```

Results:

- 10 of 10 focused live-event tests passed;
- all 30 detector, answer-resolution, and replay tests passed;
- all 835 non-environmental package tests passed;
- both production products built successfully;
- strict Swift formatting passed;
- both JSON fixtures parsed successfully; and
- whitespace checks passed.

The release compiler emitted only pre-existing warnings in unrelated audio, text-cleaning,
suggestion, and transcription sources.

## Scope boundary

No cloud service, external account, Microsoft 365 administrator permission, private document, real
meeting transcript, or customer data was used. Audio capture, ASR quality, real-meeting
false-positive measurement, retrieval ranking, and claim resolution remain separate milestones.
