# Upstream and Toolchain Baseline

Recorded on August 14, 2026 before product-specific changes.

## Upstream pin

- Repository: `https://github.com/yazinsai/OpenOats.git`
- Remote name: `upstream`
- Branch: `main`
- Pinned commit: `b9202381082f24332ba3e8a249e4cedde8daa317`
- Commit date: `2026-08-14T18:10:42+03:00`
- License: MIT; the original `LICENSE` and copyright attribution remain intact.

The public fork/origin remote is intentionally not invented locally. Add it when the project has an authorized GitHub destination. Until then, `upstream` is the only configured network remote.

## Local toolchain

- Hardware: Apple Silicon Mac
- Operating system: macOS 26.3.1, build 25D771280a
- Xcode: 26.6, build 17F113
- Swift: 6.3.3 (`swiftlang-6.3.3.1.3`)
- Apple clang: 21.0.0
- Active developer directory: `/Applications/Xcode.app/Contents/Developer`
- Full Xcode: installed; license accepted and first-run system components installed

The repository pins Swift `6.3.3` in `.swift-version`. The package itself declares Swift tools version 6.2 and macOS 15 as its minimum platform, so compatible Swift 6.2 language semantics remain explicit while the build uses Xcode's supported compiler.

## Baseline verification

| Command | Result | Meaning |
|---|---|---|
| `cd OpenOats && swift build` | Pass | The application and library compile with the installed Command Line Tools. |
| `cd OpenOats && swift test` | 702/706 pass | XCTest runs. Four inherited/environment-sensitive failures remain: one finalization timing failure and three meeting-detector assertions while Microsoft Teams is running. |
| `cd OpenOats && swift test --filter KnowledgePackLoaderTests` | Pass | All five new contract/profile tests pass. |
| `xcodebuild -version` | Pass | Xcode 26.6 (17F113) is selected. |

The complete suite now executes locally. Its remaining failures are recorded baseline debt rather than KnowledgePack regressions; the meeting-detector cases observe the real running-app environment and found Microsoft Teams. CI remains configured for `macos-26` and explicitly selects Xcode 26 before building and testing.

## Baseline warnings to triage

The upstream build currently emits warnings including:

- mutable captures used by audio conversion callbacks under Swift concurrency checking;
- a captured input buffer referenced by a concurrently executing closure;
- unnecessary `await` expressions in batch text cleanup;
- an upstream suggestion-engine local that can be a constant.

These warnings are recorded as inherited baseline debt. Product code should not add new concurrency warnings, and the inherited warnings should be reduced in isolated changes rather than mixed into the first KnowledgePack contract.

## Repeatable commands

```bash
cd OpenOats
swift package resolve
swift build -c debug
swift build -c release
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift test --skip MeetingDetectorTests
```

The final `swift test --skip MeetingDetectorTests` command uses the selected full Xcode
toolchain; MeetingDetector tests require live meeting-app state and are exercised manually
(consistent with README.md and CI).
