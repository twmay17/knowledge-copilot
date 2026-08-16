# KnowledgePack Correctness Gate

`knowledge-pack audit-correctness` is the deterministic release gate for reviewed corpus content.
It runs locally, uses no model or network service, and exits nonzero unless every pack, assertion,
calculation, citation, evidence label, and cross-pack isolation check passes.

The gate complements the conversation replay. A replay can prove that a sentence still selects a
particular card, but it cannot by itself detect every valid-looking change inside the underlying
pack. For example, changing a generic product assertion from `version=launch` to `version=pilot`
still satisfies the JSON schema. The correctness gate detects that drift before the altered pack can
be treated as reviewed release content.

## V1 contract

`fixtures/correctness-gate-v1.json` references the same two synthetic KnowledgePacks as the
101-scenario replay benchmark. Each pack has reviewed SHA-256 fingerprints for:

- the complete canonical pack;
- sources and passages;
- assertions, including subject, predicate, typed value, unit, scale, and qualifiers;
- evidence links;
- registered calculations;
- response cards, including evidence state and citation IDs; and
- question families.

Separate hashes make the failure actionable. A qualifier change fails the assertion fingerprint;
a formula change fails the calculation fingerprint; a citation or evidence-label change fails the
response-card fingerprint. The complete pack hash remains the final identity check.

The runner also applies the ordinary loader and Domain Profile validators, then audits every
non-abstention card. Each citation must resolve to an existing source file inside the active pack,
and every claimed assertion must have an attributable passage among the card's citations. Abstention
cards must carry no assertions, calculations, or citations.

## Evidence outcome probes

Eight typed probes independently reproduce every supported evidence state and its decision reason:

- `directly_sourced`;
- `calculated`;
- `supported_by_corpus`;
- `contradicted_by_corpus`;
- `contested`;
- `interpretive`;
- `not_found_in_corpus`; and
- `needs_clarification`.

Each probe pins the active pack ID, expected assertion IDs, and exact contributing passage IDs. A
probe passes only when the evidence evaluator returns the expected state, reason, claims, and safe
pack-local source files.

## Cross-pack isolation

The correctness gate runs the versioned replay benchmark after pack validation. Its `cross_pack`
scenarios intentionally ask the active pack about material found only in the other pack. V1 requires
at least two such scenarios, and every one must finish without a response card. A reference to a
passage ID that exists only in another pack fails as an unknown citation inside the owning pack.

## Run the gate

From `OpenOats/`:

```bash
swift run knowledge-pack audit-correctness \
  ../fixtures/correctness-gate-v1.json \
  --output /tmp/knowledge-correctness-report.json
```

The JSON report contains the overall verdict, eight release checks, per-pack fingerprints and
findings, all outcome-probe results, and a replay/cross-pack summary.

## Deliberately updating a reviewed baseline

After an intentional pack change has passed human review, produce the candidate fingerprints with:

```bash
swift run knowledge-pack fingerprint-correctness \
  ../fixtures/knowledge-packs/minimal-hospitality
```

Do not update the correctness spec merely to make a failure disappear. Review the semantic diff,
update affected outcome probes and replay expectations, run the tamper tests, and then replace only
the fingerprints for the deliberately changed pack.

Fingerprints detect drift in the checked-in baseline; they are not digital signatures and do not
replace repository access controls or code review.

## Fail-closed regression matrix

`KnowledgeCorrectnessGateTests` proves that the clean baseline passes and that each of these changes
fails:

- a structurally valid qualifier drift;
- a corrupted deterministic calculation output;
- a mislabeled response-card evidence state;
- a citation swapped to another existing passage in the same pack; and
- a citation borrowed from the other pack.

## Scope boundary

This gate establishes deterministic correctness for checked-in, synthetic corpus fixtures. It does
not validate live audio capture, transcription accuracy, participant consent, or real meeting
behavior. KC-24 and KC-25 remain open until the consented Teams alpha findings are incorporated;
the gate must be rerun after that dependency closes.
