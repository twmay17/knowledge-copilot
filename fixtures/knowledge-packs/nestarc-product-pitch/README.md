# NestArc Go Synthetic Product-Pitch Corpus

NestArc Go is a fictional modular diaper-bag organizer created solely for Knowledge Copilot tests
and demonstrations. Every product name, specification, test result, research response, price,
roadmap item, source conflict, and market estimate was authored for this repository.

## What the fixture proves

- the unchanged KnowledgePack v1 schema and empty Domain Profile registry load a non-financial
  product pitch;
- 17 anticipated questions and objections resolve to reviewed response cards;
- product facts, materials, testing, pricing assumptions, research, and roadmap commitments remain
  citation-bound;
- pilot-versus-launch wash instructions and incompatible market definitions remain contested;
- price and modular-design conclusions remain visibly interpretive;
- contamination-prevention and infant-sleep claims fail closed as not found;
- a version-dependent care question asks for clarification instead of guessing; and
- a partial-speech replay produces the materials answer before final transcription.

The engineering and caregiver evidence is deliberately synthetic and does not constitute product,
regulatory, medical, consumer, or market advice.

## Verify

From `OpenOats/`:

```bash
swift run knowledge-pack validate ../fixtures/knowledge-packs/nestarc-product-pitch
swift run knowledge-pack inspect ../fixtures/knowledge-packs/nestarc-product-pitch
swift run knowledge-pack replay \
  ../fixtures/knowledge-packs/nestarc-product-pitch \
  ../fixtures/knowledge-packs/nestarc-product-pitch/evaluation/live-proof-materials.json
```

## Public redistribution review

Reviewed August 16, 2026:

- [x] No source text, product identity, person, company, customer, interview, certification, or
  market estimate came from a real party or paid database.
- [x] The fictional research and engineering limitations are explicit in the source documents and
  response cards.
- [x] Unsupported baby-safety claims abstain rather than infer.
- [x] Every source is plain text intended to ship under the repository license.
- [x] Source SHA-256 hashes are verified by the unchanged loader.
