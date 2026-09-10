# Solo Teams rehearsal: evidence audit and repair plan

## Decision

**Core workflow demonstrated; general meeting readiness not yet approved.**

The final isolated run saved one remote occupancy question, one grounded answer,
and its supporting source. The operator reported correct on-screen behavior and
no duplicate microphone sentence after muting OpenOats's microphone. This is a
successful synthetic, system-audio-only rehearsal, not proof of reliable duplex
conversation, low-latency performance across arbitrary questions, or an endurance pass.

No more operator testing is required until the preparation/measurement fixes below
are ready. Keep the existing custom app; this audit does not repackage it, reset
permissions, install an upstream update, delete audio, or publish session data.

## Evidence and attribution

Six local sessions were inspected read-only. Raw recordings, private session IDs,
absolute source paths, and verbatim incidental speech are excluded from this report.
A separate private evidence index outside the repository maps A–F to session folders
and retains the before/after verifier reports. It is named
`2026-09-10-solo-audit.json` in the operator's Knowledge Copilot Test Reports folder.

The tested custom executable has SHA-256
`b681b38f11f53b71321ea2c8bb47410d4d712b33d1a8945704db67e063de7b67`.
Its base commit is `3063012f20e52088cd83e79f994fde44d818497d`, with uncommitted
remediation changes. That SHA alone is not a tested-source identity. Session C was
observed running the separately installed older copy; do not merge its results into
the custom-build acceptance claims. Both copies displayed version 1.84.3.

### Corrected frame-based measurements

Coverage below uses the CAF-declared 48 kHz rate, not a rate inferred from gaps.
Coverage measures stored frames, **not speech intelligibility**. Timestamp anchors
are currently second-resolution, so subsecond gap estimates are approximate.

| Run | Duration | Mic coverage | System coverage | Interpretation |
| --- | ---: | ---: | ---: | --- |
| A | 73 s | No stem | No stem | Permission-blocked startup; UI presented a session despite no captured audio |
| B | 103 s | 98.93% | 98.96% | Local microphone question and archived 100-room answer; mic path demonstrated |
| C | 361 s | 99.31% | 98.86% | Older installed copy; eventually stopped normally and saved audio; no whiteboard archive |
| D | 351 s | 78.29% | 98.79% | Device-change rehearsal; mic anchors expose a 74-second gap; not a healthy duplex run |
| E | 673 s | 99.94% | 99.94% | Mixed speaker/mute experiments; duplicate live utterances and answer revisions present |
| F | 107 s | 3.64% | 99.36% | Intentional OpenOats mic mute; clean isolated remote question/answer; not a duplex baseline |

All six strict reports remain **FAIL**, as expected: each is shorter than 1,800
seconds and no operator-attestation flags were supplied by the auditor. Runs A, D,
and F additionally fail track gates. The blank attestations mean *not supplied to
the tool*, not an accusation that the operator lacked consent or did not use Teams.
Do not lower thresholds or invent attestations to turn these rehearsals into passes.

### Final isolated answer and citation

- Live transcript: exactly **one `them` utterance**, asking for 2020 occupancy;
  no `you` utterance. The final batch transcript retains one `them` question.
- Whiteboard: exactly **one non-superseded, non-provisional answer**: 72.0%,
  calculated from 26,280 rooms sold / 36,500 available room nights.
- Source: Synthetic Hotel Room Inventory, `Room Inventory · A3:H3 · 2020 actual`.
  The cited excerpt agrees with the actual CSV row; 2019, budget, and 2021 rows
  were not substituted. Arithmetic: 26,280 / 36,500 = 0.72.
- Archive/session/evidence session identities agree. The event is `remote#1`,
  the engine is `local-knowledge-pack`, and the recorded pack is
  `synthetic-hotel-2020-v1`. Current pack validation passes: 3 sources, 18 assertions,
  9 prepared cards. These facts support a local prepared-answer path, not a
  frontier-model or open-ended question-answering claim.
- System stem: 5,103,104 frames at 48 kHz = 106.315 seconds; audible samples exist
  (peak 0.7446). Mic stem: 187,200 frames = 3.9 seconds before the intended mute.
- Answer archive time precedes final live transcript time by 2 seconds. Because
  partial questions can trigger answers and the files use different timestamp
  semantics, **this is not a measured speech-to-answer latency or proof that the
  answer appeared two seconds before the person finished speaking**. Instrument
  capture, ASR partial/final, candidate, accepted answer, and render timestamps first.

### Other observations and limits

- The room-count rehearsal has a custom whiteboard archive linked to its session;
  the earlier uncertainty about which build handled that success is resolved by
  that evidence. The later wrong-copy incident is a separate session.
- A RevPAR rehearsal saved a source-backed $89.50 answer despite the partial ASR
  wording “acid.” That demonstrates resilience for one prepared family only.
- The mixed run includes a provisional **“0.72 ratio”** card for an incomplete
  question. It was superseded; all three archived cards in that run ultimately
  carry superseded flags. Review formatting and lifecycle semantics before treating
  an empty current board or an unlabeled ratio as acceptable product behavior.
- Operator-observed: Word-window sharing excluded the whiteboard, including after
  the stereo rebuild. No received-share screenshot or full-display test was captured
  by this audit. Do not promise general invisibility.
- Operator-observed: speaker muting prevented useful Teams audio in this route;
  restoring speakers and muting OpenOats's mic allowed the isolated test. This is
  configuration-specific, not a universal macOS claim.
- No 2018 unsupported-answer, conflict-resolution, broad negative-question, or
  document-switch isolation live test was completed during the final short run.

## Bugs and ordered repair checklist

### M0 — Trustworthy verification (first)

- [x] **P1: verifier self-normalizes missing audio.** It estimated rate from the same
  frame/time anchors used to measure gaps. Run F's 3.9 seconds of mic audio became
  107 seconds at a fictitious 1,749.53 Hz, producing a false per-track pass.
- [x] Use the file's declared sample rate for verification. A stored rate estimate
  differing by more than 5% fails closed pending independent clock calibration;
  inferred rates must not certify their own completeness. This can conservatively
  reject genuinely mistagged tap data; resolving that requires independent timing,
  not silent normalization. Live ASR and playback correction are unchanged here.
- [x] Regression tests: sparse muted track, uniform loss in every interval, and
  rounded interval timestamps. All three failed before the fix; all pass after it.
- [ ] Add explicit per-track mute/pause/device-change intervals and fractional or
  monotonic capture timestamps. Distinguish intended mute from unexpected dropout
  without allowing a muted run to qualify as an uninterrupted duplex baseline.

Acceptance: sparse/uniformly missing data cannot pass even with all operator
attestations; a real 31-minute uninterrupted run still must meet the original gates.

### M1 — Reliable startup and an unmistakable app identity

Implementation update: [startup reliability report](2026-09-10-startup-reliability.md).
Code and 1,090 core tests pass; the launch UI runner timed out enabling automation.
The existing working app has not been replaced. The acceptance items below stay
open until the packaged build and operator checks are complete.

- [ ] **P1: false recording state while awaiting permission/startup.**
  `LiveSessionController.publish` sets `isRunning` from lifecycle `.recording` before
  `TranscriptionEngine.start` completes permission/model setup. Add explicit Preparing,
  Awaiting Permission, Capturing, Failed, and Stopping states; do not start a Live timer
  based solely on a session row. Keep a visible cancel/stop action during preparation.
- [ ] **P1: review stop-during-start cancellation.** Verify generation/session identity
  after every awaited permission/model setup step so late completion cannot start
  capture after cancellation. Add delayed-permission and delayed-model tests.
- [ ] **P1: indistinguishable installed and custom apps.** Add visible dev identity,
  executable/build fingerprint, and exact-path launcher; detect competing copies.
  Decide bundle-ID migration explicitly with user-controlled settings transfer;
  do not silently reset permissions or move credentials. Preserve the old app.
- [ ] Attribute updater prompts correctly. The custom source disables the updater;
  the older app was observed running later. The prompt's originating PID was not
  captured, so do not assert a custom-updater regression. Hide misleading disabled
  update controls and test that the dev build cannot replace itself from upstream.

Acceptance: one predictable launch target, no Live status before capture starts,
no post-cancel capture, clear permission guidance without blind rebuild loops.

### M2 — Understandable audio controls and stable device routing

Implementation update: [microphone controls and routing safeguards](2026-09-10-microphone-routing.md).
Labeled controls and initial recovery/callback protections are implemented. Physical
device-switch acceptance, backend-drain bounds, and consumer-time rate correction
remain open; do not mark M2 complete based on policy tests alone.

- [ ] **P2: mic mute is hard to find.** Keep a labeled microphone control visible in
  the main workspace, explain that it affects only OpenOats, and distinguish
  “Microphone muted — system audio active” from a blanket “Muted” state.
- [ ] **P1: device-change recovery.** Reproduce the earbuds switch while capturing;
  run D's 74-second mic gap and observed error make this a reliability blocker.
  Detect missing devices, offer explicit fallback, serialize restarts, and ensure
  old stream callbacks cannot enter a new session. Test unplug/reconnect repeatedly.
- [ ] **P1: consumer-time sample-rate inference.** StreamingTranscriber measures
  received frames against wall time in its ASR consumer loop. Model-processing
  stalls can resemble clock drift; the earlier diagnostic reported 48 kHz becoming
  about 36.5 kHz. Reproduce with injected consumer delays, then base calibration on
  capture timestamps rather than model-consumption timing.

Acceptance: silence, intentional mute, missing device, and slow ASR are distinct;
recovery is bounded and observable; no false resampling correction due to ASR load.

### M3 — Duplex listening and readable evidence

- [ ] **P1: speaker bleed creates duplicate live questions.** Preserve independent
  raw tracks, but suppress confidently matched delayed echoes from the displayed
  transcript and question pipeline. Test real overlapping speech, repeated legitimate
  questions, near matches, different speakers, and changing playback volume. Do not
  simply drop every repeated phrase or enable the currently incompatible AEC option.
- [ ] **P2: provisional answer clarity.** Render percentages as percentages, include
  period/status in early cards, and require disambiguation when evidence differs by
  year or actual/budget. Never publish an unlabeled “0.72 ratio” as ready-to-read copy.
- [ ] **P2: saved-board revision clarity.** Verify that fully superseded archives
  retain a comprehensible history and that revision/withdrawal cannot erase the
  user's only useful answer without explanation.
- [ ] **P2: trustworthy latency telemetry.** Add monotonic stage timestamps and
  distinguish acoustic question end, live-final publication, batch alignment, and
  visible-card rendering. Measure p50/p95 on a repeatable synthetic script.

Acceptance: both local and remote voices can participate with no spurious duplicate
answers, no suppression of genuine interruptions, and readable sourced responses.

### M4 — Next operator rehearsal, then release review

- [ ] Short dry run: local and remote question, citation inspection, unsupported year,
  conflicting source, non-question negative, and repeat Word-window sharing check.
- [ ] Separate controlled device-switch exercise; do not mix it into the baseline.
- [ ] 31-minute uninterrupted duplex baseline with checkpoints at 0/10/20/30 minutes,
  matching devices, consent and visible indicators; >=98% coverage and <=2 s gaps.
- [ ] Only then consider private alpha. Open-source readiness additionally requires
  clean-install onboarding, signing/update policy, privacy and retention docs,
  dependency/license review, clean-room testing, and a secrets/private-data scan.

Order is M0 → M1 → M2 → M3 → short regression → 31-minute test. These are acceptance
milestones, not calendar promises. Operator testing resumes after M1–M3 are verified;
do not book a release date based on the isolated run.

## Verification of this audit change

- Before fix: 8 verifier tests ran, 11 failed assertions across the 3 new cases.
- After fix: 8 verifier tests passed, zero failures, 0.469 seconds.
- Re-ran all six saved sessions with the corrected debug verifier, keeping thresholds
  unchanged and omitting operator attestations. The table above uses those results.
- Full suite: **1,080 tests, zero failures**, 85.223 seconds; no exclusions.
- Strict repository lint: **PASS** (`lint_swift: clean`); `git diff --check`: **PASS**.
- Confirmed the packaged app's executable hash is unchanged after the audit.
- No app bundle was rebuilt or relaunched for this verifier-only change. The currently
  packaged release verifier still has the old algorithm; use the rebuilt debug tool
  or `swift run audio-capture-verify` until the next release build.
