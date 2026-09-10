# M2a: microphone controls and device-recovery safeguards

## Status

Implemented in source; final core regression passes. Release compilation is recorded below.
The installed/working app has not been replaced, launched, or given new permissions.
Physical Bluetooth switching and sustained duplex capture are **not yet accepted**.

## What changed

- [x] A labeled microphone button remains visible in the main footer. It is inactive
  while idle, usable during session preparation and while paused, and explains that
  muting this app does not mute Teams or system audio. The level meter no longer
  dims merely because the microphone is muted while system audio continues.
- [x] AVAudioEngine configuration notifications request the existing serialized
  restart queue instead of calling `engine.start()` on a notification thread.
  A configuration change can force a fresh engine even with the same numeric device ID.
- [x] Input-device inventory notifications trigger route re-evaluation, including
  explicitly selected microphones disconnecting/reconnecting. Stored UIDs take
  precedence over numeric IDs; a recycled ID cannot silently select another mic.
  Missing explicit choices require reconnection or an explicit choice in Settings.
- [x] Startup/recovery watchdog is retained and cancelled, checks stream identity,
  and permits one automatic retry before presenting a device error. Unrelated device
  inventory notifications do not reset that retry budget for the same selected device.
- [x] Restart tasks and queued device notifications check the original session
  generation after suspension. An old task cannot clear a newer restart task handle.
- [x] Replaced microphone/system transcript callbacks, cloud-status callbacks, and
  recorder forwarding check their stream generation. Microphone tap callbacks also
  guard shared level/frame flags. Mic and system generations are independent.
- [x] Microphone routing failures no longer clear unrelated system-audio errors.
- [x] Audio-unit input selection checks its CoreAudio result; failed engine starts
  remove their installed tap. Device enumeration allocates the reported variable
  AudioBufferList size rather than space for only one buffer.

## Test evidence and corrections during development

New unit coverage includes stable-UID reconnect, numeric-ID reuse, no silent fallback,
missing default, legacy settings without UID, retry limits, replaced/stopped and delayed
callbacks, independent mic/system generations, mute during preparation, and mute while
paused without resuming capture. A scripted UI test was added for visible mute labels.
The actual tap-handler factory also has a hardware-free regression that calls it
off-main with synthetic PCM, checks mute/pause filtering, and rejects a retired
stream's late frame/level updates. It does not instantiate or start AVAudioEngine.

- Initial focused verification exposed a callback isolation error introduced in this
  refactor: a microphone tap closure inherited MainActor isolation despite running on
  AVAudioEngine's audio callback thread. The sampled stack reached
  `dispatch_assert_queue` from `MicCapture.bufferStream`. The tap and notification
  callbacks are now explicitly Sendable; configuration handling hops to MainActor.
- A pre-existing deep-link test initialized live services, queued capture, and returned
  without stopping. That start could run during subsequent tests. It now cancels its
  queued start in a defer, preserving its synchronous initialization assertions without
  starting a real microphone. The two interrupted development runs are not passes.
- Corrected focused suite: **79 tests passed**, 0 failures, 9.052 seconds, in
  `/tmp/kc-routing-focused-clean.log` (before the final retry-policy test/refinement).
- First full regression: **1,101 passed**, 0 failures, 85.012 seconds, in
  `/tmp/kc-routing-full.log` (before the final retry-policy/frame-reset refinement).
- Second full regression: **1,102 passed**, 0 failures, 85.658 seconds, in
  `/tmp/kc-routing-full-final.log` (before extracting/testing the off-main tap factory).
- Final full regression: **1,103 passed**, 0 failures, 85.464 seconds;
  `/tmp/kc-routing-verified.log`. This includes the actual off-main tap callback test.
- Final release compilation: **passed**, 75.70 seconds;
  `/tmp/kc-routing-release-verified.log`. Existing warnings remain in BatchTextCleaner
  and SuggestionEngine; no build errors.
- Scoped repository lint: clean; `/tmp/kc-routing-lint.log`. `git diff --check`: clean.
- UI automation is still an open gate after the M1 runner timed out enabling macOS
  automation. The new UI assertions have not been executed; no permission bypass or
  security reset was attempted.

One intermediate release compilation was invalidated when the tap-handler source
changed during compilation; it is not counted as a build pass. The final release
command is rerun against the frozen source after the passing regression suite.

Machine: macOS 26.3.1(a), build 25D771280a; Xcode 26.6, build 17F113.
Base revision `3063012f20e52088cd83e79f994fde44d818497d`, with the existing mixed
worktree and this milestone's changes uncommitted.

The earlier crashed XCTest process remained in macOS `UE` (exiting/uninterruptible)
state after termination signals during development. Its replacement test run was
stopped, and subsequent corrected core tests passed without that live-start leak.
Check that the old test process has exited before any physical audio rehearsal;
do not restart CoreAudio or terminate unrelated apps silently.
It still had not exited at final handoff. Save work and restart macOS before the
next physical audio rehearsal if it remains stuck. No reboot was performed.

## Boundaries and remaining work

- [ ] Validate rapid disconnect/reconnect and same-device format changes on actual
  earbuds, USB, and built-in routes; verify mic mute/pause persist through recovery.
- [ ] Add fake-hardware end-to-end restart stress tests. The generation and routing
  policy tests do not simulate AVAudioEngine/CoreAudio hardware behavior.
- [ ] Bound ASR/backend drain time during device switches. Cancellation and generation
  checks prevent stale publication, but an uncooperative backend can still delay its
  serialized replacement. This is not a promised fixed recovery time.
- [ ] Finish system-tap lifecycle/ownership stress coverage, including overlapping
  stop/start and physical output loss. This patch does not rewrite low-level system
  capture or its default-output fallback behavior.
- [ ] Fix consumer-time sample-rate inference: slow ASR consumption must not be
  mistaken for an audio hardware clock change. This remains the next M2 item.
- [ ] Add per-track mute/pause/device intervals to verification evidence (M0).
- [ ] Repackage with a preserved working bundle, verify build identity, pass launch/UI
  checks, and run the short Teams regression before the 31-minute baseline.

No settings, session files, transcripts, source corpus, or credentials were migrated,
deleted, or published. No commits or pushes were made for this milestone.
The working app's executable remains
`b681b38f11f53b71321ea2c8bb47410d4d712b33d1a8945704db67e063de7b67`;
the new release executable has not been packaged into or installed over that app.
