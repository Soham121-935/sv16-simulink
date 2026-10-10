# SV-16 Rev A — Instruction Set (ISA v0.1)

Encoding single source of truth: `Scripts/sv16_isa.m` (`sv16_isa('opcodes')`).
Formats (bit 31 = MSB):

```
 R: [31:27]=OP [26:24]=RD [23:21]=RS1 [20:18]=RS2 [17:0] =0
 I: [31:27]=OP [26:24]=RD [23:21]=RS1 [15:0] =IMM16       ([20:16]=0)
 B: [31:27]=OP [20:18]=RS1 [17:15]=RS2 [15:0] =IMM16      ([26:21]=0)
 J: [31:27]=OP [26:0] =TGT27
```

Register fields are 3 bits → addresses 0–7 = R0–R7. `sext16` = sign-extend
IMM16 to 32 bits. `SR` updates column: ✔ = flags updated per §9 of the
architecture spec.

## Opcodes

| Enc | Mnemonic | Fmt | Semantics | SR |
|-----|----------|-----|-----------|----|
| 0x00 | NOP  | R  | no operation | – |
| 0x01 | LDI  | I  | RD ← zext16(IMM16) | – |
| 0x02 | LDIS | I  | RD ← sext16(IMM16) | – |
| 0x03 | MOV  | R  | RD ← R[RS1] | – |
| 0x04 | ADD  | R  | RD ← R[RS1] + R[RS2] | ✔ |
| 0x05 | ADDI | I  | RD ← R[RS1] + sext16(IMM16) | ✔ |
| 0x06 | SUB  | R  | RD ← R[RS1] − R[RS2] | ✔ |
| 0x07 | SUBI | I  | RD ← R[RS1] − sext16(IMM16) | ✔ |
| 0x08 | AND  | R  | RD ← R[RS1] & R[RS2] | ✔ |
| 0x09 | OR   | R  | RD ← R[RS1] \| R[RS2] | ✔ |
| 0x0A | XOR  | R  | RD ← R[RS1] ⊕ R[RS2] | ✔ |
| 0x0B | NOT  | R  | RD ← ~R[RS1] | ✔ |
| 0x0C | SHL  | R  | RD ← R[RS1] << R[RS2][3:0] | ✔ (C = last bit shifted out) |
| 0x0D | SHR  | R  | RD ← R[RS1] >> R[RS2][3:0] (logical) | ✔ (C = last bit out) |
| 0x0E | MUL  | R  | RD ← low16(R[RS1] * R[RS2]) | ✔ (C=0, V=0) |
| 0x0F | DIV  | R  | RD ← R[RS1] /u R[RS2]; ÷0 → 0xFFFF (D-011) | ✔ |
| 0x10 | INC  | R  | RD ← R[RS1] + 1 | ✔ |
| 0x11 | DEC  | R  | RD ← R[RS1] − 1 | ✔ |
| 0x12 | LW   | I  | RD ← DMEM[R[RS1] + sext16(IMM16)] | – |
| 0x13 | SW   | I  | DMEM[R[RS1] + sext16(IMM16)] ← R[RS2] | – |
| 0x14 | BEQ  | B  | if R[RS1]==R[RS2] PC ← PC+4+sext16(IMM16)<<2 | – |
| 0x15 | BNE  | B  | if R[RS1]!=R[RS2] PC ← PC+4+sext16(IMM16)<<2 | – |
| 0x16 | BLT  | B  | if signed R[RS1]< R[RS2] branch | – |
| 0x17 | BGE  | B  | if signed R[RS1]>=R[RS2] branch | – |
| 0x18 | JMP  | J  | PC ← TGT27<<2 | – |
| 0x19 | JAL  | J  | RD ← PC+4; PC ← TGT27<<2 | – |
| 0x1A | JALR | R  | RD ← PC+4; PC ← R[RS1] (bit0 ignored) | – |
| 0x1F | HALT | R  | processor halts until reset | – |
| else | —    | —  | **illegal** → sticky ILLOP + halt | – |

Assembly syntax (documented, used by the assembler in `sv16_isa.m` / tests):

```
LDI  R1, 5          ; R1 = 5
ADDI R3, R1, -2     ; R3 = R1 - 2
ADD  R4, R1, R3     ; R4 = R1 + R3
SW   R4, R1, 8      ; DMEM[R1 + 8] = R4   (dest-base, src, offset)
LW   R5, R1, 8      ; R5 = DMEM[R1 + 8]
BEQ  R1, R2, 12     ; target = PC+4+12
JMP  0x40           ; absolute byte address 0x40 (TGT27 = 0x10)
HALT
```

## Example — master-prompt test program (5 + 10 = 15)

```
addr 0x00: LDI  R1, 5
addr 0x04: LDI  R2, 10
addr 0x08: ADD  R3, R1, R2      ; R3 = 15
addr 0x0C: HALT
```
Expected final state: R1=5, R2=10, R3=15, all other GPRs 0, PC=0x10, SR=0x0
(result 15 ≠ 0, unsigned-positive → Z=0 N=0 C=0 V=0).

## Encoding examples (verify in tests)

- `ADD R3,R1,R2` → OP=0x04<<27 = 0x2000_0000, RD=3<<24 = 0x0300_0000, RS1=1<<21 = 0x0020_0000, RS2=2<<18 = 0x0008_0000 → **`0x2328_0000`**.
- `LDI R1,5` → OP=0x01<<27 = 0x0800_0000, RD=1<<24 → **`0x0900_0005`**.
- `BEQ R1,R2,12` → OP=0x14<<27 = 0xA000_0000, RS1=1<<18 = 0x0004_0000, RS2=2<<15 = 0x0001_0000, IMM=12/4=3 → **`0xA005_0003`**.
- `JMP 0x40` → OP=0x18<<27 = 0xC000_0000, TGT27=0x10 → **`0xC000_0010`**.
- `HALT` → OP=0x1F<<27 → **`0xF800_0000`**. Reserved `0x1D` → **`0xE800_0000`** (illegal-program test).
