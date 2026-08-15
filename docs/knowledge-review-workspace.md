# Knowledge Review Workspace

KC-18 makes the final frontier-study review gate usable inside the OpenOats macOS app. It is a
native operator surface over the existing KC-16 review contract and KC-17 transactional importer;
it does not add a second trust path.

## Open and use the workspace

1. Select and validate the working KnowledgePack in OpenOats settings.
2. Prepare a pending review queue from that exact pack and a model-analysis JSON file:

   ```bash
   cd OpenOats
   swift run knowledge-pack prepare-study-review \
     <pack-directory> <analysis.json> --output <review-queue.json>
   ```

3. Open **Knowledge Review** from the main-window **Review** button or press
   **Command-Shift-R**.
4. Choose the pending review-queue JSON file.
5. Inspect every proposed question family and response card. Approve or reject each one and add an
   optional reviewer note when useful.
6. Confirm the named reviewer, then select **Preview Import**.
7. Inspect the validated state, counts, and resulting corpus hash.
8. Select **Apply Reviewed Import**, then confirm the write in the separate alert.

The queue is bound to the selected pack. Changing the selected pack clears the loaded review.

## Three-pane review surface

The left pane separates proposed question families, proposed response cards, contradictions, and
corpus gaps. It shows pending, approved, and rejected state without treating findings as decisions.

The center pane displays the material needed for an evidence-based decision:

- question variants, early-speech prefixes, aliases, and tags;
- proposed answer, evidence state, and caveat;
- typed assertions and their qualifiers;
- exact cited source excerpts, source titles, file paths, and locators;
- registered calculations, expressions, and input assertions;
- both sides of reported contradictions; and
- corpus gaps with explicit guidance to improve the source material rather than invent an answer.

The right pane requires a named reviewer and tracks pending, approve, and reject counts. Preview is
unavailable until every importable proposal has an explicit decision. Contradictions and gaps are
context for the reviewer and cannot be approved into the corpus by themselves.

## Fail-closed behavior

Before the workspace displays a queue, it reloads the active KnowledgePack, rebuilds its
deterministic Study Bundle, reconstructs the entire review queue from the embedded analysis, and
requires exact equality. A stale, mismatched, or modified queue is rejected.

Preview repeats the pack load and invokes the same `KnowledgeStudyReviewGate` used by the CLI. It
validates the named reviewer, decision completeness, proposal dependencies, evidence closure,
merged pack, Domain Profiles, and before/after content hashes. Editing any decision, reviewer name,
or note invalidates the prepared import and requires another preview.

Apply is a distinct confirmed action. It invokes the same locked, recoverable, idempotent
`KnowledgeStudyImportApplier` used by the CLI, including a final base-hash check under the exclusive
lock. On success, OpenOats reloads the active pack for live use and displays the receipt outcome and
resulting corpus hash.

## Deployment boundary

This workflow needs no Microsoft 365 or Teams administrator permission. Queue review, evidence
inspection, decisions, planning, application, and pack reload all happen locally. KC-18 makes no
model call, web request, or Microsoft Graph request. The frontier-model study step remains a
separate, user-operated preparation activity, so the app never silently promotes generated content
to reviewed knowledge.
