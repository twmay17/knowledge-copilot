# Supervised Microsoft Teams alpha review

This runbook turns a consented Microsoft Teams test into a reproducible private-alpha decision. It
proves the complete presenter workflow: remote speech capture, live transcription, automatic
question detection, corpus-grounded answer display, citation inspection, correction handling, and
saved notes. The test uses local macOS audio capture and requires no Teams app, meeting bot,
Microsoft Graph access, Entra registration, or Microsoft 365 administrator action.

The evaluator is a gate, not a substitute for observation. It binds the operator's attestations and
end-to-end checks to the exact strict audio-verification report and Git commit under test, then fails
closed when any required observation is missing.

## Privacy and consent boundary

- Use a synthetic or explicitly non-confidential scenario.
- Obtain consent from every human participant before starting OpenOats.
- Keep the OpenOats **Live** recording indicator visible to the operator.
- Keep the private overlay out of the Teams share region, or share only a dedicated presentation
  window.
- Do not publish raw audio, private transcripts, participant names, meeting links, tenant IDs,
  unredacted screenshots, or operator notes.
- Stop the test if a non-consenting person joins or confidential information enters the call.

A Teams test-call bot is preferable when it exercises the same remote-output path. Otherwise, use a
scheduled call with a consenting colleague. Microsoft 365 admin access is neither required nor part
of this test.

## Prepare the build and corpus

1. Record the exact full commit under test:

   ```bash
   git rev-parse HEAD
   ```

2. From `OpenOats/`, validate the redistributable synthetic corpus:

   ```bash
   swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
   ```

3. Load `fixtures/knowledge-packs/minimal-hospitality` in OpenOats and confirm the pack ID is
   `synthetic-hotel-2020-v1`.
4. Complete the one-time macOS microphone and System Audio Recording setup in
   [`teams-audio-verification.md`](teams-audio-verification.md). Select the same microphone and
   output device in Teams and OpenOats.
5. Copy the fail-closed template to a private working directory:

   ```bash
   cp ../fixtures/teams-alpha-review/submission-template.json \
     /absolute/private/path/teams-alpha-submission.json
   ```

Do not pre-check the human observation fields. Fill them during or immediately after the session
from direct observation.

## Run the 31-minute session

Join the active Teams call before starting OpenOats. Pre-call silence recorded before Teams begins
producing output callbacks lowers measured system-track coverage.

1. Confirm aloud that this is a non-confidential recording test and every participant consents.
2. Start OpenOats, acknowledge the consent notice if shown, and confirm the green **Live** timer.
3. Confirm the OpenOats overlay is outside the shared region.
4. Verify capture hiding end to end: with **Hide from screen sharing** on, confirm on the second
   device that the overlay and mini bar are absent from the shared view; turn it off and confirm
   both reappear in the share (the app rebuilds the panels). Note that the main window stays out
   of the share until the app is relaunched.
5. Have the remote participant speak these prepared prompts naturally, leaving enough time to
   observe each result:
   - “What was the RevPAR for this asset in 2020?” Expected: a grounded `$89.50` card appears
     automatically and cites the operating statement and room inventory.
   - Open one cited source from the card and confirm the matching synthetic evidence is visible.
   - “Actually, what was occupancy in 2020?” Expected: the previous answer is superseded and the
     `72.0%` occupancy card becomes current.
   - “What was RevPAR in 2018?” Expected: a supported `not_found_in_corpus` answer, not an invented
     value.
6. At minutes `0`, `10`, `20`, and `30`, complete the microphone and remote-system checkpoints in
   the audio-verification runbook.
7. Keep the call active continuously for at least 31 minutes without changing audio devices.
8. Stop OpenOats, wait for finalization, and confirm the session transcript/notes artifact exists.

Record every observed failure or material weakness, even when the session ultimately passes. Use
synthetic, share-safe wording in the issue title and detail.

## Generate and evaluate the evidence

First generate the strict audio report exactly as described in
[`teams-audio-verification.md`](teams-audio-verification.md). Its session ID must match
`audioSessionID` in the alpha submission, and its start/end timestamps must match the submission's
session window.

Then update the private submission:

- replace the placeholder test-run ID and full Git SHA, then copy the audio session ID and exact
  start/end timestamps from the strict audio report;
- set an attestation or check to `true` only when directly observed;
- add every issue with a unique ID, severity, disposition, and share-safe detail;
- add a resolution note to every fixed or backlogged issue; and
- keep participant and tenant details only in `operatorNotes`, which the public report omits.

Evaluate it from `OpenOats/`:

```bash
swift run teams-alpha-review evaluate \
  /absolute/private/path/teams-alpha-submission.json \
  --audio-report /absolute/private/path/audio-verification.json \
  --output /absolute/private/path/teams-alpha-review-report.json
```

Add `--json` to print the machine-readable report. The command returns exit code `0` only for an
unconditional `GO`; `CONDITIONAL_GO`, invalid evidence, and `NO_GO` return nonzero so automation
cannot mistake them for approval.

## Severity and decision rules

| Severity | Meaning | Example |
| --- | --- | --- |
| Critical | Consent/privacy breach, destructive loss, or unusable core path | Capture continues after consent is withdrawn |
| High | A required presenter workflow fails with no safe workaround | Remote question never produces an answer card |
| Medium | Material friction with a bounded workaround | Citation opens slowly but remains inspectable |
| Low | Cosmetic or minor usability weakness | Answer copy is longer than preferred |

The evaluator checks 14 required gates: strict audio, real Teams evidence, consent, recording
indicator, non-confidential scenario, share-safe presentation, no-admin path, remote transcription,
automatic question detection, grounded answer, source inspection, correction replacement, saved
notes, and clean finalization.

- `NO_GO`: any required gate fails, or any critical/high issue remains open or backlogged.
- `CONDITIONAL_GO`: every required gate passes, no critical/high issue remains unresolved, and one
  or more medium issues remain open or backlogged.
- `GO`: every required gate passes and no critical, high, or medium issue remains unresolved. Open
  low issues are allowed but remain visible.

`CONDITIONAL_GO` is deliberately not an automated approval. A named human must accept its listed
conditions before admitting a participant to the private alpha. Re-run the complete test after any
fix that changes audio capture, transcription, question detection, grounding, or overlay behavior.

## Evidence suitable for the public repository

Retain the generated gate report, the tested Git SHA, the KnowledgePack ID, aggregate issue counts,
and a redacted screenshot if useful. Review issue text before publication. Keep the source
submission private because it contains the audio session ID and may contain operator notes.

The report is intentionally not marked as milestone evidence until the consented real-Teams
session has completed. Synthetic unit tests prove evaluator behavior; they do not prove the live
workflow.
