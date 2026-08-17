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

## Addendum — audit remediation wave 1 (2026-08-17)

Changes on branch `fix/audit-remediation-wave-1` (HEAD `3c15809`), six commits, following an
independent audit and two review rounds:

- Claim fact-checking compares numeric values within 8 ULPs instead of requiring bit-identical
  doubles, eliminating false "Contradicted by corpus" results on fractional-percent literals whose
  parse path rounds differently than the stored decimal (~28% of two-decimal percents). Verified
  through the public `evaluate()` path with a genuinely drifting 1-ULP pair (0.0905 vs a spoken
  "9.05%") and a 9,999-value sweep.
- The Knowledge network mode defaults to **offline** at the setting, store, and resolver layers.
  Enabling external adapters requires a versioned full-disclosure confirmation;
  `knowledgeNetworkMode` is `private(set)` so the consent API is the only mutation path; a stored
  external choice made before this consent version reloads as offline until re-confirmed.
  Switching offline cancels in-flight external work (pinned by test).
- The offline mode is renamed "Offline — no Knowledge Copilot egress" and its description states
  what it does not govern. Settings warns when the KnowledgePack folder overlaps the classic
  Knowledge Base folder (canonicalized, symlink- and containment-aware), because classic KB
  collection is recursive.
- Screen-share correction: `NSWindow.sharingType` is a one-way per-window ratchet on macOS 26.3.1
  (probe-verified: `.none` sticks; re-assigning `.readOnly` is silently refused; only a freshly
  created window is capturable). Re-enabling capture now rebuilds the overlay and mini-bar panels,
  transplanting content, frame, and configuration; tests assert this truthful contract. The 906/0
  recorded above was accurate for its run; the identical command failed 2 assertions in a GUI
  session on 2026-08-17 before this fix, and the machine-state variable behind that difference was
  not identified. `applyScreenShareVisibility` over the main window remains subject to the same
  ratchet — logged for Wave 2.

Environment and results, captured at completion:

```text
Mon Aug 17 03:02:27 UTC 2026 (baseline capture)
macOS 26.3.1 (a), build 25D771280a
Xcode 26.6, build 17F113
Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), arm64-apple-macosx26.0
Branch fix/audit-remediation-wave-1, base 616a18f7, HEAD 3c15809

Authoritative GUI-session suite run (maintainer terminal, 2026-08-17, HEAD 3c15809):
	 Executed 919 tests, with 0 failures (0 unexpected) in 61.940 (61.994) seconds

PASS: KnowledgePack V1 correctness gate
Packs: 2/2 passed; outcome probes: 8/8 passed
Replay: 101/101 passed; cross-pack: 2/2 passed

UI smoke:
	 Executed 11 tests, with 0 failures (0 unexpected) in 127.281 (127.292) seconds
```

The sandboxed session runner reproduced the same zero-failure suite result at this HEAD (919/0) —
its earlier 2-assertion failures came from the replaced test asserting the ratcheted direction.

## Addendum — audit remediation wave 2 (2026-08-17)

Changes on branch `fix/audit-remediation-wave-2` (base `6ec8733`, HEAD `bf1e086`), eight commits,
each task-reviewed plus a whole-branch review whose two findings were fixed and re-confirmed:

- External vector requests are bounded to the 64 highest-locally-ranked candidates and 512 KB of
  searchable text per request (whole records only — oversized documents are dropped, never
  truncated); the network-mode disclosure copy states the bound instead of "every active-scope
  candidate".
- Pack validation now scans raw source-file bytes for credential-like material (UTF-8 files whole;
  binary files via printable-ASCII runs), one `security.secret_in_source_file` error per credential
  kind per file, values never echoed. Google `AIza…` keys and bare JWTs join the detection
  patterns.
- Synthesized prose passes a deterministic numeric-echo gate: every number the model writes must
  match a number present in the admitted evidence (within 8 ULPs, allowing percent/ratio
  re-expression), or the synthesis is discarded and the deterministic card remains. The card
  caption now reads "Drafted from the cited evidence — verify wording against the sources below"
  — a claim the code can honor. Both the reject and accept paths are pinned end to end.
- The numeric comparator fails closed on malformed values and normalizes absent units; authors get
  an `assertion.near_identical_value` warning when two pack assertions for the same fact differ by
  only a few ULPs (the contested check itself stays deliberately exact).
- Mode toggles rebuild the overlay source catalog for the active pack; the settings→store mode
  wire re-applies on appear (`initial: true`); the consent API's result can no longer be ignored;
  users downgraded to offline by the Wave 1 consent migration see an in-app notice until they
  re-confirm.
- Classic Knowledge Base indexing hard-excludes the selected KnowledgePack tree (collection-time
  filter plus cached-chunk filter, symlink-aware), so overlapping folder settings cannot route
  corpus text through an embedding provider.
- The screen-share setting's caption carries both the full-display-sharing caveat and the
  main-window relaunch ratchet; the supervised-alpha protocol gains an end-to-end capture
  verification step.

Environment and results, captured at completion:

```text
Sun Aug 17 16:00:47 UTC 2026 (baseline capture)
macOS 26.3.1 (a), build 25D771280a
Xcode 26.6, build 17F113
Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), arm64-apple-macosx26.0
Branch fix/audit-remediation-wave-2, base 6ec8733, HEAD bf1e086

Authoritative GUI-session suite run (maintainer terminal, 2026-08-17, HEAD bf1e086):
	 Executed 934 tests, with 0 failures (0 unexpected) in 66.284 (66.337) seconds

PASS: KnowledgePack V1 correctness gate
Packs: 2/2 passed; outcome probes: 8/8 passed
Replay: 101/101 passed; cross-pack: 2/2 passed

Both fixture packs validate clean (the near-twin warning and source-file scan are inert on them).
```

UI smoke: 11/11 passed at `b1cae78` (identical application code to this HEAD — later commits
touched docs and tests only, plus one settings caption). Two later runs the same day failed with
app-launch timeouts while Microsoft Teams was active; the whole-branch reviewer independently
concurred the failures are environmental (no commit in this range touches window, launch, or
audio paths). Recorded as-is rather than normalized.
