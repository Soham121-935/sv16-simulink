# SV-16 Rev A — Architecture Specification

**Status:** FROZEN. ISA v0.1 field positions, opcode numbering, byte-addressed
PC (+4), and MUL/DIV retention were **ratified by the user on 2026-10-10**
(see `decision_log.md`). No open architectural decisions remain.
**Source of truth for implementation:** `Scripts/sv16_isa.m` — this document is
its human-readable mirror. If they ever disagree, `sv16_isa.m` wins and this
document must be corrected.

---

## 1. Architectural overview

SV-16 Rev A is an original custom 16-bit microcontroller with a 16-bit
integer datapath, a 32-bit instruction container, and a 32-bit address path.
It is a multi-cycle processor: one instruction is executed per 3–5 clock
cycles through an explicit FETCH → DECODE → EXECUTE → MEMORY → WRITEBACK
state sequence driven by a hardwired control unit. It is modeled in Simulink
as a modular block design; FPGA implementation is explicitly out of scope.

## 2. Register architecture

- Eight general-purpose registers **R0–R7**, each **16 bits**, `uint16`.
- Register file: **two read ports (RA, RB) and one write port (WD)**.
- Write decoding: explicit 3-bit write address `WA` + `RegWrite` strobe;
  a register is written only when `RegWrite=1` and `WA` selects it.
- No register has a dedicated architectural role in Rev A (no hardwired SP/LR);
  `JAL/JALR` write PC+4 to the register selected by the instruction's RD field.
- Reset value of every GPR: `0x0000`.
- Full map: `register_map.md`.

## 3. PC behavior

- PC is **32 bits, byte-addressed** (`uint32`), reset value `0x0000_0000`.
- Fetch: instruction word address = `PC[31:2]` (byte addressing, 4-byte
  instructions; `PC[1:0]` must be `00`, else alignment fault, §20).
- Sequential update: `PC ← PC + 4`.
- Branch (taken): `PC ← PC + 4 + (sext16(IMM) << 2)`.
- `JMP`: `PC ← TGT27 << 2` (absolute, 29-bit byte space).
- `JAL`: `RD ← PC + 4`, then as `JMP`. `JALR`: `RD ← PC + 4`, `PC ← RS1` (LSB ignored).
- PC updates only when the control unit asserts `PCWrite`; reset forces
  `0x0000_0000` synchronously.

## 4. Instruction width and format

- Instruction container (IR): **32 bits** (`uint32`). Never truncated to 16.
- Three formats (field positions fixed in `sv16_isa.m`):

```
 R-type  31..27 OPCODE | 26..24 RD | 23..21 RS1 | 20..18 RS2 | 17..16 -- | 15..0 UNUSED
 I-type  31..27 OPCODE | 26..24 RD | 23..21 RS1 | 20..16 --    | 15..0 IMM16
 B-type  31..27 OPCODE | 26..21 --   | 20..18 RS1 | 17..15 RS2 | 15..0 IMM16
 J-type  31..27 OPCODE | 26..0 TGT27
```

- `IMM16` is zero-extended (LDI) or sign-extended (all other I-type) per opcode.
- No instruction bit is discarded: R-type keeps all fields whole; the IR drives
  the decoder with the full 32-bit word.

## 5. Opcode allocation

5-bit opcode field (32 slots). Full table in `instruction_set.md`.
Summary: `0x00` NOP, `0x01/0x02` LDI/LDIS, `0x03` MOV, `0x04–0x07` ADD/ADDI/SUB/SUBI,
`0x08–0x0B` AND/OR/XOR/NOT, `0x0C/0x0D` SHL/SHR, `0x0E/0x0F` MUL/DIV,
`0x10/0x11` INC/DEC, `0x12/0x13` LW/SW, `0x14–0x17` BEQ/BNE/BLT/BGE,
`0x18–0x1A` JMP/JAL/JALR, `0x1F` HALT, all others **reserved → illegal**.

## 6. Instruction set

See `instruction_set.md` (encoding + semantics table). 32 defined encodings,
24 of them implemented in Rev A Stage 11 scope; reserved encodings trap (§20).

## 7. Operand selection

- ALU operand A: register RA, or PC (for branch target arithmetic).
- ALU operand B: register RB, or sign-extended `IMM16` (`ALUSrcB` mux).
- Read ports are combinational: `RD1 = R[RA]`, `RD2 = R[RB]`.

## 8. ALU operations

16-bit `uint16` result `ALU_R` plus flags. Operations (ALUOp encoding fixed in
`sv16_isa.m`): ADD, SUB, AND, OR, XOR, NOT, SHL, SHR (logical), MUL (low 16),
DIV (unsigned), INC, DEC. Division by zero returns `0xFFFF` with no trap in
Rev A (decision D-011). Shift amounts use the low 4 bits of operand B (0–15).

## 9. Status flags

Status register `SR` bits: `[3]=V` overflow, `[2]=C` carry, `[1]=N` negative
(twos-complement interpretation of the 16-bit result), `[0]=Z` zero.
- Updated only by ALU-class opcodes (list in `instruction_set.md`); loads,
  stores, MOV, branches, jumps, LDI/LDIS and HALT leave SR unmodified.
- `C`: carry out (ADD/ADDI/INC), borrow complement (SUB/SUBI/DEC), shift-out
  (SHL/SHR), 0 otherwise. `V`: signed overflow for add/sub; 0 for logicals.
- `SR` is readable only via flags internally in Rev A (no explicit PUSH SR
  instruction); interrupts are not implemented in Stage 11 scope (§17).

## 10. Memory architecture

Harvard, byte-addressed, 32-bit address path on both sides.
- **IMEM**: 32-bit instruction words, indexed by `PC[31:2]`, read-only at
  runtime, initialized from a program file. Implemented size: 4096 words
  (16 KB), addressable to 2^30 words.
- **DMEM**: 16-bit data words, addressed by byte address `DM[15:0]` word-aligned
  (`addr[1:0] = 00`). Implemented size: 4096 words (8 KB). Word read is
  combinational within the MEMORY state; write commits on the clock edge.
- Read/write timing and reset: `memory_map.md`.

## 11. Addressing modes

1. Register (R-type), 2. Immediate (I-type, zero- or sign-extending),
3. Base+offset (LW/SW: `DM[RS1 + sext16(IMM16)]`),
4. PC-relative branching (`PC+4+sext16(IMM)<<2`), 5. Absolute jump (`TGT27<<2`),
6. Register-indirect jump (JALR).

## 12. Control signals

Exported by CONTROL_UNIT (all scalar, `uint8`/`boolean`): `state[2:0]`,
`PCWrite`, `PCSrc` (00=+4, 01=branch, 10=jmp/jal target, 11=alu/jalr),
`IRWrite`, `RegWrite`, `WA[2:0]`, `WDSource` (0=ALU, 1=DMEM, 2=PC+4),
`ALUOp[3:0]`, `ASelA` (0=RA, 1=PC), `ASelB` (0=RB, 1=IMM), `MemRead`,
`MemWrite`, `SRWrite`, `Halt`. Encodings fixed in `sv16_isa.m`.

## 13. Clocking and reset

- Single global clock, period `Ts` (default 1 s simulation units, configurable).
- **Synchronous, active-high reset**, asserted by the CLOCK_RESET subsystem for
  the first 2 clock cycles of simulation and by `reset` inputs of registered
  subsystems. No asynchronous reset paths. Reset values: §19.
- Halt: `Halt=1` gates `PCWrite`/`IRWrite`/`RegWrite`/`MemWrite` globally;
  the processor stays quiescent until reset.

## 14. Instruction execution stages

Fixed multi-cycle sequence (states in `sv16_isa.m`):
`FETCH(0) → DECODE(1) → EXECUTE(2) → MEMORY(3) → WRITEBACK(4) → FETCH …`
LW uses all five states; pure ALU ops skip MEMORY; stores end after MEMORY;
branches resolve in EXECUTE. State register resets to FETCH.

## 15. Branch and jump behavior

Branches compare RA/RB in EXECUTE (equality, signed less-than, signed ≥);
untaken branches fall through. Branch penalty: taken branch costs the same
multi-cycle sequence as any instruction (no pipeline → no hazard logic).
`JMP/JAL/JALR` assert `PCSrc` in EXECUTE.

## 16. Load/store behavior

`LW RD, [RS1+IMM16]`: address computed in EXECUTE, DMEM read in MEMORY,
write to register file in WRITEBACK. `SW [RS1+IMM16], RS2`: write strobe in
MEMORY state only. Unaligned address (`addr[1:0]≠0`): access suppressed and
alignment fault latched (§20); DMEM contents unchanged.

## 17. Interrupt behavior

**NOT IMPLEMENTED in Rev A Stages 2–11.** The instruction set reserves the
`INT` opcode space and the status register reserves bit `[4]=I` (interrupt
enable) and `[5]=IP` (pending) so that interrupt capability can be added
without re-encoding. Reserved opcodes trap as illegal until then.

## 18. Peripheral address map

DMEM top page reserved for memory-mapped peripherals (word addresses):
`0xF000 GPIO_OUT`, `0xF001 GPIO_IN`, `0xF002–0xF00F TIMER/PWM`,
`0xF010–0xF01F UART`, `0xF020–0xF02F SPI`, `0xF030–0xF03F I2C`,
`0xF040 INTERRUPT_CTL`, `0xF041 WATCHDOG`. Peripherals are **Stage 12** and
are NOT IMPLEMENTED yet; accesses to the page in Stage 11 read `0x0000` and
ignore writes (documented, harmless).

## 19. Reset values

| Element | Reset value |
|---|---|
| PC | `0x0000_0000` |
| IR | `0x0000_0000` (opcode 0 = NOP-safe) |
| R0–R7 | `0x0000` each |
| SR (Z,N,C,V) | `0b0000` |
| Control state | FETCH |
| Halt flag | `0` |
| DMEM | `0x0000` each word unless program preloads data |

## 20. Exception and illegal-instruction behavior

- **Illegal/reserved opcode:** decoder drives `Halt=1` and latches sticky
  `ILLOP=1` (visible testbench output). PC stops advancing at the illegal
  instruction. Recovery only via reset.
- **Alignment fault:** DMEM access with `addr[1:0]≠0` or IMEM fetch with
  `PC[1:0]≠0`: access suppressed, sticky `ALGNER=1`, PC stops (LW/SW) or is
  forced to next word boundary (fetch). Both faults are sticky until reset.
- DIV by zero is **not** an exception in Rev A (result `0xFFFF`, decision D-011).
