# Document Ingestion Fixtures

These public-safe files exercise KC-10 without real deal documents or proprietary data.

- `sample-evidence.pdf` contains one clean narrative page and one deliberately damaged OCR-like
  text layer used to verify visible quality warnings.
- `sample-evidence.docx` contains styled narrative sections and one native Word table used to verify
  section-path and table locators.

Both files contain only fictional facts and figures created for this repository. Rebuild them with:

```bash
/path/to/python3 scripts/build_kc10_document_fixtures.py \
  --output-dir fixtures/document-ingestion
```

The fixture builder normalizes DOCX ZIP timestamps and uses ReportLab's invariant PDF output so the
artifacts remain deterministic.
