# Stereo audio preflight — 2026-09-10

## Scope and finding

User authorized a focused audio fix before the synthetic Teams rehearsal.
Base: `feat/native-whiteboard-port`, HEAD `3063012f20e52088cd83e79f994fde44d818497d`,
with pre-existing, uncommitted remediation and debug-bench changes preserved.
HEAD alone does not identify this tested working-tree build.

The streaming downmix indexed `floatChannelData[channel][frame]` for every
multi-channel format. Interleaved stereo has one data buffer, so this could read
outside the channel-pointer array. The 16 kHz shortcut also read only channel zero,
dropping the right channel in planar stereo and misreading packed stereo frames.
A local AVFoundation layout probe confirmed two-channel interleaved Float32 has
one AudioBuffer. This was not a reproduction of a crash on the user's selected devices.

## Changes

- Extracted the production streaming conversion path into `StreamingAudioConverter`.
- Explicitly downmix interleaved and planar Float32/Int16/Int32 PCM into mono before
  resampling, including the 16 kHz path and effective-rate overrides.
- Keep one resampler per stream, used serially by its existing consumer task;
  recreate on rate changes and clear it when using the no-resampling path.
- Reject empty buffers/invalid rates and conversion errors without yielding an answer.
- Replaced the captured mutable input state in streaming and recording converters
  with `SingleUseAudioConverterInput`. Its lock protects one-time consumption;
  the supplied buffer is fully populated before the conversion and not mutated
  during it. This is a scoped ownership contract, not a global concurrency guarantee.
- Added ten tests exercising the actual production converter, both stereo layouts,
  right-only signal, mono, integer PCM, 44.1/48/16 kHz, corrected rates, format
  transitions, repeated buffers, and concurrent requests to the input provider.

## Verification captured so far

- Focused rebuilt suite: **30 tests, zero failures**, 0.967 seconds.
- Strict repository lint: **PASS** (`lint_swift: clean`).
- `git diff --check`: **PASS** before packaging.
- Initial test compilation missed `import os`; corrected before rerun.
- The first repeated-buffer assertion allowed 200 priming frames and observed 240.
  Replaced that guessed allowance with an invariant: every buffer after the first
  must produce exactly 1,600 frames for each 100 ms of 48 kHz input. That test passes;
  this does not assert that the live stream flushes its final converter tail.
- Full regression: **1,077 tests, zero failures**, 85.599 seconds; no test exclusions.
- Release build: **PASS**, 111.49 seconds. The two conversion-capture warnings are
  gone; pre-existing redundant-await warnings in BatchTextCleaner and the
  immutable-local warning in SuggestionEngine remain outside this fix.
- Bundle: ad-hoc signed; `codesign --verify --deep --strict --verbose=2` **PASS**.
- Executable SHA-256: `b681b38f11f53b71321ea2c8bb47410d4d712b33d1a8945704db67e063de7b67`.
- Reopened the corrected bundle: main window showed **Start** (idle); whiteboard
  showed **Ready**, Synthetic Hotel 2020 Reference Pack, 3 sources, 9 prepared answers.
- Safe-key preferences checked before/after: same input/output IDs (81/74), local
  Parakeet v2 models, blank notes model, whiteboard enabled, auto-detection disabled,
  unchanged pack path and default offline Knowledge Copilot mode. No secrets read.
- Focused conversion preflight is sufficient to proceed to a controlled synthetic
  rehearsal; real-device capture and permission checks remain part of that rehearsal.

Local detailed logs: `/tmp/kc-stereo-focused.log`, `/tmp/kc-stereo-full.log`,
`/tmp/kc-stereo-lint.log`, `/tmp/kc-stereo-release.log` (temporary, not committed).
Previous app preserved at `dist/pre-stereo-fix.Ony702/OpenOats.app`.
No installation over `/Applications`, preference reset, commit, or push was requested.

## Live-test evidence and limits

Subsequent same-day rehearsal results, the verifier false-pass regression, and
the ordered follow-up checklist are in [solo Teams audit](2026-09-10-solo-teams-audit.md).
The statements below describe the state at the end of the earlier stereo-fix pass.

- Before this rebuild, the user reported that the whiteboard was absent from the
  Word-window share as received on their phone. This is user-observed evidence for
  that window-sharing setup only, not a full-display invisibility guarantee.
- Recheck the Word-window share after reopening the corrected build.
- No Teams audio rehearsal, measured speech-to-answer latency, 31-minute endurance
  test, or screen-wide sharing validation is established by these unit tests.
- Use only the fictional hospitality pack; external Knowledge Copilot adapters stay
  offline. The operator starts recording explicitly and handles any macOS permission
  prompts. No recording or external model request was initiated for this fix.
