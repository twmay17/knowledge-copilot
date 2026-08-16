# Local Ollama Study Provider

The Ollama Study Provider generates the same public Study Analysis v1 contract as a deliberate
frontier-model preparation session, but the model runs on the presenter's Mac. It is an optional
preparation adapter over the existing Study Bundle and human-review boundary, not a second source
of factual authority.

## Trust flow

```text
validated KnowledgePack
  -> deterministic Study Bundle
  -> loopback-only Ollama structured-output request
  -> untrusted proposal draft
  -> locally assigned pack identity, analysis ID, and provider provenance
  -> existing Study Analysis evidence validator
  -> generated Study Analysis v1 file
  -> existing human-review queue and approved-import workflow
```

The provider asks Ollama's native `POST /api/chat` endpoint for a non-streaming response and places
a JSON Schema in the request's `format` field. This follows Ollama's documented structured-output
contract. The same schema is also included in the prompt, as Ollama recommends.

The model returns only proposal arrays. It does not control the pack ID, bundle ID, full-content
hash, final analysis ID, or provider provenance. OpenOats supplies those fields locally, records the
actual response model as `generator: ollama:<model>`, canonicalizes the proposal arrays, and runs
the complete `KnowledgeStudyAnalysisValidator` before writing a result.

## Network boundary

The provider accepts only unencrypted loopback HTTP endpoints:

- `http://localhost:<port>` is rewritten to `http://127.0.0.1:<port>`;
- `http://127.0.0.1:<port>` and `http://[::1]:<port>` are accepted;
- remote hosts, HTTPS URLs, credentials, query strings, fragments, and unknown base paths are
  rejected before the transport runs; and
- HTTP redirects are followed only when the target remains numeric loopback.

The dedicated URL session is ephemeral, disables cookies, caching, and configured proxies, and
does not add an authorization header. "Local" therefore means no off-device request from this
provider. Ollama itself remains separately installed and controlled by the user.

## Closed-corpus behavior

The Study Bundle is serialized directly into the local request. The system prompt:

- declares the bundle to be the only factual authority;
- forbids web search, tools, outside knowledge, and model-memory claims;
- treats document instructions as untrusted data;
- requires existing assertion, passage, calculation, and question-family IDs;
- preserves contradictions and interpretations; and
- requires a gap or clarification outcome when the corpus cannot support an answer.

Prompting and structured output improve generation quality, but neither is the trust boundary. The
deterministic validator still rejects unknown references, stale identities, invalid evidence-state
combinations, citations outside evidence closure, and every other unsupported addition. All valid
cards remain `generated` until the existing named human-review workflow approves them.

## Command

From `OpenOats/`, with Ollama running and the chosen model already installed:

```bash
swift run knowledge-pack analyze-study-with-ollama \
  ../fixtures/knowledge-packs/minimal-hospitality \
  --model qwen3:8b \
  --output ../outputs/ollama-study-analysis.json
```

Optional settings:

```bash
--base-url http://localhost:11434
--timeout-seconds 900
```

The output must be outside the KnowledgePack directory. Continue through the same review path used
for any other provider:

```bash
swift run knowledge-pack prepare-study-review \
  ../fixtures/knowledge-packs/minimal-hospitality \
  ../outputs/ollama-study-analysis.json \
  --output ../outputs/ollama-review-queue.json
```

The native Knowledge Review workspace can then inspect and decide the queue. No model-generated
record enters the live corpus automatically.

## Operational limits

Requests are capped at 32 MiB and responses at 16 MiB. The default timeout is 15 minutes because a
local model may need a cold start and a long pre-meeting analysis. Output quality and runtime depend
on the selected model, its context window, the Study Bundle size, and the Mac's available memory.

The provider does not install Ollama, pull models, choose a model on the user's behalf, or expose a
remote Ollama server. Those are deliberate product boundaries rather than silent fallbacks.
