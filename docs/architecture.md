# MoonParse architecture

MoonParse is split into a reusable MoonBit core, composition packages, host
adapters, and applications. Dependencies must point from hosts toward the core;
core packages must never import host or application code.

## Dependency graph

```text
grammar
   |
   v
tablegen
   |
   v
runtime ---> query
   |          |
   +----------+---> languagepack
                         |
                         v
                     grammars
                         |
                         v
                       root

grammar/tablegen/runtime/query/grammars
          |
          v
      wasm / cmd / scripts
          |
          v
      lsp / website
```

The diagram describes architectural flow rather than requiring every package
to import the package immediately above it. `languagepack` composes the parser
core and Query layer; `grammars` supplies embedded resources and Scanner
providers. The root package is a convenience facade. LSP and Website consume
the JavaScript/WASM distribution and do not import MoonBit packages directly.

## Package boundaries

| Package | Layer | Inputs | Outputs | Allowed project dependencies |
| --- | --- | --- | --- | --- |
| `grammar` | stable public | Grammar DSL or builder calls | `Grammar`, validation diagnostics, serialized grammar | none |
| `tablegen` | advanced | validated `Grammar` | `ParseTable`, conflicts, serialized tables | `grammar` |
| `runtime` | stable public | `ParseTable`, source, optional old tree/edit/scanner | CST, parse errors, incremental reuse | `grammar`, `tablegen` |
| `query` | stable public | CST, source, ParseTable, query text | captures, highlights, locals and binding graph | `grammar`, `tablegen`, `runtime` |
| `languagepack` | stable public | manifest and host-provided resource map | validated pack, bundle, diagnostics and corpus | `grammar`, `tablegen`, `runtime`, `query` |
| `grammars` | resource composition | core APIs and embedded Language Packs | built-in parsers, queries and scanners | `grammar`, `tablegen`, `runtime`, `languagepack` |
| root (`MoonParse`) | stable facade | DSL/Grammar and source text | typed compile/parse results and convenience strings | `grammar`, `tablegen`, `runtime`, `grammars` |
| `wasm` | host adapter | all public parser capabilities | WASM ABI and JS/TypeScript high-level API | `grammar`, `tablegen`, `runtime`, `query`, `grammars` |
| `cmd/main` | application | files, stdin and command-line options | diagnostics and generated artifacts | `grammar`, `tablegen`, `runtime`, `query` |
| `scripts` | internal tooling | grammars and benchmark/fuzz inputs | benchmark/fuzz output | `grammar`, `tablegen`, `runtime`, `grammars` |
| `lsp` | application | WASM/JS API and LSP messages | diagnostics, navigation, semantic tokens | no MoonBit package imports |
| `website` | application | WASM/JS API and browser input | playground and documentation site | no MoonBit package imports |

External `moonbitlang/core/*` imports are outside this boundary graph.

## Rules

- Core packages (`grammar`, `tablegen`, `runtime`, `query`) cannot depend on
  resource, adapter, application, or tooling layers.
- `grammar` is the leaf of the project dependency graph.
- `tablegen` may only consume `grammar`; `runtime` may only consume `grammar`
  and `tablegen`.
- `root` is a facade. Lower layers must not import it.
- Applications and adapters may compose lower layers, but no MoonBit package
  may import `cmd/main`, `wasm`, or `scripts`.
- New MoonBit packages must be registered in `api/boundaries.json` before they
  are merged.
- Cycles between project packages are forbidden even if every individual edge
  appears in an allow-list.

Run `node scripts/check-boundaries.mjs` after changing a `moon.pkg` file.

## Data flow

1. `grammar` parses and validates a DSL into a `Grammar`.
2. `tablegen` compiles it into a `ParseTable` and conflict reports.
3. `runtime` applies the table to text and returns a concrete syntax tree.
4. `query` derives structural captures, highlighting, locals, and bindings.
5. `languagepack` validates and bundles Grammar, Query, Scanner metadata and Corpus resources.
6. Root/grammars compose common use cases; WASM and CLI expose them to hosts.
7. LSP and Website provide editor and browser experiences over the host API.
