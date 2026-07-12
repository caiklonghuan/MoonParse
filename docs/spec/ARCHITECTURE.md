# MoonParse v1 Architecture Contract

Status: frozen by M1-C01. This document defines the target architecture; it is not a description of the legacy implementation.

## Product boundary

MoonParse v1 is a pure-MoonBit, editor-grade incremental parsing runtime. The runtime consumes validated immutable `.mpack` bytes and source text. Grammar compilation is an offline, deterministic operation. Hosts may adapt the runtime, but may not implement parsing, diagnostics, query evaluation, or canonical digests themselves.

## Target package tree

```text
MoonParse/
  spec.mbt                         public runtime contract
  compiler/
    spec.mbt                       public offline compiler contract
  internal/
    model/                         serializable parser, lexer, recovery, query and scanner tables
    pack/                          .mpack codec, limits, checksum and validation
    grammar/                       DSL parse, normalization and stable source-order IDs
    regex/                         regex IR and automata construction
    automata/                      canonical LR(1), witness and safe compression
    syntax/                        SourceIndex, green/red tree, EditMap and changed ranges
    engine/                        lexer, scanner VM, LR path, local GLR, recovery and reuse
    query_ir/                      query parser, validator and bytecode
    query_runtime/                 full and incremental query execution
  languages/<name>/                embedded `.mpack` construction only
  adapters/lsp/                    UTF-16 conversion and protocol transport only
  cmd/moonparse/                  filesystem/process host only
  wasm/                            one runtime ABI and resource manager only
  demo/                            fixed scenario presentation only
  tools/                           evidence, pack assembly and deterministic checks
```

## Dependency DAG

```text
internal/model
  ├─> internal/pack ──────────────┐
  ├─> internal/grammar ─> regex ─> automata
  ├─> internal/syntax ────────────┤
  ├─> internal/query_ir ──────────┤
  └─> internal/engine ────────────┤
                                  ├─> root runtime facade
internal/query_runtime ───────────┘

internal/model + grammar + pack + automata + query_ir -> compiler facade
root runtime facade -> languages/<name>
root runtime facade -> wasm
root runtime + compiler + languages/<name> -> cmd/tools/tests/examples
root runtime + wasm -> adapters/lsp and demo
```

The graph is acyclic. `internal/*` never imports the root facade, compiler, a concrete language, a host, an adapter, or a demo.

## Ownership and non-negotiable boundaries

- The root package owns all runtime public types: `Source`, coordinate values, `Language`, `Parser`, `Snapshot`, `Node`, `TreeCursor`, diagnostics, query values, and checked runtime errors.
- `compiler/` owns only offline compilation values: `PackManifest`, `PackSource`, `PackArtifact`, `CompileOutput`, `CompileDiagnostic`, `CompileSeverity`, and `CompileSpan`.
- `internal/model` owns the serializable table model. `internal/pack` and `internal/engine` must not import `internal/automata`.
- The root facade must not import `compiler/` or a concrete language package. Public signatures must not expose `internal/*` types.
- The compiler is pure: no filesystem, environment, clock, random source, or host callback.
- A language package builds `Language` exclusively from embedded `.mpack` bytes. It cannot access private tables.
- WASM consumes root runtime plus immutable pack bytes. It does not compile grammar in the browser.
- CLI, WASM, LSP, and demo are thin hosts. They cannot reimplement parser, diagnostics, query, or digest semantics.
- LSP UTF-16 conversion is confined to `adapters/lsp`; all runtime coordinates are UTF-8 byte offsets and byte columns.

## Runtime lifetime contract

`Source`, `Language`, and `Snapshot` are immutable owned values. `Node` and `TreeCursor` retain their `Snapshot`; old snapshots remain valid after reparsing. Green identity is an internal optimization and must not appear in public APIs, serialization, or canonical digests.

## Enforcement

`api/boundaries.json` is the machine-readable form of this document. Any `moon.pkg` dependency or public-interface change must pass the boundary checker before merge.
