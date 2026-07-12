# `.mpack` v1 fixture registry

Status: design frozen by M1-C04. M2-C03 creates the binary fixtures and makes
this registry executable. Fixture bytes are source-controlled; generated
temporary packs belong only under `_build/work/`.

Each fixture has one purpose. Tests must assert the stable `PackError` family
shown below, never merely that loading failed.

| ID | File name | Shape | Expected outcome |
| --- | --- | --- | --- |
| G01 | `minimal-json.mpack` | smallest valid Pack with all mandatory sections and zero queries | loads; stable fingerprint golden |
| G02 | `moonbit-complete.mpack` | full MoonBit Pack, queries and scanner when required | loads; stable fingerprint, IDs, and query-index golden |
| G03 | `deterministic-a.mpack` | clean compilation of the fixed source manifest | byte-identical to G04 and G05 |
| G04 | `deterministic-b.mpack` | second clean-process compilation of G03 source | byte-identical to G03 and G05 |
| G05 | `deterministic-c.mpack` | third clean-process compilation of G03 source | byte-identical to G03 and G04 |
| C01 | `truncated-header.mpack` | fewer than 32 bytes | `PackError::Truncated` |
| C02 | `truncated-section.mpack` | declared payload ends after file length | `PackError::Truncated` or `InvalidOffset` as fixed by validator stage |
| C03 | `offset-overflow.mpack` | `offset + length` overflows u32 / checked host index | `PackError::InvalidOffset` |
| C04 | `overlapping-sections.mpack` | two valid-looking payload ranges intersect | `PackError::InvalidOffset` |
| C05 | `duplicate-section.mpack` | duplicate section kind in ordered TOC | `PackError::DuplicateSection` |
| C06 | `bad-crc.mpack` | one changed byte with stale header CRC | `PackError::ChecksumMismatch` |
| C07 | `unknown-required.mpack` | unsupported section kind with `REQUIRED` flag | `PackError::InvalidModel` |
| C08 | `unknown-optional.mpack` | unsupported section kind with `NONE` flag | loads; unknown bytes skipped |
| C09 | `missing-required.mpack` | omits one required registry section | `PackError::MissingSection` |
| C10 | `bad-runtime-abi.mpack` | runtime ABI is not one | `PackError::UnsupportedRuntimeAbi` |
| C11 | `bad-format-major.mpack` | format major is not one | `PackError::UnsupportedFormat` |
| C12 | `resource-bomb.mpack` | bounded file declaring counts above a fixed ceiling | `PackError::LimitExceeded` without disproportionate allocation |
| C13 | `query-index-without-bytecode.mpack` | non-zero query index but no QueryBytecode | `PackError::InvalidModel` |
| C14 | `scanner-capability-without-bytecode.mpack` | scanner capability but no ScannerBytecode | `PackError::InvalidModel` |
| C15 | `nonzero-padding.mpack` | otherwise valid layout with a non-zero alignment byte | `PackError::InvalidOffset` |
| C16 | `duplicate-manifest-key.mpack` | manifest JSON repeats a key | `PackError::InvalidModel` |

The test harness labels malformed samples by this registry ID, uses fixed source
manifests and toolchain locks for G03--G05, and checks that a failure is
repeatable on Native and WASM. It does not accept a pack merely because one
backend happens to load it.
