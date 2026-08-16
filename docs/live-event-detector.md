# Live Event Detector

The live event detector is the reversible bridge between unstable ASR revisions and the answer
resolver. It runs locally, performs no retrieval, and emits only deterministic signals derived from
the active KnowledgePack's reviewed question families and opaque aliases.

## Event contract

`KnowledgeLiveEventDetector` emits seven domain-neutral event kinds:

- `QuestionCandidate` begins speculative retrieval from a prepared partial question;
- `QuestionStable` permits the resolver to consider a reviewed response card;
- `ClaimCandidate` begins corpus fact-check preparation for a likely declarative claim;
- `ClaimStable` permits the next resolver stage to evaluate the claim;
- `TopicShift` records a stable change between opaque topic IDs;
- `AnswerSuperseded` retracts a stale question or claim after correction, interruption, clearing, or
  a pack change; and
- `NoAction` makes ignored input explicit, including empty, stale, unchanged, duplicate, and
  insufficient-signal revisions.

Every input has a stream ID and monotonically increasing sequence. IDs are deterministic within a
fresh detector (`<stream>#<generation>` for questions and `<stream>#claim#<generation>` for claims),
so the same replay produces the same transitions without wall-clock or model behavior.

## Early questions and conservative claims

The existing prepared-question matcher remains authoritative for questions. A prepared partial
prefix can emit `QuestionCandidate` before punctuation or final ASR text. A second compatible
revision or a final revision promotes the same ID to `QuestionStable`.

Bare aliases are not treated as questions. A question must begin with a generic question/request
lead or match a curated partial prefix. This prevents short meeting fragments such as `Room count.`
from producing a card while preserving early retrieval for `What was the rev par`.

Claims require all of the following:

1. at least one opaque term alias;
2. declarative rather than question-shaped text; and
3. either a claim verb or a numeric/currency/percentage literal.

No hospitality type appears in the detector. Domain Profile terms are preferred when present. For
a generic pack without a Domain Profile, reviewed question-family aliases become fallback opaque
IDs such as `question_family:question-product-safety`. The detector identifies a possible claim; it
does not decide whether the claim is true.

## Revision, interruption, and duplicate rules

- A lower or repeated sequence emits `NoAction(stale_revision)`.
- A changed family, period, or literal supersedes the prior event before emitting the replacement.
- A different stream with a new semantic signal emits `AnswerSuperseded(interrupted)` so an old card
  does not remain current during a follow-up.
- A late final from an already superseded stream cannot resurrect the old question or claim.
- An equivalent question or claim on another stream emits `NoAction(duplicate_signal)` and does not
  create another card.
- A repeated final for an unchanged candidate emits `NoAction(unchanged_revision)`.
- Stable opaque topic IDs produce `TopicShift` only when they actually change.

The macOS `KnowledgePackStore` now uses this detector as its canonical transcript path. Its existing
`processTranscriptRevision(_:)` API remains compatible by projecting question and supersession
events back into the older upsert/cancel contract. New overlay work can consume
`processLiveTranscriptRevision(_:)` and `latestLiveKnowledgeEvents` directly.

## Replay and false-positive measurement

`KnowledgeLiveEventReplayRunner` starts with a fresh detector, replays a JSON fixture, records every
event kind and stable description, and compares the exact ordered trace to the expected trace. Its
report includes:

- exact trace matches;
- actionable false-positive revisions;
- actionable false-negative revisions;
- the number of negative revisions; and
- `falsePositiveRate = falsePositiveRevisionCount / negativeRevisionCount`.

A negative revision is one whose expected event contains no actionable kind (normally only
`NoAction`). The fixture declares a maximum allowed rate, so a false positive fails visibly instead
of being averaged away.

The synthetic hospitality corpus contains two public-safe fixtures:

- `evaluation/live-events-transitions.json` covers early/stable questions, claims, topic shifts,
  correction, interruption, duplicate suppression, and a stale revision; and
- `evaluation/live-events-negative.json` covers six non-actionable utterances, including a bare
  metric alias and a future-review statement.

These fixtures measure the deterministic text-to-event layer only. Audio capture quality, ASR word
error rate, speaker diarization, retrieval latency, answer quality, and real-meeting false positives
remain separate evaluation gates.

## Trust boundary

The detector may decide that retrieval or fact-check preparation should begin. It may not create an
assertion, select a source as true, generate answer prose, or bypass review. Question and claim
events can now flow into the separate [tiered answer resolver](tiered-answer-resolver.md), which
preserves the corpus-only evidence boundary while streaming hot, warm, and cold updates.
