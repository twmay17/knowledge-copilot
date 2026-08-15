# Domain Profile and Calculation Registry

KC-13 makes domain expertise a removable package extension. `OpenOatsKit` owns the generic
assertion, evidence, calculation, and answer contracts. A `KnowledgeDomainProfile` supplies only
versioned vocabulary and deterministic domain policy.

## Extension boundary

A profile publishes one or more `KnowledgeDomainProfileSchema` versions. Each schema contains:

- a normalized predicate namespace;
- typed qualifier definitions;
- predicate labels, aliases, value types, required qualifiers, and allowed units;
- deterministic calculation definitions; and
- profile-owned context keys that calculations must preserve.

The profile protocol cannot access audio capture, storage permissions, retrieval state, model
clients, or presentation UI. `HospitalityDomainProfile` is a separate Swift target that depends on
the generic kit; the generic kit does not depend on hospitality.

Generic packs with no profile references validate with `KnowledgeDomainProfileRegistry.empty`.
A pack that explicitly references an unavailable profile fails closed instead of silently skipping
its domain rules.

## Typed qualifiers

Qualifier payloads remain strings in KnowledgePack v1 for backward-compatible JSON. A profile can
register their semantic types as text, integer, number, boolean, ISO date, or four-digit year, plus
an optional allowed-value set.

Hospitality Reference Profile 1 registers:

| Key | Type | Policy |
|---|---|---|
| `period` | year | Four-digit reporting year |
| `current_period` | year | Current input year in a comparison |
| `prior_period` | year | Prior input year in a comparison |
| `scope` | text | `rooms`, `asset`, or `portfolio` |
| `status` | text | `actual`, `budget`, or `forecast` |

Every hospitality metric requires the relevant period and status. Room inventory and room
performance predicates also require room scope.

## Deterministic calculation definitions

A registered calculation records:

- stable ID and version;
- display expression;
- ordered input predicates and the allowed units for each input;
- output predicate and allowed output units;
- a deterministic operation (`sum`, `subtract`, `multiply`, `divide`, or `growth`); and
- a period rule.

The registry rejects an unregistered signature, wrong input order, wrong units, missing periods,
mixed periods, division by zero, non-finite arithmetic, or an output value that differs from the
registered operation. Stored numbers are compared after applying their explicit scales.

Most calculations use `matchingOutput`: every input and the output must share the output period.
Growth uses `orderedComparison`: the first and second input periods must be distinct and must match
the output's `current_period` and `prior_period` qualifiers. Status remains protected across both
inputs.

## Hospitality Reference Profile 1

The reference profile registers and tests deterministic rules for:

- available room nights;
- occupancy;
- ADR;
- RevPAR;
- total revenue;
- gross operating profit;
- NOI as gross operating profit less fixed charges;
- NOI margin; and
- total-revenue growth across ordered periods.

This is a reference contract, not a universal hotel-accounting opinion. A future profile version
can add account mappings or a more detailed NOI bridge without changing the generic core.

## Answer provenance

`KnowledgeCalculationSummary` resolves the stored expression, each ordered input assertion, its
scaled display value and qualifiers, its source citations, and the output assertion. The answer
overlay displays the arithmetic, source inputs, source locators, and result. If any referenced
input, evidence link, passage, source file, or output cannot be resolved, the answer resolver falls
back instead of showing a partial calculation.

Calculated cards must claim the output assertion of every calculation they display. This prevents
a reviewed answer string from attaching an unrelated formula.

