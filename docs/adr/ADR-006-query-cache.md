# ADR-006: Proof-gated Query cache with role boundaries

Status: ADOPTED (M1-C05)

## Decision

Cache a query by green identity only when the compiler proves that a
concrete-rooted pattern has no external sibling or ancestor dependency. All
other patterns run fully. Each QueryRole declares boundary node kinds; locals
cache at scope-green-node granularity.

## Why

An optimistic cache that misses ancestor or sibling effects can look fast while
returning stale editor results. The safe fallback is full execution.

## Required proof

Cache-enabled, cache-disabled, and incremental captures are item-for-item
equal; digest comparison agrees across Native and WASM; a match-limit overflow
is a stable `QueryError`.
