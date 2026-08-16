# Evidence-first overlay verification — 2026-08-15

## Scope

- Convert every tiered resolver payload into a presenter-safe overlay card.
- Display all eight evidence states with text and icons rather than color alone.
- Preserve contested and interpretive attribution.
- Keep source excerpts and calculation details collapsed until requested.
- Support pin, dismiss, correction-review, and open-source actions.
- Prevent stale, retracted, or dismissed updates from misleading the presenter.
- Keep the feature local and independent of Microsoft 365 administrator access.

## Focused verification

```text
swift test --filter KnowledgeOverlayPresentationTests
13 tests passed
```

The suite covers explicit state language, contested attribution, constrained-synthesis citations,
retrieval abstention, tier refinement, stale update rejection, pinned snapshots, dismiss tombstones,
correction requests, pack reset, live store-to-overlay wiring, and source-path containment.

```text
swift test --filter KnowledgeTieredAnswerResolverTests
12 tests passed

swift test --filter KnowledgeAnswerCardResolverTests
7 tests passed
```

## Broad regression

```text
swift test --skip MeetingDetectorTests
859 tests passed, 0 failures
```

`MeetingDetectorTests` remains excluded because it depends on live host applications and permissions;
this is the repository's existing non-environmental test boundary.

## Release builds

```text
swift build -c release --product OpenOats
Build complete

swift build -c release --product knowledge-pack
Build complete
```

Release output contains only pre-existing warnings in unrelated audio, transcription, and suggestion
sources.

## Static checks

```text
swift format lint --strict \
  Sources/OpenOats/App/KnowledgeOverlayPresentation.swift \
  Sources/OpenOats/App/KnowledgePackStore.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeTieredAnswerResolver.swift \
  Sources/OpenOats/Views/KnowledgeAnswerCardView.swift \
  Tests/OpenOatsTests/KnowledgeOverlayPresentationTests.swift

git diff --check
```

Both checks passed. The two existing panel containers retain their established four-space style; each
has only a one-line visibility-source change.

## Acceptance evidence

- [x] States are clear without relying only on color.
- [x] Answer, evidence state, why, and source use a consistent hierarchy.
- [x] Contested and interpretive cards preserve attribution.
- [x] Long evidence and calculations expand locally without blocking resolution.
- [x] Cards can be pinned, dismissed, marked for correction review, or opened at a contained source
      path.
- [x] Raw retrieval cannot appear as verified corpus support.
- [x] No Teams bot, Graph permission, tenant app, or MS365 admin role is required.

## Publication status

The implementation and this evidence remain intentionally uncommitted. The preceding resolver scope
was published separately as `fe451b82e95e318104294dddd49188edcc2d7b45`; a new explicit commit
authorization is required before publishing this overlay scope.
