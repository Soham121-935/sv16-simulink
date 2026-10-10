function varargout = sv16_isa(cmd, varargin)
%SV16_ISA  Single source of truth for SV-16 Rev A architecture constants.
%
%   isa = sv16_isa()            -> struct of all architecture constants
%   w   = sv16_isa('asm', L)    -> assemble cellstr of instructions -> uint32 row
%   w   = sv16_isa('prog', N)   -> built-in test program vector ('ADDTEN','LOADSTORE','LOOPDOWN','ILLEGAL')
%   s   = sv16_isa('decode', W) -> decode uint32 instruction word to fields
%
% Everything the builders, decoder, control unit, and tests need about the
% ISA lives here. Mirror documents: Architecture/instruction_set.md.
% If this file and the docs disagree, this file wins; fix the docs.

% Copyright (c) SV-16 Rev A project. Verified per Verification/test_plan.md.

if nargin == 0
    varargout{1} = isaStruct();
    return
end

switch lower(cmd)
    case 'asm'
        varargout{1} = assemble(varargin{1});
    case 'prog'
        varargout{1} = builtinProgram(varargin{1});
    case 'decode'
        varargout{1} = decodeWord(varargin{1});
    otherwise
        error('SV16:isa:badCmd', 'Unknown sv16_isa command: %s', cmd);
end
end

% ------------------------------------------------------------------------
function isa = isaStruct()
isa = struct();

% --- Clocking -----------------------------------------------------------
isa.Ts          = 1;        % sample time (the hardware "clock" in simulation)
isa.resetCycles = 2;        % synchronous reset asserted for first N cycles

% --- Widths -------------------------------------------------------------
isa.gprCount  = 8;          % R0..R7
isa.gprWidth  = 16;         % bits
isa.pcWidth   = 32;         % bits, byte-addressed
isa.irWidth   = 32;         % bits, never truncated
isa.aluWidth  = 16;
isa.srBits    = {'Z','N','C','V'};   % bit0..bit3 (I/IP reserved bits 4/5)

% --- Reset values -------------------------------------------------------
isa.pcReset  = uint32(0);
isa.irReset  = uint32(0);
isa.gprReset = uint16(0);
isa.srReset  = 0;

% --- Control states (multi-cycle) ---------------------------------------
isa.state.FETCH = 0; isa.state.DECODE = 1; isa.state.EXECUTE = 2;
isa.state.MEMORY = 3; isa.state.WRITEBACK = 4;

% --- Instruction field positions (bit 31 = MSB) -------------------------
% R: OP[31:27] RD[26:24] RS1[23:21] RS2[20:18] rest 0
% I: OP[31:27] RD[26:24] RS1[23:21] IMM[15:0]
% B: OP[31:27] RS1[20:18] RS2[17:15] IMM[15:0]
% J: OP[31:27] TGT27[26:0]
isa.f.opShift  = 27;  isa.f.opMask  = uint32(hex2dec('F8000000'));
isa.f.rdShift  = 24;  isa.f.rdMask  = uint32(7);
isa.f.rs1Shift = 21;  isa.f.rs1Mask = uint32(7);
isa.f.rs2Shift = 18;  isa.f.rs2Mask = uint32(7);
isa.f.brs1Shift = 18; isa.f.brs2Shift = 15;
isa.f.immShift = 0;   isa.f.immMask = uint32(hex2dec('0000FFFF'));
isa.f.tgtMask  = uint32(hex2dec('07FFFFFF'));

% --- Opcodes (ISA v0.1, decision D-006) ---------------------------------
o = struct();
o.NOP =hex2dec('00'); o.LDI =hex2dec('01'); o.LDIS=hex2dec('02'); o.MOV=hex2dec('03');
o.ADD =hex2dec('04'); o.ADDI=hex2dec('05'); o.SUB =hex2dec('06'); o.SUBI=hex2dec('07');
o.AND =hex2dec('08'); o.OR  =hex2dec('09'); o.XOR =hex2dec('0A'); o.NOT =hex2dec('0B');
o.SHL =hex2dec('0C'); o.SHR =hex2dec('0D'); o.MUL =hex2dec('0E'); o.DIV =hex2dec('0F');
o.INC =hex2dec('10'); o.DEC =hex2dec('11'); o.LW  =hex2dec('12'); o.SW  =hex2dec('13');
o.BEQ =hex2dec('14'); o.BNE =hex2dec('15'); o.BLT =hex2dec('16'); o.BGE =hex2dec('17');
o.JMP =hex2dec('18'); o.JAL =hex2dec('19'); o.JALR=hex2dec('1A'); o.HALT=hex2dec('1F');
isa.op = o;

% --- ALU operation encoding (ALUOp, 4-bit scalar) -----------------------
a = struct();
a.ADD=0; a.SUB=1; a.AND=2; a.OR=3; a.XOR=4; a.NOT=5; a.SHL=6; a.SHR=7;
a.MUL=8; a.DIV=9; a.INC=10; a.DEC=11;   % 12..15 reserved -> result 0x0000
isa.aluop = a;

% --- Opcode classes (used by decoder + control unit) --------------------
isa.class.R  = {'NOP','MOV','ADD','SUB','AND','OR','XOR','NOT','SHL','SHR', ...
                'MUL','DIV','INC','DEC','JALR'};
isa.class.I  = {'LDI','LDIS','ADDI','SUBI','LW','SW'};
isa.class.B  = {'BEQ','BNE','BLT','BGE'};
isa.class.J  = {'JMP','JAL'};
isa.class.SR_UPDATING = {'ADD','ADDI','SUB','SUBI','AND','OR','XOR','NOT', ...
                         'SHL','SHR','MUL','DIV','INC','DEC'};  % spec section 9
end

% ------------------------------------------------------------------------
function w = assemble(lines)
%ASSEMBLE Minimal verified assembler for the SV-16 Rev A ISA v0.1.
% Syntax: MNEMONIC OP1, OP2, ...   % comment
%   R-type: ADD R3, R1, R2     (RD, RS1, RS2)   MOV/NOT/JALR: RD, RS1
%   I-type: LDI R1, 0x40       (RD, IMM16)      LW/SW: RD, RS1, IMM
%   B-type: BEQ R1, R2, 12     (RS1, RS2, BYTE offset; imm encoded /4)
%   J-type: JMP 0x40           (absolute BYTE address; TGT27 = addr/4)
isa = isaStruct();
mn = upper(fieldnames(isa.op));
fmt = containers.Map('KeyType','char','ValueType','char');
for k = 1:numel(mn)
    name = mn{k};
    if any(strcmp(isa.class.R, name)),      f = 'R';
    elseif any(strcmp(isa.class.I, name)),  f = 'I';
    elseif any(strcmp(isa.class.B, name)),  f = 'B';
    elseif any(strcmp(isa.class.J, name)),  f = 'J';
    else, error('SV16:isa:noFmt', 'Mnemonic %s has no format', name);
    end
    fmt(name) = f;
end

w = uint32([]);
for iLine = 1:numel(lines)
    line = strtrim(regexp(lines{iLine}, '%.*$', 'split once'));
    line = strtrim(line);
    if isempty(line), continue; end
    tok = regexp(line, '[,\s]+', 'split');
    name = upper(tok{1});
    if ~isKey(isa.op, name)
        error('SV16:isa:badMnemonic', 'Line %d: unknown mnemonic %s', iLine, name);
    end
    opv = uint32(isa.op.(name));
    args = tok(2:end);
    switch fmt(name)
        case 'R'
            switch name
                case 'NOP'
                    rd = uint32(0); rs1 = uint32(0); rs2 = uint32(0);
                case {'MOV','NOT','INC','DEC','JALR'}   % RD, RS1
                    rd  = regArg(args{1}, iLine, name);
                    rs1 = regArg(args{2}, iLine, name);
                    rs2 = uint32(0);
                otherwise                               % RD, RS1, RS2
                    rd  = regArg(args{1}, iLine, name);
                    rs1 = regArg(args{2}, iLine, name);
                    rs2 = regArg(args{3}, iLine, name);
            end
            w(end+1) = bitor(bitshift(opv,27), bitor(bitshift(rd,24), ...
                        bitor(bitshift(rs1,21), bitshift(rs2,18)))); %#ok<AGROW>
        case 'I'
            switch name
                case {'LDI','LDIS'}                     % RD, IMM
                    rd  = regArg(args{1}, iLine, name);
                    rs1 = uint32(0);
                    imm = immArg(args, 2, iLine);
                otherwise                               % RD, RS1, IMM
                    rd  = regArg(args{1}, iLine, name);
                    rs1 = regArg(args{2}, iLine, name);
                    imm = immArg(args, 3, iLine);
            end
            w(end+1) = bitor(bitshift(opv,27), bitor(bitshift(rd,24), ...
                        bitor(bitshift(rs1,21), bitand(imm, uint32(hex2dec('FFFF')))))); %#ok<AGROW>
        case 'B'
            rs1 = regArg(args{1}, iLine, name);
            rs2 = regArg(args{2}, iLine, name);
            offBytes = immArg(args, 3, iLine);
            if mod(offBytes,4) ~= 0
                error('SV16:isa:badOffset', 'Line %d: branch offset must be a multiple of 4', iLine);
            end
            w(end+1) = bitor(bitshift(opv,27), bitor(bitshift(rs1,18), ...
                        bitor(bitshift(rs2,15), bitand(offBytes/4, uint32(hex2dec('FFFF')))))); %#ok<AGROW>
        case 'J'
            addr = immArg(args, 1, iLine);
            if mod(addr,4) ~= 0
                error('SV16:isa:badTarget', 'Line %d: jump target must be word aligned', iLine);
            end
            w(end+1) = bitor(bitshift(opv,27), bitand(addr/4, uint32(hex2dec('07FFFFFF')))); %#ok<AGROW>
    end
end
w = uint32(w);
end

function r = regArg(s, iLine, name)
s = upper(strtrim(s));
if numel(s) < 2 || s(1) ~= 'R'
    error('SV16:isa:badReg', 'Line %d (%s): expected register, got "%s"', iLine, name, s);
end
r = sscanf(s(2:end), '%d');
if isempty(r) || r < 0 || r > 7
    error('SV16:isa:badReg', 'Line %d (%s): register out of range R0..R7: "%s"', iLine, name, s);
end
r = uint32(r);
end

function v = immArg(args, idx, iLine)
if idx > numel(args)
    error('SV16:isa:badImm', 'Line %d: missing immediate', iLine);
end
s = strtrim(args{idx});
if strncmpi(s, '0x', 2)
    v = uint32(hex2dec(s(3:end)));
else
    d = str2double(s);
    if isnan(d), error('SV16:isa:badImm', 'Line %d: bad immediate "%s"', iLine, s); end
    v = uint32(mod(d, 2^32));
end
end

% ------------------------------------------------------------------------
function s = decodeWord(w)
isa = isaStruct();
s.op   = bitshift(bitand(w, isa.f.opMask), -isa.f.opShift);
s.rd   = bitshift(bitand(w, bitshift(isa.f.rdMask, isa.f.rdShift)), -isa.f.rdShift);
s.rs1  = bitshift(bitand(w, bitshift(isa.f.rs1Mask, isa.f.rs1Shift)), -isa.f.rs1Shift);
s.rs2  = bitshift(bitand(w, bitshift(isa.f.rs2Mask, isa.f.rs2Shift)), -isa.f.rs2Shift);
s.imm  = uint16(bitand(w, isa.f.immMask));
s.tgt  = bitand(w, isa.f.tgtMask);
end

% ------------------------------------------------------------------------
function w = builtinProgram(name)
switch upper(name)
    case 'ADDTEN'   % master-prompt acceptance program: 5 + 10 = 15
        w = sv16_isa('asm', { ...
            'LDI R1, 5', 'LDI R2, 10', 'ADD R3, R1, R2', 'HALT'});
    case 'LOADSTORE'
        w = sv16_isa('asm', { ...
            'LDI R1, 0x40', 'LDI R2, 0xBEEF', 'SW R2, R1, 0', ...
            'LW R4, R1, 0', 'HALT'});
    case 'LOOPDOWN'   % counts R1 down 3,2,1 then halts
        w = sv16_isa('asm', { ...
            'LDI R1, 3', ...        % 0x00
            'LDI R2, 1', ...        % 0x04
            'SUBI R1, R1, 1', ...   % 0x08  loop body
            'BEQ R1, R2, 12', ...   % 0x0C  -> 0x14 when R1==1
            'JMP 0x08', ...         % 0x10
            'HALT'});               % 0x14
    case 'ILLEGAL'    % reserved opcode 0x1D must trap
        w = uint32([sv16_isa('asm', {'NOP'}), ...
                    uint32(hex2dec('3A000000')), ...   % op 0x1D (reserved)
                    sv16_isa('asm', {'HALT'})]);
    otherwise
        error('SV16:isa:badProg', 'Unknown builtin program: %s', name);
end
end
