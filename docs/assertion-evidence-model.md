# Generic Assertion and Evidence Model

KC-12 hardens the domain-neutral KnowledgePack proposition layer. It represents what the corpus
says, how that proposition is qualified, and why the proposition is allowed to exist. It does not
embed hotel, finance, product, legal, historical, or theological vocabulary in the core.

## Assertion shape

Every `KnowledgeAssertion` records:

- stable ID;
- subject;
- predicate;
- exactly one typed value;
- normalized qualifiers;
- assertion kind;
- confidence from 0 through 1; and
- claimed evidence-link IDs.

The supported value types are text, number, boolean, ISO-8601 date or timestamp, and reference ID.
Text and reference values must be non-empty. Numbers must be finite and explicitly declare a
normalized unit and a finite scale greater than zero. Units such as `count`, `ratio`, or
`unitless` keep dimensionless quantities explicit rather than implicit.

## Normalized context

The JSON contract retains the backward-compatible `qualifiers` object. The public
`KnowledgeAssertion.context` view separates three generic dimensions:

- `period`
- `version`
- `scope`

All other keys remain available as `additionalQualifiers`. Qualifier keys use normalized lowercase
text; values must be non-empty and free of surrounding whitespace.

A calculation may only produce an output with a declared period, version, or scope when every
input declares the same value. A missing or different input dimension is a validation error. An
output can intentionally omit a dimension when the calculation aggregates it—for example, total
revenue can aggregate department scopes into an unscoped asset total.

Domain Profiles can add protected context dimensions without changing the core model. The
hospitality profile adds `status`, so an `actual` output cannot silently consume a `budget` input.
It also requires `scope=rooms` for room inventory and performance predicates.

## Assertion kinds and provenance

Assertion kinds remain distinct and have different minimum provenance:

| Kind | Required provenance |
|---|---|
| `stated` | A claimed source evidence link with relation `supports` |
| `inferred` | A claimed `supports` or `contextualizes` source link |
| `interpretive` | A claimed `supports` or `contextualizes` source link |
| `calculated` | Exactly one recorded `KnowledgeCalculation` that names the assertion as output |

Calculated assertions may also carry a `derives` evidence link to the source passage that supplied
or displays the calculation. A `derives` link on a non-calculated assertion is rejected.

Evidence ownership is bidirectional. An assertion cannot claim another assertion's evidence link,
and an evidence link cannot point at an assertion without appearing in that assertion's
`evidenceLinkIDs`. Unknown assertions and passages continue to fail closed.

## Calculation boundary

The generic calculation record retains a name, non-empty version, deterministic expression,
ordered input assertion IDs, and one calculated output assertion ID. Validation rejects:

- empty or repeated input sets;
- an output reused as its own input;
- unknown or unsourced inputs;
- non-calculated outputs;
- more than one derivation for the same calculated assertion; and
- protected context dimensions that are missing or mixed.

The expression remains provenance, not executable code. Formula registration and dimensional
calculation semantics stay in Domain Profiles and the calculation registry.

## Domain boundary

The generic loader validates shape, typed-value integrity, provenance, and protected context. A
Domain Profile owns predicate definitions, required qualifiers, allowed units, aliases, and known
calculation signatures. This division lets the same assertion/evidence contract support a hotel
pitch, consumer-product presentation, academic debate, or any other prepared corpus.
