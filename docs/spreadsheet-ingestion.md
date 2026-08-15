# XLSX and CSV Evidence Ingestion

KC-11 adds a deterministic, local spreadsheet-ingestion boundary for KnowledgePack sources. It
does not call a model, upload a workbook, recalculate formulas, or search the web.

## Supported inputs

- XLSX workbooks, expanded locally with the macOS `ditto` tool and read from their Open XML parts.
- UTF-8 CSV files, including byte-order marks, CRLF or LF line endings, quoted commas, escaped
  quotes, and embedded newlines.

Each non-empty worksheet or CSV record becomes one generic `KnowledgePassage`. The passage keeps a
`KnowledgeSpreadsheetPassage` payload containing its cells, inferred period and unit, and whether
the row is the header row. No hotel-specific field is required by the core model.

## Cell and row lineage

XLSX passages retain:

- worksheet name;
- one-based row start and end;
- exact A1 cell range;
- each populated cell's A1 reference and first-row header;
- typed cached value (`blank`, `boolean`, `error`, `number`, or `text`);
- formula, when present; and
- Excel number-format code, when present.

CSV passages use stable A1 references over each logical record. Quoted physical newlines remain
part of the field, but do not create a new record or change later row locators. A header named
`Period`, `Year`, `Date`, `As Of`, or `as_of` supplies generic period context. A header named
`Unit`, `Units`, or `Currency` supplies generic unit context.

The source record stores the exact workbook or CSV SHA-256 hash. Passage text is a deterministic
tab-delimited rendering of the row, including both cached values and formulas. Its exact SHA-256
hash is stored in the locator and contributes to the stable passage ID. Import time does not affect
source or passage identity.

`KnowledgeSpreadsheetIngestionResult.resolvedSourceURL(for:relativeTo:)` fails closed unless:

- the passage belongs to the ingestion result's source;
- its current text matches the locator's content hash;
- its source path stays inside the supplied root directory; and
- the current source file matches the source record's SHA-256 hash.

The KnowledgePack validator applies the same content-hash check and additionally rejects a
spreadsheet payload attached to a non-spreadsheet source, empty cell arrays, duplicate or invalid
A1 references, and empty formulas.

## Formula policy

OpenOats records formulas; it does not execute untrusted workbook logic. If the XLSX contains a
cached result, the cell retains both the formula and that value. If a formula has no cached result,
ingestion keeps the formula, emits `xlsx_formula_missing_cached_value`, and the KnowledgePack
validator retains a visible review warning. It never invents a result.

This boundary is important for grounded live answers: a presenter can cite the exact workbook cell
and distinguish a stated value from a workbook calculation without silently recalculating or
searching elsewhere.

## Command

From `OpenOats/`:

```bash
swift run knowledge-pack ingest-spreadsheet \
  ../fixtures/spreadsheet-ingestion/sample-evidence.xlsx \
  --relative-path sources/sample-evidence.xlsx \
  --output ../tmp/xlsx-ingestion.json

swift run knowledge-pack ingest-spreadsheet \
  ../fixtures/spreadsheet-ingestion/sample-evidence.csv \
  --relative-path sources/sample-evidence.csv \
  --output ../tmp/csv-ingestion.json
```

The JSON result contains one `KnowledgeSource`, its `KnowledgePassage` records, and visible
warnings. Pack-authoring code can serialize the source and passages as JSONL after copying the
exact source file to the recorded relative path.

## Current limits

- XLS, XLSB, ODS, password-protected workbooks, and macro extraction are outside v1 scope.
- Formulas are preserved with their stored values but are not recalculated.
- Charts, pivot tables, comments, threaded notes, named ranges, hidden-state semantics, external
  links, Power Query, and embedded files are not extracted.
- The first non-empty worksheet row is treated as the header row; merged or multi-row headers need
  a later normalization step.
- Blank cells omitted by XLSX are not expanded into synthetic cells.
- CSV values are typed conservatively from their text and CSV has no native formula or style
  metadata.
- XLSX expansion currently depends on `/usr/bin/ditto`, consistent with the product's macOS 15+
  platform boundary.

These limits are explicit so the product can abstain instead of presenting guessed spreadsheet
structure as fact.
