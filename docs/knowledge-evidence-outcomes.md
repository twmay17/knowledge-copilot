# Knowledge Evidence Outcomes and Abstention

## Purpose

Retrieval is not an answer. A search can return several individually valid assertions that disagree,
use different definitions, describe different periods, or contain an analyst's interpretation.
`KnowledgeEvidenceOutcomeEvaluator` turns those typed, pack-bound retrieval results into a
structured outcome without silently selecting a winner or generating new factual prose.

The evaluator is domain-neutral. A hospitality question can require an asset, period, and scope; a
product pitch can require a product version; a historical argument can preserve two sourced
interpretations. The calling Domain Profile or playbook decides which context fields are required.

## Query contract

An evidence query supplies:

- a canonical predicate;
- an optional subject, representing the entity being discussed;
- exact qualifier values such as period, scope, version, or domain-specific context;
- optional source restrictions;
- the fields that must be present before evaluation; and
- an optional proposed typed value for fact checking.

The evaluator searches only the active pack's assertion records through its exact content-hash-bound
index. It then rechecks the pack ID, content hash, predicate, subject, qualifiers, and authoritative
assertion IDs before evaluation.

## Deterministic decision order

The order is deliberately conservative:

1. Missing required entity, period, scope, or version returns `needs_clarification`.
2. No matching assertion returns `not_found_in_corpus`; absence is never rewritten as a negative
   factual claim.
3. If the bounded search result cannot contain every eligible typed assertion, evaluation returns
   `needs_clarification` instead of silently dropping a possible competing claim.
4. Missing or unsafe provenance returns `needs_clarification` while retaining the typed claims and
   naming unresolved assertion IDs for diagnosis.
5. Unbound qualifier differences, conflicting typed values, or explicit counter-evidence return
   `contested` with every side intact.
6. A proposed value that disagrees with the single consistent corpus value returns
   `contradicted_by_corpus`.
7. Any surviving interpretive assertion makes the outcome `interpretive`.
8. Otherwise the outcome is `calculated`, `directly_sourced`, or `supported_by_corpus` according to
   the contributing assertion kinds.

Conflicts take priority over contradiction of a proposed value: if the corpus itself disagrees, the
system reports that contest instead of pretending the corpus has one authoritative position.

## Structured QA projection

`KnowledgeEvidenceOutcome` is Codable and includes:

- the exact pack ID and canonical full-content hash;
- the evidence state and machine-readable decision reason;
- every contributing assertion with typed value, display value, qualifiers, kind, and confidence;
- every assertion-to-passage evidence relation and note;
- deduplicated source references with source ID, title, safe local file URL, locator, and excerpt;
- missing required fields; and
- assertion IDs whose provenance could not be resolved.

Calculated assertions use their own derivation citations when present. If a calculated output has no
direct evidence link, the evaluator walks its one registered calculation to the input assertions and
preserves their source attributions. Cycles, ambiguous derivations, missing files, or paths outside the
active pack fail closed.

## App integration

`KnowledgePackStore` creates and clears the evaluator with the validated pack and its search index.
The application can call `evaluateKnowledgeEvidence(_:)` for pre-answer analysis or live fact
checking. This milestone does not allow the evaluator to synthesize read-aloud wording and does not
replace the separate reviewed response-card gate.

That separation is intentional:

```text
question or claim
      |
      v
pack-bound retrieval
      |
      v
deterministic evidence outcome ----> structured claims and source links
      |
      v
reviewed response or explicit abstention
```

## Cost and safety boundary

- Evaluation is local and deterministic; it requires no model, web search, paid service, or Microsoft
  365 administrator access.
- Models may help prepare candidate assertions before a meeting, but generated records still require
  human review before entering the searchable pack.
- The evaluator reports what the selected corpus contains. It does not claim that the corpus is
  complete or that a contested source is correct.
- A future quick model may phrase or rank an already structured outcome, but it must not remove
  sources, collapse conflicts, or upgrade an abstention state.
