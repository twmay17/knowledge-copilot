# KC-19 Public Evidence Summary — Hybrid Search and Corpus Invalidation

Date: 2026-08-15

## Claim

OpenOats now builds a deterministic, pack-bound search index for every validated KnowledgePack. It
combines no-cost exact and SQLite full-text retrieval with an optional, sandboxed vector-ranking
adapter and rebuilds when the canonical corpus hash changes.

## Implemented controls

- Every query is bound to the exact active pack ID and can be restricted by record kind, source, and
  required qualifiers.
- Results identify their pack ID and full-content hash and expose their source IDs, qualifiers,
  matching channels, and component scores.
- Only human-reviewed response cards enter the search index.
- The local exact and FTS5 lanes need no account, network access, or paid service.
- Optional vector search receives only locally scoped candidates; unknown IDs and adapter failures
  cannot introduce material.
- Typed record comparison and transitive dependency traversal cover source, passage, evidence,
  assertion, calculation, response-card, question-family, and manifest changes.
- Identical content reuses its existing index; changed content rebuilds; another pack ID always starts
  fresh.
- The application store builds and clears the validated pack and its index as one lifecycle.
- A JSON CLI search command provides a repeatable integration proof.

## Verification boundary

The focused suite covers pack, source, record-kind, and qualifier isolation; exact and full-text
retrieval; optional vector containment and fallback; source and manifest invalidation; unchanged
content reuse; cross-pack replacement; rebuild reporting; and application-store refresh behavior.
The milestone verification set also includes the related KnowledgePack, answer-card, Study Bundle,
review, import, and workspace regressions; the non-environmental package suite; both release builds;
strict formatting; CLI output inspection; and whitespace checks.

No private corpus, meeting audio, credentials, local filesystem paths, or proprietary underwriting
data is included in this evidence summary.
