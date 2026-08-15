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
