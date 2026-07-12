# MoonParse v1 Query Contract

Status: frozen by M1-C06. `Query::compile` and `Language::query` are declared
in `spec.mbt`; M2-C05 and M2-C20 implement the compiler and runtime.

## Accepted surface

v1 accepts only named nodes, anonymous tokens, wildcard nodes, fields,
captures, alternation, `?`, `*`, `+`, sibling anchors, and these predicates:

```text
#eq?       #not-eq?       #match?       #not-match?       #any-of?
```

Anything outside that set fails compilation with
`QueryError::UnsupportedFeature`; it is never silently ignored. Unknown node
and field names use `QueryError::UnknownNode` and `QueryError::UnknownField`.
Syntax failures carry a source byte offset in `QueryError::ParseError`.

`Language::query(role)` returns only the precompiled query declared in that
pack for the requested role. `Query::compile(language, source)` is a pure,
deterministic, temporary same-language compilation; it reads no files or host
state. Query and snapshot language fingerprints must match.

## Query bytecode sub-ABI

The `QueryIndex` section has one entry per precompiled query. Each entry names
its `QueryRole`, has a program range within `QueryBytecode`, and declares the
query bytecode sub-ABI. A runtime validates that sub-ABI before it decodes the
program. Query bytecode is not source text and no pack may rely on a host
callback to run it.

Compiler output is deterministic: pattern numbers are source order; capture
declaration indexes are zero-based source order within their pattern;
instruction ordinals are canonical program order. Maps used while compiling or
serializing are ordered by UTF-8 key bytes. A minor `.mpack` reader may skip an
unknown optional section, but it never interprets an unsupported query sub-ABI.

## Capture semantics and order

`Snapshot::captures(query, within)` returns every match occurrence; it does
not deduplicate semantically identical captures. The only ordering is this
`CaptureOrderKey`:

```text
node.start_byte ASC
node.end_byte ASC
pattern_index ASC
capture_declaration_index ASC
match_key lexicographic ASC
node_preorder_path lexicographic ASC
```

`node_preorder_path` is the child-index path from the query execution root to
the capture node. `match_key` is a length-prefixed byte sequence of
`(instruction_ordinal, node_preorder_path)` pairs in instruction order. Object
addresses, hash-map iteration, worker completion order, and green-node IDs may
not break ties. Native and WASM return item-for-item identical order.

`within=None` does not filter and includes EOF zero-width nodes. An explicit
empty range returns no captures. For a non-empty range, normal spans use
half-open intersection and a zero-width span at `position` is included exactly
when `range.start_byte <= position < range.end_byte`. Invalid, reversed,
out-of-source, or split-UTF-8 ranges return `QueryError::InvalidRange`.

## Incremental cache contract

Only a compiler-proven concrete-rooted pattern that does not depend on an
ancestor or sibling outside its subtree may cache by green identity. Any pattern
that cannot be proven local runs as a full query.

Every pack declares boundary node kinds per `QueryRole`. On a syntax change,
the runtime expands the syntax changed range to that role's nearest boundary,
removes captures there, and recomputes it. Roles may therefore invalidate
different regions. Locals use scope green nodes as cache units; a changed scope
is recomputed as a whole. A locals query missing its scope, definition, or
reference convention fails compilation.

The canonical query digest contains pattern index, capture name, node kind,
start byte, end byte, and flags. It excludes green IDs, object addresses, and
localized text. Cached execution and incremental execution must each be
item-for-item equal to cache-disabled execution on the final tree. Exceeding
the resolved query-match budget returns `QueryError::MatchLimitExceeded`.
