# KnowledgePack Hybrid Search and Invalidation

## Purpose

The live copilot must retrieve a useful answer quickly without allowing material from another
presentation, deal, or research corpus to leak into the result. `KnowledgePackSearchIndex` provides
that boundary for every validated KnowledgePack.

The implementation is domain-neutral. Hospitality terms work because the hospitality profile and
pack supply aliases and qualifiers; a product pitch or historical debate can use the same search
contract with a different pack.

## Search lanes

Every query names the exact `packID` it is allowed to search. A mismatched pack ID fails closed.
Within that boundary, the caller may also require record kinds, source IDs, and exact qualifier
values such as `period=2020`. Preferred qualifiers increase rank but never create evidence.

The index combines three lanes:

1. **Exact** — normalized identifiers, titles, predicates, source paths, question variants, aliases,
   partial prefixes, and tags. This is the strongest local signal.
2. **Full text** — an in-memory SQLite FTS5 index using the Unicode tokenizer. It indexes titles,
   bodies, and aliases and requires no account, network call, or paid service.
3. **Vector** — an optional adapter for semantic ranking. The adapter receives only candidates that
   already passed the active pack, record-kind, source, and required-qualifier filters. Unknown IDs,
   non-finite scores, and adapter failures cannot add foreign evidence; the local result remains
   available.

Only `reviewed` response cards are searchable. Generated or rejected cards remain outside the live
answer path. Search results carry the pack ID, canonical full-content hash, source IDs, qualifiers,
matched channels, and individual score components so downstream evidence checks can inspect rather
than infer their provenance.

## Content binding and invalidation

The index uses the same deterministic full-content hash as the closed-corpus Study Bundle. Reloading
identical content reuses the existing index. Any changed hash rebuilds it, while a different pack ID
always gets a fresh index.

`KnowledgePackDependencyInvalidator` compares the old and new typed records, then walks both versions
of the dependency graph. This handles additions, edits, deletions, and rewired relationships:

```text
manifest -> source -> passage -> evidence link -> assertion -> calculation -> response card
                       |                         |                           ^
                       +-------------------------+---------------------------+

manifest -> question family -> response card
```

A source change therefore invalidates its passages and every transitive assertion, calculation, and
response card. A manifest change invalidates the full graph. The rebuild report exposes both direct
changes and the complete invalidated set for diagnostics and future persistent-cache work.

## App and command-line integration

`KnowledgePackStore` builds the index off the main actor after loader and Domain Profile validation.
If validation or indexing fails, the selected pack and index are cleared together. The store exposes
local and optional-vector search methods for the coming live orchestration layer.

The CLI provides an inspectable local proof:

```bash
cd OpenOats
swift run knowledge-pack search \
  ../fixtures/knowledge-packs/minimal-hospitality \
  "fictional investment memo inconsistent" \
  --kind passage \
  --source source-investment-memo \
  --limit 3
```

Optional flags are `--kind`, `--source`, `--qualifier key=value`, and `--limit 1-100`. JSON output is
suitable for fixtures and integration checks.

## Security and cost boundary

- Local exact and full-text retrieval require no Microsoft 365 administrator access and no API key.
- The implementation does not call a model, the web, Teams, Notion, or any remote search service.
- Vector search is optional and is ranking assistance, not evidence authority.
- Search cannot cross a KnowledgePack boundary, even when a vector adapter returns an invented or
  stale candidate ID.
- The answer layer must still apply the evidence gate before displaying a live response.

This milestone deliberately establishes trustworthy retrieval and invalidation. Automated question
detection can now ask this index for tightly scoped material without depending on the legacy
free-form embedding cache.
