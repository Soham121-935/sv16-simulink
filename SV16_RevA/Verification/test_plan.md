# SV-16 Rev A — Test Plan

Every test computes its expected results **independently in MATLAB** (never by
reading the DUT's own outputs back as the expectation) and asserts observed ==
expected. A test passes only on genuine match. Statuses per the master prompt:
PASS / FAIL / NOT TESTED / BLOCKED / NOT IMPLEMENTED.

## Harness contract

- Each subsystem test builds `test_<SUBSYSTEM>.slx` in a temp folder:
  stimulus via `From Workspace` (time-stamped vectors, fixed step `Ts`),
  DUT subsystem under test, `To Workspace` logging of every output.
- `sv16_run_tests.m` simulates each harness with `sim()`, extracts logs,
  compares against expected vectors, and writes `Verification/test_results.md`.
- Structural gate for every subsystem: `sv16_audit` PASS **and** model update
  (compile) PASS — a functional pass with a structural failure is a FAIL.

## Stage 2 — CLOCK_RESET

| ID | Test | Checks |
|----|------|--------|
| TC-CR-01 | Reset asserted cycles 0–1 | reset output = 1 for first 2 clocks, then 0 |
| TC-CR-02 | Clock period | clock toggles at exactly Ts; 50% duty |
| TC-CR-03 | Nothing floats | clk/reset driven every cycle (audit covers wiring) |

## Stage 3 — REGISTER_BANK

| ID | Test | Checks |
|----|------|--------|
| TC-RF-01 | Reset state | RD1/RD2 = 0 for all addresses after reset |
| TC-RF-02 | Write-enable decode | write to each of WA=0..7; only that register changes (all 8 verified) |
| TC-RF-03 | Read both ports | distinct values in all 8 regs; RA≠RB reads correct |
| TC-RF-04 | Hold without WE | WE=0 → no register changes |
| TC-RF-05 | Boundary values | 0x0000 and 0xFFFF round-trip |
| TC-RF-06 | Overwrite | sequential writes to same address; last wins |
| TC-RF-07 | Simultaneous read/write | same-cycle read returns old value; next-cycle new value |
| TC-RF-08 | Reset mid-run | reset re-zeroes all registers |

## Stage 4 — PROGRAM_COUNTER

| ID | Test | Checks |
|----|------|--------|
| TC-PC-01 | Reset value | PC = 0x00000000 after reset |
| TC-PC-02 | Increment | PCSrc=0 → +4 per clock while PCWrite=1 |
| TC-PC-03 | Hold | PCWrite=0 → PC unchanged |
| TC-PC-04 | Branch load | PCSrc=1, target = PC+4+IMM<<2 exactness |
| TC-PC-05 | Jump load | PCSrc=2 → TGT27<<2; PCSrc=3 → RS1 value |
| TC-PC-06 | Width integrity | values ≥ 2^16 preserved (no 16-bit truncation) |
| TC-PC-07 | Re-reset | PC returns to 0 from a large value |

## Stage 5 — ALU

| ID | Test | Checks |
|----|------|--------|
| TC-AL-01 | ADD | e.g. 5+10=15; 0xFFF0+0x0020=0x0010 wrap |
| TC-AL-02 | SUB | 10−4=6; 3−5=0xFFFE |
| TC-AL-03..06 | AND/OR/XOR/NOT | truth tables incl. 0x0000/0xFFFF |
| TC-AL-07/08 | SHL/SHR | shifts 0–15; shift ≥16 → 0; C = last bit out |
| TC-AL-09 | MUL | low16 exactness (e.g. 300×300 → 0x2EE0 low16 of 90000) |
| TC-AL-10 | DIV | exact, truncating, ÷0 → 0xFFFF |
| TC-AL-11/12 | INC/DEC | 0→1, 0x0000→0xFFFF wrap on DEC |
| TC-AL-13 | Flags | Z,N,C,V on boundary set (0x7FFF+1 V=1, 0xFFFF+1 C=1 Z=1, 0−1 N=1 C=0, equal-sub Z=1) |
| TC-AL-14 | Undefined ops | reserved ALUOp returns 0x0000, no crash |

## Stage 6 — STATUS_REGISTER

| ID | Test | Checks |
|----|------|--------|
| TC-SR-01 | Reset 0 | Z=N=C=V=0 |
| TC-SR-02 | Update only on SRWrite | data flows only when strobe asserted |
| TC-SR-03 | Hold across non-flag ops | values persist when SRWrite=0 |

## Stage 7 — IR + DECODER · Stage 8 — DATAPATH · Stage 9 — CONTROL · Stage 10 — MEMORY · Stage 11 — EXECUTION

Detailed case tables are generated alongside each stage's builder
(NOT IMPLEMENTED yet). Stage 11 includes the master-prompt program
(LDI 5, LDI 10, ADD, HALT → R3=15, PC=0x10, SR=0) plus loads/stores,
taken/untaken branches, jumps, illegal-opcode trap, alignment fault,
and the regression suite of every earlier stage.

## Regression & audit policy

`sv16_build_all.m` reruns `sv16_audit` + compile + all existing tests after
every new subsystem (CRITICAL STOP CONDITION: any structural failure aborts
the build with the exact block/port named). Milestone snapshots are written to
`Milestones/` only after the full gate passes.
