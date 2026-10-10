# SV-16 Rev A — Clean Rebuild Project

Original custom 16-bit microcontroller, modeled as a fully connected,
executable, testable Simulink design. Governed by the master prompt
(connection integrity is a hard requirement: **a model with dangling lines is
a failed model**).

The legacy `/SV16.slx` at the repo root is **reference only** — it is never
copied. Its full dissection is in
[`Verification/legacy_model_audit.md`](Verification/legacy_model_audit.md).

---

## ⚠️ Honest environment note (read first)

This repository was prepared in a sandbox **without MATLAB/Simulink**
(installation is impossible here: no license, no network access to MathWorks).
Therefore, per the master prompt's own status rules:

| Item | Status |
|---|---|
| Stage 0 — legacy model inspection | **PASS** (structural evidence in `Verification/legacy_model_audit.md`) |
| Stage 1 — architecture spec + decision log | **PASS** (documents complete; 3 decisions FROZEN-v0.1 await your veto window) |
| Wiring API proof (`sv16_api_check`) | **NOT TESTED** — runs in your MATLAB |
| Auditor (`sv16_audit`) | **NOT TESTED** — runs in your MATLAB |
| Stages 2–6 builders + tests | **NOT TESTED** — runs in your MATLAB |
| Stages 7–13 | **NOT IMPLEMENTED** (by design, in stage order) |

Nothing here is labeled PASS based on unverified claims. The scripts are
written to fail loudly rather than guess (see `sv16_setp`, `sv16_lib_probe`).

## Quick start (your R2026a machine)

```matlab
cd SV16_RevA/Scripts        % or addpath it
sv16_api_check              % 1. prove the wiring method in THIS MATLAB
sv16_build_all              % 2. build stages 2–6 with audit+test gates & milestones
sv16_run_tests              % 3. full regression, writes Verification/test_results.md
sv16_report                 % 4. writes Verification/session_report.md
```

`sv16_build_all` implements the CRITICAL STOP CONDITION: after each subsystem
it runs the connection-integrity audit **and** the functional tests; any
failure aborts the build naming the exact subsystem/block/port. Milestones
are snapshotted to `Milestones/` only after both gates pass.

## Layout

```
SV16_RevA/
├── Simulink/        SV16_RevA.slx (created by sv16_new_model in MATLAB)
├── Scripts/         all builders, auditor, tests (pure MATLAB, self-checking)
├── Architecture/    architecture_specification, instruction_set, register_map,
│                    memory_map, decision_log
├── Verification/    legacy_model_audit, test_plan, generated artifacts
└── Milestones/      stage snapshots (created after verified gates)
```

## Architecture in one line

8 × 16-bit GPRs (R0–R7, 2R/1W), 32-bit byte-addressed PC, 32-bit IR, 5-bit
opcode / R-I-B-J formats, multi-cycle FETCH→DECODE→EXECUTE→MEMORY→WRITEBACK,
flags Z/N/C/V, Harvard IMEM/DMEM, synchronous active-high reset. Full detail:
`Architecture/architecture_specification.md`; single source of truth for
encodings: `Scripts/sv16_isa.m`.

## Decisions — ratified and FROZEN (2026-10-10)

1. **Instruction encoding = ISA v0.1** (D-005/D-006): 5-bit opcode at
   [31:27], 3-bit register fields, R/I/B/J formats — exactly as in
   `Architecture/instruction_set.md`.
2. **Byte-addressed PC, +4 per instruction** (D-003).
3. **MUL/DIV retained** (D-011; ÷0 → 0xFFFF, no trap), memories 4096 words
   each (D-013).

No open architectural decisions remain. Next: verification of Stages 2–6 on
the user's MATLAB, then Stages 7–9 implementation.

## Key scripts

| Script | Purpose |
|---|---|
| `sv16_lib_probe` | Verifies every required library block exists in YOUR release before anything is built |
| `sv16_api_check` | Proves port-handle wiring creates real, round-trip-verifiable lines; compiles+simulates a scratch model |
| `sv16_isa` | Architecture constants, opcode table, assembler, decode, builtin test programs |
| `sv16_audit` | Connection-integrity auditor (ports, lines, branches, boundaries, grounds/terminators, compile) → `Verification/connection_audit.txt` |
| `sv16_build_all` | Stage-ordered build with audit+test gates, STOP CONDITION, milestone snapshots |
| `sv16_run_tests` | Independent-reference test suites → `Verification/test_results.md` |

## Roadmap (master prompt stages)

Done here: 0, 1, tooling for 2–6. Next MATLAB sessions: run gates for 2–6,
then implement 7 IR/decoder, 8 datapath, 9 control unit, 10 memory, 11
full-CPU execution tests, 12 peripherals, 13 integration/final verification —
each behind the same four-category quality gate (functional, structural,
Simulink, visual).
