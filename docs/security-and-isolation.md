# Security, privacy, and isolation

The Knowledge Copilot path treats meeting speech, corpus content, and source metadata as untrusted
private data. The deterministic evidence gate remains authoritative; an optional language model can
format only evidence that the active pack has already admitted.

## Prompt-injection boundary

`KnowledgeConstrainedSynthesisEnvelope` separates a fixed application instruction from a
JSON-encoded user payload. Questions, claims, source titles, qualifiers, and evidence excerpts are
quoted only inside that payload. The instruction explicitly forbids following directives embedded
in those fields, using prior knowledge, searching, calling tools, or citing unknown records.

Every synthesis result is checked again after the adapter returns. It must cite only admitted record
IDs and satisfy every claim-level citation requirement. Invalid, invented, or incomplete citations
are discarded, leaving the deterministic answer visible.

## Network modes and outbound disclosure

The Knowledge Copilot settings expose two modes:

- **Offline — no device egress:** deterministic pack search remains available; on-device and
  loopback adapters are allowed; external vector and synthesis adapters are never called.
- **Allow external adapters:** an external vector adapter may receive the query plus every
  active-scope candidate's record ID, title, and complete searchable text, including evidence
  excerpts, aliases, and qualifier values. An external synthesis adapter may receive the detected
  question or claim, admitted evidence text, source titles, corpus identifiers, and evidence
  qualifiers.

Each vector request and synthesis envelope records its destination, disclosed data classes, record
counts, and character counts. Neither contains pack files, credentials, retrieval capability, or
tools. Adapters are conservatively classified as external unless they explicitly declare an on-device
or loopback destination.

## Credential handling

Application API keys and webhook secrets use the macOS Keychain-backed secret store and are not
written to `UserDefaults`. Pack validation rejects common private-key, provider-token, bearer-token,
and credential-assignment patterns across the pack's structured text fields. Validation findings
identify only the record location and credential class; they never echo the detected value.

Diagnostic breadcrumbs are redacted before they are written. Diagnostics exports apply the same
redactor again to both breadcrumbs and unified-log text. The Knowledge Pack runtime itself emits no
source text to a telemetry transport, and transcript logging uses OSLog private interpolation.

## Deletion contract

`KnowledgeDataDeletionService` accepts explicit targets for Knowledge Packs, transcripts, audio,
and caches. Every target must be a descendant of its caller-supplied allowed root; deleting the root
itself or anything outside it fails closed. Successful deletion returns a per-artifact receipt that
records whether the target existed and proves it is absent afterward. The operation is idempotent.

The service is deliberately not connected to an automatic broad-directory cleanup. Product UI must
show the exact paths and obtain confirmation before asking it to remove real user data.

The V1 settings review confirms that no destructive deletion action is exposed. This is intentional:
the service contract is available and tested, but a future UI must show each exact target and require
an explicit confirmation before it can call the service.

## Active-pack isolation

Search, evidence evaluation, response cards, optional synthesis, and the correctness gate are bound
to both the active pack ID and its canonical content hash. External adapters receive only candidates
already admitted inside that scope. Cross-pack replay scenarios must abstain without returning a
card from the inactive pack.

## Local storage ownership

V1 reads a user-selected KnowledgePack directory in place and does not create an app-managed pack
copy. Its SQLite full-text index is memory-only. This keeps the app from creating a second plaintext
copy and leaves at-rest protection of the source directory to FileVault or a user-selected encrypted
volume. An automated load test snapshots every fixture file before loading and verifies that all
bytes are unchanged afterward and that the active directory is the original selected directory.

If a later release adds app-managed pack persistence, that feature must use authenticated encryption,
store its key outside the archive, cover recovery and key rotation with tests, and update the deletion
receipt contract before it can ship.

## Remaining hardening before KC-27 closes

- Complete the post-live-findings KC-26 rerun, then rerun the KC-27 security matrix against the final
  corpus behavior.
