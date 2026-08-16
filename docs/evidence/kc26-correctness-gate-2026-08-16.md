# KC-26 Dependency-Safe Correctness Gate Evidence — 2026-08-16

## Status

The dependency-safe KC-26 correctness gate is implemented and locally verified. Final KC-26 closure
still follows KC-25, which must incorporate the relevant redacted findings from the KC-24 consented
Teams alpha session.

## Implemented

- Added stable category fingerprints for complete pack content, sources, passages, assertions,
  evidence links, calculations, response cards, and question families.
- Added a machine-readable correctness spec and report.
- Added card-to-claim citation-closure and pack-local source-file audits.
- Added eight exact evidence-outcome probes covering every evidence state and decision reason.
- Reused the 101-scenario replay benchmark as a downstream behavior check.
- Required at least two explicit cross-pack scenarios to abstain without returning a card.
- Added CLI commands to run the gate and generate candidate fingerprints after deliberate review.
- Added a five-case tamper matrix for qualifier, calculation, label, same-pack citation, and
  cross-pack citation corruption.

## Local correctness result

Command, from `OpenOats/`:

```bash
swift run knowledge-pack audit-correctness \
  ../fixtures/correctness-gate-v1.json \
  --output /tmp/kc26-correctness-report.json
```

Observed result:

- verdict: `PASS`;
- packs: 2 of 2 passed;
- outcome probes: 8 of 8 passed;
- evidence states covered: 8 of 8;
- replay scenarios: 101 of 101 passed;
- cross-pack scenarios: 2 of 2 passed without returning a card;
- false cards: 0; and
- pack findings: 0.

## Focused verification

```bash
swift test --filter KnowledgeCorrectnessGateTests
swift test --skip MeetingDetectorTests
swift run knowledge-pack audit-correctness \
  ../fixtures/correctness-gate-v1.json \
  --output /tmp/kc26-correctness-report.json
swift build -c release --product knowledge-pack
swift format lint --strict \
  Sources/OpenOats/KnowledgePack/KnowledgeCorrectnessGate.swift \
  Sources/KnowledgePackTool/main.swift \
  Tests/OpenOatsTests/KnowledgeCorrectnessGateTests.swift
jq empty ../fixtures/correctness-gate-v1.json
git diff --check
```

- correctness-gate tests: 6 passed, 0 failed;
- broad deterministic suite excluding the pre-existing environment-sensitive
  `MeetingDetectorTests`: 891 passed, 0 failed;
- clean release gate: passed;
- structurally valid qualifier drift: rejected;
- corrupted calculation output: rejected before replay;
- evidence-state relabeling: rejected by fingerprints and replay;
- same-pack citation substitution: rejected by provenance closure and replay; and
- cross-pack citation borrowing: rejected as an unknown pack-local passage;
- the release `knowledge-pack` product built successfully with only pre-existing warnings in
  unrelated audio, text-cleaning, suggestion, and transcription sources; and
- strict Swift formatting, JSON parsing, and whitespace checks passed.

## Remaining dependency

Do not mark KC-26 Done until KC-25 closes after the KC-24 supervised Teams review and any relevant
redacted findings have been represented in the reviewed fixtures. No Microsoft 365 administrator
action is required for this deterministic gate.
