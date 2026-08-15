# KnowledgePack v1 Contract

KnowledgePack v1 is the corpus boundary for the live copilot. It is intentionally simple, inspectable, and friendly to Git, local tools, and preparation workflows.

## Directory layout

```text
knowledge-pack/
  manifest.json
  sources.jsonl
  passages.jsonl
  assertions.jsonl
  evidence-links.jsonl
  calculations.jsonl
  response-cards.jsonl
  question-families.jsonl
  sources/
```

Each JSONL file contains one JSON object per non-empty line. Lines beginning with `#` are ignored. Source files are addressed by safe paths relative to the pack root and carry a lowercase SHA-256 content hash.

## Base records

### Manifest

Defines the schema version, stable pack ID, human title, creation time, default locale, and optional DomainProfile references.

### Source

Identifies a document, spreadsheet, presentation, note, transcript, or structured-data file. A source records its relative path, content hash, kind, and import time.

### Passage

Stores retrievable source text plus a stable locator. Locators may include page, table, document
block, section path, sheet, cell range, row range, and an exact passage-content SHA-256 hash without
requiring domain-specific fields. Ingested passages may also record their extraction method,
quality, confidence, and visible quality flags.

The PDF/DOCX ingestion contract, source-resolution rules, OCR-quality behavior, and explicit format
limits are documented in [PDF and DOCX evidence ingestion](document-ingestion.md).

### Assertion

Stores a normalized proposition as subject, predicate, typed value, qualifiers, assertion kind, confidence, and evidence links. Values may be text, number, boolean, date, or a reference. Units and scales are valid only for numbers.

Assertion kinds are:

- `stated`
- `calculated`
- `inferred`
- `interpretive`

### Evidence link

Connects an assertion to a source passage and records whether that passage supports, contradicts, derives, or contextualizes the assertion.

### Calculation

Records a deterministic expression, version, input assertion IDs, and output assertion ID. The expression is provenance, not code to execute blindly.

### Question family

Groups a canonical question with paraphrases, partial prefixes, ASR aliases, and tags. This is the preparation-to-live bridge that lets retrieval begin before a sentence ends.

## Partial-speech question events

The live detector accepts ordered transcript revisions without depending on an ASR vendor or a
specific business domain. Each revision carries a stream ID, a monotonically increasing sequence,
text, and either `partial` or `final` stability.

When a partial revision matches a prepared question family, the detector emits a provisional
`QuestionCandidate`. A second compatible revision, or a final revision, promotes the same
candidate ID to stable. Repeating the final text does not emit a duplicate event. If the ASR text
changes the question family or a material binding such as the period, the detector cancels the
stale candidate before emitting its replacement. Clearing a partial also emits a cancellation so
speculative retrieval can be discarded.

DomainProfile vocabulary enters this path only as opaque term IDs and aliases. For example, the
hospitality profile maps both `RevPAR` and spoken `rev par` to `hospitality.revpar`; the generic
detector does not contain hotel-specific types or formulas. Matching is local and deterministic,
so question detection does not call a language model or the web.

`KnowledgePackStore.processTranscriptRevision(_:)` is the app integration boundary. It retains the
active candidate per transcript stream and exposes the latest upsert/cancel events for the next
retrieval stage.

## Presenter answer resolution

Only a stable candidate may surface a factual presenter card. The resolver selects exactly one
reviewed response card whose question family and resolved bindings agree with the candidate. A
requested period must match a cited assertion's period, and a resolved term must match an
assertion predicate. This prevents a prepared 2020 answer from being reused after ASR corrects the
question to 2021.

Resolution fails closed when there is no reviewed match, more than one reviewed match, a missing
calculation, or evidence that cannot be resolved to a safe local file inside the selected pack.
The resulting fallback says either `not_found_in_corpus` or `needs_clarification`; it never
synthesizes a factual answer.

Each resolved citation carries the source title, a human-readable locator such as
`Operating Statement · A3:J3 · 2020 actual`, the source excerpt, and the verified local file URL.
The presenter overlay shows the read-aloud answer first, followed by its evidence state,
calculation, and one-action evidence buttons. The same trusted card appears in both the classic
private overlay and Sidecast mode.

### Response card

Contains presenter-sized answer text and references to question families, assertions, passages, and calculations. A card also carries review status and exactly one primary evidence state.

## Evidence states

- `directly_sourced`
- `calculated`
- `supported_by_corpus`
- `contradicted_by_corpus`
- `contested`
- `interpretive`
- `not_found_in_corpus`
- `needs_clarification`

Calculated cards require a calculation, output assertion, and source citation. Other factual or interpretive cards require at least one citation passage. Abstention cards may not imply an unsupported answer.

## Loader validation

The v1 loader fails closed on:

- unsupported schema versions;
- missing required files;
- malformed JSON or JSONL;
- empty or duplicate IDs;
- unsafe source paths;
- invalid SHA-256 values;
- ingested passage text that does not match its locator content hash;
- extraction confidence outside 0 through 1;
- broken source, passage, assertion, evidence, calculation, question-family, or card references;
- values whose populated field does not match their declared type;
- confidence outside 0 through 1;
- calculated cards without a recorded derivation;
- supported cards without citation passages.

DomainProfile references also fail closed when the profile is unavailable, duplicated, or at an
unsupported version. Registered profiles validate their predicate namespace, typed values,
required qualifiers, allowed units, and deterministic calculation signatures.

Warnings are retained for reviewable conditions that do not make the pack structurally unsafe.
Low-quality extracted text is one such warning and remains visibly flagged on the passage.

## Commands

From `OpenOats/`:

```bash
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift run knowledge-pack inspect ../fixtures/knowledge-packs/minimal-hospitality
swift run knowledge-pack replay \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../fixtures/knowledge-packs/minimal-hospitality/evaluation/live-proof-revpar.json
swift run knowledge-pack ingest-document \
  ../fixtures/document-ingestion/sample-evidence.docx \
  --relative-path sources/sample-evidence.docx
```

The fixture is synthetic and redistributable. It exercises the generic contract through the
separate `HospitalityDomainProfile` Swift target. The core loader depends only on the public
`KnowledgeDomainProfile` interface; applications and tools choose which profiles to register.

## Synthetic hospitality reference fixture

`fixtures/knowledge-packs/minimal-hospitality` is the public first-proof corpus. It contains:

- a fictional multi-period operating statement with actual and budget P&L rows;
- a fictional room-inventory schedule;
- a deliberately inconsistent investment memo used to test contradiction handling;
- direct, calculated, contested, and corpus-missing response cards;
- deterministic room-night, occupancy, ADR, RevPAR, total-revenue, and GOP calculations;
- machine-readable expected responses in `evaluation/golden-cases.jsonl`;
- a provenance and redistribution checklist in the fixture README.

The loader verifies every source hash. The focused test suite also maps every golden case to a
reviewed response card and checks that its expected evidence state and answer fragments match.
Hospitality units, aliases, predicates, and formulas remain owned by the separate profile target;
none are added to the generic KnowledgePack model.

The timestamped replay specification is an executable vertical slice. It verifies the prepared
partial question, stable reviewed card, response deadline, processing-latency budget, expected
answer fragments, and exact citation files from a clean in-memory state. See
[the replay protocol](knowledge-proof-replay.md).
