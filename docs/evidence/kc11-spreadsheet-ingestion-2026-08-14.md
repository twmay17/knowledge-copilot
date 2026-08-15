# KC-11 Spreadsheet Ingestion Evidence — August 14, 2026

## Result

The local KC-11 acceptance slice passes against genuine, visually reviewed XLSX and CSV fixtures.

- XLSX: 9 row passages across 2 worksheets with exact sheet, A1 cell-range, row, and content-hash
  locators.
- Formula lineage: local and cross-sheet formula cells retain both their formula and cached value,
  including `Operating Statement!C4` as `=C2/C3` with value `90`.
- Context: data rows retain their first-row headers plus generic period and unit values.
- CSV: 4 logical row passages preserve a quoted comma, escaped quotes, and a multiline field with
  stable A1 locators.
- Source resolution: every emitted passage resolves to its exact containment-checked,
  hash-verified fixture file.
- Fail-closed behavior: changed passage text fails KnowledgePack validation, unsafe relative paths
  are rejected, and formulas without cached values remain visible warnings.

## Verification

```bash
swift test --filter 'KnowledgeSpreadsheetIngestorTests|KnowledgePackLoaderTests'
swift run knowledge-pack ingest-spreadsheet \
  ../fixtures/spreadsheet-ingestion/sample-evidence.xlsx \
  --relative-path sample-evidence.xlsx
swift run knowledge-pack ingest-spreadsheet \
  ../fixtures/spreadsheet-ingestion/sample-evidence.csv \
  --relative-path sample-evidence.csv
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
```

The workbook's two rendered previews were inspected with no clipping or formula display errors.
The fixture's Open XML contains cached `<v>` results for every formula cell. The checked-in builder
uses formulas rather than hard-coded calculated outputs, and two consecutive builds produce
identical XLSX and CSV SHA-256 hashes. The combined spreadsheet, document, and KnowledgePack loader
verification run passed 21 of 21 tests.

This evidence contains no real meeting transcript, audio, business document, customer identity,
tenant detail, or proprietary figure.
