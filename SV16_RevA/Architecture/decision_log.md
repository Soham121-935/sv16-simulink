# SV-16 Rev A — Decision Log

Every architectural decision that different subsystems must not contradict.
Statuses: `FROZEN` (binding), `FROZEN-v0.1` (binding for Stages 2–8, open to
user veto before Stage 9 control unit), `OPEN` (awaiting user decision),
`SUPERSEDED` (legacy decision explicitly rejected).

| ID | Decision | Rationale | Alternatives considered | Status |
|----|----------|-----------|--------------------------|--------|
| D-001 | 8 GPRs R0–R7, 16-bit | Master spec mandate | Legacy model used R0–R15 — SUPERSEDED | FROZEN |
| D-002 | Register file 2 read ports + 1 write port | Master spec mandate; matches legacy concept | 3-port file rejected (unneeded) | FROZEN |
| D-003 | PC 32-bit, byte-addressed, +4 per instruction | Honors 32-bit address path; byte addressing scales to byte ops in Rev B | (a) word-addressed PC +1; (b) legacy +3 (24-bit instr) — SUPERSEDED | FROZEN-v0.1 |
| D-004 | IR 32-bit, instruction = 1 word | Master spec mandate ("do not truncate") | Legacy 24-bit-in-32 container — SUPERSEDED | FROZEN |
| D-005 | Formats R/I/B/J with 3-bit register fields, 5-bit opcode at [31:27] | Preserves legacy field *shape* (OP,RS1,RS2,RD,IMM) sized cleanly into 32 bits; 3-bit fields match 8 GPRs | 6-bit opcode at [31:26] with 4-bit fields (legacy widths) — rejected: 4-bit fields imply 16 registers | FROZEN-v0.1 |
| D-006 | Opcode table per `instruction_set.md` | 24 implemented + reserved; HALT at 0x1F | Exact numbering is arbitrary; renumbering before Stage 9 costs one file edit (`sv16_isa.m`) | FROZEN-v0.1 |
| D-007 | Multi-cycle FETCH/DECODE/EXECUTE/MEM/WB, 3–5 cycles/instr | Explicit, verifiable sequencing; no hazards; matches memory read latency | Single-cycle (rejected: combinational IMEM of registered banks unrealistic); pipelined (rejected for Rev A) | FROZEN |
| D-008 | Synchronous active-high reset, 2 cycles, no async paths | Deterministic simulation; legacy had none | Async reset rejected (nondeterministic in sim) | FROZEN |
| D-009 | Flags V,C,N,Z; updated only by ALU-class ops | Fixes legacy unsigned "Negative" bug; complete flag set for branches & future carry ops | Carry-rich variants (rotates/ADC/SBC) deferred to Rev B | FROZEN |
| D-010 | Register primitives: `Unit Delay Enabled` + external reset, or `Unit Delay`+Switch fallback — chosen at runtime by `sv16_lib_probe` | Removes HDL Coder (`hdlsllib`) dependency F-02 | hdlsllib blocks (legacy) — SUPERSEDED | FROZEN |
| D-011 | DIV by zero → result 0xFFFF, no trap in Rev A | Simple deterministic behavior; trap costs an exception mechanism Rev A doesn't have yet | Trap + fault latch | FROZEN-v0.1 |
| D-012 | Illegal opcode → sticky ILLOP + halt; alignment → sticky ALGNER + halt | Master spec §20 requires defined behavior | Silently ignore rejected (hides faults) | FROZEN |
| D-013 | IMEM 4096 words, DMEM 4096 words implemented | Ample for Stage 11 programs; keeps memory block count sane | Larger/parametric sizes — size is one constant in `sv16_isa.m` | FROZEN-v0.1 |
| D-014 | Harvard split IMEM/DMEM | Legacy had no data memory (F-08); split simplifies fetch vs load/store timing | Von Neumann (single port, needs bus arbitration) | FROZEN |
| D-015 | No interrupts in Rev A Stages 2–11; SR bits I/IP reserved | Per master prompt, peripherals/INTC come later and must not destabilize the core | Implement trap early — deferred | FROZEN |
| D-016 | Status register not directly readable/writable by instructions in Rev A | No READSR/WRITESR opcode allocated; avoids half-designed flag games | Add opcodes — deferred to Rev B with interrupts | FROZEN-v0.1 |
| D-017 | Peripheral page `0xFFFF_xxxx` reserved, reads 0/writes ignored until Stage 12 | Deterministic Stage 11 behavior with map already fixed | Fault on peripheral access — harsher, no benefit yet | FROZEN |

## OPEN items requiring a user decision

**None.** The veto window was exercised on 2026-10-10: the user ratified
ISA v0.1 (D-005/D-006), the byte-addressed PC +4 (D-003), and MUL/DIV
retention (D-011). All formerly FROZEN-v0.1 items are now **FROZEN**.
(1) D-013 memory sizes (4096 words each) stands as ratified by silence with
the rest of the package; it remains a one-constant change (`sv16_isa.m`)
should the user ever revisit it.
