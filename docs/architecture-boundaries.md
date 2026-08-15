# Architecture Boundaries

## Product boundary

This fork is a real-time, corpus-grounded question and claim copilot. The reusable core does not know what RevPAR, a baby product, or a historical argument means. It knows how to load evidence, observe a conversation event, retrieve relevant material, apply an evidence contract, and render a response card.

Hospitality is the first reference profile because it gives us precise calculations and high-value acceptance tests. It is not the core ontology.

## Dependency direction

```text
macOS application and overlay
          |
          v
conversation events -> retrieval -> evidence gate -> response cards
          |                 |
          v                 v
    KnowledgePack core <- DomainProfile extensions
          |
          v
 versioned sources, assertions, evidence, calculations, provenance
```

Allowed dependencies:

- application features may depend on generic core interfaces;
- a DomainProfile may depend on KnowledgePack and calculation interfaces;
- fixtures may depend on a DomainProfile;
- optional model adapters may depend on generic preparation/live interfaces.

Forbidden dependencies:

- KnowledgePack core must not import a hospitality or product-pitch profile;
- evidence validation must not call an LLM or the web;
- live cards must not bypass the evidence gate;
- a selected pack must not retrieve records from another pack;
- domain profiles must not control microphone, storage, or UI permissions.

## Existing OpenOats seams we will reuse

- `AudioRecorder`, `MicCapture`, and `SystemAudioCapture` for permitted local audio;
- `TranscriptionBackend` and `StreamingTranscriber` for pluggable local ASR;
- `RealtimeGate` as the initial low-latency event/surfacing seam;
- `PreFetchCache` for speculative retrieval during partial speech;
- `KnowledgeBase` as a migration source for chunking and embedding behavior;
- overlay and sidecast panels for private presenter cards;
- settings, Keychain use, session storage, consent, and screen-share controls.

The existing free-form knowledge base remains operational while the versioned KnowledgePack path is developed. Migration should be additive until the new evidence and provenance requirements are proven.

## New generic seams

### KnowledgePack

A portable, versioned collection of sources, passages, assertions, evidence links, deterministic calculations, question families, and response cards.

### DomainProfile

An optional extension that registers domain vocabulary, aliases, typed qualifiers, deterministic calculations, and evaluation fixtures. The first implementation will be hospitality.

The Swift package enforces this boundary with a separate `HospitalityDomainProfile` target that
depends on `OpenOatsKit`. The generic loader receives an explicit registry and rejects unknown or
unsupported profile references instead of silently ignoring their semantics.

### SessionPlaybook

Meeting-specific context: audience, goals, tone, likely objections, topics, and presentation constraints. It may influence ranking but may not create evidence.

### Conversation events

The live detector will emit domain-neutral candidates and stable events for questions, claims, topic shifts, and superseded answers.

### Evidence gate

Every displayed answer receives one of eight states: directly sourced, calculated, supported by corpus, contradicted by corpus, contested, interpretive, not found in corpus, or needs clarification.

### Pack-bound retrieval

The active KnowledgePack owns a content-hash-bound hybrid index. Exact and local full-text retrieval
are the dependable baseline. Optional semantic ranking may operate only on candidates already scoped
to that pack, permitted record kinds, sources, and qualifiers. It may reorder eligible material but
cannot create evidence or introduce a record from another pack. Typed dependency invalidation makes
corpus changes explicit before index rebuild.

## First integration sequence

1. Validate and inspect a KnowledgePack from the command line.
2. Load the selected pack in the app without replacing the legacy knowledge base.
3. Map a prepared response card to the existing suggestion UI.
4. Replace keyword-only question detection with domain-neutral conversation events.
5. Add the hospitality profile and deterministic RevPAR calculation.
6. Prove portability with a non-financial product-pitch pack.
