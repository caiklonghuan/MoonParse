# MoonParse v1 Compiler Contract

Status: frozen by M1-C03. The public declarations are in `compiler/spec.mbt`; M2-C06 supplies the implementation.

`compile_pack` is a pure function from immutable `PackSource` to `CompileOutput`. Equal inputs must produce byte-identical artifacts and identically ordered diagnostics. It does not read files, environment variables, clocks, random sources, or runtime parser objects.

All `grammar_name` and `source_name` values are logical UTF-8 relative paths using `/`. The compiler rejects empty, absolute, backslash-containing, NUL-containing, `.`/`..`-segmented, duplicate, and Unicode simple-case-fold-colliding paths with stable diagnostics. Every query role and scanner source appears at most once; duplicate declarations diagnose rather than use last-write-wins.

An error-severity diagnostic requires `CompileOutput::artifact()` to return `None`. Diagnostic order is by logical source-path UTF-8 bytes, start byte, then code. `PackArtifact::bytes()` returns a defensive copy, and its fingerprint is derived from immutable canonical bytes.
