# KC-21 Local Ollama Study Provider Evidence — August 15, 2026

## Acceptance slice

KC-21 adds a provider that can generate the public Study Analysis v1 contract with a locally
running Ollama model while retaining the existing deterministic evidence and human-review gates.

Verified behavior:

- Ollama requests use the native non-streaming `/api/chat` structured-output contract;
- the request includes a proposal-only JSON Schema in `format` and in the prompt;
- `localhost` is rewritten to numeric loopback;
- only HTTP `127.0.0.1` or `::1` endpoints and loopback redirects are permitted;
- remote hosts, HTTPS, credentials, query strings, fragments, unknown paths, cookies, caches,
  configured proxies, and authorization headers are excluded;
- the model cannot author the pack ID, bundle ID, full-content hash, final analysis ID, or
  provenance;
- the actual Ollama response model is stored as `generator: ollama:<model>`;
- the final analysis ID is deterministic over the canonical validated output and provider
  provenance;
- malformed, incomplete, empty, oversized, HTTP-error, and unsupported-evidence responses fail
  closed;
- the existing Study Analysis validator checks every reference, evidence-state rule, calculation,
  and citation closure before output is returned; and
- every returned proposal remains generated and enters the existing named human-review workflow.

## Reproducible checks

From `OpenOats/`:

```bash
swift test --filter KnowledgeOllamaStudyProviderTests

swift test --filter \
  'KnowledgeOllamaStudyProviderTests|KnowledgeStudyReviewWorkspaceModelTests|KnowledgeStudyImportApplierTests|KnowledgeStudyReviewTests|KnowledgeStudyBundleTests'

swift test --skip MeetingDetectorTests
swift build -c release --product knowledge-pack
swift build -c release --product OpenOats

swift run knowledge-pack analyze-study-with-ollama \
  ../fixtures/knowledge-packs/minimal-hospitality \
  --model qwen3:8b \
  --base-url http://ollama.example:11434 \
  --output ../outputs/should-not-exist.json

swift format lint --strict \
  Sources/OpenOats/KnowledgePack/KnowledgeOllamaStudyProvider.swift \
  Sources/KnowledgePackTool/main.swift \
  Tests/OpenOatsTests/KnowledgeOllamaStudyProviderTests.swift
git diff --check
```

Results:

- 7 of 7 focused provider tests passed;
- all 45 Study Bundle, provider, review, import, and native-workspace tests passed;
- 825 of 825 non-environmental package tests passed on the final broad run;
- an inherited lifecycle timing test failed once because its fixed wait observed `ending`, then
  passed in isolation and in the final complete run without a code change;
- release builds passed for both `knowledge-pack` and `OpenOats`;
- the CLI exposed the new command and rejected the remote endpoint with exit code 1 before creating
  its requested output file;
- strict Swift formatting passed for the provider, CLI, and tests; and
- whitespace validation passed.

## Environment boundary

Ollama was not installed or listening on `127.0.0.1:11434` in this build environment. The provider's
HTTP contract, output decoding, provenance, canonicalization, evidence validation, and fail-closed
behavior were therefore verified through an injected recording transport rather than a live model.
A real-model smoke run remains an operator verification step on a Mac with Ollama and an explicitly
selected model installed; no cloud fallback is attempted.

All test data is synthetic. No private corpus, credentials, meeting audio, or proprietary
underwriting documents were sent or recorded.
