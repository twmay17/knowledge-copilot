# KC-17 Reviewed-Import Application Evidence

Date: 2026-08-15

Branch: `feat/teams-audio-verification`

Corpus: public synthetic `minimal-hospitality` fixture only

## Acceptance claim

A human-approved Study Analysis artifact can be previewed without mutation and applied to a
writable KnowledgePack through a fail-closed, locked, recoverable transaction. The application
rechecks the exact live corpus hash, imports only explicitly approved reviewed records, validates
the final on-disk pack, recovers interrupted mixed states, avoids duplicates, and returns a
machine-readable audit receipt.

This is a local boundary. It does not call a model, automate ChatGPT, search the web, access Teams,
or require Microsoft 365 administrator privileges.

## Automated tests

Focused application coverage:

```bash
cd OpenOats
swift test --filter KnowledgeStudyImportApplierTests
```

Result: 10 of 10 tests passed. They cover:

- read-only planning and the exact base hash;
- installation of only the approved question family and reviewed response card;
- a receipt with the exact resulting full-corpus hash;
- repeat-application idempotency;
- stale-corpus rejection before transaction staging;
- tampered result-hash rejection before mutation;
- rejection of a card whose status was changed back to `generated`;
- an exact match between approval decisions and included records;
- verified rollback after forced failure between the two live-file installations;
- recovery from a simulated journaled mixed state before a clean retry; and
- a validated `no_changes` result for a reject-only artifact.

The combined preparation boundary passed 31 of 31 tests:

```bash
swift test --filter \
  'KnowledgeStudyImportApplierTests|KnowledgeStudyReviewTests|KnowledgeStudyBundleTests'
```

Broad regression, excluding the known environment-sensitive detector suite while Microsoft Teams
was open:

```bash
swift test --skip MeetingDetectorTests
```

Result: 790 tests passed with zero failures.

## CLI acceptance

The release `knowledge-pack` executable was run against a temporary copy of the public fixture:

```bash
knowledge-pack plan-study-import <pack-copy> <approved-import> --output <plan>
knowledge-pack apply-study-import <pack-copy> <approved-import> --output <receipt>
knowledge-pack apply-study-import <pack-copy> <approved-import> --output <second-receipt>
knowledge-pack validate <pack-copy>
```

Observed results:

- hashes of both mutable JSONL files were identical before and after planning;
- plan state was `ready`;
- active/base hash was
  `9df58033540bc64272debe5abf4dbc02c062176328cdba72e576f63cca229b35`;
- first outcome was `applied`;
- final hash was
  `890ed3c631ea5a1ba7f546807d6074211e128e2de28dcaff5037418c53d602af`;
- second outcome was `already_applied`, with its before and result hashes equal;
- the installed pack validated with 10 response cards; and
- an attempted plan output inside the pack was rejected without creating that file.

The checked-in fixture was never used as an application target.

## Build and static checks

```bash
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats
xcrun swift-format lint --strict \
  Sources/OpenOats/KnowledgePack/KnowledgeStudyImportApplier.swift \
  Sources/OpenOats/KnowledgePack/KnowledgeStudyReviewGate.swift \
  Sources/KnowledgePackTool/main.swift \
  Tests/OpenOatsTests/KnowledgeStudyImportApplierTests.swift
jq empty ../schemas/study-import-plan-v1.schema.json \
  ../schemas/study-import-receipt-v1.schema.json
git diff --check
```

Both release products built successfully. The compiler repeated inherited warnings in unrelated
audio and intelligence code; KC-17 introduced no build failures. All changed Swift files passed
strict formatting, both public JSON Schemas parsed, and the final diff passed whitespace checks.

## Transaction boundary

Two independent JSONL files cannot be replaced by one POSIX rename. The implementation therefore
makes a narrower, testable claim: same-directory staged files, synchronized file and directory
metadata, an exclusive advisory lock, a synchronized recovery journal, original-file backups,
post-install full-pack validation, ordinary-error rollback, and next-run crash recovery.

The persistent lock file is inert when no process holds its operating-system lock. Transaction
staging, backup, and journal files are removed after success or verified rollback.

## Next product slice

The remaining manual step is reviewing JSON and authoring the decision file. The next slice should
render the existing queue and evidence in the macOS app, capture explicit human decisions, show the
read-only import plan, and require a deliberate Apply action. The reusable core trust boundary and
CLI remain authoritative underneath that UI.
