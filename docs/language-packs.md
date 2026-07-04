# Language Packs

A Language Pack is the canonical source unit for one MoonParse language. It
groups a versioned manifest, Grammar, optional Query and Scanner metadata, and
Corpus tests without coupling the MoonBit core to a filesystem.

## Layout

```text
languages/<id>/
  language-pack.json
  grammar/main.grammar
  queries/highlights.scm
  queries/locals.scm
  queries/bindings.scm
  queries/folding.scm
  queries/modules.scm
  scanner/scanner.json
  corpus/*.txt
```

The paths above are defaults. A manifest may override them, but absolute paths,
backslashes, drive prefixes, empty segments, `.` and `..` are rejected.

The manifest and bundle formats have independent `schemaVersion` values. Pack
release versions use SemVer. Scanner APIs and ParseTable data retain their own
versions. See the machine-readable schemas under [`schemas/`](../schemas/).

## Loading model

Hosts read files and create `LanguagePackSource(manifest, files)`. The
`languagepack` MoonBit package then performs manifest, resource, Grammar,
ParseTable, Query, Scanner and Corpus validation. It never opens a file itself,
so the same logic works in native, Node and WASM hosts.

`LanguageBundle` contains both ParseTable JSON and binary bytes. Serialized
bundles carry both representations and reject corruption or semantic mismatch.
Corpus resources remain in the Pack and are not shipped in the runtime bundle.

## Modules query contract

Packs that declare `queries.modules` enable import-aware workspace resolution.
The query may emit these captures:

- `module.name`: optional logical module name.
- `module.export`: a definition name that is public outside its package.
- `import.source`: imported module/package path.
- `import.alias`: optional alias; the final source path segment is the default.
- `module.reference`: alias used by a qualified reference.
- `module.member`, `module.member.value`, or `module.member.type`: referenced
  member and namespace.

`import.source` and its optional alias must share one `match_id`. A qualified
reference must contain exactly one `module.reference` and one member capture in
the same match. Hosts ignore malformed, duplicate, or out-of-range match groups.
Capture text is trimmed; matching quotes and a leading `@` on aliases are
removed. `MoonLanguage.modules(tree)` exposes the normalized capture stream and
returns an empty array for packs without the capability.

The MoonBit pack combines this query with `moon.mod.json`, `moon.work`, and
`moon.pkg`: package-private declarations resolve only inside their package,
while imported packages expose only `pub` declarations.

## Pack CLI

```sh
moonparse pack init my-language
moonparse pack check my-language
moonparse pack test my-language
moonparse pack test my-language --update
moonparse pack build my-language
moonparse pack build my-language --target bundle --target moonbit --target wasm --target npm
moonparse pack build my-language --target lsp --target vscode --target web
```

Explicit targets are generated from one in-memory Bundle under `dist/<id>`.
Use `--out-dir` to change that root and `--package-name` to override the default
NPM name `@moonparse-language/<id>`. The NPM target is deliberately thin and
declares `moonparse` as a peer dependency; the WASM target is self-contained.
The `lsp`, `vscode`, and `web` targets are peers of the distribution targets:
they copy the canonical runtime files and the same Bundle, but do not implicitly
create a separate `wasm/` target directory.

The generated LSP target copies the repository's canonical `lsp/src` runtime
code, excluding tests. The generated VS Code target embeds that LSP target under
`server/`, packages a VSIX, and obtains document highlight, folding, document
symbol, definition, references, diagnostics, rename, and completion from the
same `server/dist` code as the built-in LSP. TextMate grammar generation remains
a v1 skeleton (`scopeName`, `fileTypes`, empty `patterns`); semantic highlighting
comes from LSP semantic tokens.

The regular `parse` and `query` commands accept `-b/--bundle`. Bundle parsing
automatically activates its Scanner, while query patterns named `highlights`,
`locals`, `bindings`, or `folding` select the corresponding compiled Pack query.

## Query conventions

See also [`query/QUERY_CONTRACT.md`](../query/QUERY_CONTRACT.md) for the
editor-facing contract shared by LSP, Website, WASM/JS, and generated tools.

Highlight captures use the names exported by the `query` package. Dotted names
keep their full spelling in the Bundle; semantic-token consumers map them by
their first segment, so `keyword.control` maps to `keyword` and
`string.special` maps to `string`. Unknown highlight names are ignored by LSP
consumers.

Binding queries use `@scope.<kind>`, `@definition.<kind>`, and
`@reference.<kind>`. A `@reference.soft.<kind>` capture still resolves to a
visible definition, but does not produce an unresolved diagnostic when no
definition exists. A declaration node may be captured as `@symbol.<kind>` in
the same query match as its name's `@definition.<kind>` capture; matching kinds
attach the declaration's full range to that definition.

Folding queries use `@fold`, `@fold.region`, `@fold.comment`, or
`@fold.imports`. The query reports structural ranges; editors are responsible
for removing single-line ranges and duplicate spans.

Binding diagnostics use stable LSP codes: unresolved references are warnings
with `MP_BIND_UNRESOLVED`; duplicate definitions and ambiguous references are
errors with `MP_BIND_DUPLICATE` and `MP_BIND_AMBIGUOUS`. Rename is intentionally
conservative: a server should only rename a single-document binding group when
the target resolves uniquely, the new name is a valid word token, and a dry-run
does not introduce duplicates, shadowing, ambiguity, unresolved references, or
other binding changes.

`pack init` without an id starts a TTY-only, line-oriented wizard. On Windows,
prefer the non-interactive `--name` option for non-ASCII display names. Pack
diagnostics support `moonparse pack --format json ...`; this option is scoped
to the Pack command group and does not change legacy CLI output.

Corpus format `moonparse-corpus-v1` remains unchanged. Version 2 adds an
indented, inline full-tree snapshot:

```text
====
number
====
42
----
error: ok
sexp:
  (document (number))
```

Snapshot updates require a manifest that explicitly selects
`moonparse-corpus-v2`. Each test invocation rebuilds its Bundle to avoid using
stale parse tables; cached or prebuilt Bundle testing is a future optimization.

## Built-in packs

JSON, Python and MoonBit under `languages/` are canonical. Run:

```sh
node scripts/embed-language-packs.mjs --write
node scripts/embed-language-packs.mjs --check
```

The generator maintains tracked MoonBit, Website, and LSP embeddings plus the
legacy `grammars/<id>.grammar` compatibility mirrors. Python resolves the
`python-indent` Scanner through a host-provided `PackScannerProvider`.
