# Knowledge Copilot — first remediation pass

September 9, 2026. Working tree based on `3063012f20e52088cd83e79f994fde44d818497d`, branch `feat/native-whiteboard-port`.

## What changed, plainly

The native whiteboard now consumes the project's existing source-checked answer engine instead of asking a separate model to answer and certify itself. It requires a validated corpus, shows citations and uncertainty, rejects results from retired sessions/corpora, and automatically saves accepted answers to the correct meeting.

This is a substantial foundation repair, **not the finished product or a public-release approval**. The current native path handles prepared/term-matched questions and claims locally. A general-purpose frontier-model listener that recognizes arbitrary questions is still future M2 work. Heavy model study and human review remain the intended preparation model; no paid live provider or subscription automation was enabled.

Editable plan: [milestone checklist](2026-09-09-remediation-plan.md). Historical findings: [baseline review](2026-09-09-project-review.md). Captured verification excerpts: [evidence](evidence/2026-09-09-remediation-verification.txt).

## Planned versus actual

| Milestone | Original estimate | This pass | Still needed |
| --- | --- | --- | --- |
| M0: baseline/containment | 1 engineering day | Containment, deterministic test seams, safe bench exports/rendering, reproducible local verification command | Keep gates on the eventual committed/release SHA |
| M1: trust/lifecycle | 4–6 days | Shared evidence engine; session/event/pack identity; stale-result rejection; explicit missing/conflicting evidence; scripted whiteboard UI verified | Broader end-to-end adversarial and transport-permission matrix; real-meeting verification |
| M2: live usefulness | 3–4 days | Lone prepared question works; partial/final upserts; changed-year regression; one selected live owner; bench timing/reset fixes | General model question detection, optional adapters, deadlines/backoff/queue stress, real detection-recall and end-to-end latency/cost measurements |
| M3: preparation/history | 3–4 days | Automatic cited history and restore; initial coverage/gap/disagreement summary; third domain fixture; prototype corpus admission/chunking fixes | Unified loose-document import → study → human review UX; richer readiness; pin/dismiss/pause; force-quit recovery and retention choices |
| M4: pilot/release | 3–5 days | All 12 UI smoke tests pass; launch/accessibility fixes; update checks disabled; unsafe release claims corrected | Consented Teams/share run; fork identity/migration/signing; package/clean-install/release checks |

Actual effort recorded here is one implementation session, not completed days against every estimate. The original 14–20 engineering-day range remains a planning baseline, not a promised launch date. No user/operator live acceptance has been recorded.

## Changes and finding coverage

### Native authority and lifecycle — R01, R02, R03, R04, R05, R06, R09, R11

- `AppContainer` and the root app now inject one `KnowledgePackStore`. The production whiteboard no longer constructs an OpenRouter listener/answerer or reads a loose corpus folder.
- `SidecastWhiteboardCoordinator` is a main-actor lifecycle/presentation bridge to the existing detector, resolver, evidence evaluator and accepted overlay-card contract. General-knowledge fallback and model-declared grounding are absent from this production path.
- Displayed and saved notes carry actual session ID, event/revision ID, pack ID/hash, evidence state, source locators/excerpts, provisional/historical status and actual engine identity (`local-knowledge-pack`). A configured chat model is not falsely reported as having answered.
- End, clear, disablement and corpus changes invalidate current work. Immediate delivery rechecks lifecycle and stream generation. Failed corpus selection pauses assistance; historical answers retain their original provenance. A load-generation token guards superseded loads, including returning to an earlier path.
- Accepted history writes are serialized and use immutable session-specific snapshots. A previous accepted answer may finish saving to its own session, but unfinished answers cannot publish after stop/new-session/clear.
- The shared prepared-question detector processes a lone question without waiting for another utterance or the prototype's eight-second cadence. Partial/final revisions upsert one event; a changed year is not dropped by the old lexical duplicate filter.
- When the whiteboard owns the live path, legacy suggestions/Sidecast do not receive duplicate utterances or start classic prefetch. Those older modes remain available separately when the whiteboard is disabled. Their own data settings still apply.
- Removed raw question/error content from the retained prototype listener/orchestrator log messages. No provider was called during verification.

The obsolete standalone listener/orchestrator types remain for isolated tests, but have no production construction call sites. They are not an alternate supported live engine. Broad detection, retries, model cost reporting and richer outbound permissions still need the planned adapter work. Local whiteboard processing does **not** imply local transcription or an entirely offline app.

### Corpus and notes — R07, R08, R10

- Production answers use only the selected, validated KnowledgePack. The prototype text utility now excludes hidden descendants and escaping symlinks, caches chunks after reading, bounds long lines, limits repetitive file domination and skips candidates that do not fit instead of stopping before smaller matches.
- Every accepted whiteboard revision is atomically upserted to `sessions/<id>/whiteboard.json`. A new session or Clear does not silently destroy earlier history. History & export can reopen the most recently saved board, with its evidence, and export it.
- Save/read failures are visible. Source excerpts and paths are plaintext local session data; the privacy documentation now says so. Session deletion includes the archive; the regression checks its move into the existing recoverable recently-deleted folder. No automatic retention timer or broad deletion was added.
- The preparation disclosure reports reviewed question families, known gaps, disagreements and cards awaiting review. These are inventory counts, not a recall or accuracy score. Source changes still require a pack reload.
- Added the entirely fictional Aster historical-discussion pack with no domain profile. Through the production whiteboard it retains conflicting accounts, labels interpretation, abstains on an unknown chairperson, and does not follow an untrusted marginal instruction. It makes no claims about actual history or religion.

### Bench safety and correctness — R12, R13a/b/c

- API keys remain in tab memory; preferences and exports omit them, and previously persisted keys are purged on load. Transcript/persona/answer rendering uses text nodes and validated colors instead of raw dynamic HTML.
- Client and server TypeScript checks are part of `npm run verify`; the deep transcript import has a typed declaration. Added a bench CI workflow. The proxy binds loopback and no longer grants wildcard cross-origin transcript access.
- Caption normalization uses the actual parsed format: legacy seconds remain seconds, srv3 milliseconds are converted. Tests drive the installed parser with synthetic XML; small offsets and invalid values are covered. No live YouTube request was made.
- Source/position reset aborts and retires old transcript, summary and answer work. Late transport completion cannot commit old results. Inactive player clocks are ignored, and stale YouTube ready/state callbacks cannot regain control after a source switch. Existing paste/virtual-player work is preserved.
- This does not turn the experimental bench into the native evidence-gated product. Its broader persona/research modes remain outside a supported-release claim. Real browser/UI and provider-matrix verification are still pending.

### Containment and verification — R14, R15

- The whiteboard defaults off; explicit activation and its current capability limits are visible.
- Automatic/manual update checks are disabled and upstream feed/key values removed from the source plist. README download wording now identifies upstream builds as upstream, not this fork. App/bundle/storage identity and release workflow ownership still require M4 decisions.
- Panel tests no longer presume a universal macOS capture-state transition or object identity. Injected readback exercises fallback reconstruction while preserving content/frame checks. Documentation and the whiteboard warn that a sharing-policy readback does not prove remote invisibility.
- Added `testWhiteboardDisplaysCitedAnswerFromScriptedConversation` with a synthetic product-pitch pack, scripted transcription, citation inspection and a share-warning assertion. The initial run was authentication-blocked; an unlocked-desktop retry ran and exposed the additional launch/accessibility defects below. After fixes, the focused scenario passed and its captured window screenshot was inspected with the source excerpt expanded. This is scripted text, not microphone capture or a live meeting.
- Canonical lint now includes the rewritten coordinator, archive/readiness types and native integration tests. A single local command runs Swift, correctness, lint and both bench type checks/tests; UI execution is a separate explicit opt-in.

### Additional bugs discovered and fixed during implementation

1. **Rapid sessions/imports could share an ID.** Second-resolution timestamps allowed two sessions to overwrite metadata and merge saved answers. New IDs retain the readable timestamp and add a UUID. Same-date imports and immediate restart/history separation are regression-tested; no existing session identity was migrated.
2. **A reviewed missing-data answer could disappear.** Warm keyword retrieval could replace a reviewed abstention with a generic related-passage preview. The common resolver now requires actual verified evidence to improve that answer; a core test and the historical whiteboard test cover it.
3. **Tests depended on the user's running apps.** Meeting-detector tests mocked microphones/cameras but scanned real applications, failing when Teams was open. The scanner is now injectable; tests specify inventories, including positive Teams/custom-app cases. Default production scanning remains in place. The full suite now runs without the old CI exclusion.
4. **A lifecycle test raced its own delay.** Its five-second finalization wait equaled the repository's deliberate five-second delayed transcript write. Added bounded scheduling margin while retaining the completion/count assertions; no production behavior was weakened.
5. **Saved-history containment differed for missing directories.** Canonical path-component comparison now avoids URL directory-trailing-slash identity differences after deletion while still rejecting traversal/escaping symlinks.
6. **The root App was not installed by SwiftUI.** Both executable wrappers read `OpenOatsRootApp(...).body` from a temporary instance. The real UI test transcribed and resolved a question, but the whiteboard did not auto-open. Both entry points now call the root App's launch method, retaining state/delegate ownership; the production hospitality registry is supplied before launch. The test host refuses to launch without explicit UI-test mode, so opening its binary cannot fall back to live storage or recording services.
7. **Whiteboard accessibility and evidence interaction were fragile.** A root identifier propagated over the sharing-warning identifier. Removed that unused container identifier, read macOS text from AXValue in the test, and made the entire Evidence label an accessible button with explicit expanded/collapsed state. The UI test now clicks it and verifies the visible source excerpt; the successful screenshot shows the answer, warning, provenance, link and excerpt.

## Observed verification

Environment: macOS 26.3.1(a), build 25D771280a; Xcode 26.6 (17F113); Swift 6.3.3; Node 26.7.0. Working-tree changes are uncommitted; HEAD remains the baseline above.

| Check | Observed result | What it does not prove |
| --- | --- | --- |
| `bash scripts/verify_knowledge_copilot.sh` | PASS | Does not include UI tests unless explicitly opted in |
| Full `swift test` | **1,067 tests, zero failures, no exclusions**, rerun after final launch/view fixes at 16:37 | Not a real meeting or remote screen-share test |
| KnowledgePack correctness gate | PASS; existing 101/101 scenarios, 2/2 cross-pack scenarios, zero false cards | Original golden gate remains two-domain; third-domain native integration is tested separately |
| Canonical Swift lint | PASS, including new canonical whiteboard files | Legacy style exclusions remain documented in the script |
| Bench `npm run verify` | PASS: client and server type checks; **9 tests, zero failures** | Strict DOM/test doubles, not a real browser penetration test |
| Native three-domain loaded-pack replay | Latest 30/30 prepared responses checked; p50 0.8605 ms, p95 1.5495 ms, max 1.58675 ms; zero answer-model calls | Synthetic final-text-to-accepted-model timing only; excludes capture, STT, cold loading and actual window rendering |
| Whiteboard-enabled UI smoke | PASS on unlocked retry after fixes: 1 test, zero failures, 7.640 seconds; expanded-source screenshot inspected | Scripted conversation only; not actual audio latency or remote share/capture acceptance |
| Full UI smoke regression after launch/view fixes | PASS: **12 tests, zero failures**, 91.204 seconds; includes whiteboard, consent, setup, settings, notes, history and session controls | Not a real meeting; one earlier isolated runner attempt lost its process handshake and a fresh retry was required |
| Test-host standalone guard | Running the built host with `OPENOATS_UI_TEST` removed exited successfully without opening a window or starting app services | Applies to this test host, not the production executable |
| Final `swift build -c release` | PASS after launch/view fixes, 73.50 seconds; warnings remain in untouched code | No packaged, signed, installed or supported binary claim |

Earlier intermediate runs exposed and drove the fixes above. They are not hidden by counting only a focused pass: a final combined run includes the entire Swift suite, the correctness gate and bench checks. The first release compile was invalidated by a source edit while compilation was in progress; the rerun with Swift sources frozen passed. Node 26 reports a dependency-loader deprecation warning; bench checks still pass.

Release compilation still warns about captured mutable values in `AudioRecorder.swift` (`consumed`) and `StreamingTranscriber.swift` (`inputBuffer`), redundant awaits in `BatchTextCleaner.swift`, and an immutable local in `SuggestionEngine.swift`. These files were not changed in this pass. The capture/conversion warnings need targeted concurrency review and tests before the pilot; a successful build alone does not dismiss them.

September 10 follow-up: the focused stereo/callback fix and its current verification
are documented in [stereo audio preflight](2026-09-10-stereo-audio-preflight.md).
That work addresses the two conversion captures and adds production-path tests;
it does not replace the real Teams audio/share acceptance gates below.

## Next work and user/operator dependencies

1. Whiteboard scripted UI/layout/source inspection and the full 12-test UI smoke regression are now complete. Real capture/conversion review and a supervised Teams/audio/share pilot remain; no authentication action is currently required from the user.
2. Complete the single preparation/import workflow and expand the adversarial/correction/recall matrix. Keep manual subscription-assisted study and human review as the default; do not assume a subscription is an API entitlement.
3. Design/verify broader model question detection and any explicitly enabled external adapters against the same evidence contract, with budgets, revocation, deadlines and measured latency/cost. Do not resurrect model self-certification.
4. Run the consented Teams/audio/share pilot. No Microsoft 365 tenant-admin integration has been introduced. Device permissions and organizational recording rules still apply.
5. Resolve public app name, bundle/storage migration, signing/update ownership and clean-install/release checks before a supported binary launch.

No commit, push, remote write, private-corpus upload, paid model call, real meeting recording, or installation over the existing app was performed. Original debug-bench edits were retained; the new reset integration necessarily adds narrow changes to its existing `main.ts` and `player.ts`. Review those overlapping files before staging. The existing `dist/OpenOats.app` was left untouched.
