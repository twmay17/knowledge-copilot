# KC-25 Dependency-Safe Replay Benchmark Evidence — 2026-08-16

## Status

The dependency-safe portion of KC-25 is implemented and locally verified. The task remains open
because KC-24 still requires a consented 31-minute real Teams alpha session; relevant live findings
must be represented in the benchmark before final acceptance.

## Implemented

- Added a versioned multi-pack replay benchmark contract and runner.
- Added the `knowledge-pack benchmark-replay` CLI with fixture-root path confinement and nonzero
  failure behavior.
- Added a 101-scenario synthetic corpus spanning hospitality and a non-financial product pitch.
- Captured exact event kinds, reviewed/fallback/no-answer outcomes, evidence states, response
  fragments, citations, false-card rate, and processing-latency metrics.
- Added clean-state, deliberate-mismatch, and minimum-count regression tests.
- Fixed declared question-family variants so an exact configured variant is an admissible specific
  signal without weakening rhetorical detection to arbitrary substring matches.

## Local benchmark result

Command, from `OpenOats/`:

```bash
swift run knowledge-pack benchmark-replay \
  ../fixtures/replay-benchmark-v1.json \
  --output /tmp/kc25-replay-report.json
```

Observed result:

- verdict: `PASS`;
- scenarios: 101 of 101 passed;
- hospitality: 38;
- product pitch: 63;
- negative false-card cases: 4;
- false cards: 0;
- false-card rate: 0%;
- measured processing-latency p95: below the 50 ms fixture budget.

The exact latency sample varies by machine and run; the versioned acceptance gate is the declared
50 ms p95 budget, not a checked-in timing constant.

## Focused verification

```bash
swift test --filter KnowledgeReplayBenchmarkTests
swift test --filter \
  'QuestionCandidateDetectorTests|KnowledgeLiveEventDetectorTests|KnowledgeProofReplayTests|KnowledgeProductPitchPortabilityTests'
```

- replay benchmark tests: 4 passed, 0 failed;
- detector, live-event, proof-replay, and portability slice: 27 passed, 0 failed;
- broad deterministic suite excluding the pre-existing environment-sensitive `MeetingDetectorTests`:
  885 passed, 0 failed;
- strict Swift formatting and JSON parsing: passed.

## Remaining human dependency

Do not mark KC-25 Done until the KC-24 supervised Teams review is completed and its redacted,
non-confidential findings have been evaluated for additional versioned scenarios. No Microsoft 365
administrator action is required for that session.
