# SV-16 Rev A — Register Map

## General-purpose registers (register file)

| Reg | Width | Type | Reset | Notes |
|-----|-------|------|-------|-------|
| R0 | 16 | uint16 | 0x0000 | GPR (no hardwired role in Rev A) |
| R1 | 16 | uint16 | 0x0000 | GPR |
| R2 | 16 | uint16 | 0x0000 | GPR |
| R3 | 16 | uint16 | 0x0000 | GPR |
| R4 | 16 | uint16 | 0x0000 | GPR |
| R5 | 16 | uint16 | 0x0000 | GPR |
| R6 | 16 | uint16 | 0x0000 | GPR |
| R7 | 16 | uint16 | 0x0000 | GPR |

- Interface: read ports `RA[2:0] → RD1[15:0]`, `RB[2:0] → RD2[15:0]`
  (combinational); write port `WA[2:0]`, `WD[15:0]`, strobe `RegWrite`
  (synchronous on clock edge).
- Write-while-read: a register written on edge N reads (combinationally) the
  **old** value during cycle N and the new value from cycle N+1. Test
  `TC-RF-07` covers the simultaneous read/write case.
- Write decoding is explicit: register i is written iff
  `RegWrite==1 && uint8(WA)==i` (verified for all 8 addresses by `TC-RF-02`).

## Architectural (non-GPR) registers

| Reg | Width | Reset | Notes |
|-----|-------|-------|-------|
| PC | 32 | 0x0000_0000 | byte-addressed, `uint32`; update per `PCSrc/PCWrite` |
| IR | 32 | 0x0000_0000 | full 32-bit instruction container; loaded only in FETCH |
| SR | 6 | 0b00_0000 | [5]=IP [4]=I (reserved) [3]=V [2]=C [1]=N [0]=Z |
| STATE | 3 | 0 (FETCH) | control-unit state register |
| ILLOP | 1 | 0 | sticky illegal-opcode latch |
| ALGNER | 1 | 0 | sticky alignment-fault latch |
| HALTED | 1 | 0 | halt latch |

## Register-file implementation notes (Simulink)

- Eight 16-bit register primitives (see `Scripts/sv16_lib_register.m`):
  enable = `RegWrite && (WA == i)`, synchronous reset to 0x0000.
- Read muxes: two 8:1 `Multiport Switch` blocks indexed by RA / RB
  (explicit index control — no bit slicing).
- Write decode: 8 `Compare To Constant` + `Logical AND` with RegWrite
  (explicit scalar decoding — no bit masks on packed words).
