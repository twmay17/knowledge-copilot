# Verification Record — August 14, 2026

## Environment

- macOS 26.3.1 (25D771280a), Apple Silicon
- Xcode 26.6 (17F113)
- Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`)
- Apple clang 21.0.0 (`clang-2100.1.1.101`)
- Developer directory: `/Applications/Xcode.app/Contents/Developer`

## Passing product-path checks

The following commands pass from `OpenOats/`:

```bash
swift build
swift build -c release
swift test --filter KnowledgePackLoaderTests
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift run knowledge-pack inspect ../fixtures/knowledge-packs/minimal-hospitality
```

The focused test run executes six tests with zero failures. It covers:

- a structurally valid pack;
- calculated-card derivation requirements;
- evidence ownership;
- fail-closed unknown DomainProfile behavior;
- fail-closed unregistered hospitality predicates;
- app-level loading and summary of the on-disk synthetic fixture.

The CLI validates the fixture as one source, one passage, three assertions, and one reviewed
response card. The expected 2020 RevPAR is $89.50, derived from $3,266,750 room revenue divided by
36,500 available room nights.

Strict Swift-format lint passes for all newly added KnowledgePack, DomainProfile, app-store, CLI,
and focused-test files. `git diff --check` also passes.

## Initial inherited-suite baseline (before KC-4 additions)

`swift test` compiles and executes the complete upstream suite under full Xcode:

- 706 tests executed;
- 702 passed;
- 4 assertions failed;
- all six KnowledgePack/DomainProfile/app-load tests passed.

Observed baseline failures:

1. `AppCoordinatorIntegrationTests.testUserStoppedFinalizesSessionAndRefreshesHistory` timed out
   waiting for a finalized session.
2. `MeetingDetectorTests.testMicAloneDoesNotTriggerDetection` failed two assertions while the real
   Microsoft Teams process was running.
3. `MeetingDetectorTests.testQueryCurrentStateIncludesCamera` detected the running Microsoft Teams
   app where the test expected no meeting app.

These failures are outside the newly added product path and are retained as baseline work. The
detector tests should inject process state or run in a controlled environment; the finalization
test should use deterministic synchronization rather than a timing assumption.

## Remote CI status

The repository now has the authorized `origin` at `twmay17/knowledge-copilot`, and the KnowledgePack
foundation was merged through pull request #1. Work described below remains local on
`feat/teams-audio-verification` until publication is separately authorized.

## KC-4 Teams audio verification implementation

The no-admin audio-capture gate now has deterministic instrumentation and a documented operator
protocol:

- microphone and system audio remain separate retained CAF stems;
- each capture path records frame-to-wall-clock timing anchors every five seconds and at the final
  capture snapshot;
- `audio-capture-verify` fails closed on a missing track, insufficient duration or coverage, an
  inaudible track, an unrecovered callback gap, or missing human attestations;
- the recording-consent prompt and dedicated `Live` status have stable accessibility identifiers;
  and
- the [Teams verification runbook](teams-audio-verification.md) requires a consented 31-minute run
  and excludes raw audio and private meeting data from public evidence.

Passing local checks:

```bash
swift test --filter AudioCaptureVerificationTests
swift test --filter AudioRecorderTests
swift test --skip MeetingDetectorTests
swift build -c release
swift run audio-capture-verify --help
```

Results:

- 5 audio-verifier tests passed;
- 8 recorder tests passed;
- 703 package tests outside the environment-sensitive meeting detector passed;
- the release build and verifier CLI build passed; and
- strict Swift-format lint passed for the three newly added verifier/CLI/test files, while
  `git diff --check` passed for the complete change set.

The installed Teams client exposes **Settings → Devices → Make a test call** without administrator
access. The local consent flow was exercised directly: the agreement button remained disabled
until acknowledgement, and accepting it revealed an accessibility-visible `Live 0:00` indicator.

## Real Microsoft Teams Echo smoke test

A consented Teams **Make a test call** was completed with the installed desktop client and a
locally built, ad-hoc-signed OpenOats app. The test required no Microsoft 365 administrator,
Microsoft Graph, Entra application, bot, or meeting-policy change. The operator explicitly approved
the microphone transmission to Microsoft and the macOS **System Audio Recording Only** permission
for OpenOats.

Observed product-path results:

- OpenOats transcribed the MacBook Air microphone as `You` and the Teams Echo prompt/playback as
  `Them` while the call was active;
- final local re-transcription completed and increased the saved transcript from 13 to 17
  utterances;
- `audio/mic.caf` retained 7,440,000 mono frames (29,764,096 bytes), with a `0.61082` peak;
- `audio/sys.caf` retained 5,997,568 mono frames (23,994,368 bytes), with a `0.81934` peak;
- microphone timing anchors reported no unrecovered callback gap over `1.000s`; and
- system timing anchors reported no unrecovered callback gap over `0.128s` after Teams media began.

The strict short-run report intentionally records **FAIL**, not PASS: OpenOats was started about 30
seconds before the Echo call produced system media, so the system stem covered `80.57%` of the
155-second OpenOats session rather than the required `98%`. The microphone covered `98.04%`. This
run proves real two-stem capture, speaker separation, retention, and batch re-transcription, but it
does not certify full-session coverage.

The test also exposed a session-integrity defect: batch re-transcription replaced the recording
start/end timestamps with the first/last spoken-word timestamps. The repository now preserves the
original capture window during live finalization and batch transcript replacement. Two regression
tests cover a quiet opening and a batch overwrite with a shorter spoken interval. The smoke
session's metadata was restored to the observed `00:26:45Z`–`00:29:20Z` capture window before the
strict report was regenerated.

The final KC-4 acceptance gate remains open. A follow-up must keep an already-active, consented
Teams media session running for at least 31 minutes and retain a strict passing JSON report. Raw
audio, transcripts, tenant details, and unredacted screenshots remain local and are not committed.

The macOS UI suite initially executed 11 tests: the 10 inherited smoke tests passed, and the new
consent test exposed an accessibility-container identifier collision that has since been fixed.
Subsequent automated reruns were blocked before app code by a local Xcode/LaunchServices test-host
startup hang. Direct launch and accessibility inspection verified the corrected product flow; the
automated UI rerun remains a tooling follow-up rather than accepted evidence for the 30-minute gate.

## KC-5 synthetic hospitality reference corpus

The public fixture now covers the first-proof hotel questions without using proprietary material:

- three fictional, hash-verified sources: an operating statement, room-inventory schedule, and
  deliberately inconsistent investment memo;
- 18 typed assertions and six deterministic calculations covering available room nights,
  occupancy, ADR, RevPAR, total revenue, and gross operating profit;
- nine anticipated question families and nine reviewed response cards;
- direct, calculated, contested, and `not_found_in_corpus` evidence behavior; and
- seven machine-readable golden cases with expected card IDs, evidence states, and answer
  fragments.

The expanded fixture passes `knowledge-pack validate` with zero loader errors and
`knowledge-pack inspect` renders all nine expected cards. `KnowledgePackLoaderTests` passes 8 of 8,
including source-hash verification, golden-case mapping, unknown-profile rejection, and unit
mismatch rejection. Strict Swift-format lint passes for the changed profile and test files, JSON
and JSONL parsing passes, and `git diff --check` passes.

A broader package rerun was stopped after an inherited integration path blocked inside
`AVAudioEngine.start` while the fresh ad-hoc app identity awaited macOS microphone authorization.
The process stack showed a Core Audio permission/device wait rather than an assertion failure. The
previous 703-test non-detector pass remains the broad baseline; the changed KC-5 code is covered by
the focused passing suite above.

## KC-7 partial-speech question detection

The live path now converts ordered, revisable transcript text into domain-neutral
`QuestionCandidateEvent` values:

- a matching partial emits a provisional candidate before the complete question arrives;
- a compatible follow-up promotes the same candidate ID to stable;
- an equivalent final revision emits no duplicate, including when ASR changes `rev par` to
  `RevPAR`;
- a question-family correction cancels the stale candidate before creating its replacement;
- a material period correction cancels and restarts the candidate even within the same family;
- clearing a partial cancels speculative work, and out-of-order revisions are ignored; and
- profile vocabulary resolves aliases to opaque term IDs without adding hospitality types to the
  core event model.

`KnowledgePackStore` configures the detector from the selected pack and registered profiles,
retains active candidates per stream, and exposes the event boundary that the retrieval/card
milestone will consume. Detection itself is deterministic and makes no model or network call.

Passing local checks from `OpenOats/`:

```bash
swift test --filter QuestionCandidateDetectorTests
swift test --filter 'QuestionCandidateDetectorTests|KnowledgePackLoaderTests'
swift build -c release --product knowledge-pack
xcrun swift-format lint --strict \
  Sources/OpenOats/KnowledgePack/QuestionCandidateDetector.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeDomainProfile.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Tests/OpenOatsTests/QuestionCandidateDetectorTests.swift
git diff --check
```

Results:

- 9 of 9 detector tests passed;
- the combined detector and loader run passed 17 of 17 tests;
- the release `knowledge-pack` product built successfully;
- all four changed Swift files passed strict format lint; and
- `git diff --check` passed.

The release compiler continues to report pre-existing warnings in audio capture, batch cleanup,
suggestion, and streaming-transcriber files; KC-7 adds no new compiler warning.

## KC-8 first sourced presenter card

Stable question candidates now resolve directly to a reviewed KnowledgePack response card without
using a model or network call. The first proof maps the stable 2020 RevPAR candidate to
`card-revpar-2020` and displays the $89.50 calculated answer in the private presenter overlay.

Trust and interaction behavior:

- provisional speech does not surface a factual answer;
- period and term bindings must agree with the card's assertions;
- unreviewed, ambiguous, incomplete, or unavailable evidence fails closed;
- the answer appears before its evidence state and calculation details;
- workbook evidence shows its exact sheet/cell/section locator;
- each evidence row is one button that opens the verified local source file; and
- correction, cancellation, session stop, or KnowledgePack replacement removes the stale card.

The remote transcript bridge consumes both revisable `volatileThemText` and finalized remote
utterances. The trusted card is available in the default classic overlay and the alternate Sidecast
panel. Accessibility identifiers cover the card, answer, evidence state, calculation, and each
evidence button.

Passing local checks from `OpenOats/`:

```bash
swift test --filter KnowledgeAnswerCardResolverTests
swift test --filter \
  'KnowledgeAnswerCardResolverTests|QuestionCandidateDetectorTests|KnowledgePackLoaderTests'
swift build -c release --product OpenOats
xcrun swift-format lint --strict \
  Sources/OpenOats/KnowledgePack/QuestionCandidateDetector.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeAnswerCardResolver.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeDomainProfile.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Sources/OpenOats/Views/KnowledgeAnswerCardView.swift \
  Tests/OpenOatsTests/QuestionCandidateDetectorTests.swift \
  Tests/OpenOatsTests/KnowledgeAnswerCardResolverTests.swift
git diff --check
```

Results:

- 7 of 7 resolver/store tests passed;
- the combined first-proof run passed 24 of 24 tests;
- the release `OpenOats` app product built successfully;
- all new and KC-specific core, card-view, and test files passed strict format lint; and
- `git diff --check` passed.

The release build reports the same inherited warnings listed for KC-7 and no new KC-8 compiler
warning.

## KC-9 deterministic first working proof

The KnowledgePack CLI now replays timestamped transcript revisions from a clean detector/resolver
state and writes a machine-readable PASS/FAIL report. The report combines the simulated revision
timestamp with measured local processing time, rather than reporting the revision timestamp alone.

The checked-in synthetic RevPAR proof passed:

- the provisional candidate appeared on `What was the rev par`;
- the same candidate became stable on the 420 ms partial;
- the calculated $89.50 card was ready at 420.776 ms;
- the response deadline was 1,000 ms, leaving 579.224 ms of headroom;
- final speech arrived at 900 ms, 479.224 ms after the answer was ready;
- median processing latency was 0.605 ms;
- p95 and maximum processing latency were 0.776 ms against a 50 ms budget;
- all eight proof checks passed; and
- both expected citations existed inside the selected synthetic KnowledgePack with exact locators.

The public-safe evidence is recorded in
[the human proof summary](evidence/kc9-first-proof-2026-08-14.md) and
[machine-readable JSON](evidence/kc9-first-proof-2026-08-14.json). The report contains pack-relative
paths only; it contains no real audio, real meeting transcript, tenant detail, absolute local path,
or proprietary figure.

Passing local checks:

```bash
swift test --filter KnowledgeProofReplayTests
swift run knowledge-pack replay \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../fixtures/knowledge-packs/minimal-hospitality/evaluation/live-proof-revpar.json \
  --output ../docs/evidence/kc9-first-proof-2026-08-14.json
```

Results:

- 4 of 4 replay tests passed, including clean-state repeatability and intentional expected-card
  mismatch failure;
- the combined loader, detector, resolver, and replay run passed 28 of 28 tests;
- the replay command exited successfully with `PASS`; and
- the output report retained all per-revision timing, event, card, and citation checks;
- the release `knowledge-pack` product built successfully;
- all KC-specific Swift files passed strict format lint; and
- both replay-spec and evidence-report JSON files parsed successfully.

This proof measures the deterministic in-process path after transcript revisions arrive. It does
not include audio capture or ASR latency; those remain separate verification gates.

## KC-10 PDF and DOCX evidence ingestion

The next milestone now ingests genuine PDF and DOCX files locally into generic KnowledgePack source
and passage records:

- PDFs retain one-based page and document-block locators;
- DOCX narrative retains nearest-heading section paths;
- native DOCX tables retain one-based table and document-block locators;
- every passage records an exact content SHA-256 hash used in its stable ID and later validation;
- every passage can resolve back to the exact, containment-checked, hash-verified source file; and
- missing or suspicious PDF text layers produce visible review warnings instead of invented text.

The public-safe fixtures were generated reproducibly and visually inspected after rendering. The
PDF has two clean pages. The DOCX has one clean page, and its table passed exact Word geometry checks
for `tblW`, `tblInd`, `tblGrid`, and every `tcW`.

Passing local checks so far:

```bash
swift test --filter 'KnowledgeDocumentIngestorTests|KnowledgePackLoaderTests'
swift run knowledge-pack ingest-document \
  ../fixtures/document-ingestion/sample-evidence.pdf \
  --relative-path sample-evidence.pdf
swift run knowledge-pack ingest-document \
  ../fixtures/document-ingestion/sample-evidence.docx \
  --relative-path sample-evidence.docx
```

Results:

- 5 of 5 ingestion tests passed;
- the combined ingestion and loader run passed 13 of 13 tests;
- the PDF produced two page passages and visibly flagged the deliberately damaged second page;
- the DOCX produced six passages, including one table passage with the expected RevPAR row; and
- source containment, file hashes, passage hashes, deterministic IDs, and unsafe-path rejection all
  passed.

See [the ingestion contract](document-ingestion.md) and
[the public-safe KC-10 evidence summary](evidence/kc10-document-ingestion-2026-08-14.md).

## KC-11 XLSX and CSV evidence ingestion

The next corpus milestone now ingests genuine XLSX and CSV files locally into generic
KnowledgePack source and passage records:

- XLSX rows retain worksheet, exact A1 cell range, one-based row, first-row headers, cached values,
  formulas, and number formats;
- CSV logical records retain stable A1 locators through quoted commas, escaped quotes, CRLF input,
  and embedded newlines;
- conventional period and unit columns become generic row context without adding hospitality
  fields to the core model;
- source IDs and passage IDs remain stable across import times;
- every passage records an exact content SHA-256 hash used in validation and source resolution;
- every passage can resolve back to the exact, containment-checked, hash-verified source file; and
- formula cells without cached results remain formulas with visible warnings rather than invented
  values.

The public-safe fixtures were generated with `@oai/artifact-tool`. Both workbook worksheets were
rendered and visually inspected without clipping. The XLSX Open XML contains a cached `<v>` result
for every local and cross-sheet formula.

Passing local checks:

```bash
swift test --filter KnowledgeSpreadsheetIngestorTests
swift test --filter \
  'KnowledgeSpreadsheetIngestorTests|KnowledgeDocumentIngestorTests|KnowledgePackLoaderTests'
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
```

Results:

- 8 of 8 spreadsheet-ingestion tests passed;
- the combined spreadsheet, document, and loader run passed 21 of 21 tests;
- the XLSX produced 9 passages across 2 worksheets with formula and cached-value lineage;
- the CSV produced 4 logical passages with stable locators through all quoted-field edge cases; and
- source containment, file hashes, passage hashes, deterministic IDs, pack validation, and
  unsafe-path rejection all passed;
- both release products built successfully;
- all five changed Swift files passed strict Swift-format lint; and
- two consecutive fixture builds produced identical XLSX and CSV SHA-256 hashes.

See [the spreadsheet ingestion contract](spreadsheet-ingestion.md) and
[the public-safe KC-11 evidence summary](evidence/kc11-spreadsheet-ingestion-2026-08-14.md).
