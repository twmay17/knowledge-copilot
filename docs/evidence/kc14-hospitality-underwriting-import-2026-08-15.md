# KC-14 Hospitality Underwriting Import Evidence — August 15, 2026

## Acceptance slice

KC-14 pins the hospitality underwriting mapping in the repository and converts synthetic JMI-style
P&L and STAR CSVs into generic KnowledgePack records using `hospitality@0.2.0`.

Verified behavior:

- leading provenance comments survive generic CSV ingestion with physical row locators;
- both documented P&L filename shapes can infer a calendar period;
- mapped P&L lines become typed stated assertions with exact evidence links;
- unmapped controlled rows remain passages and emit visible warnings;
- percentage-point occupancy and index values retain exact source numbers plus scale `0.01`;
- STAR subject, true comp-set, and market-proxy values remain distinct;
- invalid reporting periods and comparison-basis pairs fail closed; and
- the existing `hospitality@0.1.0` synthetic pack remains compatible.

## Reproducible commands

From `OpenOats/`:

```bash
swift test --filter \
  'HospitalityUnderwritingImporterTests|KnowledgeSpreadsheetIngestorTests'

swift run knowledge-pack import-underwriting-csv \
  ../fixtures/hospitality-underwriting/Synthetic_PL_2020.csv \
  --relative-path "Deal/JMI Analysis/00 Extraction CSVs/Synthetic_PL_2020.csv" \
  --asset-id synthetic-hotel \
  --output ../outputs/kc14-synthetic-pl-import.json
```

The focused suite passed 14 of 14 tests. The CLI produced 16 supported assertions and one visible
warning for the intentionally unmapped A&G detail line.

The broader gate also passed:

- 759 non-environmental tests passed with zero failures when the inherited
  `MeetingDetectorTests` suite was excluded;
- the unfiltered 770-test run had only the 3 known environment-sensitive failures caused by
  Microsoft Teams being open while tests asserted that no meeting app was running;
- the published `hospitality@0.1.0` pack still validated with 3 sources, 3 passages, 18 assertions,
  and 9 cards;
- release builds succeeded for both `knowledge-pack` and `OpenOats`;
- all six changed Swift files passed strict Swift-format lint; and
- the diff passed whitespace validation.

## Fixture safety

Both underwriting fixtures are synthetic and contain no CoStar, STR, operator, broker, or private
deal-room content. Licensed and confidential sources remain outside the public repository.
