# Microsoft Teams audio-capture verification

This runbook proves that Knowledge Copilot can capture the presenter and the remote side of a Microsoft Teams conversation without a Teams app, meeting bot, Microsoft Graph access, Entra registration, or Microsoft 365 tenant-admin consent.

The application captures:

- the selected microphone through `AVAudioEngine`; and
- the selected macOS output device through a local Core Audio process tap.

Only ordinary macOS microphone and System Audio Recording permissions are required. A managed Mac can still restrict those permissions through endpoint policy; that is an operating-system policy constraint, not a Microsoft 365 integration requirement.

## Safety and privacy

Run this test only after every human participant has consented to recording. A Teams test-call bot is preferred when the feature is available. Otherwise, use a scheduled test with a consenting colleague.

The verification workflow retains separate microphone and system-audio CAF files locally. They can contain the complete conversation. Do not use confidential meeting content for this test, and delete the raw stems when the evidence has been reviewed. OpenOats normally expires retained batch stems after seven days.

## One-time setup

1. Build and launch the signed app bundle so macOS permissions attach to the real application identity.
2. In macOS **System Settings → Privacy & Security**, allow OpenOats to use:
   - Microphone
   - System Audio Recording
3. In OpenOats **Settings → Transcription**:
   - select the microphone used by Teams;
   - select the speaker/output device carrying Teams audio;
   - enable **Re-transcribe with higher accuracy after meeting** so separate stems are retained;
   - enable diagnostic logging; and
   - set automatic silence stop to `0` for this controlled test.
4. In Teams, select the same microphone and output device.

No Microsoft 365 administrator action belongs in this checklist.

For repeatable local testing, prefer an Apple Development or Developer ID signing identity. An
ad-hoc signature is sufficient to launch the app, but its code identity changes when the binary is
rebuilt. macOS can therefore require microphone and System Audio Recording approval again even
while the old OpenOats toggle still appears enabled.

## Thirty-minute protocol

Use a 31-minute session so startup and shutdown margins do not make a valid test appear shorter than 30 minutes.

1. Start a Teams test call or join the consented test meeting.
2. Confirm aloud that the session is a recording test and that all human participants consent.
3. Start OpenOats.
4. Confirm the **Recording Consent Notice** appears before capture on a fresh profile, acknowledge it, and verify the green **Live** timer is visible.
5. At minutes `0`, `10`, `20`, and `30`:
   - say a short microphone checkpoint, such as “presenter checkpoint ten”; and
   - have the remote participant or Teams test bot produce a distinct response.
6. Keep the call running continuously. Do not pause OpenOats or change audio devices during the baseline test.
7. Stop OpenOats after at least 31 minutes and wait for session finalization.

Start OpenOats only after Teams is in the active call. Time recorded before the selected output
device begins producing capture callbacks counts against track coverage, even when no one is
speaking.

## Generate deterministic evidence

Find the completed session directory under:

```text
~/Library/Application Support/OpenOats/sessions/session_*
```

From the `OpenOats` package directory, run:

```bash
swift run audio-capture-verify verify "/absolute/path/to/session_directory" \
  --minimum-seconds 1800 \
  --minimum-coverage 0.98 \
  --maximum-gap-seconds 2 \
  --teams-session-confirmed \
  --participant-consent-confirmed \
  --recording-indicator-confirmed \
  --verified-by "Operator name" \
  --output "/absolute/path/to/session_directory/audio-verification.json"
```

Use an attestation flag only when the operator actually observed that condition. The command exits nonzero when any gate fails.

## Passing gates

The report passes only when:

- `session.json` proves the session lasted at least 30 minutes;
- both `audio/mic.caf` and `audio/sys.caf` exist and are readable;
- each track covers at least 98% of the session;
- each track contains an audible checkpoint above the configured peak threshold;
- periodic frame-to-wall-clock anchors show no unrecovered gap longer than two seconds;
- the Teams session, participant consent, and visible recording indicator are confirmed.

Silence is not treated as a dropout. The verifier compares periodic frame progress with wall-clock progress, so it can distinguish a quiet interval from a capture callback that stopped and never recovered.

## Evidence to retain

Retain only what the project needs:

- `audio-verification.json`;
- a screenshot showing the OpenOats **Live** timer beside the active Teams test call, with private details redacted;
- the app version or Git commit tested; and
- a short note identifying the microphone and output-device types.

Do not commit raw audio, private transcripts, participant names, meeting links, tenant identifiers, or unredacted screenshots to the public repository.

## Failure triage

- **Missing system track:** confirm the selected output matches Teams and macOS System Audio Recording permission is enabled.
- **Missing microphone track:** confirm the selected input matches Teams and macOS Microphone permission is enabled.
- **Low peak:** repeat the checkpoint with normal speech volume; do not lower the threshold merely to force a pass.
- **Low coverage or a long gap:** export diagnostics, record the device route and timestamp, and treat the run as failed until the capture restart path is fixed and the full protocol is repeated.
- **No timing anchors:** the run predates the periodic-anchor instrumentation and cannot certify dropout recovery; repeat with a current build.
