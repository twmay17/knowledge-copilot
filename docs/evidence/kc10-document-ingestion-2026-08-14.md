# KC-10 Document Ingestion Evidence — August 14, 2026

## Result

The local KC-10 acceptance slice passes against genuine, visually reviewed PDF and DOCX fixtures.

- PDF: 2 page passages, stable page/block/content-hash locators, and 1 visible
  `low_quality_ocr` warning on the deliberately damaged page.
- DOCX: 6 passages, heading-path lineage, and 1 native table passage containing the expected RevPAR
  row.
- Source resolution: every emitted passage resolves to its exact hash-verified fixture file.
- Fail-closed behavior: changed passage text fails KnowledgePack validation against the stored
  content hash, and unsafe relative paths are rejected.

## Verification

```bash
swift test --filter 'KnowledgeDocumentIngestorTests|KnowledgePackLoaderTests'
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
```

The focused ingestion-plus-loader run passed 13 of 13 tests. The PDF rendered as two clean pages;
the DOCX rendered as one clean page with no clipping or overlap. Its fixed table geometry passed the
`tblW`, `tblInd`, `tblGrid`, and per-cell `tcW` audit.

This evidence contains no real meeting transcript, audio, business document, customer identity,
tenant detail, or proprietary figure.
