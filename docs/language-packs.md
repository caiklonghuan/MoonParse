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

## Pack CLI

```sh
moonparse pack init my-language
moonparse pack check my-language
moonparse pack test my-language
moonparse pack test my-language --update
moonparse pack build my-language
moonparse pack build my-language --target bundle --target moonbit --target wasm --target npm
```

Explicit targets are generated from one in-memory Bundle under `dist/<id>`.
Use `--out-dir` to change that root and `--package-name` to override the default
NPM name `@moonparse-language/<id>`. The NPM target is deliberately thin and
declares `moonparse` as a peer dependency; the WASM target is self-contained.

The regular `parse` and `query` commands accept `-b/--bundle`. Bundle parsing
automatically activates its Scanner, while query patterns named `highlights`,
`locals`, or `bindings` select the corresponding compiled Pack query.

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
