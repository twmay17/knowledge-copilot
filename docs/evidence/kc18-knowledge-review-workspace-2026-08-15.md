# KC-18 Public Evidence Summary — Knowledge Review Workspace

Date: 2026-08-15

## Claim

OpenOats now has a native, no-admin human-review workspace that carries an exact-pack-bound Study
Bundle analysis through explicit proposal decisions, read-only preview, and deliberate
transactional application without giving generated model output authority over the KnowledgePack.

## Implemented controls

- A dedicated **Knowledge Review** macOS window is available from the main window and application
  menu.
- The chosen queue is reconstructed from its embedded analysis and the active pack's freshly built
  Study Bundle; any mismatch fails before review.
- Proposed response cards are shown beside typed assertions, exact cited excerpts, source locators,
  and registered calculations.
- Contradictions and corpus gaps are visible as non-importable reviewer context.
- A normalized named reviewer and an explicit approve or reject decision for every importable
  proposal are mandatory.
- Any edit after preview invalidates the approved artifact and plan.
- Preview reuses the tested human-review gate and import planner without mutation.
- Apply requires a separate confirmation and reuses the locked, recoverable transactional applier.
- The active pack reloads after success, and the UI shows the receipt outcome and resulting corpus
  hash.

## Verification boundary

The focused workspace-model suite covers valid loading, tampered queues, reviewer and decision
requirements, preview invalidation, successful application, reject-only no-change imports, and
pack changes after queue load. Broader KC-15 through KC-18 regression checks, the non-environmental
package test suite, strict formatting of new and touched two-space Swift sources, whitespace checks,
and a release OpenOats build form the milestone verification set.

No private corpus, meeting audio, credentials, local filesystem paths, or proprietary underwriting
data is included in this evidence summary.
