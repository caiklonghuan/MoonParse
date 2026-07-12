# M1 Algorithm Spike Reports

Status: completed design spikes for M1-C05. These are not performance claims
and do not replace M2 conformance evidence. Each result selects the structure
to implement and names the later machine gate that can overturn it.

| Spike | Question | Result | Follow-up evidence |
| --- | --- | --- | --- |
| S01 | Can immutable green nodes preserve old snapshots while supporting shared reparses? | ADOPT green/red split; no global hash-cons or generation arena | M2-C08 invariants and M2-C19 differential |
| S02 | Can byte-only coordinates make CRLF and batch edits deterministic? | ADOPT UTF-8 SourceIndex plus checked composed EditMap | M2-C02 coordinate golden tests |
| S03 | Can a compact table retain an auditable parser correctness baseline? | ADOPT canonical LR(1) oracle before row compression | M2-C07 compiler/table oracle |
| S04 | Can ambiguity remain local without throwing away parse histories? | ADOPT GSS at declared multi-action cells; preserve all path scores | M2-C09 GSS fixtures |
| S05 | Can malformed editor input stay useful under hard resource bounds? | ADOPT Insert/Delete/Pop bounded best-first recovery | M2-C17 recovery/adversarial suite |
| S06 | Can Query be incremental without stale captures? | ADOPT proof-gated local cache and full-execution fallback | M2-C20/C21 equality tests |

All six are **ADOPT** decisions because they preserve a direct correctness
oracle. Any later result that violates its listed evidence condition changes
the ADR to ADJUST or REJECT before an optimization can ship.
