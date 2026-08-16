# Overlay operator controls

The answer overlay is designed to remain nonactivating so the meeting application keeps focus. Its operator controls therefore support both direct pointer use and dedicated global keyboard shortcuts while the overlay is visible.

## Keyboard controls

The keyboard target is selected deterministically:

1. The active remote-speaker answer.
2. The newest other active answer.
3. The newest non-superseded pinned answer.

The target card is labeled `Shortcut target` in the overlay. Shortcuts are monitored only while an overlay panel is visible.

| Action | Shortcut |
| --- | --- |
| Copy the answer, evidence state, reason, and source labels | `Option-Shift-Command-C` |
| Open the first available corpus source | `Option-Shift-Command-E` |
| Pin or unpin the target answer | `Option-Shift-Command-P` |
| Mark the target answer for correction review | `Option-Shift-Command-W` |
| Dismiss the target answer | `Option-Shift-Command-X` |
| Toggle compact answer cards | `Option-Shift-Command-K` |

The three-modifier chord avoids ordinary typing and reduces conflicts with common meeting controls. The existing overlay show/hide shortcut remains `Shift-Command-O`.

## One-action source inspection

When a card contains an openable corpus file, its action row includes an `Open first source` button. The button and keyboard shortcut open the first eligible source directly; the evidence disclosure does not need to be expanded first.

Only file URLs already resolved inside the selected knowledge-pack root are eligible. Retrieval-only records without a safe file URL remain visible as evidence but cannot be opened as files.

## Copy and compact mode

Copy produces a plain-text block containing:

- the answer title and answer;
- the explicit evidence state;
- the explanation shown under `Why`; and
- each source title and locator.

Compact mode retains the evidence-state badge, answer, target state, and action row. It collapses the longer reasoning, claim, calculation, and evidence sections without changing the underlying answer or citations.

## Share-safe behavior

`Hide from screen sharing` changes the AppKit window sharing type at runtime for the classic overlay, Sidecast overlay, mini bar, and other app windows.

This is a window-capture control, not a guarantee for full-display capture. The overlay therefore always shows one of two explicit notices:

- With exclusion on: window capture is protected where macOS supports it, but full-display sharing may still expose the overlay.
- With exclusion off: both window and full-display sharing may expose the overlay.

The recommended Teams workflow is to share a single application window, not the entire display. This behavior requires no Microsoft 365 administrator permission or Teams integration.

## Trust boundaries

These controls do not expand the answer engine's authority. Copy, compact, pin, and source inspection operate only on the corpus-grounded presentation already produced by the evidence-first resolver. Opening a source never triggers web search or a new model request.
