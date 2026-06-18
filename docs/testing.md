# Testing and CI

MoonParse uses Node.js 22 and the MoonBit toolchain recorded below:

- `moon 0.1.20260417+8650a31`
- `moonc 0.9.0+69d374a17`

Newer toolchains may be evaluated separately, but release artifacts and the P0
baseline must be reproduced with this compatibility baseline. CI installs the
same toolchain identifier through `hustcer/setup-moonbit`.

## MoonBit

```sh
moon check
moon test
moon fmt --check
moon info
git diff --exit-code -- "**/pkg.generated.mbti"
```

## Architecture and public API

```sh
npm run test:scripts
npm run check:boundaries
npm run check:api
npm run check:wasm-abi
npm run check:version
npm run check:docs
```

Use `node scripts/api-snapshots.mjs --write` only when intentionally accepting
a public API change. Update the changelog and migration guide in the same
change.

## WASM

```sh
npm run build:check
moon test wasm
npm run test:wasm
```

The Node smoke test requires Node 22 because the WASM build uses JS string
builtins.

## LSP

```sh
cd lsp
npm ci
npm run build
npm test
```

## Website

```sh
moon build --target wasm-gc wasm
cd website
npm ci
npm run test:corpus
npm run build
```

Website build first synchronizes the authoritative runtime from `wasm/`, then
regenerates precompiled grammar tables.
