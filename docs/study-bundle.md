# Study Bundle Preparation Boundary

The Study Bundle is the preparation bridge between a validated KnowledgePack and a heavier
frontier-model study session. It lets a presenter do the hard analysis before a meeting while the
live application stays fast, deterministic, and independent of any one model provider.

This boundary is domain-neutral. A hospitality pack, product pitch, historical debate, or any
other evidence corpus uses the same export. Domain Profiles improve normalization and calculations
but are not required.

## Two separate intelligence lanes

### Preparation lane

The local `knowledge-pack` tool exports a deterministic JSON Study Bundle. A user may deliberately
upload that file to ChatGPT and use a capable frontier model to map the corpus, anticipate question
families, find contradictions, identify missing facts, and draft cited presenter responses.

This is the subscription-assisted path: ChatGPT is a user-operated preparation workbench, not a
hidden programmatic dependency. The application does not scrape, automate, or reuse a ChatGPT
session, and it does not claim that a ChatGPT subscription supplies API access. OpenAI describes
ChatGPT as able to analyze files and data, while its API Platform is the separate product for
building model calls into applications:

- [ChatGPT Learn](https://learn.chatgpt.com/) describes file and data analysis in ChatGPT Work.
- [OpenAI API Platform](https://platform.openai.com/overview) is the integration path for an
  application that makes model requests itself.

Model output remains proposed preparation material. The
[study-analysis and human-review gate](study-analysis-review.md) validates IDs, citations, evidence
states, calculations, and explicit reviewer decisions before any generated card can become
`reviewed`.

### Live lane

The V1 live path does not need a language-model call to answer a prepared question. Local
transcription revisions feed deterministic partial-question detection, which starts retrieval
before the sentence finishes. Only a stable candidate can resolve a reviewed, cited response card.
If the corpus does not support one answer, the overlay abstains.

This separation makes the meeting easier because expensive reasoning happened beforehand. It also
avoids depending on Microsoft 365 tenant administration: the bundle is created on the presenter's
Mac, Teams remains an ordinary meeting client, and no Teams bot, Graph subscription, or tenant app
installation is required.

An optional future live-model adapter may use a user-selected local model or separately authorized
API provider for unprepared phrasing and summarization. That adapter must remain behind the same
closed-corpus evidence gate; it cannot turn web access or model memory into factual authority.

## Exported contract

The schema-v1 JSON bundle contains:

- the source titles, safe pack-relative paths, and SHA-256 hashes;
- the complete normalized assertion ledger;
- exact evidence excerpts and locators for every assertion link;
- exact excerpts for every passage cited by a reviewed response card;
- registered deterministic calculations;
- existing question families and speech prefixes;
- reviewed response cards only;
- a full-content hash and deterministic bundle ID; and
- an explicit policy declaring closed-corpus operation, disabled web search, required citations,
  document instructions as untrusted data, and `not_found_in_corpus` as the unsupported-answer
  state.

The exporter fails closed on absolute or parent-traversing source paths, unresolved assertion
evidence, calculated assertions without one derivation, and broken references in reviewed cards.
Changing record content changes the bundle hash even when the record IDs stay the same.

The bundle deliberately omits audio, live transcripts, API credentials, absolute file locations,
and unreviewed/generated cards.

## Command

From `OpenOats/`:

```bash
swift run knowledge-pack export-study-bundle \
  ../fixtures/knowledge-packs/minimal-hospitality \
  --output ../outputs/study-bundle.json
```

The file can then be attached to a user-operated ChatGPT study session with the
[closed-corpus preparation prompt](study-bundle-chatgpt-prompt.md).

## Confidentiality boundary

A Study Bundle includes exact source excerpts. It must be treated with the same confidentiality as
the underlying deal or research materials. Users should upload it only when their organization and
chosen account permit that data handling. Public fixtures and tests must remain synthetic and
redistributable; private Study Bundles must never be committed to the open-source repository.

## Current acceptance slices

KC-15 establishes deterministic export and the user-operated preparation workflow. KC-16 defines
the machine-readable analysis-result contract and a human review/import gate. Direct API
automation, if added later, remains a replaceable adapter and is not required to obtain value from
the subscription-assisted workflow.
