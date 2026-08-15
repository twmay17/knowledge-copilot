# Spreadsheet Ingestion Fixtures

These public-safe files exercise KC-11 without real deal documents or proprietary data.

- `sample-evidence.xlsx` contains two formatted worksheets, hotel operating values, local formulas,
  and one cross-sheet formula. Formula cells contain genuine cached values.
- `sample-evidence.csv` contains a header and three logical data rows, including a quoted comma,
  escaped quotes, CRLF line endings, and one quoted multiline field.

All facts and figures are fictional. Rebuild both fixtures and their ignored visual previews with:

```bash
NODE_PATH=/path/to/node_modules /path/to/node \
  scripts/build_kc11_spreadsheet_fixtures.mjs
```

The builder uses `@oai/artifact-tool`, visually renderable formatting, formula-driven calculated
values, CSV import validation, fixed ZIP timestamps, and normalized relationship identifiers for
deterministic artifacts. It writes PNG previews under the ignored
`outputs/kc11-spreadsheet-fixtures/` directory.
