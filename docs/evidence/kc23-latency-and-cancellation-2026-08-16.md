# KC-23 Latency and Stale-Card Cancellation Evidence — August 16, 2026

This public-safe record covers Notion task KC-23, `Tune latency and stale-card cancellation`.

## Implemented

- Added privacy-safe hot, warm, and cold timing sample and percentile types.
- Preserved the 40 ms hot and 250 ms warm resolver budgets while separately enforcing the roadmap's
  1,000 ms hot and 2,500 ms warm live p50 targets.
- Measured from sufficient transcript receipt, through event detection and answer resolution, to
  overlay presentation-state application.
- Added a bounded 500-sample store window and deterministic nearest-rank p50/p95 reporting.
- Added one active answer-job owner per transcript stream.
- Canceled provisional, corrected, superseded, pack-replaced, and cleared work without allowing an
  old task to remove a newer task's bookkeeping.
- Added cancellation checks around every resolver lane and before publication.
- Added injectable, capability-limited vector and synthesis adapters to the live store path.
- Added a reusable `knowledge-pack benchmark-latency` command with JSON output and a failing exit
  status when a p50 target is missed.

## Release benchmark

Environment: Apple M5, arm64, macOS 26.3.1. Command:

```bash
swift run -c release knowledge-pack benchmark-latency \
  ../fixtures/knowledge-packs/minimal-hospitality \
  --samples 100 \
  --output ../docs/evidence/kc23-latency-benchmark-2026-08-16.json
```

| Lane | Samples | Resolver budget | Resolver p50 | Live p50 target | End-to-end p50 | End-to-end p95 | Maximum | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Hot | 100 | 40 ms | 0.093 ms | 1,000 ms | 0.345 ms | 0.464 ms | 1.023 ms | Pass |
| Warm | 100 | 250 ms | 0.178 ms | 2,500 ms | 0.195 ms | 0.227 ms | 0.354 ms | Pass |

Machine-readable result:
[kc23-latency-benchmark-2026-08-16.json](kc23-latency-benchmark-2026-08-16.json)

## Corrected-speech and cancellation proof

`testStoreCancelsSupersededWarmWorkAndReplacesTheOldCard` starts a deliberately blocked warm vector
search for provisional RevPAR speech, then supplies corrected final occupancy speech on the same
stream. It verifies the emitted supersession, observes `CancellationError` in the old adapter, and
asserts that the only visible card belongs to the replacement event and is titled `2020 occupancy`.

`testSupersessionRetractsVisibleAnswerAndPreventsResurrection` independently verifies that the
visible update retracts and that a late copy of the old event cannot publish again. State-currentness
checks remain active even if a third-party adapter is slow to cooperate with cancellation.

## Verification results

- 14 of 14 focused tiered-resolver tests passed.
- 69 of 69 resolver, detector, search, evidence, card, and overlay tests passed.
- 866 of 866 non-environmental package tests passed with `MeetingDetectorTests` skipped according to
  the repository's established local verification boundary.
- The `OpenOats` and `knowledge-pack` release products built successfully.
- Strict Swift formatting and Git whitespace checks passed.
- The release compiler emitted only the pre-existing warnings in unrelated audio, text-cleaning,
  suggestion, and transcription sources.

## Verification boundary

The benchmark begins when a transcript revision containing sufficient speech enters the detector.
It includes detection, resolver work, async-stream delivery, overlay-card conversion, and
presentation-state assignment. It excludes audio capture, Teams routing, and ASR stabilization,
which remain separate gates. It uses only the local synthetic hospitality pack; no network, model,
customer document, or Microsoft 365 administrator permission is involved.
