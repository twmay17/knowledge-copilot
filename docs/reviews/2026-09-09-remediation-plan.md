# Knowledge Copilot remediation plan and milestone tracker

Prepared September 9, 2026 against `3063012f20e52088cd83e79f994fde44d818497d` on `feat/native-whiteboard-port`.
Companion findings: `docs/reviews/2026-09-09-project-review.md`.

## Outcome

Deliver a dependable, corpus-only live question buddy with advance preparation, source-backed answers, clear uncertainty, reliable session boundaries, and an honest cost/privacy model. Preserve the domain-neutral core, the simple whiteboard, and local meeting capture that does not require Microsoft 365 tenant-admin integration.

Implementation began September 9, 2026. The first remediation pass implements containment, consolidates the native whiteboard onto the existing evidence engine, and adds saved answers, bench fixes, and three-domain replay coverage. This is **not** completion of the whole plan. Checked items refer to implemented and tested code, not a verified live pilot. See [the progress/evidence ledger](2026-09-09-remediation-progress.md) for exact checks and limits. All changes are currently uncommitted.

## Milestones at a glance

Estimates are focused engineering days for one primary implementer, including regression tests. They are not a booked schedule or a promise about model latency. Signing, a clean-machine install, and a consenting Teams test partner are external dependencies. Re-estimate after M1 because integrating the whiteboard with the existing result contract is the largest uncertainty.

| Milestone | What you will see | Planned effort | Planned cumulative workday | Actual/status |
| --- | --- | --- | --- | --- |
| M0 — Baseline and containment | One reproducible test command; risky defaults visibly contained | 1 day | 1 | Implemented; automated gate recorded in progress ledger |
| M1 — Trustworthy live answers | Answers cite the selected corpus; old meetings/data cannot leak into new answers | 4–6 days | 5–7 | Core integration implemented; full pilot/adversarial matrix pending |
| M2 — A useful real-time buddy | Questions followed by silence work; year/value changes are answered; clear provider readiness | 3–4 days | 8–11 | Prepared local path + bench fixes implemented; broader model listening pending |
| M3 — Study, corpus, and saved notes | One preparation/import flow, readiness view, reliable files, saved session answers | 3–4 days | 11–15 | Saved notes, basic readiness, third fixture implemented; unified preparation UX pending |
| M4 — Pilot and open-source release | Verified Teams run, documented privacy limits, fork-owned package and contributor setup | 3–5 days | 14–20 | Whiteboard UI scenario passes after launch/accessibility fixes; pilot/release pending |

Planning range: roughly **3–4 working weeks**, plus any external waiting time. M1 enables controlled synthetic testing of the corrected native path; M2/M3 produce the supervised personal pilot candidate; M4 is the public binary/support gate. Source publication and a supported app release are different milestones—do not label an experimental source snapshot production-ready.

## M0 — Establish a trustworthy baseline and contain known hazards

Addresses R12, R13c, R14, immediate containment for R01/R09/R15.

- [x] Record branch, full SHA, existing dirty files, OS/Xcode/Swift/Node versions, test commands, and exact failure set.
- [x] Preserve the in-progress debug-bench changes. Use narrow commits and explicit file lists; do not overwrite or stage unrelated work.
- [x] Replace standalone prototype observations with current-path regression tests. The new coordinator tests exercise the actual detector/resolver/model with synthetic packs; removed listener/answerer behavior is no longer production authority. Bench tests use deferred responses for reset boundaries.
- [x] Correct unconditional panel-identity test assumptions; inject the failed-readback branch. Preserve behavior checks and keep actual capture verification separate.
- [x] Make experimental whiteboard activation explicit pending the trust fixes, with honest unavailable/experimental UI; document how to run the intended engine.
- [x] Disable upstream updater use in development/fork builds as an immediate containment change. Do not change user data or automatically migrate identities in this step.
- [x] Remove keys from bench preset exports and unsafe transcript/persona HTML rendering before further untrusted replay work.
- [x] Fix the bench's typed server import and add both client/server type-check commands.

Gate: baseline is reproducible; any remaining failure is named and understood; no new regressions; no new key-bearing exports; no implied production-readiness claim. Completion evidence includes the actual test log, not an expected test count.

## M1 — Unify trust, permissions, and lifecycle

Addresses R01, R02, R03, R06, R11; establishes contracts used by all later work.

- [x] Define a single live-event/result envelope carrying session ID, event/revision ID, active corpus hash, evidence state, source locators, and actual provider/model when used. Reuse existing KnowledgePack types where possible.
- [ ] Introduce an explicit pipeline lifecycle: ready, loading corpus, listening, answering, unavailable, ended. Settings changes and corpus changes are transitions, not independent view mutations.
- [x] Route the whiteboard through the existing pack-bound retrieval, tiered resolver, deterministic evidence evaluator, and response-card rules. Preserve the compact presentation.
- [x] Disable no-corpus general-knowledge answers. Surface missing, contested, interpretive, and clarification outcomes explicitly; do not use model self-reported grounding as acceptance.
- [ ] Add citation/source inspection to each factual answer. Reject unknown references, fabricated grounding, changed numeric values, wrong qualifiers, and injected document instructions.
- [x] Carry session/generation identity through the consolidated native detector, resolver, corpus refresh, and accepted-result callback; reject stale results before enqueueing persistence. Accepted immutable snapshots may finish saving only to their original session.
- [ ] Own cancellation handles and serialize start/end/clear/switch. Bound actual outstanding requests, not just the current epoch's counter. Define any intentional post-stop completion as belonging only to the original session.
- [ ] Introduce a current permission check at the outbound boundary, including retries. Separate recording consent, transcript disclosure, corpus disclosure, and permitted provider/destination. Revocation must not require another utterance.
- [x] Make corpus replacement atomic and revision-bound. Pause on a requested switch failure or require an explicit named last-good selection; invalidate stale work and cache/dedup state appropriately.
- [x] Remove raw question content from public logs and make diagnostic exports safe by default.

Gate:

- [ ] No-corpus/unsupported/conflicting adversarial fixtures produce the required abstention or evidence state, not an invented factual answer.
- [ ] All displayed factual claims in the release fixture set have valid references and the correct active-corpus identity.
- [ ] Revocation tests produce zero new unauthorized transport starts; cancellable work is cancelled and stale completions cannot display.
- [ ] End/new-session/clear/corpus-switch stress tests produce zero cross-boundary notes or activity pollution.
- [ ] Existing core correctness gate remains green, and the new whiteboard path passes the same relevant fixtures end to end.

These test gates establish behavior on defined cases, not a mathematical guarantee that arbitrary model prose can never be wrong. Prefer constrained rendering/reviewed claims where stronger guarantees are required.

## M2 — Make the live experience timely and dependable

Addresses R04, R05, R09, R13a/R13b; builds on M1 identities and cancellation.

- [ ] Add a bounded single-question debounce and timer; drain eligible work after a listener pass without requiring more speech.
- [x] Reuse partial-speech/prepared-question detection and speculative retrieval, with cancellation when the question changes. Label provisional results; unconstrained anticipatory prose is not implemented.
- [x] Replace the native prototype's lexical-only suppression with shared event/claim identities and qualifier-aware handling. Covered regressions include changed years and partial/final upsert; the broader variants/negations/retry pilot matrix remains below.
- [ ] Establish one live assistant owner. Test classic/Sidecast/whiteboard selection and prevent unintended duplicate provider calls.
- [ ] Add provider capability checks and real readiness/error states. Implement local and optional external adapters for the common result contract; unsupported choices must not pretend to be Live or silently fall back to cloud.
- [ ] Set live deadlines, bounded queues, retry/backoff budgets, and a circuit breaker. Keep heavy study out of the live request queue.
- [ ] Instrument question-end-to-display latency, prefetch hits, detection misses, revisions, dropped work, actual outstanding calls, and usage/cost where available, without logging private speech.
- [x] Fix caption timestamp normalization with legacy/srv3 fixtures; never infer units from timestamp size.
- [x] Add source-generation cancellation to bench load, summary, generation, reset, and seek without replacing the user's in-progress paste/player work.

Gate:

- [ ] A single final question followed by silence is processed within its configured detection deadline.
- [ ] Two questions arriving during an in-flight pass are subsequently processed; final utterances are not stranded.
- [ ] 2020 versus 2021, revised values, product variants, negations, retries, and topic corrections behave correctly.
- [ ] Old bench summaries/results cannot land after source replacement or seek; both caption formats use seconds internally.
- [ ] Measured latency/quality/cost report covers local and explicitly enabled external modes on the target Mac.

Initial performance targets to validate, not advertised guarantees: prepared-card p95 display within one second of a stable final question; retrieved/model-assisted p95 within three seconds where the chosen provider/hardware permits it. Record partial-to-answer timing separately. If targets are missed, diagnose detection, retrieval, provider, or rendering delay and disclose the supported operating envelope rather than hiding it with averages.

## M3 — Complete the study-to-meeting workflow

Addresses R07, R08, R10 and the preparation, generality, retrieval, and presenter-UX improvements.

- [ ] Use one admitted-source inventory and one active pack. Bridge existing document/spreadsheet ingestion and the whiteboard's folder input; preserve file/page/sheet/cell locators.
- [ ] Exclude hidden descendants by default; test containment, symlinks, nesting, encoding, unreadable files, and size limits. Show truthful skipped reasons, including size caps rather than labeling every skip “non-text.”
- [ ] Bound long chunks/CSV rows, fit evidence budgets safely, and retain smaller valid matches when one candidate is oversized.
- [ ] Build/reuse indexes on content-hash changes; remove repeated whole-corpus chunking from the hot path. Add Unicode/short-entity tests and keep domain weighting out of generic policy.
- [ ] Connect Study Bundle export, manual model-analysis return, local optional preparation, human review, and reviewed-card import into one understandable workflow.
- [ ] Add readiness indicators: covered likely questions, unresolved disagreements, missing facts, skipped documents, and stale study artifacts.
- [x] Persist accepted answer revisions automatically to the correct session, including evidence/provenance and actual engine identity; restore on reopen and export from saved state. Clear preserves history; full process-crash validation remains pending.
- [ ] Add retention/deletion controls and visible write/export failures. Test unexpected termination and a new session without prior manual export.
- [ ] Preserve a quiet presenter UI with short answers, evidence inspection, pin/dismiss, pause assistance, and explicit uncertainty/provider states.
- [x] Add a historical-discussion corpus alongside hospitality and product-pitch examples to prove domain neutrality and disagreement handling.

Gate:

- [ ] A user can import documents, study, approve preparation, enter a conversation, inspect a cited answer, and reopen its saved notes without command-line intervention for normal operation.
- [ ] The three domain fixtures exercise prepared, retrieved, calculated where applicable, contested, interpretive, and missing-evidence answers through the same production path.
- [ ] No answer depends on a hidden/unapproved file or a stale preparation hash; import and saved-note failure paths are visible and recoverable.

Subscription/cost boundary: retain the existing manual, provider-neutral study import as the baseline. Do not make undocumented ChatGPT UI automation or an assumed subscription API entitlement a dependency. Any future automated subscription adapter needs separate verification of a supported interface. Show any optional live API usage explicitly; local mode must be both network-bounded and honestly benchmarked.

## M4 — Verify the pilot and prepare a responsible public release

Addresses R14/R15 completion and all release acceptance gates.

- [x] Run the full current Swift gate, whiteboard end-to-end replay, lint, client/server checks, bench security tests, and a new whiteboard-enabled UI smoke scenario. September 9 final working-tree rerun: 1,067 Swift tests, 12 UI tests, 9 bench tests, core correctness and lint pass; repeat on the eventual release SHA.
- [ ] Build the release app without installing over an existing app during automated verification. Inspect the actual packaged bundle identity, updater configuration, entitlements, dependencies, and version.
- [ ] Choose a fork-owned app/bundle/URL/storage identity; implement an explicit, non-destructive migration and rollback path. Preserve upstream attribution and required license notices.
- [ ] Fix README downloads, release workflow repository targets, support links, and update feed/key ownership. Keep updates disabled until the fork's signing/update chain is tested.
- [ ] Complete a consented 31-minute Teams test using `docs/teams-audio-verification.md`: both audio tracks, checkpoint evidence, at least 98% coverage, and no unrecovered gap longer than two seconds under that verifier.
- [ ] Separately test selected-window and full-display screen sharing with whiteboard/panels hidden and visible, toggling during a call. Record what the remote participant actually sees; `sharingType` readback is not sufficient. Do not promise full-display invisibility without proof.
- [ ] Exercise interruptions, topic/year corrections, no-corpus, missing facts, provider failure, revocation, stop/start, and corpus changes in a supervised meeting replay/live pilot.
- [ ] Review the remaining release-build concurrency warnings in AudioRecorder and StreamingTranscriber with targeted audio-conversion tests; separately clean up redundant awaits/immutable-local warnings without treating warning removal as concurrency proof.
- [ ] Test a clean profile/clean installation beside upstream, local mode, required macOS permissions, and recovery after restart. Record managed-device limitations separately from Microsoft 365 tenant permissions.
- [ ] Update contributor setup, architecture, privacy/data-flow disclosure, cost model, supported OS/provider matrix, security reporting, dependency/license inventory, and release/rollback checklist.
- [ ] Scan staged content and intended release artifacts for keys, private corpus files, audio/transcripts, private absolute paths, and unrelated work. Publish only synthetic/redacted evidence.

Public-release gate: no unresolved P1 findings in shipped paths; all required automated gates pass on the release SHA; operator-observed capture/share tests are recorded; installation and update destinations belong to this fork; remaining limitations are documented. Any excluded experimental bench feature must be clearly excluded from the support/release claim.

## September 9 scope decisions and remaining sequence

- Consolidation replaces the native prototype's independent listener/answerer; its self-grounding boolean, eight-second cadence, cached OpenRouter eligibility and raw-folder fallback are not used by production. The old prototype types remain for isolated tests and are not release guarantees.
- Prepared local questions now run immediately, including a lone question followed by silence. The originally proposed replacement debounce timer is unnecessary for that path. A broadly capable model-based detector and its budgets are still M2 work; no such provider has been silently enabled.
- Added findings while implementing: timestamp-only session IDs merged rapid sessions/imports; reviewed missing-data answers were displaced by generic passage previews; detector tests depended on actual running apps. Fixes and observed tests are in the progress ledger.
- The unlocked-desktop retry cleared the authentication blocker and exposed an app-launch ownership bug: both executable wrappers read a temporary App's body. Both now launch the actual root App, preserving SwiftUI state/delegate ownership and the production domain registry. The whiteboard UI scenario now passes through opening a source excerpt; the test host exits outside explicit test mode. Captured screenshots were inspected locally.
- All 12 UI smoke tests now pass, including onboarding, recording consent, notes/history, session controls, settings and the whiteboard. One intervening runner launch lost its process handshake; the successful full run and earlier failures are recorded separately rather than treating the original authentication failure as an app failure.
- Next: integrate loose-document ingestion, Study Bundle export/return and human review into one preparation flow, expand readiness and the adversarial/correction matrix, and benchmark the supported live path. Run the consented Teams/share pilot after capture/conversion review, then finalize fork identity/signing. A controlled prepared-pack rehearsal can precede the broader workflow's completion; it is not a general-purpose or release-ready pilot.
- Actual effort so far is one implementation session on September 9, not 14–20 completed engineering days. Original estimates above remain the planning baseline; no public-release date has been certified. No commits, pushes, paid model calls, real recording or installation over the existing app were performed in this pass.

## How progress should be reported

For every implementation change, update this tracker with:

- Finding IDs and checklist items completed.
- Commit/PR and exact tests/evidence.
- User-visible behavior changed.
- Planned effort versus actual effort and any scope change.
- Remaining blocker or next item.

Do not check off a milestone because code is written or a narrow unit test passes. Link the milestone gate evidence. Keep source snapshots, local test results, live operator attestations, commits, and pushes as distinct states.

Suggested commit sequence: baseline tests/containment → result contract and gated whiteboard → lifecycle/corpus isolation → outbound policy/logging → cadence/dedup/provider behavior → bench timing/reset → corpus/preparation/persistence → full-path verification → release identity/docs. Keep independent fixes reviewable; avoid mixing broad formatting or unrelated bench edits into trust-boundary changes.

## Deliberately deferred

Not required for this iteration: a meeting bot, Graph/Entra integration, tenant-admin deployment, Notion as the real-time processing engine, automatic web research, more personas, a proprietary vector database, mobile clients, or elaborate multi-agent orchestration. Export/integration conveniences can follow once the core is reliable.

Outstanding user/operator choices before M4, not blockers for M0–M3 planning: public app name and signing ownership; consenting test participant/time; retention preference; whether the experimental bench ships with a supported release. A new provider, paid service, external disclosure, or broad migration requires its own explicit authorization.
