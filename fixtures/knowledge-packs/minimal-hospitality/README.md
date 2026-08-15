# Synthetic Hospitality Reference Corpus

This fixture is a fictional 100-room hotel created for OpenOats tests and demonstrations. All
names, facts, operating figures, calculations, and prose were authored for this repository. They
do not describe a real hotel, investor, operator, tenant, meeting, or transaction.

## What the fixture proves

- a direct fact: 100-room inventory;
- deterministic calculations: occupancy, ADR, and RevPAR;
- explicit `period`, room `scope`, and actual/budget `status` context that cannot be silently mixed;
- a directly reported value: 2020 RevPAR of $89.50;
- a deliberate contradiction: a fictional memo claims 2020 RevPAR of $92.00;
- an explicit absence: no 2018 performance data exists in the corpus;
- fuller operating context: actual and budget P&L rows for room, food-and-beverage, other,
  departmental, undistributed, and gross-operating-profit values;
- reusable golden expectations under `evaluation/golden-cases.jsonl`.
- a timestamped partial-speech vertical slice under `evaluation/live-proof-revpar.json` that can
  produce a machine-readable latency and citation-validity report.

## Public redistribution review

Reviewed August 14, 2026:

- [x] No source file was copied from a real deal, hotel, employer, paid database, or client.
- [x] No person, company, property address, tenant, meeting link, or account identifier appears.
- [x] Every source is plain text and covered by the repository license.
- [x] The intentional $92.00 conflict is clearly labeled as fictional test data.
- [x] SHA-256 hashes in `sources.jsonl` are checked by the loader before use.

The data is safe to publish with the repository, but it must always be presented as synthetic.
