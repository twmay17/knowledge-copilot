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

Passing local checks:

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

## KC-12 generic assertion and evidence model

The proposition layer now fails closed on unsupported or contextually unsafe facts without adding
a financial ontology to the core:

- all five value types require exactly one valid payload;
- numeric values require finite numbers, explicit normalized units, and positive finite scales;
- `period`, `version`, and `scope` are normalized generic context dimensions;
- calculations preserve every context dimension declared by their output;
- stated, inferred, and interpretive assertions require source evidence;
- calculated assertions require exactly one recorded derivation;
- evidence ownership is checked in both directions; and
- Domain Profiles can protect additional dimensions, with hospitality protecting `status` and
  requiring room scope for room predicates.

Passing local checks:

```bash
swift test --filter KnowledgeAssertionEvidenceModelTests
swift test --filter \
  'KnowledgeAssertionEvidenceModelTests|KnowledgePackLoaderTests|KnowledgeAnswerCardResolverTests|KnowledgeProofReplayTests|KnowledgeSpreadsheetIngestorTests|KnowledgeDocumentIngestorTests|QuestionCandidateDetectorTests'
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <six changed Swift files>
git diff --check
```

Results:

- 7 of 7 KC-12 acceptance tests passed;
- the combined KnowledgePack regression run passed 48 of 48 tests;
- the published synthetic hospitality pack still loads with 18 assertions and 6 calculations; and
- changing an actual calculation input to budget or removing required room scope fails closed;
- both release products built successfully; and
- all six changed Swift files passed strict Swift-format lint, the JSONL fixture parsed, and the
  diff passed whitespace validation.

See [the assertion/evidence contract](assertion-evidence-model.md) and
[the public-safe KC-12 evidence summary](evidence/kc12-assertion-evidence-model-2026-08-15.md).

## KC-13 domain-profile and calculation registry

The extension layer now makes domain vocabulary and deterministic arithmetic removable and
auditable:

- profile schemas register typed qualifiers, vocabulary, aliases, units, and protected context;
- calculation definitions register ordered inputs, input/output unit policies, executable
  deterministic operations, and period rules;
- stored calculated values are checked against scaled source inputs;
- invalid units, mixed periods, zero denominators, non-finite results, and altered outputs fail
  closed;
- ordered-period growth validates current and prior input lineage;
- answer summaries and the overlay expose resolved operands, results, and source locators; and
- a generic pack loads with an empty registry and no hospitality package installed.

Passing local checks:

```bash
swift test --filter KnowledgeDomainProfileRegistryTests
swift test --filter \
  'KnowledgeDomainProfileRegistryTests|KnowledgePackLoaderTests|KnowledgeAnswerCardResolverTests|KnowledgeAssertionEvidenceModelTests|QuestionCandidateDetectorTests|KnowledgeProofReplayTests'
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <seven changed Swift files>
git diff --check
```

Results:

- 7 of 7 KC-13 acceptance tests passed;
- the combined domain registry and live KnowledgePack regression run passed 43 of 43 tests;
- the synthetic hospitality fixture validated with 3 sources, 3 passages, 18 assertions, and 9
  answer cards;
- both release products built successfully; and
- all seven changed Swift files passed strict Swift-format lint and the diff passed whitespace
  validation.

See [the profile and calculation registry contract](domain-profile-registry.md) and
[the public-safe KC-13 evidence summary](evidence/kc13-domain-profile-registry-2026-08-15.md).

## KC-14 hospitality underwriting import profile

The preparation boundary now understands the verified extraction conventions used by the
hospitality underwriting workflow without adding them to the generic core:

- `hospitality@0.2.0` supports calendar, monthly, TTM, and YTD reporting-period labels;
- status, value stage, subject/comp/market benchmark, and comparison basis remain typed and
  calculation-protected;
- source paths receive explicit broker, extraction, model, verification, or narrative roles;
- JMI-style P&L and STAR CSV rows become stated assertions with exact row evidence;
- leading provenance comments survive generic CSV ingestion and remain content-hashed passages;
- unmapped line items stay retrievable and generate warnings rather than guessed assertions; and
- `hospitality@0.1.0` remains available for the published synthetic reference pack.

Initial focused check:

```bash
swift test --filter \
  'HospitalityUnderwritingImporterTests|KnowledgeSpreadsheetIngestorTests'
```

Results:

- 5 of 5 underwriting-import acceptance tests passed;
- 9 of 9 generic spreadsheet-ingestion tests passed; and
- 759 non-environmental tests passed with zero failures;
- the full unfiltered run executed 770 tests and reproduced only the 3 inherited
  environment-sensitive meeting-detector failures while Microsoft Teams was open;
- the existing `hospitality@0.1.0` pack still validated;
- both release products built successfully;
- all six changed Swift files passed strict Swift-format lint and the diff passed whitespace
  validation; and
- both synthetic underwriting fixtures contain no licensed or confidential deal data.

See [the import contract](hospitality-underwriting-import-profile.md) and
[the public-safe KC-14 evidence summary](evidence/kc14-hospitality-underwriting-import-2026-08-15.md).

## KC-15 closed-corpus Study Bundle

The preparation lane can now package a validated corpus for deeper frontier-model study without
making the live application depend on that model or provider:

- the export is domain-neutral and works without a Domain Profile;
- its canonical full-content hash produces a deterministic bundle identity;
- source paths remain pack-relative and every used citation carries an exact excerpt and locator;
- registered calculations, existing question families, and reviewed cards are included;
- generated or rejected cards are excluded;
- broken evidence and reviewed-card references fail closed; and
- the embedded policy requires citations, disables web authority, treats document instructions as
  evidence data, and abstains when the corpus is missing an answer.

The first subscription-assisted workflow is intentionally user operated: export the JSON, upload it
to an approved ChatGPT account, and use the repository's closed-corpus study prompt. It neither
automates a ChatGPT session nor assumes that a subscription supplies application API access.

Passing local checks:

```bash
swift test --filter KnowledgeStudyBundleTests
swift run knowledge-pack export-study-bundle \
  ../fixtures/knowledge-packs/minimal-hospitality \
  --output ../outputs/kc15-study-bundle.json
swift test --skip MeetingDetectorTests
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <three changed Swift files>
git diff --check
```

Results:

- 9 of 9 focused acceptance tests passed, including a generic product-pitch pack;
- two independent CLI exports were byte-for-byte identical;
- the synthetic bundle contains 3 sources, 3 cited passages, 18 assertions, 6 calculations, 9
  question families, and 9 reviewed cards;
- all 768 non-environmental tests passed;
- both release products built successfully; and
- strict Swift formatting, policy/citation closure, and whitespace checks passed.

See [the Study Bundle boundary](study-bundle.md),
[the reusable preparation prompt](study-bundle-chatgpt-prompt.md), and
[the public-safe KC-15 evidence summary](evidence/kc15-study-bundle-2026-08-15.md).

## KC-16 study-analysis and human-review gate

Frontier-model preparation results now return through an explicit untrusted-proposal contract:

- every analysis is bound to one exact Study Bundle, pack, and full-content hash;
- public JSON Schemas define the model result and human decision files;
- model output cannot set review status and every queued card remains `generated`;
- references, evidence-state requirements, calculations, and citation closure fail closed;
- pending queues expose exact assertions, excerpts, locators, and calculations for review;
- stale and tampered queues are rejected;
- a named, timestamped reviewer must approve or reject every question and card proposal;
- only approved cards become `reviewed` after the complete merged pack validates; and
- the command emits an auditable import artifact without changing the pack.

Passing local checks:

```bash
swift test --filter 'KnowledgeStudyReviewTests|KnowledgeStudyBundleTests'
swift run knowledge-pack prepare-study-review <pack> <analysis> --output <queue>
swift run knowledge-pack approve-study-review <pack> <queue> <decisions> --output <import>
swift test --skip MeetingDetectorTests
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <four changed Swift files>
git diff --check
```

Results:

- 12 of 12 KC-16 acceptance tests and all 21 preparation-boundary tests passed;
- both CLI artifacts were deterministic across repeated runs;
- the pending queue remained generated and the approved import contained only the two explicitly
  approved additions;
- all 780 non-environmental tests passed;
- both release products built successfully; and
- JSON syntax, strict Swift formatting, and whitespace checks passed.

See [the analysis/review contract](study-analysis-review.md), the
[public model-output schema](../schemas/study-analysis-v1.schema.json), the
[public human-decision schema](../schemas/study-review-decisions-v1.schema.json), and the
[public-safe KC-16 evidence summary](evidence/kc16-study-analysis-review-2026-08-15.md).

## KC-17 reviewed-import application

The approved artifact now has a deliberate, fail-closed path into a writable KnowledgePack:

- planning validates the artifact and exact before/after hashes without mutation;
- only IDs with explicit `approve` decisions may appear in the import;
- every imported response card must still be `reviewed`;
- the pack is reloaded under an exclusive advisory lock immediately before staging;
- existing JSONL bytes are preserved and only approved records are appended;
- a recovery journal and original-file backups protect the two-file update;
- an ordinary mid-transaction failure rolls back and verifies the original full-corpus hash;
- the next apply recovers a simulated interrupted mixed state before retrying;
- a repeated import is idempotent; and
- each application returns a machine-readable audit receipt.

Focused checks:

```bash
swift test --filter KnowledgeStudyImportApplierTests
swift run knowledge-pack plan-study-import <pack> <approved-import> --output <plan>
swift run knowledge-pack apply-study-import <pack-copy> <approved-import> --output <receipt>
swift run knowledge-pack apply-study-import <pack-copy> <approved-import> --output <second-receipt>
swift run knowledge-pack validate <pack-copy>
```

Passing local checks:

```bash
swift test --filter \
  'KnowledgeStudyImportApplierTests|KnowledgeStudyReviewTests|KnowledgeStudyBundleTests'
swift test --skip MeetingDetectorTests
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict <four changed Swift files>
jq empty schemas/study-import-plan-v1.schema.json \
  schemas/study-import-receipt-v1.schema.json
git diff --check
```

Results:

- 10 of 10 KC-17 application tests and all 31 preparation/review/application tests passed;
- the CLI preview reported `ready` without changing the pack;
- the first CLI application reported `applied` with the exact approved result hash;
- the second application reported `already_applied` without duplicating records;
- an unsafe in-pack plan-output path was rejected before any file was written;
- the resulting synthetic pack passed full loader and Domain Profile validation with 10 reviewed
  response cards;
- all 790 non-environmental tests passed;
- both release products built successfully; and
- public schemas, strict Swift formatting, and whitespace checks passed.

See [the application contract](study-import-application.md) and the
[public-safe KC-17 evidence summary](evidence/kc17-study-import-application-2026-08-15.md).

## KC-18 native Knowledge Review workspace

The macOS app now exposes the final human gate without weakening the tested CLI contracts:

- **Review** in the main window and **Command-Shift-R** open a dedicated Knowledge Review window;
- a queue is shown only after the active pack is reloaded, its Study Bundle is rebuilt, and the
  reconstructed queue exactly equals the selected file;
- question families and response cards require one explicit approve or reject decision each;
- proposed answers are rendered beside their assertions, exact cited passages, source locators,
  caveats, and registered calculations;
- contradictions and corpus gaps are visible as non-importable reviewer context;
- a normalized named reviewer is mandatory and optional notes are bounded and normalized;
- editing a reviewer, decision, or note invalidates the prepared artifact and plan;
- Preview invokes the existing human-review gate and read-only import planner against a fresh pack
  load;
- Apply is separately confirmed and invokes the existing locked, recoverable transactional applier;
  and
- a successful application reloads the active KnowledgePack for live use and displays the receipt
  result and hash.

Passing local checks:

```bash
swift test --filter KnowledgeStudyReviewWorkspaceModelTests
swift test --filter \
  'KnowledgeStudyReviewWorkspaceModelTests|KnowledgeStudyImportApplierTests|KnowledgeStudyReviewTests|KnowledgeStudyBundleTests'
swift test --skip MeetingDetectorTests
swift build -c release --product OpenOats
xcrun swift-format lint --strict \
  Sources/OpenOats/App/KnowledgeStudyReviewWorkspaceModel.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Sources/OpenOats/Views/KnowledgeStudyReviewWorkspaceView.swift \
  Tests/OpenOatsTests/KnowledgeStudyReviewWorkspaceModelTests.swift
git diff --check
```

Results:

- 7 of 7 focused workspace-model tests passed;
- all 38 KC-15 through KC-18 preparation, review, application, and workspace tests passed;
- all 797 non-environmental package tests passed;
- the production OpenOats product and a local unsigned `.app` QA bundle built successfully;
- strict Swift formatting passed for the new workspace sources, its test, and the touched
  two-space store source;
- the built app's main-window Review control and native no-active-pack workspace were inspected
  through macOS accessibility state and a rendered screenshot; and
- whitespace checks passed.

See [the workspace contract](knowledge-review-workspace.md) and the
[public-safe KC-18 evidence summary](evidence/kc18-knowledge-review-workspace-2026-08-15.md).

## KC-19 hybrid search and corpus invalidation

The validated KnowledgePack path now owns a deterministic hybrid index instead of relying on the
legacy free-form knowledge-base cache:

- every query names the exact pack ID and may require record kinds, source IDs, and qualifiers;
- exact normalized aliases and a local in-memory SQLite FTS5 index provide the no-cost baseline;
- optional vector adapters receive only locally admitted candidates and cannot add unknown records;
- only reviewed response cards are indexed;
- every result carries its pack ID, full-content hash, sources, qualifiers, match channels, and score
  components;
- typed comparison and transitive dependency traversal invalidate affected artifacts when sources,
  passages, evidence, assertions, calculations, question families, cards, or the manifest change;
- identical pack content reuses its index, changed content rebuilds, and another pack always starts
  fresh; and
- `KnowledgePackStore` builds the index with the selected pack and clears both on failure.

Passing local checks:

```bash
swift test --filter KnowledgePackSearchIndexTests
swift test --filter \
  'KnowledgePackSearchIndexTests|KnowledgePackLoaderTests|KnowledgeAnswerCardResolverTests|KnowledgeStudyBundleTests|KnowledgeStudyImportApplierTests|KnowledgeStudyReviewTests|KnowledgeStudyReviewWorkspaceModelTests'
swift test --skip MeetingDetectorTests
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
swift run knowledge-pack search \
  ../fixtures/knowledge-packs/minimal-hospitality \
  'fictional investment memo inconsistent' \
  --kind passage --source source-investment-memo --limit 3
swift format lint --strict \
  Sources/OpenOats/KnowledgePack/KnowledgePackSearchIndex.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Sources/KnowledgePackTool/main.swift \
  Tests/OpenOatsTests/KnowledgePackSearchIndexTests.swift
git diff --check
```

Results:

- 11 of 11 focused search and invalidation tests passed;
- all 65 related retrieval, loader, evidence, preparation, review, import, and workspace tests passed;
- all 808 non-environmental package tests passed;
- both release products built successfully;
- the scoped CLI proof returned only `passage-memo-revpar-2020` from
  `source-investment-memo`, labeled with the active pack ID and content hash;
- strict Swift formatting passed for all new and touched two-space Swift sources; and
- whitespace checks passed.

See [the search and invalidation contract](knowledge-pack-search.md) and the
[public-safe KC-19 evidence summary](evidence/kc19-hybrid-search-invalidation-2026-08-15.md).

## KC-20 evidence outcomes and abstention

Pack-bound assertion retrieval now feeds a deterministic evidence evaluator before a dynamic result
can be treated as a corpus conclusion:

- required entity, period, scope, and version fields can force clarification before retrieval;
- absent matching assertions produce `not_found_in_corpus` without inventing a negative fact;
- conflicting values, incompatible unbound qualifiers, and explicit counter-evidence remain
  contested with every typed assertion intact;
- proposed values are contradicted only when the matching corpus assertions are internally
  consistent;
- interpretive assertions remain labeled and attributed;
- unavailable evidence fails closed and names the unresolved assertion IDs;
- calculated claims can trace source attribution through their registered input assertions; and
- Codable QA output carries the exact pack hash, decision reason, typed claims, evidence relations,
  safe source URLs, locators, and excerpts.

Passing local checks:

```bash
swift test --filter KnowledgeEvidenceOutcomeEvaluatorTests
swift test --filter \
  'KnowledgeEvidenceOutcomeEvaluatorTests|KnowledgePackSearchIndexTests|KnowledgeAssertionEvidenceModelTests|KnowledgePackLoaderTests|KnowledgeAnswerCardResolverTests|KnowledgeStudyBundleTests|KnowledgeStudyReviewTests|KnowledgeStudyImportApplierTests|KnowledgeStudyReviewWorkspaceModelTests'
swift test --skip MeetingDetectorTests
swift build -c release --product OpenOats
swift build -c release --product knowledge-pack
swift format lint --strict \
  Sources/OpenOats/KnowledgePack/KnowledgeEvidenceOutcomeEvaluator.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Tests/OpenOatsTests/KnowledgeEvidenceOutcomeEvaluatorTests.swift
git diff --check
```

Results:

- 10 of 10 focused evidence-outcome tests passed;
- all 82 related retrieval, assertion/evidence, loader, resolution, preparation, review, import, and
  workspace tests passed;
- all 818 non-environmental package tests passed;
- both release products built successfully;
- the release compiler reported only pre-existing warnings in unrelated audio, text-cleaning,
  suggestion, and transcription sources;
- strict Swift formatting passed for the new evaluator, its tests, and the touched store source; and
- whitespace checks passed.

See [the evidence-outcome contract](knowledge-evidence-outcomes.md) and the
[public-safe KC-20 evidence summary](evidence/kc20-evidence-outcomes-2026-08-15.md).
