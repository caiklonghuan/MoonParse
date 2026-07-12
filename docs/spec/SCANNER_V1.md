# MoonParse v1 Portable Scanner Contract

Status: frozen by M1-C06. M2-C04 and M2-C15 implement the lexer and scanner VM.

## Supported scanner model

The v1 lexer supports literals, regular expressions, extras, keyword remaps,
lexer modes, `nested(open, close)`, and
`delimited(start, end, escape, allow_newline)`. It does not support arbitrary
host callbacks.

When multiple tokens are available, selection is exactly:

1. the current parse state's valid-token set;
2. longest UTF-8 byte match;
3. highest explicit lexical priority;
4. literal before regex;
5. earliest canonical grammar declaration.

The compiler emits `Lexer` metadata and, when needed, `ScannerBytecode`. Any
manifest or lexer declaration using nested, delimited, or scanner capability
requires `ScannerBytecode`. Without it, scanner program/state counts are zero
and the manifest scanner capability is false.

## Scanner bytecode sub-ABI and state

Each scanner bytecode payload identifies a scanner sub-ABI. The runtime checks
that ABI before executing an instruction. Scanner state has one canonical
serialization which includes, at minimum, the mode stack, nesting depth,
delimiter, escape state, and scanner-program version.

Green nodes retain immutable scanner-state references whose canonical bytes are
available for reuse checks. An implementation may hash those bytes to accelerate
interning, but a hash hit is never sufficient for semantic equality: reuse
compares complete canonical bytes. This remains true across parser and snapshot
instances with an equal language fingerprint.

Scanner programs, states, and bytecode are bounded by the `.mpack` v1 resource
limits. Malformed state encodings, an unsupported sub-ABI, or a state transition
outside the declared bounds rejects the pack or parse deterministically; it
cannot silently fall back to host behavior.

## Import boundary

An imported Tree-sitter external scanner may produce an explicitly unsupported
interface and a compatibility report. It must not produce a production Pack
that appears successful while omitting scanner semantics. A portable v1 Pack is
self-contained: no C, JS, MoonBit host source, absolute paths, build clocks, or
random IDs are part of its scanner representation.
