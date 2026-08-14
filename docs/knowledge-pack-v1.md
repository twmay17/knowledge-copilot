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

Stores retrievable source text plus a stable locator. Locators may include page, section path, sheet, cell range, or row range without requiring domain-specific fields.

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
- broken source, passage, assertion, evidence, calculation, question-family, or card references;
- values whose populated field does not match their declared type;
- confidence outside 0 through 1;
- calculated cards without a recorded derivation;
- supported cards without citation passages.

DomainProfile references also fail closed when the profile is unavailable, duplicated, or at an
unsupported version. Registered profiles validate their predicate namespace, typed values,
required qualifiers, allowed units, and deterministic calculation signatures.

Warnings are retained for reviewable conditions that do not make the pack structurally unsafe.

## Commands

From `OpenOats/`:

```bash
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift run knowledge-pack inspect ../fixtures/knowledge-packs/minimal-hospitality
```

The fixture is synthetic and redistributable. It exercises the generic contract through the
separate `HospitalityDomainProfile` Swift target. The core loader depends only on the public
`KnowledgeDomainProfile` interface; applications and tools choose which profiles to register.
