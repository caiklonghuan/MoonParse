# MoonParse v1 Runtime API Semantics

Status: frozen by M1-C02. The declarations live in `spec.mbt`; M2-C12 supplies their implementation.

## Coordinates and source ownership

- Every public byte offset is a UTF-8 byte offset. Ranges are half-open: `[start_byte, end_byte)`.
- `Point.row` and `Point.byte_column` are zero-based. `byte_column` is UTF-8 bytes, never UTF-16 units or display columns.
- CRLF is one line break. The offset at LF within CRLF maps to the preceding row at the byte column after CR; the offset after LF maps to the next row at column zero.
- `Source` owns immutable validated UTF-8. `Source::from_utf8` rejects invalid input, and `Source::to_bytes` returns a defensive copy.
- All externally supplied ranges and edits must be in bounds and at UTF-8 code-point boundaries.

## Parse and snapshot lifetime

- `Parser::parse` creates a new immutable `Snapshot`; it has no changed ranges, reports `reparsed_bytes = source_bytes`, and reports zero reused bytes.
- `Parser::reparse` is equivalent to `reparse_many` with one edit. `reparse_many` applies edits in array order, after validating every edit before producing a new snapshot.
- If any edit fails, no partial snapshot is returned. Error indices and offsets refer to the source visible at that edit step.
- An empty edit batch creates a new snapshot sharing the previous immutable green root; changed ranges are empty and reparsed bytes are zero.
- `Node` and `TreeCursor` retain the snapshot that created them. Old node text and spans remain valid after later reparses.

## Nodes, diagnostics, and queries

- Nodes are lossless: token text, whitespace, comments, recovered text, ERROR nodes, and zero-width MISSING nodes remain observable.
- `Node::span` is lazy from snapshot source data. Green identity is never public or serialized.
- Stable diagnostic data are code, severity, span, expected symbols, recovery action, and optional fix. Human-readable messages may improve without changing that machine contract.
- `Language::query` returns only precompiled pack queries. `Query::compile` is deterministic and performs no I/O.
- Query language fingerprints must match. A mismatch returns `QueryError::LanguageMismatch`.
- `Snapshot::captures(within=Some(range))` returns only captures whose spans intersect the half-open range. A zero-width capture is included only when `range.start_byte <= position < range.end_byte`; an explicit empty range returns no captures.
- Capture order is deterministic and no implicit deduplication occurs.

## Checked error codes

| Error | Stable cases |
| --- | --- |
| `SourceError` | invalid UTF-8, invalid byte range, split code point, invalid point |
| `PackError` | magic/version/ABI failure, truncation, offsets, duplicate or missing sections, checksum, limits, invalid model |
| `ParseFailure` | language mismatch, indexed invalid edit, split edit boundary, invalid limits, parser budget exhaustion |
| `QueryError` | query parse/feature/name failure, language mismatch, invalid range, match limit exhaustion |

Syntax errors, ERROR/MISSING nodes, and bounded recovery outcomes are diagnostics, not `ParseFailure`.

## Limits

`ParseLimits` is opaque. Each builder rejects non-positive or over-maximum values with `ParseFailure::InvalidLimit`; it never clamps or wraps. Query limits belong to the snapshot that executes the query and cannot be read from mutable global configuration.
