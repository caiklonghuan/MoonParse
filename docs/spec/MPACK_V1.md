# MoonParse `.mpack` v1 Binary Format

Status: frozen by M1-C04. M2-C03 implements the encoder, decoder, and
validator. This document is normative for every v1 producer and consumer.

## Encoding and acceptance order

All integers are unsigned little-endian values. A v1 pack is at most
`67_108_864` bytes. Decoders must reject an input at the first failed
validation condition and must validate counts and `count * element_size`
before allocating.

The acceptance order is fixed:

1. Read the fixed header and verify magic, reserved bytes, format major, and
   exact runtime ABI.
2. Verify `file_length` equals the supplied byte length and is within the
   pack-size limit.
3. Verify the TOC range, its count limit, and the CRC-32/ISO-HDLC checksum.
4. Decode every TOC entry with checked addition; reject duplicate kinds,
   overlaps, ranges in the header/TOC, and non-zero alignment padding.
5. Reject an unknown required section; skip an unknown optional section.
6. Require every mandatory section, then validate section-local limits and
   all cross-section invariants.

An invalid input returns a stable `PackError`; it must never cause a panic,
an unbounded allocation, or a partial `Language` value.

## Header and table of contents

The header is exactly 32 bytes.

| Offset | Size | Field | Required v1 value / meaning |
| ---: | ---: | --- | --- |
| 0 | 8 | `magic` | `4D 50 41 43 4B 0D 0A 1A` |
| 8 | 2 | `format_major` | `1` |
| 10 | 2 | `format_minor` | `0` |
| 12 | 2 | `runtime_abi` | exact value `1` |
| 14 | 2 | `flags` | reserved for file-level v1 flags; must be `0` |
| 16 | 4 | `file_length` | complete file byte length |
| 20 | 2 | `section_count` | `0..64` |
| 22 | 2 | `reserved` | `0` |
| 24 | 4 | `toc_offset` | `32` in v1 |
| 28 | 4 | `payload_crc32` | CRC-32/ISO-HDLC of `bytes[32:file_length]` |

The TOC immediately follows the header. Each entry is exactly 12 bytes.

| Entry offset | Size | Field |
| ---: | ---: | --- |
| 0 | 2 | `section_kind` |
| 2 | 2 | `section_flags` |
| 4 | 4 | `offset` |
| 8 | 4 | `length` |

Entries are strictly ascending by `section_kind`; kinds are unique. Section
payloads start on an 8-byte boundary, do not overlap each other or the
header/TOC, and every intervening padding byte is zero. `offset + length` is
checked before comparison with `file_length`.

`section_flags` accepts only `NONE = 0` and `REQUIRED = 1`. A producer marks
every v1 mandatory section `REQUIRED`. An unknown section with `REQUIRED` is
rejected; an unknown section with `NONE` is skipped. There is no generic
section compression in v1.

The language fingerprint is the lowercase hexadecimal SHA-256 of the complete
canonical pack bytes. It is not serialized inside the bytes it identifies.

## Section registry

The following sections are mandatory.

| Kind | Name | Canonical content |
| ---: | --- | --- |
| 1 | `Manifest` | RFC 8785 canonical UTF-8 JSON: name, version, license, source, capabilities |
| 2 | `Strings` | deduplicated UTF-8 string table |
| 3 | `SymbolsFields` | symbols, fields, node schema, stable IDs |
| 4 | `Lexer` | DFA, valid-token metadata, lexer sub-ABI |
| 5 | `Parser` | canonical LR(1) action/goto, productions, compressed rows |
| 6 | `Recovery` | synchronization metadata and recovery policy |
| 7 | `QueryIndex` | query role/name, bytecode ranges, query sub-ABI |

The following sections are optional.

| Kind | Name | Canonical content |
| ---: | --- | --- |
| 8 | `QueryBytecode` | precompiled Query programs |
| 9 | `ScannerBytecode` | serializable scanner VM programs |
| 10 | `DebugMap` | source ranges and conflict witnesses, never absolute paths |

Parse-table compression is limited to row displacement, default actions, and
identical-row deduplication. Distribution may create a separately compressed
artifact with locked Brotli parameters, but those bytes are not canonical
`.mpack` bytes.

## Cross-section invariants

- `QueryIndex` is always present and may contain zero entries.
- A non-empty `QueryIndex` requires `QueryBytecode`. Each program range lies
  within it and program ranges do not overlap.
- If `QueryBytecode` is absent, `QueryIndex.item_count` is zero.
- A nested, delimited, or scanner capability declared by `Manifest` or `Lexer`
  requires `ScannerBytecode`.
- Without `ScannerBytecode`, scanner program and state counts are zero and the
  manifest scanner capability is false.
- Manifest JSON uses RFC 8785 JCS, is valid UTF-8, and rejects duplicate keys.
  Producers sort serialized map keys by UTF-8 bytes; no result may depend on
  host map iteration order.
- Every query and scanner bytecode payload declares its own sub-ABI. Its ABI
  is validated before its instructions are interpreted.

Runtime ABI is an exact compatibility boundary: any `runtime_abi != 1` is
`PackError::UnsupportedRuntimeAbi`, not a request for migration. A differing
format major is rejected. A newer minor may only add known-to-be-optional
sections; all other v1 rules remain in force.

## Deterministic production

Symbol, field, production, state, and query IDs derive from canonical source
order. Before serialization, maps are sorted by UTF-8 key bytes. Identical
`PackSource` values must produce byte-identical packs in three clean-process
builds.

Packs are runtime artifacts, not source archives. They must not contain grammar
DSL/JSON, query source, corpus or snapshots, duplicate JSON/binary parse tables,
host C/JS/MoonBit source, build timestamps, absolute paths, or random IDs.

## Resource limits

| Limit | Value |
| --- | ---: |
| pack bytes | 67,108,864 |
| sections | 64 |
| strings | 1,000,000 |
| symbols | 262,144 |
| parser states | 1,000,000 |
| productions | 1,000,000 |
| query programs | 1,024 |
| query bytecode bytes | 16,777,216 |
| scanner states | 65,536 |

These are ceilings, not preallocation sizes. A malformed pack may not trigger
an allocation disproportionate to the supplied file size.

## Compatibility and test fixtures

Every format change adds a golden pack, a malformed pack, and migration notes.
The fixture registry and expected validator outcome are tracked in
[`tests/fixtures/mpack/v1/README.md`](../../tests/fixtures/mpack/v1/README.md).
M2-C03 turns that registry into executable round-trip, compatibility,
determinism, and corrupt-input tests.
