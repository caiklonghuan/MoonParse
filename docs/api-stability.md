# API stability policy

MoonParse is currently pre-1.0. Stability is therefore explicit per surface,
not inferred merely from a symbol being `pub`.

## Stability levels

### Stable public

- Root typed and documented convenience APIs.
- Grammar parsing, builder, validation, and serialization APIs.
- Runtime parse/CST/incremental APIs.
- Query compile/execute/highlight/binding APIs.
- Language Pack manifest, diagnostics, bundle and host-source APIs.
- High-level JavaScript API: `loadMoonParse`, `MoonParser`, `ParseTree`,
  `TreeCursor`, and `MoonQuery`.

Additive changes are allowed. Removal, signature changes, or semantic changes
require a version bump, changelog entry, migration note, and a deprecation
period of at least one minor release.

### Advanced

- Table generation stages and LR data structures.
- Public fields of `ParseTable` and related construction types.
- Low-level integer-handle WASM exports.
- ParseTable JSON and binary representations.

These APIs are supported and tested but may evolve before 1.0. Changes must
still update snapshots and migration notes. Serialized representations carry a
schema version independently of the package version.

### Application

- CLI commands, flags, output routing, and exit codes.
- LSP standard protocol behavior and custom configuration.
- Website routes and UI behavior.

Existing CLI commands and exit codes are compatibility surfaces. Standard LSP
methods remain protocol-compatible; MoonParse-specific LSP settings are
experimental until 1.0. Website internals are not a programmatic API.

### Internal

- Development scripts, fuzz/benchmark entrypoints, generated sources, caches,
  and build directories.
- Non-exported MoonBit and TypeScript implementation details.

Internal code may change without migration notes, provided public snapshots and
consumer tests remain unchanged.

## Review requirements

MoonBit interfaces are snapshotted in tracked `pkg.generated.mbti` files. WASM
exports, TypeScript declarations, and CLI help have snapshots under
`api/snapshots/`.

Any public API change must:

1. update the relevant generated snapshot;
2. add an entry to `CHANGELOG.md`;
3. describe compatibility and migration in `docs/migrations.md`;
4. keep compatibility consumer examples passing;
5. follow the versioning and deprecation policy.

Snapshot updates must be explicit (`--write`). Check commands never rewrite the
working tree.
