# SV-16 Rev A — Memory Map

Harvard architecture, byte-addressed 32-bit address path on both sides.
Implemented sizes are Simulink-model sizes; the *architectural* space is the
full 32 bits with faults undefined outside implemented ranges in simulation.

## Instruction memory (IMEM)

| Item | Value |
|---|---|
| Word size | 32 bits (one instruction) |
| Implemented size | 4096 words (16 KiB) at reset-time configuration |
| Index | `PC[31:2]` (byte address / 4) |
| Access | read-only at runtime; initialized by `sv16_load_program` from an encoding vector or assembler text |
| Reset contents | all words = `0x00000000` = NOP (safe), or program image |
| Fetch alignment | `PC[1:0] == 00` required, else ALGNER fault (spec §20) |

## Data memory (DMEM)

| Item | Value |
|---|---|
| Word size | 16 bits |
| Implemented size | 4096 words (8 KiB) |
| Addressing | byte address, word-aligned: `A[1:0]=00`, word index = `A[15:2]` |
| Access | LW combinational read in MEMORY state; SW write strobe in MEMORY state only |
| Reset contents | `0x0000` everywhere unless preloaded |
| Unaligned access | suppressed + sticky ALGNER fault; memory unchanged |

### DMEM address use in Rev A Stage 11

| Range (byte addr) | Region |
|---|---|
| `0x0000_0000 – 0x0000_0FFF` | program data (implemented 4096 B) |
| `0x0000_1000 – 0x0000_FFFF` | reserved (reads 0x0000, writes ignored in model) |
| `0xFFFF_0000 – 0xFFFF_FFFF` | peripheral page (spec §18) — NOT IMPLEMENTED until Stage 12; reads 0x0000, writes ignored |

Address decode is implemented with explicit range comparisons on the byte
address (documented constants in `sv16_isa.m`) — never by Gain/shift bit
slicing.

## Timing

| Signal | Behavior |
|---|---|
| `MemRead` | asserted by control unit during MEMORY state of LW; data stable same cycle |
| `MemWrite` | 1-cycle strobe in MEMORY state of SW; commit on next clock edge |
| Reset | all DMEM words forced to reset contents while reset is asserted |

## Program image format (test/tooling contract)

Programs are specified as a row vector of `uint32` words in program order;
`sv16_load_program(model, words)` writes `words(i)` to IMEM index `i-1` and
records the image in the verification log. The assembler helper in
`Scripts/sv16_assemble.m` (Stage 8+) produces this vector from assembly text
and is itself verified against the encoding table of `instruction_set.md`.
