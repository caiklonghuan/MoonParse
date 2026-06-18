# Generated artifacts

MoonParse follows a **published artifact in Git** policy: one authoritative
runtime distribution is tracked for offline use, while derived copies are
rebuilt on demand.

## Tracked

- `wasm/moonparse.wasm`: authoritative release WASM.
- `wasm/moonparse.js` and `wasm/moonparse.d.ts`: public host wrapper sources.
- `wasm/build-info.json`: software version, ParseTable schema, and build commit.
- `pkg.generated.mbti` in each MoonBit package: public API snapshots.
- Files under `api/snapshots/`: WASM, TypeScript, CLI and LSP API baselines.
- `grammars/language_packs_generated.mbt`: embedded built-in Pack resources.
- `website/src/data/languagePackResources.js`: Website view of the same Packs.

## Generated and ignored

- `_build/`, `build/`, `dist/`, and `out/`.
- `website/public/moonparse.js` and `moonparse.wasm`.
- `website/src/data/precompiledTables.js`.
- LSP and Website production `dist/` directories.

Run `npm run build` to update the authoritative WASM. Run
`npm run build:check` to rebuild into `_build` and verify that the tracked
artifact is fresh. Website's `npm run build` synchronizes its runtime copies
before precompiling grammars.

Generated files must not be edited manually. API snapshots are the exception:
they are generated but intentionally tracked, and updates must be explicit.
Language Pack embeddings are also tracked; `languages/` is authoritative and
`scripts/embed-language-packs.mjs --check` enforces freshness.
