# Evidence-first overlay

The overlay is the presenter-facing trust boundary between live transcript events and the selected
KnowledgePack. It renders resolver updates; it does not search, browse, or decide that retrieved text
is true.

## Card hierarchy

Every card uses the same reading order:

1. Explicit evidence label and icon, with color used only as a secondary cue.
2. Answer title and the shortest corpus-grounded answer that can be stated safely.
3. **Why**, explaining the evidence decision or abstention in plain language.
4. Attributed claim lines when competing or interpretive material must remain visible.
5. Collapsed calculation and evidence sections that can expand without pausing resolution.
6. Pin, correction-review, dismiss, and open-source actions.

## Evidence states

| State | Presenter meaning | Required behavior |
| --- | --- | --- |
| Directly Sourced | A named source states the value | Show the source and locator |
| Calculated | Cited inputs produce the value through a recorded calculation | Keep the expression and inputs expandable |
| Supported by Corpus | Multiple corpus records support the claim | Preserve supporting records |
| Contradicted by Corpus | A spoken claim conflicts with the typed corpus value | State the conflict and show the corpus value |
| Contested | Comparable corpus claims disagree | Show every competing value with attribution |
| Interpretive | The corpus contains an attributed interpretation | Preserve the author/source; never present it as direct fact |
| Not Found in Corpus | No admissible answer exists | Abstain explicitly |
| Needs Clarification | Context is missing, retrieval is incomplete, or a possible match is unverified | Ask for context or source verification |

Warm-lane retrieval is always shown as **Needs Clarification** until the evidence evaluator or a
reviewed card establishes a stronger state. A similarity score is not a truth score.

## Update lifecycle

| Resolver action | Overlay behavior |
| --- | --- |
| `show` | Add the fastest admissible card for the event |
| `supersede` | Replace the earlier card only when revision and update lineage allow it |
| `refine` | Improve presentation without weakening evidence support |
| `retract` | Remove the active card; retain a user-pinned copy as a visibly superseded snapshot |

Dismissed event IDs remain tombstoned for the loaded pack session. This prevents a slower warm or
cold result from resurrecting an answer the presenter intentionally removed. Same-revision late
updates also cannot roll a card back over an admitted refinement.

## Presenter actions

- **Pin** moves the current event into a persistent area so the next question can appear beside it.
- **Dismiss** removes the event and suppresses its later resolver updates for the current pack
  session.
- **Mark for correction** records the exact event, update, answer, and evidence state for a review
  workflow. It never edits the corpus during a call.
- **Open source** uses the locally validated source URL. Relative KnowledgePack paths are resolved
  only when they remain inside the selected pack directory.

## Model boundary

Optional cold-lane synthesis receives only admitted evidence records. Its overlay payload carries the
underlying evidence outcome as well as the model output, allowing the UI to retain cited claims and
openable source references. The overlay has no network or tool callback and cannot broaden the
corpus.

## Microsoft 365 boundary

This feature is local to OpenOats and the existing screen-share-hidden macOS panel. It requires no
Teams bot installation, Graph API consent, tenant application registration, meeting-policy change,
or Microsoft 365 administrator access. Teams is an audio source to the capture path, not an
integration dependency for the evidence UI.
