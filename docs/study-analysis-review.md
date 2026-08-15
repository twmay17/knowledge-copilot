# Study Analysis and Human Review Gate

KC-16 turns a frontier model's Study Bundle analysis into a bounded, reviewable proposal. It does
not let the model write to a KnowledgePack and it does not infer human approval from model text.

The contract is provider-neutral. ChatGPT can be the first subscription-assisted preparation
workbench, but any model capable of returning the public JSON schema can produce the same untrusted
analysis file.

## Trust states

```text
validated KnowledgePack
  -> deterministic Study Bundle
  -> untrusted model analysis
  -> validated pending review queue (still generated)
  -> explicit human approve/reject decisions
  -> reviewed import artifact
  -> future atomic pack application
```

Only the human decision gate creates `KnowledgeResponseCard` records with `reviewStatus` equal to
`reviewed`. The analysis input type has no review-status field. If model output includes one anyway,
Swift decoding ignores it and the queue explicitly records `generated`.

The final command in KC-16 still does not mutate the active pack. It emits an approved-import
artifact containing the reviewed additions, base pack hash, resulting pack hash, reviewer,
timestamp, source analysis, and source queue identity. This makes the next atomic-write step
auditable and prevents a half-written pack.

## Stage 1: validate model analysis

The public input schema is
[`schemas/study-analysis-v1.schema.json`](../schemas/study-analysis-v1.schema.json). The validator
rebuilds the current Study Bundle and requires exact equality for:

- bundle ID;
- pack ID; and
- full pack-content hash.

It then fails closed on:

- unsupported schemas or oversized proposal sets;
- malformed, duplicate, or colliding IDs;
- blank, unnormalized, duplicated, or oversized text fields;
- unknown question-family, assertion, passage, or calculation references;
- abstention cards that carry factual evidence;
- factual cards without assertions and citations;
- calculated cards without a registered calculation and its output assertion;
- contested cards without at least two sides; and
- any citation outside the evidence closure of the claimed assertions and registered calculation
  inputs.

The resulting queue embeds the exact assertions, cited excerpts, locators, and calculation records
a reviewer needs. It has a deterministic `review-...` identity and the state
`pending_human_review`.

## Stage 2: explicit human decisions

The decision schema is
[`schemas/study-review-decisions-v1.schema.json`](../schemas/study-review-decisions-v1.schema.json).
It requires a reviewer, ISO-8601 timestamp, exact queue/analysis/bundle identities, and one explicit
`approve` or `reject` decision for every proposed question family and response card.

Before producing an import artifact, the gate:

- rebuilds the active bundle to reject stale queues;
- reconstructs and compares the entire queue to detect tampering;
- rejects missing, duplicate, and unknown decisions;
- converts only explicitly approved card proposals to `reviewed`;
- builds the would-be merged pack in memory;
- runs the complete KnowledgePack and Domain Profile validation suite; and
- records both the base and resulting full-content hashes.

If an approved card depends on a rejected proposed question family, merged-pack validation fails.
Rejecting every proposal is valid and produces no additions.

## Commands

From `OpenOats/`:

```bash
swift run knowledge-pack prepare-study-review \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../fixtures/study-analysis/synthetic-hospitality-analysis.json \
  --output ../outputs/kc16-review-queue.json

swift run knowledge-pack approve-study-review \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../outputs/kc16-review-queue.json \
  ../fixtures/study-analysis/synthetic-hospitality-decisions.json \
  --output ../outputs/kc16-approved-import.json
```

The first command is safe to run on untrusted model output. The second command should be run only
after the named reviewer has inspected the pending queue and deliberately authored the decision
file. Neither command calls a model, searches the web, talks to Microsoft 365, or changes pack
files.

## What remains manual

KC-16 proves the contract and command-line review gate, not the final reviewer UI. Today, the human
reviews JSON and writes the small decision file. The next slice can add an in-app review surface and
an atomic pack writer that rechecks `basePackContentHash` immediately before applying the approved
additions.
