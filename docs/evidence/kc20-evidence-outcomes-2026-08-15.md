# KC-20 Public Evidence Summary — Evidence Outcomes and Abstention

Date: 2026-08-15

## Claim

OpenOats now evaluates retrieved KnowledgePack assertions through a deterministic, domain-neutral
evidence contract that preserves disagreement and attribution instead of silently choosing one
answer.

## Implemented controls

- Evaluation is bound to the exact active pack ID and canonical full-content hash.
- Missing required entity, period, scope, or version returns `needs_clarification` before factual
  evaluation.
- No matching assertion returns `not_found_in_corpus` without inventing a negative claim.
- Conflicting values remain separate with their typed values, qualifiers, and per-claim citations.
- Assertions with incompatible unbound contexts remain visible as a contested outcome.
- Interpretive assertions are labeled and retain the source passage that supports or contextualizes
  them.
- A proposed typed value can be marked `contradicted_by_corpus` only when the matching corpus values
  are internally consistent and disagree with it.
- Missing, unsafe, cyclic, or ambiguous provenance fails closed while retaining diagnostic assertion
  IDs.
- A bounded retrieval that cannot include every eligible assertion requests clarification instead of
  silently discarding a possible competing claim.
- Calculated outputs can trace attribution through their registered input assertions.
- Structured JSON output links to every contributing local source, locator, and excerpt.
- The application-store lifecycle creates and clears the evaluator with the active validated pack and
  search index.

## Verification boundary

The focused suite covers the synthetic RevPAR conflict, incompatible definition versions,
interpretive attribution, missing context, corpus absence, explicit claim contradiction, unavailable
evidence, app-store lifecycle, stale index rejection, and JSON round-trip behavior. Related search,
loader, assertion/evidence, answer-resolution, preparation, review, and import tests plus the
non-environmental package suite and release builds form the broader milestone verification set.

No private corpus, meeting audio, credentials, local filesystem paths, or proprietary underwriting
data is included in this evidence summary.
