# Language Pack core

`languagepack` is the filesystem-independent MoonBit core for loading and
checking Language Pack manifests, compiling Grammar and Query resources, and
building portable `LanguageBundle` values.

Hosts read a directory into `LanguagePackSource`; this package never opens
files directly. Default paths are `grammar/main.grammar`, `queries/*.scm`, and
`corpus/*.txt`. Manifest paths may override them but cannot be absolute or
escape the Pack root.

Corpus v1 provides error and S-expression fragment assertions. Corpus v2 adds
the optional inline `sexp:` full-tree snapshot used by `moonparse pack test
--update`; v1 remains unchanged and is never upgraded implicitly.

The canonical schemas are:

- [`language-pack.schema.json`](../schemas/language-pack.schema.json)
- [`language-bundle.schema.json`](../schemas/language-bundle.schema.json)

Run `node scripts/embed-language-packs.mjs --check` after modifying one of the
built-in Packs under `languages/`. Use `--write` to intentionally refresh the
MoonBit and Website embedded resources.
