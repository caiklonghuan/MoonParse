# ADR-005: Monotone reuse cursor and identity-derived changed ranges

Status: ADOPTED (M1-C05)

## Decision

Advance a reuse cursor monotonically in old-source order. Reuse only a candidate
meeting the LR, scanner-byte, edit/lookahead, safety-flag, and source-byte tests
in `ALGORITHMS.md`. Derive changed ranges by comparing old/new green identity
through the normalized EditMap.

## Why

This prevents an O(tokens × tree) DFS strategy and makes reported reuse a real
shared reference, rather than an estimate based on unchanged text.

## Required proof

Head insertions and middle deletions must share an unrelated right subtree by
reference identity. Full and incremental tree/diagnostic/query digests match on
the fixed edit generator with zero mismatches.
