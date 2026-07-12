# MoonParse v1 Algorithm Decisions

Status: frozen by M1-C05. The decisions below are the implementation contract
for M2. Every optimization keeps an independently testable correctness oracle;
none may change public API semantics, canonical digests, or `.mpack` bytes.

| Area | Decision | Oracle / required evidence |
| --- | --- | --- |
| syntax storage | immutable lossless green tree plus snapshot-owned red views | width, range, field continuity, and old-snapshot invariants |
| source/edit mapping | UTF-8 `SourceIndex` and normalized composed `EditMap` | byte/point round trips including CRLF and multibyte edits |
| parsing | canonical LR(1) correctness oracle; row compression only after equivalence | JSON, expression, MoonBit corpus and stable IDs |
| ambiguity | local GSS only at declared multi-action cells | all active paths preserved and canonically ordered |
| recovery | bounded best-first Insert/Delete/Pop search | golden diagnostics and no panic/hang/allocation escape |
| incrementality | monotone reuse cursor plus green identity comparison | full/incremental tree, diagnostics, Query digest equality |
| queries | compiler-proven local cache; otherwise full execution | cache/full/incremental item equality across Native/WASM |

## Non-negotiable invariants

- A green node has no absolute position, source, parent, or snapshot reference.
  Its width is the sum of child widths; the root width equals source byte length.
  Tokens, extras, comments, newlines, ERROR text, and zero-width MISSING nodes
  are lossless CST data.
- `SourceIndex` uses UTF-8 bytes. Public ranges are half-open and code-point
  aligned. It treats CRLF as one line break while retaining the distinct CR and
  LF byte offsets.
- An edit batch is applied in caller order only after every edit is valid. Its
  composed `EditMap` has checked, ordered, non-overlapping segments.
- A reuse candidate needs matching entry LR state, byte-for-byte matching
  scanner state, no error/missing/fragile marker, no edit or lookahead overlap,
  and unchanged source bytes. A non-equal-length edit must still be able to
  share a valid right subtree.
- Syntax `changed_ranges` derive from green identity and `EditMap`; they are
  ordered, non-overlapping, merged when inseparable, and expanded only for
  lexer lookahead or structural fragility. Query-role expansion is a separate
  query-runtime operation.

## Parser and recovery

Canonical LR(1) is the correctness oracle. Row displacement, default reduction,
and identical-row deduplication are permitted compression. LR(0)-core merging is
allowed only in an independently reviewed change that proves equal action
behavior and no new action set.

A declared multi-action cell enters a graph-structured stack. Its node key is
the byte position, LR state, and complete canonical scanner-state bytes. An
active version includes a path reference and accumulated score; scores do not
belong to a merged GSS node. Work is canonically ordered by input position,
state, scanner bytes, action, production, and predecessor path. Ties resolve by
recovery cost ascending, dynamic precedence descending, error-node count
ascending, production ID ascending, then canonical path bytes.

Recovery can only Insert an expected terminal, Delete an actual token, or
PopToSync. It uses bounded best-first search and must consume input, lower stack
height, or make bounded missing progress at every step. The fixed costs are 20
to start a region, 10 to insert, `10 + min(token_byte_width, 20)` to delete,
and 5 to pop one syntax node. A candidate stabilizes only after three real
tokens or EOF.

## Limits and gates

The editor default resolves per source to at most 64 active versions, 256
recovery-frontier entries, 16 recovery actions per site, four real-token
lookahead, 100,000 query matches, 65,536 tree depth, 100,000,000 parser steps,
and 10,000,000 tree nodes. Parser steps and nodes use the min/per-byte/cap
policies frozen in the execution plan. Public builders reject invalid values;
they never clamp or wrap.

M2 cannot claim real incrementality until 20,000 fixed-seed PR edits and the
nightly one-million-edit suite show zero full/incremental mismatches. It cannot
expose the WASM node API before lossless, lifetime, sharing, and retention
invariants pass. The detailed decisions and spike results live in ADR-001
through ADR-006.
