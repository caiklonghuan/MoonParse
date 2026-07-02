# Language Intelligence Query Contract

Language Pack query resources use one shared contract across the CLI, WASM/JS,
LSP, Website, and generated language tools.

## Highlight Captures

Highlight captures may use dotted names such as `keyword.control` or
`string.special`. Semantic-token consumers map by the first segment and ignore
unknown capture families. For example, `keyword.control` maps to the LSP
`keyword` token family.

## Binding Captures

Binding queries use:

- `@scope.<kind>` for lexical scopes.
- `@definition.<kind>` for definitions.
- `@reference.<kind>` for strict references.
- `@reference.soft.<kind>` for references that participate in navigation but do
  not produce unresolved diagnostics when no definition is visible.
- `@symbol.<kind>` for the full declaration node paired with a definition from
  the same query match.

When `@symbol.<kind>` and `@definition.<kind>` have the same kind in one match,
the symbol capture supplies the declaration range used by document symbols. If
the kinds do not match, consumers fall back to the definition name range.

## Folding Captures

Folding queries use:

- `@fold`
- `@fold.region`
- `@fold.comment`
- `@fold.imports`

LSP consumers filter single-line ranges and normalize ranges that end at the
first column of the next line.

## Diagnostics

Binding diagnostics use stable LSP codes:

- `MP_BIND_UNRESOLVED`: unresolved strict reference, warning.
- `MP_BIND_DUPLICATE`: duplicate definition in the same namespace and scope,
  error.
- `MP_BIND_AMBIGUOUS`: more than one candidate in the nearest matching scope,
  error.

## Rename

Rename is conservative and single-document in P1. A server should rename only
when the target resolves uniquely, the new name matches the grammar word token,
and a dry-run rebuild proves the edit does not introduce duplicate, shadowing,
ambiguous, unresolved, or binding-drift behavior.
