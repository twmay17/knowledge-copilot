# Verification Record — August 14, 2026

## Environment

- macOS 26.3.1 (25D771280a), Apple Silicon
- Xcode 26.6 (17F113)
- Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`)
- Apple clang 21.0.0 (`clang-2100.1.1.101`)
- Developer directory: `/Applications/Xcode.app/Contents/Developer`

## Passing product-path checks

The following commands pass from `OpenOats/`:

```bash
swift build
swift build -c release
swift test --filter KnowledgePackLoaderTests
swift run knowledge-pack validate ../fixtures/knowledge-packs/minimal-hospitality
swift run knowledge-pack inspect ../fixtures/knowledge-packs/minimal-hospitality
```

The focused test run executes six tests with zero failures. It covers:

- a structurally valid pack;
- calculated-card derivation requirements;
- evidence ownership;
- fail-closed unknown DomainProfile behavior;
- fail-closed unregistered hospitality predicates;
- app-level loading and summary of the on-disk synthetic fixture.

The CLI validates the fixture as one source, one passage, three assertions, and one reviewed
response card. The expected 2020 RevPAR is $89.50, derived from $3,266,750 room revenue divided by
36,500 available room nights.

Strict Swift-format lint passes for all newly added KnowledgePack, DomainProfile, app-store, CLI,
and focused-test files. `git diff --check` also passes.

## Complete inherited-suite baseline

`swift test` compiles and executes the complete upstream suite under full Xcode:

- 706 tests executed;
- 702 passed;
- 4 assertions failed;
- all six KnowledgePack/DomainProfile/app-load tests passed.

Observed baseline failures:

1. `AppCoordinatorIntegrationTests.testUserStoppedFinalizesSessionAndRefreshesHistory` timed out
   waiting for a finalized session.
2. `MeetingDetectorTests.testMicAloneDoesNotTriggerDetection` failed two assertions while the real
   Microsoft Teams process was running.
3. `MeetingDetectorTests.testQueryCurrentStateIncludesCamera` detected the running Microsoft Teams
   app where the test expected no meeting app.

These failures are outside the newly added product path and are retained as baseline work. The
detector tests should inject process state or run in a controlled environment; the finalization
test should use deterministic synchronization rather than a timing assumption.

## Remote CI status

The existing macOS 26 workflow now also validates the synthetic KnowledgePack. It has not run
remotely because this local repository intentionally has no invented public `origin`. Remote CI is
pending an authorized GitHub destination.
