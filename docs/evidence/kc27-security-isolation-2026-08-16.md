# KC-27 security and isolation evidence — 2026-08-16

## Implemented dependency-safe slice

- Fixed-instruction, JSON-quoted synthesis envelopes keep prompt-injection strings in untrusted data.
- Returned synthesis is still constrained by the existing admitted-record and citation-completeness
  gate.
- Persisted **Offline — no device egress** mode is visible in Knowledge Copilot settings and blocks
  external vector and synthesis adapters while the deterministic baseline loop continues.
- External mode distinguishes vector-search egress (the query and every active-scope candidate's
  searchable text, title, and identifiers) from synthesis egress (the question or claim and admitted
  evidence); each runtime request records data classes, counts, and destination.
- Common credential material fails pack validation without being echoed in findings.
- API secrets remain in the Keychain-backed secret store rather than `UserDefaults`.
- Diagnostic breadcrumbs and exports redact detected credentials before persistence or export.
- Root-contained, explicit pack/transcript/audio/cache deletion returns a testable absence receipt;
  broad-root and out-of-root targets fail closed.
- V1 creates no app-managed KnowledgePack copy: a load test snapshots every selected-folder file,
  verifies byte-for-byte non-mutation, and confirms the active path remains the selected directory.
  The search index is in-memory SQLite; the settings UI discloses the source-folder/FileVault boundary.
- Existing content-hash-bound cross-pack correctness coverage remains in force.

## Verification

Focused security, deletion, diagnostics, settings, pack loading/search, and tiered-answer runs passed
throughout implementation. The broad regression run passed on 2026-08-16:

```text
swift test --skip MeetingDetectorTests
Executed 906 tests, with 0 failures (0 unexpected)
```

Formatting and repository hygiene checks:

```text
swift format lint --strict <new and already-formatted KC-27 Swift files>
git diff --check
```

Manual telemetry-boundary audit:

```text
rg -n 'Log\.|DiagnosticsSupport\.record' OpenOats/Sources/OpenOats/KnowledgePack
# expected: no matches
```

Supervised UI review used a freshly rebuilt local app bundle in an isolated UI-test profile. The
Knowledge Copilot settings section rendered the in-place/no-copy storage notice, FileVault boundary,
network-mode control, and exact external data classes without clipped text or ambiguous placement.
The review also confirmed that V1 exposes no destructive deletion action: the deletion service stays
disconnected until an exact-target confirmation flow is deliberately designed.

## Acceptance mapping

- Prompt injection: implemented and automatically tested.
- Offline baseline loop: implemented, user-selectable, persisted, and automatically tested.
- Secret isolation: Keychain persistence, pack rejection, and diagnostics redaction are tested.
- Deletion: all four artifact classes plus containment and idempotence are tested.
- External disclosure: settings copy and runtime disclosure metadata are implemented and tested.
- Source-text telemetry: the Knowledge Pack path has no telemetry calls; transcript OSLog text remains
  private; diagnostics apply credential redaction.
- At-rest storage: V1 avoids an app-owned copy; the selected source folder remains user-managed and
  the search index is memory-only. Authenticated encryption is a release gate if app-owned persistence
  is introduced later.
- Cross-pack isolation: covered by the KC-26 correctness gate and replay fixtures.

## Closure boundary

KC-27 remains **In Progress** only for the dependency-driven rerun after KC-26's live-findings
closure.
