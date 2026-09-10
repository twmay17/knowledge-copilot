# Knowledge Copilot: code review and product alignment

Review date: September 9, 2026. Branch: `feat/native-whiteboard-port`.
Source baseline: `3063012f20e52088cd83e79f994fde44d818497d`, plus the existing working-tree edits listed below.

**Historical review snapshot.** Findings and line numbers below describe that baseline, not the
subsequent remediated working tree. See [implementation progress](2026-09-09-remediation-progress.md)
for current changes, tests, and remaining gates. The standalone probe below intentionally targets
the old prototype contract; current native regressions are in `SidecastWhiteboardCoordinatorTests`.

## Purpose, plainly

Build a real-time question buddy for someone presenting or having a conversation. It studies the documents you choose beforehand, listens during the conversation, and quietly puts useful answers, anticipated questions, and fact checks on your screen without requiring you to search.

Its factual authority is the supplied corpus, not the model's general knowledge. It shows where an answer came from, preserves disagreements, and says when information is missing or a question needs clarification. A corpus can establish what its sources say; it cannot guarantee that every source is true.

Hospitality is a reference use case, not the product boundary. Product pitches, research discussions, and historical debates should use the same core with different documents. The intended operating model is heavier study upfront, a fast and economical live path, local capture without Microsoft 365 tenant-admin integration, and an affordable open-source distribution.

## Executive assessment

**Keep the foundation; consolidate the live paths before adding more features.** There is substantial working infrastructure: versioned KnowledgePacks, provenance, deterministic calculations, explicit evidence outcomes, study proposals and human review, ingestion, replay benchmarks, session storage, and local audio-capture verification tooling.

The newer native whiteboard has not inherited those guarantees. It retrieves plain text and trusts the answering model's own `grounded` boolean. It also has independently implemented permissions, session lifecycle, retrieval, and duplicate suppression. Several reproduced failures occur precisely at those seams.

The current branch is a useful development prototype, but I would not treat its default whiteboard as ready for unsupervised confidential meetings or a supported public binary release.

The implementation plan and editable milestone checklist are in `docs/reviews/2026-09-09-remediation-plan.md`. No product fixes, commits, pushes, installations, or external service changes were made in this review.

## Scope and evidence

Reviewed the new whiteboard end to end; its app/settings/transcript integration; the existing evidence/study architecture and release gates; corpus admission and retrieval; relevant persistence, panel, packaging, and CI code; and the TypeScript debug bench. This is a risk-focused engineering review, not a claim that every line or dependency has been security-audited.

Existing changes preserved:

- Modified: `tools/sidecast-debug/index.html`, `src/main.ts`, `src/player.ts`, `src/types.ts`.
- Untracked: `tools/sidecast-debug/src/paste.ts`, `src/virtual-player.ts`.
- Bench findings apply to the inspected working tree; particularly the reset integration overlaps work in progress and should be fixed with its author, not overwritten.

Actual checks on macOS 26.3.1(a), Xcode 26.6, Swift 6.3.3, Node 26.7.0:

| Check | Observed result | Limit |
| --- | --- | --- |
| `swift test --skip MeetingDetectorTests` | 1,038 tests; 3 assertion failures in 2 panel tests | MeetingDetectorTests excluded, as in repository CI |
| Focused `KnowledgeOverlayPresentationTests` rerun | 19 tests; same 3 assertion failures | Does not establish actual screen-capture visibility |
| KnowledgePack correctness gate | PASS: packs 2/2, outcomes 8/8, replay 101/101, cross-pack 2/2 | Tests the trusted core, not the default whiteboard end to end |
| Canonical Swift lint | PASS | Current lint selection excludes Whiteboard sources |
| Debug-bench client TypeScript check | PASS | Not a browser or security test |
| Debug-bench server TypeScript check | FAIL: TS7016 at `server/transcript-proxy.ts:3` | Undeclared deep package import |
| Synthetic native probes | Reproduced 9 problematic observations | Real pipeline sources, mock LLM, minimal surrounding app stubs |
| Installed caption parser with synthetic XML | Legacy-format timestamps become 1,000x too early in the proxy; srv3 format is correct | No live YouTube request |

No paid model calls, real meeting recording, GUI smoke suite, signed release installation, live updater cycle, or Teams/Zoom capture test was performed. Historical August verification is not treated as current proof. No private knowledge corpus was loaded into a provider.

## Findings

Priority: **P1** = fix before relying on the affected feature with sensitive data or distributing it; **P2** = significant reliability, usability, or verification defect. These are engineering priorities, not formal vulnerability scores. There are 15 finding groups; R13 contains three separate bench tasks.

### R01 — P1: the whiteboard bypasses the evidence contract

Locations: `OpenOats/Sources/OpenOats/Whiteboard/SidecastQuestionOrchestrator.swift:102`, `:135`, `:156`; `SidecastWhiteboardModels.swift:10`, `:106`, `:114`, `:149`; `SidecastWhiteboardView.swift:30`.

The output schema supplies only answer text, a model-declared `grounded` flag, and usefulness. The emitted note has no source IDs, source locators, pack hash, typed claim, or evidence state. An unsupported answer that claims `grounded=true` can display without independent verification. With no corpus, even `grounded=false` is not rejected: the synthetic probe displayed one such answer. The fallback explicitly invites general-knowledge answers. With a corpus but no retrieval match, the question is silently dropped rather than becoming a visible abstention.

This contradicts both the project purpose and the documented prohibition on live cards bypassing the evidence gate. Prompt wording alone cannot enforce that boundary.

**Fix:** route whiteboard events through the existing pack-bound resolver and evidence gate. Render a concise view of that result, including inspectable citations, not an independently trusted answer type. No-corpus mode should request documents, not invent a fallback. Treat model suggestions as untrusted; use reviewed claims/calculations or clearly labeled source excerpts when support cannot be validated. Test fabricated grounding, prompt injection, missing evidence, conflicting sources, and incorrect numbers.

### R02 — P1: permission revocation can miss a new cloud request

Locations: `SidecastWhiteboardCoordinator.swift:43`, `:56`, `:199`, `:278`, `:293`; `OpenOats/Sources/OpenOats/App/AppContainer.swift:19`.

The egress gate is a cached boolean refreshed on session start and incoming utterances. It checks only an OpenRouter selection and nonempty key. If the user switches to a local provider while a question-detection request is pending, its result can initiate a new answer request before another utterance updates the gate. The probe reproduced that call. The actual production adapter rereads key/model, not provider permission.

The whiteboard also does not participate in the versioned external-knowledge consent used by KnowledgePack adapters. That existing setting is not currently an app-wide network kill switch; the issue is a separate corpus-upload path without an equally clear permission contract.

**Fix:** define one explicit policy covering transcript and corpus disclosure, check current authorization immediately before each outbound request/retry, cancel queued and cancellable in-flight work on revocation, and show the active destination. Keep recording permission distinct from permission to send text externally. Test revocation without a subsequent utterance, feature disablement, key removal, local-mode selection, and legacy stored settings.

### R03 — P1: old-session listener work can publish into a new session

Locations: `SidecastQuestionListener.swift:102`, `:122`, `:137`; `SidecastQuestionOrchestrator.swift:62`, `:89`, `:98`; `SidecastWhiteboardCoordinator.swift:120`, `:182`, `:209`, `:221`, `:256`.

Session start replaces the listener, but does not cancel its existing task. When an old listener finishes, it submits questions to the shared orchestrator, which stamps them with its *current* epoch. They therefore pass the existing stale-answer check. The probe produced one old-session note in a new session. Clear has the same unretired-listener problem. Main-actor callbacks also carry no session identity.

Additionally, clearing resets `inFlight` to zero without cancelling or retaining the underlying tasks. Repeated resets can exceed the intended three-request resource bound. Ending a session allows old listener work to start new answers, not just finish already-started answers.

**Fix:** carry a session/generation identity from transcript ingestion through detection, retrieval, answer, activity, and final UI delivery. Own task handles and cancel them. Serialize transitions. Define end-of-session draining explicitly; any permitted completion must belong only to its original session. Include rapid start/stop/start, clear-during-listen, clear-during-answer, delayed callback, and actual active-request-count tests.

### R04 — P2: question detection can stall exactly when someone waits for an answer

Locations: `SidecastQuestionListener.swift:19`, `:89`, `:105`; `SidecastWhiteboardModels.swift:54`; `OpenOats/Sources/OpenOats/App/LiveSessionController.swift:573`.

Detection requires two new utterances, eight seconds since the previous pass began, and no pass in flight. It is triggered only by another utterance. A single question followed by silence can remain unprocessed; eligible speech arriving during an in-flight pass is not drained when that pass finishes. The probe fed two more utterances after the cooldown, completed the first pass, and observed no follow-up detection.

The native path receives finalized utterances and the live adapter defaults to a 300-second request timeout. Together these cannot establish the promised near-question-completion experience.

**Fix:** use a bounded debounce/timer, schedule pending work on completion, handle single final questions, and expire stale work. Reuse the prepared-question/partial-event machinery for speculative retrieval, with explicit revision handling. Add fake-clock tests and measure question-end-to-visible-answer latency, not just retrieval speed.

### R05 — P2: lexical dedup suppresses genuinely different facts and retries

Locations: `SidecastQuestionOrchestrator.swift:33`, `:78`, `:82`, `:145`; `SidecastQuestionListener.swift:112`.

These questions have Jaccard similarity 0.8333 and only one reaches the answering model:

- “What was the reported RevPAR for this particular asset in 2020?”
- “What was the reported RevPAR for this particular asset in 2021?”

Answer dedup has an even lower threshold, 0.5, so changed values in similar wording can also disappear. Questions are marked recently covered before they succeed; failed or evicted work can suppress a needed retry.

**Fix:** identify the subject, metric/claim, period, unit, qualifiers, polarity, corpus revision, and event revision. Treat changed years/numbers/negations as substantive. Deduplicate successful equivalent results, not merely similar strings; preserve retryable failures. Cover product variants and historical dates as well as financial periods.

### R06 — P1: corpus switching does not invalidate answers or clearly retire old data

Locations: `SidecastCorpusService.swift:138`; `SidecastQuestionOrchestrator.swift:103`, `:124`; `SidecastWhiteboardView.swift:200`, `:210`; `SidecastWhiteboardCoordinator.swift:305`.

A failed folder read retains the previous corpus. The UI reports an error, but answering can continue against the last successful data. A successful switch does not invalidate in-flight answers or duplicate history. The probe started an answer on corpus A, loaded corpus B, then published A's answer. There is no corpus identity in the note to reveal that mismatch.

**Fix:** use a single coordinator-owned active-corpus state with immutable revision/hash snapshots. Bind retrieval and display to that identity; atomically activate a validated replacement and invalidate incompatible work. During a failed selection, pause affected answering or offer an explicit, clearly named “continue with previous corpus” choice. Distinguish an unchanged periodic refresh failure from a requested switch. Test failed reads, empty folders, rapid A/B/A changes, edited sources, and stale completions.

### R07 — P2: hidden subdirectories can enter the corpus unexpectedly

Location: `SidecastCorpusService.swift:83`.

The enumerator walks hidden directories and filters only dot-prefixed *filenames*. A synthetic `.private/notes.md` was loaded. Its contents can consequently become model evidence even though hidden files appear to be excluded. This is a source-selection/privacy hardening gap, not evidence that any actual private file was transmitted.

**Fix:** prune hidden directories by default, apply canonical containment rules, and show an explicit included/skipped inventory with reasons before activation. If hidden material is intentionally supported, require deliberate inclusion. Test hidden ancestors, symlinks, nesting, unreadable entries, size limits, and expected corpus boundaries using synthetic fixtures.

### R08 — P2: an oversized retrieval chunk hides otherwise valid evidence

Locations: `SidecastCorpusService.swift:193`, `:209`, `:235`.

Chunking keeps a single long line whole. Evidence assembly stops at the first chunk that exceeds the 9,000-character budget. A 12,600-character highest-ranked line plus a short matching source caused retrieval to return nil, although the short source contained the requested answer.

**Fix:** enforce chunk limits even for long lines, preserve CSV row/header semantics, account for wrapper overhead, and skip or safely split oversized candidates instead of abandoning all remaining matches. Test long prose, CSV headers/rows, multibyte text, and exact budget boundaries. Improve ranking so repetition cannot crowd out a precise answer.

### R09 — P1: the default feature configuration can silently disable the chosen assistant

Locations: `OpenOats/Sources/OpenOats/Settings/SettingsStore.swift:1598`; `OpenOats/Sources/OpenOats/App/AppContainer.swift:169`; `LiveSessionController.swift:579`, `:602`; `SidecastWhiteboardCoordinator.swift:293`.

The whiteboard defaults on and is wired exclusively to OpenRouter. Selecting Ollama or another provider closes its gate, but in Sidecast mode the same feature flag suppresses the legacy provider-capable engine. The board can show Live with no working answer path. Conversely, default classic-suggestions mode runs both classic suggestions and the whiteboard from the same speech, potentially duplicating cloud work. No user-facing whiteboard enable toggle was found in the inspected settings views.

**Fix:** make one explicitly selected live assistant own the pipeline. Add capability/readiness checks and a visible provider/connection status. Implement the intended local and optional external adapters behind the common contract, or visibly mark an unsupported choice as unavailable before starting. Do not silently switch providers or run a second paid assistant. Test the default profile and every exposed provider/mode combination.

### R10 — P2: whiteboard notes disappear unless manually exported

Locations: `SidecastWhiteboardModel.swift:112`, `:120`; `SidecastWhiteboardCoordinator.swift:198`; `SidecastWhiteboardView.swift:240`.

Whiteboard notes live in memory and manual TXT/JSON export. Starting another session clears them; the reviewed session-storage path does not persist these notes. An accidental restart or new meeting can therefore lose the answer stream even though the application already saves ordinary session data. Export model identity is also captured when services are constructed, not recorded per response.

**Fix:** persist accepted notes and revisions to their session with source references, corpus hash, event ID, actual provider/model, and timing. Restore them on reopening; export from that durable record. Provide a clear retention/delete policy and visible write failures. Test crashes/restarts, session transitions, mid-call model changes, and disk-write failures.

### R11 — P2: raw meeting questions are explicitly public in diagnostic logs

Locations: `SidecastQuestionOrchestrator.swift:79`, `:110`, `:136`, `:141`, `:146`, `:159`.

Several dropped-question and error paths log the full question with `privacy: .public`. Outbound prompt redaction does not protect these original strings. Diagnostic captures can therefore contain meeting details despite the separate sensitive-data guard.

**Fix:** log event IDs, timing, result categories, and counts by default, not question text. Any content-debug mode needs explicit opt-in, bounded local retention, and redacted exports. Scrub provider errors as well. Test logs using synthetic secret markers without placing real secrets in fixtures.

### R12 — P1, debug bench only: unescaped transcript HTML and exported API keys

Locations: `tools/sidecast-debug/src/ui.ts:576`, `:606`; `src/settings.ts:25`, `:104`.

Transcript text is interpolated into `innerHTML`; selected persona fields are also unescaped. Untrusted text can become executable browser markup. The same origin stores the provider key in localStorage, and preset export explicitly includes `apiKey`. This creates a credential exposure path and makes innocently shared presets sensitive. Static sink/storage inspection confirms the unsafe composition; no browser exploit or real-key access was attempted.

**Fix:** render untrusted strings with DOM text APIs, validate structured attributes, omit secrets from exports, and avoid persisting a key by default. Restrict the local helper to loopback and intended origins. Add harmless HTML-injection and key-redaction tests. Do not share existing real-key presets or use untrusted transcripts with the bench until fixed.

### R13 — P2, debug bench: timing, asynchronous reset, and type checking need repair

**R13a — Timestamp normalization.** `server/transcript-proxy.ts:29` divides every offset/duration by 1,000. Installed `youtube-transcript` 1.3.0 returns milliseconds for srv3 XML but seconds for legacy XML. A synthetic legacy segment at 120 seconds became 0.12 seconds; the equivalent srv3 segment correctly became 120. Normalize from a documented, format-aware adapter contract; do not guess units from magnitude. Add fixtures for both formats and validate sorted finite timestamps/durations.

**R13b — Stale bench results after reset.** `src/main.ts:79`, `:289`, `:300`, `:313` reset shared state but do not invalidate pending generation. `src/transcript.ts:104` can restore an old running summary after `resetSummary()`. This is a static async-control-flow finding in the current working tree. Introduce source-generation identities and cancellation throughout summary/generation/load/seek; deferred-response tests must prove old results cannot enter a new source. Preserve the existing paste/player work while doing this.

**R13c — Server compilation fails.** The deep ESM import at `server/transcript-proxy.ts:3` has no declaration and currently fails TS7016. Use a typed adapter/export compatible with the pinned package; do not hide the problem with `any` or disabling strictness. Check both client and server in CI.

### R14 — P2: test expectations and coverage do not establish default-path readiness

Locations: `OpenOats/Tests/OpenOatsTests/KnowledgeOverlayPresentationTests.swift:107`, `:129`; `OpenOats/Sources/OpenOats/Views/OverlayPanel.swift:203`; `Views/MiniBarPanel.swift:107`; `App/AppContainer.swift:115`; `.github/workflows/validate-swift.yml:40`; `scripts/lint_swift.sh:13`.

All three observed failures require the panel object to be replaced. Production code rebuilds only if the existing object fails to accept `.readOnly`. In this run the setting and content/frame checks passed, so unconditional identity replacement is an over-specific assertion. The focused rerun reproduced exactly that result. This does **not** prove either a screen-sharing privacy bug or successful real-world exclusion; it also does not justify changing the enum to `.readWrite`.

Separately, scripted UI scenarios explicitly disable the default-on whiteboard, the core correctness benchmark does not traverse it, and canonical lint omits its new source directory.

**Fix:** test desired behavior, inject the failed-readback branch to exercise rebuilding deterministically, and verify real capture separately. Add default-on whiteboard UI scenarios and end-to-end replay/permission/race tests. Expand appropriate lint/type checks. Capture fresh failure sets and environment details; do not suppress unrelated failures or publish anticipated totals.

### R15 — P1 before distributing a fork: updater and release identity still target upstream

Locations: `OpenOats/Sources/OpenOats/Info.plist:9`, `:46`; `App/AppUpdaterController.swift:11`; `scripts/build_swift_app.sh:25`, `:63`; `.github/workflows/release-dmg.yml:165`; `README.md:145`.

The app retains `com.openoats.app`, upstream URL scheme/name, upstream update feed/public key, and enabled automatic checks. The package script copies that configuration. The release workflow hardcodes upstream download and publishing targets; README install instructions also install upstream. A fork binary can check for upstream updates, and whether it replaces itself depends on the offered version/signature/update flow. No replacement was attempted or observed.

**Fix:** disable updater startup for development/fork builds until a deliberate fork-owned identity, signed feed, and key configuration exist. Audit application-support and Keychain namespaces and provide a non-destructive migration strategy. Correct downloads, release targets, attribution, and support instructions. Test installation beside upstream and inspect the packaged plist—not just source configuration—before distribution.

## Improvements beyond defect repair

1. **One product, one trust engine.** Keep the whiteboard's quiet, readable interface; make it consume the established evidence-backed result type. Limit the TypeScript tool to a clearly labeled experimentation/replay role. Share fixtures/contracts rather than maintaining separate production semantics by verbatim porting.
2. **Make upfront study earn its cost.** Reuse the Study Bundle, pending-review queue, reviewed response cards, and content-hash invalidation. Add a readiness page showing likely questions covered, unresolved contradictions, missing facts, and stale preparation. The existing manual model-analysis import supports subscription-assisted study without assuming an automated subscription-backed live endpoint. The current native live adapter explicitly uses an API key; this review did not verify new provider entitlements or prices.
3. **Measure responsiveness and spend together.** Record local, content-free timestamps for speech/partial, final question, detection, retrieval, validation, first visible card, and correction. Track provider usage when supplied; otherwise label estimates. Add session request/token budgets, timeouts, backpressure, and a circuit breaker. Prepared answers should have an LLM-free fast lane.
4. **Improve corpus quality, not just model size.** Bridge document/spreadsheet ingestion into the active pack; preview skipped files accurately; precompute chunks/indexes on content changes instead of rechunking every question and rereading every eight seconds. Preserve source locators. Add Unicode-aware matching and keep domain-specific weighting in optional profiles.
5. **Design for a presenter under pressure.** Show a short answer first, evidence on demand, and distinct “not found,” “conflicting sources,” “needs clarification,” and “provider unavailable” states. Keep updates stable, allow pin/dismiss, make fact corrections visibly different from duplicates, and let the presenter pause listening independently of recording.
6. **Make generality demonstrable.** Keep hospitality and product-pitch fixtures; add a historical-debate pack with competing interpretations, dates, textual variants, and attribution. A larger model must not convert an interpretation into a verified fact. Anticipated questions must be visually distinct from questions actually asked.
7. **Make public release reproducible.** Keep synthetic fixtures public and private corpora/audio out of history. Add contributor setup, dependency/license review, a security policy, release checklist, migration/rollback guidance, and a supported OS/provider matrix. Do not require Graph, a meeting bot, or tenant-admin approval for the baseline; separately test endpoint/macOS permission restrictions.

## Reproduction record

Full-suite log from this run: `/tmp/knowledge-copilot-review-2026-09-09-suite.log`.
Correctness output: `/tmp/knowledge-copilot-review-2026-09-09-correctness.json`.
These temporary files are local evidence, not permanent public artifacts.

The portable synthetic probe is `docs/reviews/evidence/2026-09-09-native-probe.swift`. It compiles the reviewed production pipeline directly, substitutes minimal settings/bookmark/speaker types and a fake LLM, and creates only synthetic fixture files. It is a diagnostic demonstration, not yet a CI test: observations must be turned into deterministic regression assertions in M0/M1/M2. It does not validate the real GUI, provider transport, or recording stack.

From repository root, create a fresh probe directory with `mktemp -d /tmp/kc-native-review.XXXXXX`, then substitute its returned path for `<PROBE_DIR>`:

```sh
swiftc -parse-as-library -swift-version 6 -o <PROBE_DIR>/probe \
  docs/reviews/evidence/2026-09-09-native-probe.swift \
  OpenOats/Sources/OpenOats/Whiteboard/SidecastCorpusService.swift \
  OpenOats/Sources/OpenOats/Whiteboard/SidecastQuestionListener.swift \
  OpenOats/Sources/OpenOats/Whiteboard/SidecastQuestionOrchestrator.swift \
  OpenOats/Sources/OpenOats/Whiteboard/SidecastWhiteboardCoordinator.swift \
  OpenOats/Sources/OpenOats/Whiteboard/SidecastWhiteboardModel.swift \
  OpenOats/Sources/OpenOats/Whiteboard/SidecastWhiteboardModels.swift \
  OpenOats/Sources/OpenOats/Intelligence/OpenRouterClient.swift \
  OpenOats/Sources/OpenOats/Utils/Logging.swift \
  OpenOats/Sources/OpenOats/Utils/SensitiveDataGuard.swift
<PROBE_DIR>/probe <PROBE_DIR>/fixtures
```

Observed at the reviewed baseline:

```text
no_corpus_grounded_false_displayed=1
eligible_followup_after_listen_completed_listen_calls=1
old_session_listener_notes_in_new_session=1
new_answer_calls_after_provider_switched_to_local=1
year_question_similarity=0.8333333333333334 distinct_year_answer_calls=1
hidden_directory_files_loaded=[".private/notes.md"]
oversized_top_chunk_evidence_is_nil=true
failed_folder_switch_retains_old_corpus=true
old_corpus_answers_published_after_switch=1
```

The corrected expectations are no unsupported note, a drained follow-up detection pass, no cross-session/cross-corpus note, no newly authorized-by-stale-state cloud answer, two distinct year requests, no implicit hidden-directory inclusion, and usable bounded retrieval. Failed corpus switching requires the explicit product-state behavior described in R06, not merely changing the service's transaction semantics.

The caption probe called the installed package's `YoutubeTranscript.parseTranscriptXml` with `<text start="120" dur="2">Test</text>` and `<p t="120000" d="2000">Test</p>`, then applied the current proxy's division. Results were respectively 0.12 and 120 seconds. Both fixtures represent 120 seconds.

## Recommendation

Start with the evidence/permission/session boundary fixes and their regression tests. Do not spend the next iteration adding another model, richer personas, web search, or additional third-party integrations. The existing core is the leverage: connect the live experience to it, measure that complete path, and release only after the capture/privacy and packaging gates pass.
