# Answer Latency and Stale-Work Cancellation

The live answer path measures and controls the interval after the transcript contains enough speech
to emit a question or claim event. Audio capture and ASR have separate latency gates; they are not
silently folded into this measurement.

## Two latency boundaries

The product and component limits serve different purposes:

| Boundary | Hot | Warm | Meaning |
| --- | ---: | ---: | --- |
| Live p50 target | 1,000 ms | 2,500 ms | Sufficient transcript revision enters the detector until the update is applied to overlay state |
| Resolver component budget | 40 ms | 250 ms | Work inside one answer lane before the lane is canceled |

`KnowledgePackStore` starts the live timer before event detection and records a sample only when a
non-retraction answer update reaches overlay presentation state. Samples contain the lane and two
durations; they contain no transcript text, answer text, event ID, source locator, or corpus data.
The store keeps at most the latest 500 samples and clears measurements when the active pack changes.

`KnowledgeAnswerLatencyReport` uses a deterministic nearest-rank calculation and reports sample
count, end-to-end p50, p95, maximum, resolver p50, and target status for each populated lane. The
live gate passes only when both hot and warm have samples and meet their p50 targets.

## Reproducible benchmark

Run the local, corpus-only release benchmark with:

```bash
swift run -c release knowledge-pack benchmark-latency \
  ../fixtures/knowledge-packs/minimal-hospitality \
  --samples 100 \
  --output ../docs/evidence/kc23-latency-benchmark-2026-08-16.json
```

The command selects a reviewed response card for hot-lane replay and removes response cards from an
in-memory copy of the same pack for warm pack-search replay. Every sample uses a unique stream and
event ID. The command exits unsuccessfully if either live p50 target is missed. The JSON report is
suitable for CI artifacts and milestone evidence.

This synthetic benchmark isolates application processing after sufficient speech. It is not a
claim about microphone, Teams routing, ASR stabilization, model-network latency, or the time from a
person beginning a sentence.

## Cancellation ownership

The store owns at most one active answer job per transcript stream. A new candidate or stable
revision cancels the previous job for that stream before starting its replacement. An explicit
`answerSuperseded` event also cancels the previous event's task before its retraction is resolved.
Retraction work has an independent task key, so a replacement event cannot accidentally cancel the
retraction that removes its old card.

Task identity tokens prevent a canceled task from deleting a newer task's bookkeeping. The resolver
checks cancellation before and after every lane and before every publication. Its state actor also
rejects updates whose event ID or revision is no longer current, so cancellation and publication
validation form independent protections against stale output.

Vector and synthesis adapters are Swift `Sendable` async capabilities and must honor cooperative
task cancellation. The deterministic cancellation test uses a deliberately slow vector adapter,
waits until the old warm retrieval starts, sends corrected speech, and proves that:

- the adapter receives `CancellationError`;
- the store records a cancellation request;
- the prior event's card is removed; and
- only the corrected event's reviewed card remains visible.

Pack replacement, clearing, and session-path reset cancel all remaining answer tasks and discard
their timing samples, preventing measurements or work from crossing corpus boundaries.
