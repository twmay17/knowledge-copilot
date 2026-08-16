# Multi-Pack Replay Benchmark

The `knowledge-pack benchmark-replay` command runs a versioned conversation corpus through the
same domain-neutral live event detector and reviewed-card resolver used by the app. It is a
deterministic hardening gate, not a model-quality demo: it makes event, answer, evidence, citation,
false-card, and processing-latency expectations machine-checkable.

## KC-25 v1 corpus

`fixtures/replay-benchmark-v1.json` expands to 101 scenarios from two wholly synthetic and
redistributable KnowledgePacks:

- 38 hospitality scenarios;
- 63 product-pitch scenarios;
- 78 final-utterance cases generated from explicitly versioned templates; and
- 23 multi-revision or negative scenarios covering partial speech, corrections, ambiguity,
  conflicting evidence, missing evidence, rhetorical language, cross-pack isolation, and rapid
  follow-ups.

Each scenario starts with a fresh detector. Its expected contract records exact event kinds and the
final answer mode (`reviewed`, `fallback`, or `none`). Answered scenarios also pin the question
family, response card, evidence state, required response fragments, and exact citation passage IDs.
The runner verifies that citation files exist inside the active pack.

Negative scenarios opt into the false-card denominator explicitly. A scenario that validly shows
an answer and then clears it after a correction is not mislabeled as a false positive merely because
its final state is no answer.

## Run it

From `OpenOats/`:

```bash
swift run knowledge-pack benchmark-replay \
  ../fixtures/replay-benchmark-v1.json \
  --output /tmp/knowledge-replay-benchmark.json
```

The command exits nonzero unless all of these gates pass:

- the expanded corpus meets its declared minimum scenario count;
- every revision emits the exact expected event-kind sequence;
- every scenario reaches the expected reviewed, fallback, or no-answer state;
- evidence state, response fragments, citations, and pack containment match;
- the measured false-card rate stays within budget; and
- aggregate p95 detector/resolver processing latency stays within budget.

The benchmark file may reference only pack directories inside its own fixture root. Absolute paths
and paths escaping that root fail closed.

## Scope boundary

This benchmark measures deterministic transcript-to-card processing. It does not claim to measure
audio capture, speech-recognition accuracy, network latency, participant consent, or real meeting
behavior. The KC-24 consented Teams alpha session remains the source of live findings that must be
incorporated before KC-25 can be closed.
