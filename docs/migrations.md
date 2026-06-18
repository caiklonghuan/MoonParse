# Migration guide

## Unreleased

No user migration is required. The P0 stabilization work records the current
0.1.0 APIs as the compatibility baseline without changing their behavior.
The WASM ABI addition `tree_byte_offset_to_char_col` is additive and requires
no caller changes.

JSON, Python and MoonBit resources now originate in `languages/<id>`. Existing
MoonBit constants, parser functions, and `grammars/<id>.grammar` paths remain
available. Language tooling should adopt `languagepack` and `LanguageBundle`;
the legacy Grammar paths are compatibility mirrors for at least one minor
release.

## Policy

- Additive APIs are documented in the changelog.
- Deprecated APIs remain available for at least one minor release and should
  be moved to the package's `deprecated.mbt` where applicable.
- Breaking changes before 1.0 require a minor version bump and a concrete
  before/after example in this document.
- Serialized ParseTable and future Language Bundle formats use independent
  schema versions. A package version bump does not imply a schema change.
