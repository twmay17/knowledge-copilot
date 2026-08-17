# OpenOats

[![Auto-Maintainer](https://am.whhite.com/badge/yazinsai/openoats)](https://am.whhite.com)

A meeting note-taker that talks back.

> **Knowledge Copilot development branch:** this fork is extending OpenOats with a domain-neutral, corpus-grounded question and claim engine. The first new foundation is a versioned `KnowledgePack` contract that keeps sources, assertions, calculations, response cards, and citations portable across hospitality, product pitches, and other evidence-heavy conversations. See [the architecture boundary](docs/architecture-boundaries.md), [KnowledgePack v1 contract](docs/knowledge-pack-v1.md), and [current verification record](docs/verification-2026-08-14.md).

The portability gate now includes a second, completely generic demonstration pack: a synthetic
baby-product pitch with 17 anticipated questions, citation-bound product and research facts,
contested wash and market claims, interpretive objections, and explicit safety abstentions. It
loads with no Domain Profile or hospitality code. See the
[NestArc Go fixture](fixtures/knowledge-packs/nestarc-product-pitch/README.md).

The hospitality reference profile can also convert house-standard P&L and STAR extraction CSVs
into typed, cited KnowledgePack assertions while keeping broker evidence, analyst work product,
comparison basis, and modeled values distinct. See the
[hospitality underwriting import profile](docs/hospitality-underwriting-import-profile.md).

Validated packs can also be exported as a deterministic, closed-corpus Study Bundle for deliberate
pre-meeting analysis in a user-operated frontier-model session. This keeps subscription-assisted
preparation separate from the fast local meeting path and never treats generated material as
reviewed. See the [Study Bundle preparation boundary](docs/study-bundle.md).

Frontier-model analysis returns through a bundle-hash-bound proposal schema and remains
`generated` until a named human explicitly approves or rejects every proposed question family and
response card. The gate validates the would-be merged pack before emitting an auditable import
artifact. See [study analysis and human review](docs/study-analysis-review.md).

The same Study Analysis contract can now be generated with a locally running Ollama model. The
adapter permits only numeric loopback traffic, uses Ollama's schema-constrained structured output,
records the actual model as provenance, and sends every proposal through the existing evidence and
human-review gates. See [local Ollama Study Provider](docs/ollama-study-provider.md).

Reviewed imports can now be planned without mutation and then applied through a locked,
recoverable transaction. The writer rechecks the active corpus hash immediately before staging,
preserves the existing JSONL content, validates the installed pack, rolls back partial failures,
and returns an idempotent JSON receipt. See
[reviewed import application](docs/study-import-application.md).

The macOS app now includes a native Knowledge Review workspace for the final human gate. A named
reviewer can inspect proposed answers beside their exact assertions, source excerpts, and registered
calculations; explicitly approve or reject every proposal; preview the validated corpus change; and
deliberately apply it. See [Knowledge Review workspace](docs/knowledge-review-workspace.md).

Each loaded KnowledgePack now receives its own content-hash-bound hybrid search index. Exact aliases
and local SQLite full-text search work without a paid service; an optional vector adapter can rerank
only candidates already admitted by the active pack and its source, record-kind, and qualifier scope.
Changes trigger explicit dependency invalidation before rebuilding. See
[KnowledgePack hybrid search](docs/knowledge-pack-search.md).

Retrieved assertions can now be projected through a deterministic evidence-outcome evaluator before
the live layer treats them as an answer. Conflicting values and incompatible contexts remain
separate with per-claim source links; interpretations are labeled; incomplete questions request
clarification; unsupported questions return not found; and a proposed claim can be explicitly
contradicted by the corpus. See [evidence outcomes and abstention](docs/knowledge-evidence-outcomes.md).

Streaming transcript revisions now pass through a domain-neutral live event detector. Prepared
questions can trigger retrieval before final punctuation; declarative claims, topic changes,
supersession, duplicates, stale revisions, and explicit no-action outcomes are deterministic and
replayable. Synthetic fixtures measure actionable false positives rather than hiding them in a demo.
See [the live event detector contract](docs/live-event-detector.md).

A versioned 101-scenario, two-domain replay benchmark now grades the complete deterministic event
and answer path across direct, partial, corrected, ambiguous, conflicting, missing, rhetorical,
cross-pack, and rapid-follow-up speech. It pins evidence states, response fragments, citations,
false-card rate, and processing latency while keeping every fixture synthetic and redistributable.
See [the multi-pack replay benchmark](docs/replay-benchmark.md).

The release path now adds a separate closed-corpus correctness gate over those conversations.
Reviewed category fingerprints detect silent changes to sources, passages, assertion qualifiers,
evidence links, calculations, response cards, or question families; eight typed outcome probes cover
every evidence state; and explicit cross-pack scenarios must abstain without leaking a card. See
[the KnowledgePack correctness gate](docs/correctness-gate.md).

Knowledge Copilot privacy boundaries now include a persisted offline mode, fixed-instruction
synthesis envelopes, explicit outbound-data disclosure, credential rejection/redaction, and
root-contained deletion receipts. See
[security, privacy, and isolation](docs/security-and-isolation.md).

The no-admin Microsoft Teams capture baseline is documented in the
[Teams audio-capture verification runbook](docs/teams-audio-verification.md), and the consented
end-to-end private-alpha gate is documented in the
[supervised Teams review runbook](docs/supervised-teams-alpha-review.md).

<p align="center">
  <a href="https://github.com/yazinsai/OpenOats/releases/latest">
    <img src="https://img.shields.io/badge/Download_for_Mac-DMG-black?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Mac" />
  </a>
</p>

OpenOats sits next to your call, transcribes both sides of the conversation in real time, and searches your own notes to surface things worth saying — right when you need them.

---

### Sponsored by Recall.ai — API for desktop recording

If you're looking for a hosted desktop recording API, consider checking out [Recall.ai](https://dub.sh/openoats), an API that records Zoom, Google Meet, Microsoft Teams, in-person meetings, and more.

---

### Sponsored by <a href="https://dub.sh/apismart"><img src="assets/sponsors/apismart.svg" alt="ApiSmart" height="24" style="vertical-align: 2px;" /></a> — One API for Leading AI Models

[ApiSmart](https://dub.sh/apismart) unifies leading LLM, image, and video models through one OpenAI-compatible API. Use one key to switch models, simplify billing, and improve reliability with automatic failover.

---

<p align="center">
  <img src="assets/hero.svg" width="720" alt="OpenOats during a call — suggestions drawn from your own notes appear at the top, live transcript below" />
</p>

## Features

- **Invisible to the other side** — the app window is hidden from screen sharing by default, so no one knows you're using it
- **Fully offline transcription** — speech recognition runs entirely on your Mac; no audio ever leaves the device
- **Runs 100% locally** — pair with [Ollama](https://ollama.com/) for LLM suggestions and local embeddings, and nothing touches the network at all
- **Pick any LLM** — use [OpenRouter](https://openrouter.ai/) for cloud models (GPT-4o, Claude, Gemini) or Ollama for local ones (Llama, Qwen, Mistral)
- **Live transcript** — see both sides of the conversation as it happens, copy the whole thing with one click
- **Auto-saved sessions** — every conversation is automatically saved as a plain-text transcript and a structured session log, no manual export needed
- **Knowledge base search** — point it at a folder of notes and it pulls in what's relevant using [Voyage AI](https://www.voyageai.com/) embeddings, local Ollama embeddings, or any OpenAI-compatible endpoint (llama.cpp, llamaswap, LiteLLM, vLLM, etc.)

## How it works

1. You start a call and hit **Live**
2. OpenOats transcribes both speakers locally on your Mac
3. When the conversation hits a moment that matters — a question, a decision point, a claim worth backing up — it searches your notes and surfaces relevant talking points
4. You sound prepared because you are

## Recording Consent & Legal Disclaimer

**Important:** OpenOats records and transcribes audio from your microphone and system audio. Many jurisdictions have laws requiring consent from some or all participants before a conversation may be recorded (e.g., two-party/all-party consent states in the U.S., GDPR in the EU).

**By using this software, you acknowledge and agree that:**

- **You are solely responsible** for determining whether recording is lawful in your jurisdiction and for obtaining any required consent from all participants before starting a session.
- **The developers and contributors of OpenOats provide no legal advice** and make no representations about the legality of recording in any jurisdiction.
- **The developers accept no liability** for any unauthorized or unlawful recording conducted using this software.

**Do not use this software to record conversations without proper consent where required by law.**

The app will ask you to acknowledge these obligations before your first recording session.

## Download

Install via Homebrew:

```bash
brew tap yazinsai/openoats https://github.com/yazinsai/OpenOats
brew install --cask yazinsai/openoats/openoats
```

To upgrade later:

```bash
brew upgrade --cask yazinsai/openoats/openoats
```

Or grab the latest DMG from the [Releases page](https://github.com/yazinsai/OpenOats/releases/latest).

Or build from source:

```bash
./scripts/build_swift_app.sh
```

## Quick start

1. Open the DMG and drag OpenOats to Applications
2. Launch the app and grant microphone + system audio recording permissions
3. Open Settings (`Cmd+,`) and pick your providers:
   - **Cloud**: add your OpenRouter and Voyage AI API keys
   - **Local**: select Ollama as your LLM and embedding provider (make sure Ollama is running)
   - **OpenAI-compatible**: select "OpenAI Compatible" as your embedding provider and point it at any `/v1/embeddings` endpoint
4. Point it at a folder of `.md` or `.txt` files — that's your knowledge base
5. Click **Idle** to go live

The first run downloads the local speech model (~600 MB).

## What you need

- Apple Silicon Mac, macOS 15+
- Xcode 26 / Swift 6.2
- **For cloud mode**: [OpenRouter](https://openrouter.ai/) API key + [Voyage AI](https://www.voyageai.com/) API key
- **For local mode**: [Ollama](https://ollama.com/) running locally with your preferred models (e.g. `qwen3:8b` for suggestions, `nomic-embed-text` for embeddings)
- **For OpenAI-compatible embeddings**: any server implementing `/v1/embeddings` (llama.cpp, llamaswap, LiteLLM, vLLM, etc.)

## Knowledge base

Point the app at a folder of Markdown or plain text files. That's it. OpenOats chunks, embeds, and caches them locally. When the conversation shifts, it searches your notes and only surfaces what's actually relevant.

Works well with meeting prep docs, research notes, pitch decks, competitive analysis, customer briefs — anything you'd want at your fingertips during a call.

## Privacy

- Speech is transcribed locally — audio never leaves your Mac
- **With Ollama**: everything stays on your machine. Zero network calls.
- **With cloud providers**: KB chunks are sent to Voyage AI (or your chosen OpenAI-compatible endpoint) for embedding (text only, no audio), and conversation context is sent to OpenRouter for suggestions
- API keys are stored in your Mac's Keychain
- The app window is hidden from screen sharing by default
- Transcripts are saved locally to `~/Documents/OpenOats/`

### Cloud mode: what data leaves your Mac

When using cloud providers, OpenOats makes the following network requests. **No audio is ever sent** — only text. In fully-local mode (Ollama for both LLM and embeddings), nothing touches the network at all.

#### 1. Knowledge base indexing — Voyage AI (`api.voyageai.com/v1/embeddings`)

**When:** Each time you index your knowledge base folder (on launch or when files change).

**What is sent:**
- Text chunks from your `.md` / `.txt` knowledge base files (split by markdown headings, 80–500 words each, with the header breadcrumb prepended)
- Model name (`voyage-4-lite`) and requested output dimensions (`256`)
- Input type (`document`)

Chunks are sent in batches of 32. Only new or changed files are embedded — unchanged files use a local cache.

#### 2. Knowledge base search — Voyage AI (`api.voyageai.com/v1/embeddings`)

**When:** Each time the suggestion pipeline runs (triggered by a substantive utterance from the other speaker, subject to a 90-second cooldown).

**What is sent:**
- 1–4 short query strings derived from the conversation: the latest utterance text, the current conversation topic, a short conversation summary, and the top open question
- Model name, dimensions, and input type (`query`)

#### 3. Knowledge base reranking — Voyage AI (`api.voyageai.com/v1/rerank`)

**When:** Immediately after step 2, if Voyage AI is the embedding provider.

**What is sent:**
- The primary search query (the latest utterance text)
- Up to 10 candidate KB chunk texts (from your own notes) for reranking
- Model name (`rerank-2.5-lite`)

#### 4. Conversation state update — OpenRouter (`openrouter.ai/api/v1/chat/completions`)

**When:** Periodically during a session when the conversation state needs refreshing.

**What is sent (as an LLM prompt):**
- The previous conversation state (topic, summary, open questions, tensions, recent decisions, goals — all derived from earlier LLM calls)
- Recent transcript utterances (both speakers, text only — labeled "You" / "Them")
- The latest utterance from the other speaker
- A system prompt instructing the model to update the conversation state

#### 5. Surfacing gate — OpenRouter (`openrouter.ai/api/v1/chat/completions`)

**When:** After the KB search returns relevant results, to decide whether a suggestion is worth showing.

**What is sent (as an LLM prompt):**
- The latest utterance from the other speaker
- Recent transcript exchange (both speakers, text only)
- Current conversation state (topic, summary, open questions, tensions)
- The detected trigger type and excerpt
- Up to 5 KB evidence chunks (text from your notes, with source file and header, plus relevance scores)
- Recently shown suggestion angles (short strings, to avoid repeats)

#### 6. Suggestion generation — OpenRouter (`openrouter.ai/api/v1/chat/completions`)

**When:** Only if the surfacing gate approves (all quality scores above threshold).

**What is sent (as an LLM prompt):**
- The latest utterance from the other speaker
- Current conversation state (topic and summary)
- The gate's reasoning string
- Up to 3 KB evidence chunks (text from your notes, with source file and header)

#### 7. Meeting notes generation — OpenRouter (`openrouter.ai/api/v1/chat/completions`)

**When:** When you click "Generate Notes" after a session.

**What is sent (as an LLM prompt):**
- The full session transcript (both speakers, with timestamps, labeled "You" / "Them") — truncated to ~60,000 characters if very long
- The meeting template's system prompt (e.g., instructions for formatting notes)

#### What is never sent

- **Audio** — transcription is always on-device via Apple Speech
- **File paths or filenames from your system** (only KB source filenames appear in prompts)
- **Your API keys to anyone other than the respective provider** (OpenRouter key to OpenRouter, Voyage key to Voyage)
- **Any data when using Ollama** — all requests go to your local machine

## Build

```bash
# Full build → sign → install to /Applications
./scripts/build_swift_app.sh

# Dev build only
cd OpenOats && swift build -c debug

# Package DMG
./scripts/make_dmg.sh
```

Optional env vars for code signing and notarization: `CODESIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.

## Repo layout

```
OpenOats/             SwiftUI app (Swift Package)
scripts/              Build, sign, and package scripts
assets/               Screenshot and app icon source
```

## License

MIT
