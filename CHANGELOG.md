# Changelog

All notable changes to MoonParse are recorded here. The project follows
Semantic Versioning; before 1.0, incompatible changes are limited to minor
releases and include migration guidance.

## Unreleased

### Added

- Established the P0 architecture boundary, API snapshot, and compatibility
  consumer baseline.
- Exported the existing `tree_byte_offset_to_char_col` WASM function so the
  JavaScript wrapper and declared ABI remain aligned.
- Fixed JSON5 comment tokenization exposed by the unified Website corpus gate.
- Added the filesystem-independent `languagepack` package, Language Pack and
  LanguageBundle schema v1, dual ParseTable encodings, stable diagnostics, and
  JSON/Python/MoonBit sample Packs.
- Migrated built-in JSON, Python and MoonBit parser resources to canonical
  Packs while preserving their existing public parser facades.

## 0.1.0

- Initial GLR parser generator, runtime, query engine, WASM API, CLI, LSP, and
  browser playground baseline.
