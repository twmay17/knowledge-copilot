# Hospitality Underwriting Import Profile

KC-14 turns a house-standard hospitality underwriting folder into typed KnowledgePack evidence
without making those conventions part of the domain-neutral core. The importer is deterministic,
local, and versioned as `hospitality@0.2.0`.

The mapping was pinned from the underwriting-process reference at commit
`003d3c2cbc1261eb07cf57e7ddda4d602ccc24af`. The adapter intentionally incorporates the reviewed
credit-card-fee vocabulary addition that was still uncommitted in that working tree. It does not
read the external repository at runtime, so later process edits cannot silently change a compiled
KnowledgePack.

## Evidence and work-product boundary

The source tree and analysis tree remain distinct:

| Folder or artifact | Source role | KnowledgePack treatment |
|---|---|---|
| Broker `01 OM` through `08 Market` | `broker_source` | Original evidence and citations |
| `JMI Analysis/00 Extraction CSVs` | `jmi_extraction` | Exact or canonical structured assertions |
| `01 BOE` and `06 Full Model` | `jmi_model` | Modeled values; never relabeled as direct facts |
| `04 Flags & Verification` | `jmi_verification` | Contradictions, gaps, tie-outs, and review evidence |
| Business plan, IC memo, and thesis | `jmi_narrative` | Interpretive conclusions and prepared talking points |

The current executable importer promotes P&L and STAR extraction CSVs. The path classifier already
labels common CoStar exports, BOEs, PIP matrices, mix lists, flags, tie-outs, business plans, full
models, IC memos, and the central-question document for later adapters.

The full methodology repository is not inserted into a live deal pack. It is a build-time mapping
specification. Each property receives an isolated KnowledgePack so examples or another deal's facts
cannot leak into a live answer.

## Filename policy

Both documented P&L aliases are accepted:

- `PL_{period}.csv`
- `{Short}_PL_{period}.csv`

Filename inference is a convenience, not the authority. `--period` wins when supplied. Pack
preparation should eventually record period and status in an explicit import manifest rather than
depending on a filename.

Canonical reporting-period labels are:

- `YYYY`
- `YYYY-MM`
- `TTM:YYYY-MM`
- `YTD:YYYY-MM`

Status is separately typed as `actual`, `budget`, or `forecast`. This prevents a calendar label
from disguising whether a value was observed or projected.

## P&L crosswalk

The importer promotes these controlled `(section, metric)` pairs. All other rows remain retrievable
evidence and produce an `unmapped_metric` warning instead of being guessed.

| Extraction key | KnowledgePack predicate | Normalized unit |
|---|---|---|
| `stats.rooms_available` | `hospitality.available_room_nights` | `room_night` |
| `stats.rooms_sold` | `hospitality.rooms_sold` | `room_night` |
| `stats.occupancy` | `hospitality.occupancy` | `ratio` |
| `stats.adr` | `hospitality.adr` | `USD_per_sold_room` |
| `stats.revpar` | `hospitality.revpar` | `USD_per_available_room` |
| `revenue.rooms` | `hospitality.room_revenue` | `USD` |
| `revenue.food` / `beverage` | separate food and beverage predicates | `USD` |
| `revenue.food_beverage` | `hospitality.food_beverage_revenue` | `USD` |
| `revenue.other_operated` | `hospitality.other_revenue` | `USD` |
| `revenue.misc_income` | `hospitality.miscellaneous_income` | `USD` |
| `revenue.total_revenue` | `hospitality.total_revenue` | `USD` |
| `departmental_expense.total_dept_expense` | `hospitality.departmental_expense` | `USD` |
| `undistributed_expense.total_undistributed` | `hospitality.undistributed_expense` | `USD` |
| `fixed_charges.total_fixed*` | `hospitality.fixed_charges` | `USD` |
| `ebitda.gop` / `ebitda` / `noi` | GOP / EBITDA / NOI predicates | `USD` |

`rooms_available` means available room nights for the stated period. It is never treated as the
physical key count. Percentage-point inputs such as `68.49` retain the exact number with scale
`0.01`; a source value already stored as `0.6849` keeps scale `1`.

Detailed lines such as A&G, credit-card fees, taxes, insurance, resort fees, and parking are
retained but are not yet promoted unless a registered predicate exists. This is deliberate:
preserving evidence with a visible warning is safer than collapsing distinct economics into a
generic “other” fact.

## STAR crosswalk and protected context

Each STAR row can produce three assertions:

1. subject performance with `benchmark=subject` and `comparison_basis=direct_asset`;
2. comparison performance with either `comp_set/star_compset` or `market/market_proxy`; and
3. MPI, ARI, or RGI as a ratio with the same comparison basis.

`hospitality@0.2.0` protects `status`, `value_stage`, `benchmark`, and `comparison_basis` during
deterministic calculations. A market proxy cannot be validated as a STAR comp set, and room
performance must use `scope=rooms`.

## Provenance

Leading extraction comments are preserved as source passages and parsed into the import result:

```text
# source filename: ...
# page/tab: ...
# extractor: ...
# date: ...
```

Every promoted assertion has one `supports` evidence link to its exact CSV row. Source and passage
IDs are derived from content hashes, so import time does not change lineage.

## Command

From `OpenOats/`:

```bash
swift run knowledge-pack import-underwriting-csv \
  ../fixtures/hospitality-underwriting/Synthetic_PL_2020.csv \
  --relative-path "Deal/JMI Analysis/00 Extraction CSVs/Synthetic_PL_2020.csv" \
  --asset-id synthetic-hotel \
  --output ../tmp/hospitality-import.json
```

Use `--period` for labels that cannot be inferred safely and `--status` when the filename does not
correctly communicate actual, budget, or forecast.

## Open-source and confidentiality boundary

The repository ships schemas, deterministic adapters, and synthetic fixtures. It must not ship
licensed CoStar or STR exports, confidential deal-room documents, or derived data that cannot be
redistributed. A real-deal acceptance pack must be private or fully redacted.

## Current limits

- The first adapter promotes extraction CSVs, not arbitrary broker P&L layouts.
- Detailed USALI line items remain evidence until their predicates and calculation policies are
  registered.
- The adapter does not resolve conflicting sources yet; that belongs to the contradiction-study
  stage.
- It produces source, passage, assertion, and evidence records, but not reviewed response cards.
  Prepared questions and presenter cards are the next preparation milestone.
