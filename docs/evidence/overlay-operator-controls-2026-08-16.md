# KC-22 overlay operator controls — verification evidence

Date: 2026-08-16

Status: implemented, verified, and approved for publication.

## Acceptance evidence

### Core controls work without a mouse

- The overlay remains a nonactivating `NSPanel`, preserving focus in Teams or another presentation application.
- Keyboard monitoring starts only while a Classic or Sidecast overlay is visible and stops when the overlay is hidden or closed.
- Dedicated `Option-Shift-Command` shortcuts cover copy, open source, pin, mark wrong, dismiss, and compact mode.
- The active remote answer is the deterministic first keyboard target; fallback ordering is tested.
- The target card and shortcut guide are visible in the overlay.

### Evidence opens in one action

- Each card with an eligible corpus file exposes an `Open first source` action without requiring the Evidence disclosure to be expanded.
- `Option-Shift-Command-E` opens that same deterministic source.
- Source URLs continue to be admitted only when they resolve inside the selected knowledge-pack root.

### Full-display sharing produces a clear warning

- Classic and Sidecast always show an explicit full-display warning.
- With capture exclusion enabled, the warning explains that whole-display sharing may still expose the overlay and recommends sharing a single app window.
- With capture exclusion disabled, the warning explicitly states that window and full-display sharing may expose the overlay.
- The settings description no longer claims that the app is universally invisible during sharing.
- Existing overlay and mini-bar panels update their AppKit sharing type at runtime.

## Verification commands

```text
swift test --filter KnowledgeOverlayPresentationTests
17 tests, 0 failures

swift test --skip MeetingDetectorTests
864 tests, 0 failures

swift build -c release --product OpenOats
passed

swift build -c release --product knowledge-pack
passed

xcrun swift-format lint --strict <new and previously formatted overlay files>
passed

git diff --check
passed
```

The release build emitted only pre-existing warnings in unrelated audio, cleanup, suggestion, and transcription files. No warning originated in the KC-22 implementation.

## Microsoft 365 constraint

No Microsoft Graph, Teams app registration, tenant installation, or Microsoft 365 administrator permission is required. The control layer operates locally on macOS around the meeting window.

## Product limitation preserved honestly

macOS window-sharing exclusion does not establish that a third-party meeting client will omit the overlay from a full-display capture. The product warns instead of claiming detection or protection it cannot guarantee.
