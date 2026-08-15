# KC-9 First Working Proof — August 14, 2026

## Result

**PASS** — the synthetic 2020 RevPAR answer was ready at **420.776 ms**, before the 1,000 ms
response deadline and **479.224 ms before final speech**.

Measured local detector/resolver processing latency across the three transcript revisions:

| Measure | Result | Budget |
| --- | ---: | ---: |
| Median | 0.605 ms | 50 ms maximum |
| p95 | 0.776 ms | 50 ms maximum |
| Maximum | 0.776 ms | 50 ms maximum |

## Verified vertical slice

- Partial `What was the rev par` produced provisional candidate `remote#1`.
- The 420 ms partial promoted the same candidate to stable.
- The reviewed `card-revpar-2020` appeared with `calculated` evidence state.
- The response contained $89.50, $3,266,750, and 36,500 available room nights.
- `passage-operating-2020-actual` resolved to `Operating Statement · A3:J3 · 2020 actual`.
- `passage-inventory-2020-actual` resolved to `Room Inventory · A3:H3 · 2020 actual`.
- Both cited files existed inside the selected synthetic KnowledgePack.
- The equivalent final ASR spelling produced no duplicate event.

The machine-readable report is [kc9-first-proof-2026-08-14.json](kc9-first-proof-2026-08-14.json).

## Reproduce

From `OpenOats/`:

```bash
swift run knowledge-pack replay \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../fixtures/knowledge-packs/minimal-hospitality/evaluation/live-proof-revpar.json \
  --output ../docs/evidence/kc9-first-proof-2026-08-14.json
```

This evidence covers the deterministic in-process path after transcript revisions arrive. Audio
capture and ASR timing remain separately verified and are not included in the 420.776 ms figure.
