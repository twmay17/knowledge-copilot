# PDF and DOCX Evidence Ingestion

KC-10 adds a deterministic, local document-ingestion boundary for KnowledgePack sources. It does
not call a model, upload a document, or search the web.

## Supported inputs

- PDF files with an extractable text layer, read page-by-page with PDFKit.
- DOCX files, expanded locally with the macOS `ditto` tool and parsed from
  `word/document.xml`.

DOCX paragraphs inherit their nearest Word heading path. Native Word tables become one tab- and
newline-delimited passage with a stable one-based table locator. PDF passages retain one-based page
locators. Every passage also receives a document-order block number and a SHA-256 hash of its exact
normalized text.

## Stable identity and source resolution

The source ID is derived from the source file's SHA-256 hash. A passage ID is derived from the
source hash, locator, section path, and passage-content hash. Import time does not affect either ID.

`KnowledgeDocumentIngestionResult.resolvedSourceURL(for:relativeTo:)` fails closed unless:

- the passage belongs to the ingestion result's source;
- its current text matches the locator's content hash;
- its source path stays inside the supplied root directory; and
- the current source file matches the source record's SHA-256 hash.

The KnowledgePack validator applies the same passage-content-hash check when an ingested passage is
loaded later.

## OCR-quality signals

This milestone does not add an OCR engine. PDFKit reads the PDF text layer already present in the
file. A page with no extractable text emits a `no_extractable_text` warning and no invented passage.
A short or suspiciously corrupted text layer is retained but marked with:

```json
{
  "quality": "low",
  "flags": ["low_quality_ocr"]
}
```

The CLI prints every warning, and the KnowledgePack validator preserves low-quality extraction as a
review warning. It never silently upgrades uncertain text into trusted evidence.

## Command

From `OpenOats/`:

```bash
swift run knowledge-pack ingest-document \
  ../fixtures/document-ingestion/sample-evidence.pdf \
  --relative-path sources/sample-evidence.pdf \
  --output ../tmp/pdf-ingestion.json

swift run knowledge-pack ingest-document \
  ../fixtures/document-ingestion/sample-evidence.docx \
  --relative-path sources/sample-evidence.docx \
  --output ../tmp/docx-ingestion.json
```

The JSON result contains one `KnowledgeSource`, its `KnowledgePassage` records, and visible warnings.
Pack-authoring code can serialize the source and passages as JSONL after copying the exact source
file to the recorded relative path.

## Current limits

- Image-only PDFs are flagged for OCR/review but not OCR-processed in this milestone.
- PDF tables remain page text because PDF files generally do not encode a reliable table structure.
- DOCX headers, footers, comments, tracked changes, drawings, charts, and embedded files are outside
  the v1 ingestion scope.
- DOCX expansion currently depends on `/usr/bin/ditto`, consistent with the product's macOS 15+
  platform boundary.

These limits are explicit so the product abstains instead of losing lineage or presenting guessed
structure as fact.
