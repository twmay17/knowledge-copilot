# Deterministic Knowledge Proof Replay

The `knowledge-pack replay` command runs the prepared conversation-to-answer path from a clean
in-memory state and emits a machine-readable proof report. It is intended for regression tests,
release gates, and privacy-safe open-source demonstrations.

## What it measures

A replay specification supplies ordered transcript revisions on a simulated meeting timeline. For
each revision, the runner measures the real local processing time for question detection and
reviewed-card resolution. The reported answer-ready time is:

```text
revision timestamp + measured detector/resolver processing latency
```

The report checks:

- expected question family;
- expected reviewed response card and evidence state;
- required answer fragments;
- exact citation passage IDs;
- source-file existence and containment inside the selected KnowledgePack;
- answer-ready time against the response deadline;
- whether the answer was ready before final speech, when required; and
- maximum processing latency against the replay budget.

Any failed check makes the CLI exit nonzero and records `FAIL`. The runner starts with a new
detector and resolver on every invocation. It does not reuse candidate state, call a model, access
the web, or generate an unsupported answer.

## First synthetic proof

From `OpenOats/`:

```bash
swift run knowledge-pack replay \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../fixtures/knowledge-packs/minimal-hospitality/evaluation/live-proof-revpar.json \
  --output ../docs/evidence/kc9-first-proof-2026-08-14.json
```

The checked-in scenario sends:

1. `What was the rev par` at 0 ms as a partial;
2. `What was the rev par for this asset in 2020` at 420 ms as a partial; and
3. the final punctuated question at 900 ms.

The answer must be ready by 1,000 ms, before the final revision, with no processing sample above
50 ms. The expected card is `card-revpar-2020`, and both exact source passages must remain valid.

## Scope

This replay certifies the deterministic transcript-revision → question-candidate → reviewed-card →
citation path. It deliberately excludes audio capture and ASR latency, which have separate
verification gates. Because the fixture is wholly synthetic, its spec and proof report contain no
meeting audio, transcript from a real person, tenant identifier, or proprietary financial data.
