# Tiered Answer Resolver

The tiered resolver turns a live question or claim event into an incremental answer stream without
giving any lane permission to leave the active KnowledgePack. It is domain-neutral: the only
domain-specific inputs are opaque term IDs, question families, typed assertions, reviewed response
cards, and source evidence already admitted into the pack.

## Lanes and default budgets

| Lane | Default budget | Work allowed | Typical overlay result |
| --- | ---: | --- | --- |
| Hot | 40 ms | Reviewed-card lookup and exact typed assertion/calculation evaluation | Reviewed answer, exact value, fact-check, conflict, or explicit abstention |
| Warm | 250 ms | Pack-bound exact/full-text search plus an optional scoped vector reranker | Retrieved evidence preview when no canonical predicate is available |
| Cold | 2,000 ms | Optional prose refinement over an immutable evidence allow-list | Same-evidence answer refinement with complete citations |

All budgets are explicit and configurable through `KnowledgeAnswerLatencyBudgets`. A timed-out lane
is cancelled and cannot delay a faster visible result. A later result does not win merely because it
is newer or slower.

## Authority and visible replacement

The resolver tracks support and presentation quality separately:

1. reviewed, corpus-supported response card;
2. exact typed evidence admitted by `KnowledgeEvidenceOutcomeEvaluator`;
3. pack-bound retrieval preview; and
4. explicit abstention.

A result may supersede the visible card only when its support level is strictly stronger. A cold
answer may refine an exact-evidence card at the same support level only when both have the identical
pack hash, evidence state, assertion set, and source set. This permits clearer phrasing without
allowing generated prose to overrule evidence. Reviewed cards bypass cold synthesis entirely.

Every update identifies the event, stream, ASR revision, lane, budget, measured processing time,
support level, presentation quality, and the update it replaces. `AnswerSuperseded` produces an
explicit retraction. Superseded event IDs are tombstoned so a late ASR revision cannot resurrect an
old answer.

## Corpus-only synthesis contract

`KnowledgeConstrainedAnswerSynthesizer` receives one
`KnowledgeConstrainedSynthesisRequest`. That request contains only:

- the active pack ID and exact content hash;
- the source question or claim text;
- the evidence outcome state;
- typed claims and passages admitted by the evidence evaluator;
- current-pack hybrid retrieval records; and
- citation requirements covering every admitted claim.

The protocol exposes no KnowledgePack, search index, retrieval closure, URL loader, browser, network
client, or tool callback. An implementation cannot ask the resolver to search the web. Its output is
discarded unless every citation belongs to the request allow-list and every admitted claim has at
least one cited assertion or passage. This is a structural evidence gate; it does not claim that
string matching alone can prove semantic entailment.

A future provider adapter may call a local model, a user-selected frontier API, or a manually
bridged ChatGPT workflow. That adapter remains outside the resolver and must preserve this closed
request/response contract.

## Questions, claims, and missing context

Questions with one canonical `term` binding use the term as the assertion predicate. A unique
`period` binding becomes a required qualifier. If every matching assertion has the same subject,
that subject is bound automatically. Provisional questions may surface exact evidence before final
punctuation; reviewed cards remain stable-question only.

Claims use the same typed evidence path. A single numeric literal is parsed only when the matching
assertions agree on value type and unit. The proposed value is then passed to the evidence evaluator,
which can return `contradicted_by_corpus`, `contested`, or another existing evidence state. Ambiguous
terms, units, or literals fail closed rather than being guessed.

If no canonical predicate exists, the warm lane can show a pack-bound evidence preview. Retrieval by
itself is never promoted to a corpus-verified factual answer.

## Application integration

`KnowledgePackStore` constructs and clears the resolver atomically with the active pack, index, and
evidence evaluator. Overlay work can call `answerUpdates(for:vectorAdapter:synthesizer:)` for every
live event while the existing synchronous reviewed-card path remains compatible.

This layer requires no Microsoft 365 administrator permission, Teams bot installation, tenant
registration, cloud account, or network service. Audio capture and transcription feed live events
through separate adapters.
