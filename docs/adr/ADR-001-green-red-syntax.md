# ADR-001: Immutable green syntax with snapshot-owned red views

Status: ADOPTED (M1-C05)

## Decision

Use immutable, lossless green nodes with no absolute positions, source, parent,
or snapshot references. Expose locations through red `Node`/`TreeCursor` views
that strongly retain their snapshot and compute spans lazily from `SourceIndex`.

## Why

This permits safe sharing across snapshots and keeps old node text/spans valid
after an edit. A mutable tree or a global snapshot arena would make sharing and
retention unprovable.

## Required proof

Full/error/manual-tree tests verify width, range, and field continuity. A
10,000-edit retention test proves discarded snapshots do not linearly retain
green nodes. ERROR, MISSING, and fragile nodes never qualify for reuse.
