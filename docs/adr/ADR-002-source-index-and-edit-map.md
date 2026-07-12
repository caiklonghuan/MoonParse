# ADR-002: UTF-8 SourceIndex and normalized EditMap

Status: ADOPTED (M1-C05)

## Decision

Model source positions exclusively as UTF-8 byte offsets and zero-based
byte-column points. Build a `SourceIndex` from immutable bytes and represent
each replacement as `prefix + replacement + suffix`; compose batch edits into
a checked, ordered, non-overlapping `EditMap`.

## Why

Byte coordinates match pack/runtime semantics and are deterministic across
hosts. CRLF must be specified at both CR and LF offsets to make edits in the
middle of a line ending unambiguous.

## Required proof

Black-box tests cover CR, LF, CRLF before/middle/after edits, emoji, combining
marks, Chinese, file boundaries, empty source, empty batches, and sequential
coordinate changes. Every valid byte/point pair round-trips.
