# SV-16 Rev A — Stage 0 Audit of the Legacy `SV16.slx` Model

**Audit date:** 2026-10-10
**Method:** Offline structural dissection of the SLX (OPC/XML) package — every
`simulink/systems/system_*.xml` parsed, all block SIDs inventoried, every
`Line`/`Branch` `Src`/`Dst` endpoint resolved against block SIDs.
**Tool version that produced the legacy model:** MATLAB/Simulink **R2026a (26.1.0.3312084, Update 4)**.
**Stateflow machine:** present but empty (no charts, no MATLAB Function scripts).

This audit was performed without MATLAB (see README — sandbox limitation), by
parsing the model XML directly. It covers structure, architecture, and library
dependencies. Compile-time and runtime behavior remain **NOT TESTED** until the
new-model toolchain is run in MATLAB.

---

## 1. Inventory

| Metric | Value |
|---|---|
| System files (hierarchies) | 50 |
| Total blocks | 698 |
| Root-level subsystems | ALU, CONTROL_UNIT, INSTRUCTION_MEMORY, IR, PROGRAM COUNTER, REGISTER_FILE, Status Word |
| Reference (library) blocks — `Compare To Constant` | 47 (`simulink/Logic and Bit Operations`) |
| Reference blocks — `Unit Delay Enabled Synchronous` | **34 — source library `hdlsllib` (HDL Coder)** |
| Reference blocks — `Bitwise Operator` | 8 (`simulink/Logic and Bit Operations`) |

### Reconstructed hierarchy

```
SV16 (root)
├── ALU                 [system_589]   20 blocks, 12-entry op mux
├── CONTROL_UNIT        [system_639]   65 blocks, Gain/ArithShift bit slicing
├── INSTRUCTION_MEMORY  [system_658]
│   ├── MEMORY_BANK_8_B0 [system_711]  8 cells × 8 bit + 8:1 mux
│   ├── MEMORY_BANK_8_B1 [system_1391] 8 cells × 8 bit + 8:1 mux
│   └── Subsystem        [system_1367] address decode via Gain/ArithShift
├── IR                  [system_37]    uint32 in/out
├── PROGRAM COUNTER     [system_20]    uint32, increments by +3
├── REGISTER_FILE       [system_58]
│   ├── DECODER 0       [system_158]   16-way write decode
│   ├── MUXA / MUXB     [system_238 / 262]  17-input read muxes (2 read ports)
│   └── R0 … R15        16 × 16-bit register cells  ← SIXTEEN registers
└── Status Word         [system_626]   Zero + "Neagtive" (sic) only
```

## 2. Connection integrity (XML level)

Every persisted `Line`/`Branch` endpoint resolves to a valid block SID; no
empty `Src`/`Dst` references; no orphan line segments are present in the XML.
Two caveats are required for honesty:

1. Simulink only persists well-formed connections; lines that merely *look*
   attached but were never snapped to a port do not exist in the file at all.
   Structural well-formedness of the XML therefore does **not** prove the model
   compiles or behaves correctly.
2. Compile-time errors (width/type/library resolution) cannot be observed from
   XML. Status: **NOT TESTED**.

## 3. Findings (what must NOT be carried into Rev A)

| # | Finding | Evidence | Severity |
|---|---|---|---|
| F-01 | **Register-file width contradiction.** REGISTER_FILE implements **16 registers R0–R15** (4-bit decoded addresses), while the approved SV-16 architecture defines **eight registers R0–R7**. A second, unrelated R0–R7 bank exists *inside* the instruction-memory banks (those are byte cells, confusingly named). | system_58 children R0–R15; decoder 158; MUXA/MUXB are 17-input | High |
| F-02 | **Hard dependency on HDL Coder.** 34 storage elements reference `hdlsllib/Discrete/Unit Delay Enabled Synchronous`. Without an HDL Coder license the model resolves to missing-library blocks. | Reference SourceBlock scan | High |
| F-03 | **PC increments by +3** while the IR is 32-bit and the instruction memory stores 16-bit words. +3 only makes sense for the reconstructed legacy 24-bit (3-byte) instruction format; it is incompatible with any word-organized memory of 16-bit words. | PC Constant2 = 3; memory banks 8×8 bit ×2 | High |
| F-04 | **Instruction memory holds only 16 bytes** (2 banks × 8 words × 8 bits) and the IR fetch path converts 2×8-bit banks → 32-bit in a way that cannot deliver a 24-bit instruction in one piece. | system_658/711/1391/1367 | High |
| F-05 | **Negative flag computed on unsigned data.** Status Word derives "Neagtive" (typo intact) from `uint16` results; sign on an unsigned type is meaningless. No Carry or Overflow flags exist at all. | system_626 | High |
| F-06 | **Bit-slicing address/field extraction** with Gain and ArithShift blocks in CONTROL_UNIT and memory decode — exactly the fragile pattern the Rev A rules ban in favor of explicit field extraction. | system_639 (4 Gain blocks), system_1367 (Gain/ArithShift) | Medium |
| F-07 | **ALU has no shift operations**, no INC/DEC, and only 12 mux entries; ALUOp is a bare index with no documented encoding. | system_589 | Medium |
| F-08 | **No data memory subsystem.** INSTRUCTION_MEMORY doubles as the only storage; no load/store datapath exists. | root children | High |
| F-09 | **Debug instrumentation fused into the design** — root-level Constants (e.g. PC seed `100`, IR seed) and Displays are wired into datapath inputs, so the "processor" cannot run without its testbench constants. | root XML | Medium |
| F-10 | **No clock/reset subsystem.** `Unit Delay Enabled Synchronous` elements are enabled but the model has no explicit reset sequencing; StopTime = 0.1 with unnamed solver in configSet0. | configSet0.xml | Medium |
| F-11 | Data types used: PC/IR `uint32` ✓, registers `uint16` ✓ — these two decisions are **correct and are preserved**. | block params | Info |

## 4. Salvageable design decisions (carried into Rev A)

1. Two read ports + one write port register file (MUXA/MUXB + write decoder concept).
2. uint32 PC and IR; uint16 register/ALU datapath.
3. Instruction layout shape: `OPCODE | RS1 | RS2 | RD | IMMEDIATE` (field *shape* kept; widths re-derived cleanly for 32 bits in `instruction_set.md`).
4. Explicit control signals exported by the control unit: RegWrite, ALUSrc, MemRead, MemWrite, MemToReg, Branch, Jump, ALUOp, RD, RS1, RS2, Immediate (superset kept, renamed and completed).

## 5. Verdict

The legacy model is a structurally well-formed but **architecturally
inconsistent experiment** (16 registers vs 8, +3 PC vs word memory, unsigned
sign flag, no data memory, HDL-Coder-only primitives). Per the master prompt,
it is used **only** as a source of architectural intent; the Rev A model is
built clean from `sv16_build_all.m`, never by copying it.

Legacy file: `/SV16.slx` (kept at repo root, untouched, as reference only).
