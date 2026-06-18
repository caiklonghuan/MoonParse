# Compatibility policy

MoonParse follows the single SemVer value in the repository root `VERSION`.
Data formats use their own `schemaVersion` and do not inherit the software
version.

- Patch releases fix defects and do not remove public interfaces.
- Minor releases add capabilities. Before 1.0, an unavoidable incompatible
  change requires a changelog entry and migration note.
- Major releases carry incompatible changes after 1.0.
- Deprecated MoonBit blocks stay available for at least one minor release and
  should be moved to the package's `deprecated.mbt`.
- Existing CLI commands, arguments, and exit codes remain compatible by
  default.
- WASM exports are additive. Removing or changing an export signature is a
  breaking change.
- Standard LSP methods remain protocol compatible; MoonParse-specific settings
  are experimental before 1.0.
- Unknown scanner identifiers, corrupt serialized data, and unsupported schema
  versions must fail explicitly rather than silently degrade.

Generated artifacts record software version, schema version, and source commit
in `wasm/build-info.json`. Detailed surface stability levels and review rules
are defined in [api-stability.md](api-stability.md).
