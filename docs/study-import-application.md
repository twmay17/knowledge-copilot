# Reviewed Study Import Application

KC-17 is the write boundary between an approved frontier-analysis artifact and an active
KnowledgePack. It adds no model access and grants no model authority. Only records already marked
as explicitly human approved can cross this boundary.

## Safety contract

Planning is read-only. Before returning `ready`, the planner verifies:

- schema, pack, import, queue, analysis, and bundle identities;
- normalized reviewer and decision records;
- canonical ordering and unique decisions and approved record IDs;
- an exact match between `approve` decisions and included records;
- an exact match between all `reject` decisions and the rejected audit subset;
- `reviewed` status on every approved response card;
- the active full-corpus hash against `basePackContentHash`;
- the complete merged KnowledgePack and registered Domain Profiles; and
- the calculated merged hash against `resultingPackContentHash`.

A reject-only artifact is a validated `no_changes` plan. If the exact reviewed records and result
hash are already present, the plan and receipt report `already_applied`; no duplicate lines are
written.

## Transaction and recovery

Application takes an advisory exclusive lock inside the pack and reloads the active pack under that
lock. It then rechecks the base hash immediately before staging. This closes the gap between a
previous preview and the actual write.

The writer preserves existing JSONL bytes and appends only the approved, canonical JSON records to
two same-directory staging files. Before replacing either live file, it synchronizes the staged
files and writes a recovery journal. Each original is moved to a transaction-specific backup before
its staged replacement is installed. The complete on-disk pack is reloaded and its content hash
must equal the approved result hash.

A POSIX filesystem cannot atomically rename two independent files as one operation. KC-17 therefore
describes this accurately as a **recoverable transaction**, not an indivisible two-file rename. An
ordinary failure rolls both files back and verifies the original corpus hash. If the process or Mac
stops between replacements, the next apply operation reads the journal under the lock and either:

- finalizes a fully installed pack whose hash equals the approved result; or
- restores every available original backup and verifies the approved base hash before retrying.

Unsafe or malformed journal paths fail closed. The stable
`.knowledge-copilot-study-import.lock` file is intentionally retained; the operating-system lock,
not the file's mere presence, determines whether another writer is active.

## Commands

From `OpenOats/`, preview first:

```bash
swift run knowledge-pack plan-study-import \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../outputs/kc16-approved-import.json \
  --output ../outputs/kc17-import-plan.json
```

The plan command never changes KnowledgePack files. Apply only after inspecting a `ready` plan:

```bash
swift run knowledge-pack apply-study-import \
  <writable-pack-directory> \
  ../outputs/kc16-approved-import.json \
  --output ../outputs/kc17-import-receipt.json
```

The second command intentionally mutates the named pack. Test fixtures and source-controlled
corpora should be copied to a writable working pack before running it. The receipt records outcome,
reviewer, approval time, application time, exact before/after hashes, imported IDs, and whether an
interrupted transaction was recovered.

Plan and receipt output paths must be outside the pack directory. The CLI rejects an in-pack output
before application so an audit artifact cannot overwrite a manifest, source, or corpus JSONL file.

The machine-readable outputs follow the public
[`study-import-plan-v1`](../schemas/study-import-plan-v1.schema.json) and
[`study-import-receipt-v1`](../schemas/study-import-receipt-v1.schema.json) schemas.

Neither command calls ChatGPT, uses an API, searches the web, or requires Microsoft 365 or Teams
administrator access.

## Remaining UI work

KC-17 proves and tests the write boundary as reusable Swift code and CLI commands. The next slice is
an in-app reviewer that renders the pending cards, evidence excerpts, calculations, contradictions,
and gaps, captures explicit approve/reject decisions, previews this plan, and requires a deliberate
Apply action.
