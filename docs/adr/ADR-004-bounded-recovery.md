# ADR-004: Bounded best-first recovery

Status: ADOPTED (M1-C05)

## Decision

Recovery is a bounded best-first search over Insert(expected), Delete(actual),
and PopToSync only. Fixed costs and progress rules are defined in
`ALGORITHMS.md`; an accepted candidate consumes three real tokens or reaches
EOF.

## Why

It keeps malformed editor input useful without turning error handling into an
unbounded alternate parser. Syntax errors produce diagnostic-bearing snapshots,
not `ParseFailure`.

## Required proof

Golden Insert/Delete/Pop trees, diagnostics, and fixes; arbitrary-byte fuzz
termination; deterministic `BudgetExceeded`; and equal full/incremental
diagnostic digests.
