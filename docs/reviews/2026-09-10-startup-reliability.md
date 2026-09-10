# M1 implementation: honest startup status and development identity

## Outcome

Startup now has a separate capture-readiness state. A session row or a model-loading
task does not authorize a Live badge or timer. Stop cancels the coordinator's startup
task and invalidates an engine startup generation, including late permission/model
completion and queued model progress callbacks.

**Implemented and core-tested; packaged-app/operator acceptance remains open.**
The working `dist/OpenOats.app` was not replaced or relaunched. Its executable SHA-256
remains `b681b38f11f53b71321ea2c8bb47410d4d712b33d1a8945704db67e063de7b67`.
These changes therefore are not yet visible in that running copy.

## Checklist

- [x] Distinguish Preparing, Awaiting microphone permission, Loading speech models,
  Starting audio, Waiting for audio, Partial audio, Live, Failed, and Stopping.
- [x] Keep Stop available during preparation; delay the displayed capture timer until
  capture is first observed. Suppress generic no-audio notices during permission/model waits.
- [x] Require both streams for Live, except deliberately muted microphone + system
  frames. A captured stream plus a missing stream/error reports Partial audio.
- [x] Cancel queued startup; invalidate late permission/model results and progress.
- [x] Test Stop before queued startup, while permission is suspended, and while an
  uncooperative model loader is suspended. No audio or network is used by the new fixtures.
- [x] Label the main window/header `Knowledge Copilot Dev`; hover exposes revision,
  UTC build timestamp, and exact bundle path. Packager stamps revision with a dirty marker.
- [x] Add `bash scripts/launch_knowledge_copilot.sh --check` and exact-path launch.
  Refuse a competing OpenOats executable; never kill another app or start recording.
- [x] Hide disabled upstream update controls in the menu-bar popover and app menu.
  Existing updater guards remain disabled and covered by the settings tests.
- [ ] Repackage once the next audio-control work is ready, preserving the working
  bundle and using `SKIP_INSTALL=1`. Verify stamped metadata and signature on that bundle.
- [ ] Rerun launch UI assertions and visually inspect long startup labels at minimum width.
- [ ] Rehearse actual macOS permission wait → Stop → late approval and verify no capture;
  then a normal Start with the selected Teams route. Mocked permissions do not prove TCC behavior.

## Verification captured on this machine

Base revision: `3063012f20e52088cd83e79f994fde44d818497d`, with existing uncommitted
remediation work preserved. macOS 26.3.1(a), build 25D771280a; Xcode 26.6, build 17F113.

| Check | Result | Local evidence |
| --- | --- | --- |
| Focused startup/controller tests | 65 passed, 0 failures | `/tmp/kc-startup-focused-final.log` |
| Full Swift test suite | 1,090 passed, 0 failures; 86.744 seconds | `/tmp/kc-startup-full.log` |
| Repository scoped lint | Clean (legacy files remain outside strict formatting scope) | `/tmp/kc-startup-lint.log` |
| Shell syntax + diff whitespace | Passed | `bash -n` on build/launch scripts; `git diff --check` |
| Exact-path launcher dry run | Passed with current custom app running | `--check` launches nothing |
| Competing-copy detection | Rejected a temporary sleep executable named OpenOats under a separate app path | Real app left untouched |
| Build metadata stamping | Passed on a temporary plist; bundle identifier unchanged | Display name, dirty revision and UTC date round-tripped with `plutil` |
| Launch-only UI test | Runner failed before assertions: `Timed out while enabling automation mode.` | `/tmp/kc-startup-ui.log` |
| Release compilation | Passed; 77.91 seconds | `/tmp/kc-startup-release.log` |

The XCTest result bundle is under `.build/ui-smoke/DerivedData/Logs/Test/`, named
`Test-OpenOatsUITestHost-2026.09.10_10-23-12--0500.xcresult`.
No permission grants, security resets, account changes, transcript deletion, or
upstream installation were performed. Changes are uncommitted.

## Limits and next work

- The frame flags establish that capture has started, not continuous speech,
  intelligibility, ASR progress, or dropout-free recording. Ongoing device/stream
  recovery and per-track timing remain M2/M0 work. The timer is not latency telemetry.
- The bundle ID remains `com.openoats.app` to preserve current settings and storage.
  This is visible development identification, not complete OS-level app isolation.
  The launcher checks a process snapshot, not a system-wide launch mutex. A future
  bundle-ID migration needs an explicit settings/credentials/permissions plan.
- A dirty revision plus timestamp distinguishes builds but is not a reproducible
  source fingerprint. Record the packaged executable hash when staging the next app.
- Cancellation does not forcibly abort an OS permission sheet or model download;
  it prevents the old startup from applying its results. Device-restart callback
  ownership and cancellation during repository row creation still need stress coverage.
- Next: labeled microphone control and stable device routing, then duplicate-question
  handling/readable partial answers, then the short live regression and endurance run.

## Launch after the next packaged build

From the repository root:

```sh
bash scripts/launch_knowledge_copilot.sh --check
bash scripts/launch_knowledge_copilot.sh
```

If another copy is reported, save/end its session and quit it normally before retrying.
The launcher deliberately does not perform those actions for the operator.
