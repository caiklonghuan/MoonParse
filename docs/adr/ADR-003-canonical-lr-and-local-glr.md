# ADR-003: Canonical LR(1) oracle with local GSS ambiguity handling

Status: ADOPTED (M1-C05)

## Decision

Generate unmerged canonical LR(1) as the correctness oracle. Use a simple stack
for a single action and a GSS only for explicit grammar-declared multi-action
cells. Preserve every GSS predecessor path and order it by canonical bytes.

## Rejected alternatives

Globally merging states before proving action equivalence and silently choosing
one ambiguous branch are rejected: both break deterministic diagnostics and
incremental equivalence.

## Required proof

Corpus oracle, three declared-conflict fixtures, randomized construction-order
tests, and repeated Pack builds must retain all paths and stable state/
production IDs.
