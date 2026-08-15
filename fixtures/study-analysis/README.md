# Synthetic Study Analysis Fixture

These files contain no licensed, confidential, or real deal data. They are bound to the synthetic
`minimal-hospitality` KnowledgePack and exercise the full KC-16 review boundary.

- `synthetic-hospitality-analysis.json` represents untrusted frontier-model proposals.
- `synthetic-hospitality-decisions.json` represents explicit human approve/reject decisions.

The analysis copies the exact Study Bundle ID and full pack-content hash. If the reference pack
changes, export a new Study Bundle, update those two fields, run `prepare-study-review`, and update
the decision fixture's queue ID. A stale analysis or decision file is expected to fail closed.

Generated review queues and approved-import artifacts belong in `outputs/`, which is ignored by
Git. The approval command does not edit the reference KnowledgePack.
