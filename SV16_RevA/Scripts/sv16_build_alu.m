function h = sv16_build_alu(mdl, parentPath)
%SV16_BUILD_ALU Stage 5 -- ALU: 12 operations + flags (spec section 8).
%
%   h = sv16_build_alu(mdl)
%   h = sv16_build_alu(mdl, parentPath)
%
% Interface:
%   In  A     : uint16  operand A
%       B     : uint16  operand B
%       ALUOp : uint8   0 ADD 1 SUB 2 AND 3 OR 4 XOR 5 NOT 6 SHL 7 SHR
%                       8 MUL 9 DIV 10 INC 11 DEC, 12..15 reserved
%   Out R     : uint16  result (reserved ops -> 0x0000)
%       Z N C V: boolean flags of THIS operation (SR stage registers them
%                when the control unit asserts SRWrite)
%
% All 12 data operations are NATIVE blocks. Exactly two narrowly scoped,
% explicitly documented MATLAB Function blocks are used (master prompt
% allowance; decision D-018):
%   SHIFT16 : variable barrel shifter -> Rl, Cl (SHL) and Rh, Ch (SHR)
%   FLAGS   : Z/N/C/V computation from A,B,ALUOp,R,Cl,Ch
% Reserved ALUOp values are clamped for the mux (never a runtime index
% error) and forced to result 0x0000 by an explicit guard switch.

if nargin < 2, parentPath = [mdl '/CPU_CORE']; end
isa = sv16_isa();
sys = [parentPath '/ALU'];
add_block('built-in/Subsystem', sys, 'Position', [560 40 860 320]);

% --- Interface ports ------------------------------------------------------
add_block('simulink/Sources/In1', [sys '/A'],     'Port','1');
add_block('simulink/Sources/In1', [sys '/B'],     'Port','2');
add_block('simulink/Sources/In1', [sys '/ALUOp'], 'Port','3');
outNames = {'R','Z','N','C','V'};
for k = 1:numel(outNames)
    add_block('simulink/Sinks/Out1', [sys '/' outNames{k}], 'Port', num2str(k));
end
sv16_setp([sys '/A'],     {'OutDataTypeStr','DataType'}, 'uint16');
sv16_setp([sys '/B'],     {'OutDataTypeStr','DataType'}, 'uint16');
sv16_setp([sys '/ALUOp'], {'OutDataTypeStr','DataType'}, 'uint8');
sv16_setp([sys '/R'],     {'OutDataTypeStr','DataType'}, 'uint16');
for k = 2:5
    sv16_setp([sys '/' outNames{k}], {'OutDataTypeStr','DataType'}, 'boolean');
end

% --- Constants -------------------------------------------------------------
add_block('simulink/Sources/Constant', [sys '/ONE'],    'Value','uint16(1)', ...
    'SampleTime', num2str(isa.Ts), 'Position',[20 210 70 240]);
add_block('simulink/Sources/Constant', [sys '/MASK16'], 'Value','uint32(65535)', ...
    'SampleTime', num2str(isa.Ts), 'Position',[20 640 80 670]);
add_block('simulink/Sources/Constant', [sys '/DIVZ'],   'Value','uint16(65535)', ...
    'SampleTime', num2str(isa.Ts), 'Position',[20 880 80 910]);
add_block('simulink/Sources/Constant', [sys '/RSV'],    'Value','uint16(0)', ...
    'SampleTime', num2str(isa.Ts), 'Position',[420 420 470 450]);
add_block('simulink/Sources/Constant', [sys '/OP11'],   'Value','uint8(11)', ...
    'SampleTime', num2str(isa.Ts), 'Position',[240 20 290 50]);

% --- ADD / SUB / INC / DEC (wrapping uint16) -------------------------------
add_block('simulink/Math Operations/Sum', [sys '/ADD'], 'Inputs','++', ...
    'OutDataTypeStr','uint16', 'SaturateOnIntegerOverflow','off', 'Position',[120 80 160 120]);
add_block('simulink/Math Operations/Sum', [sys '/SUB'], 'Inputs','+-', ...
    'OutDataTypeStr','uint16', 'SaturateOnIntegerOverflow','off', 'Position',[120 140 160 180]);
add_block('simulink/Math Operations/Sum', [sys '/INC'], 'Inputs','++', ...
    'OutDataTypeStr','uint16', 'SaturateOnIntegerOverflow','off', 'Position',[120 200 160 240]);
add_block('simulink/Math Operations/Sum', [sys '/DEC'], 'Inputs','+-', ...
    'OutDataTypeStr','uint16', 'SaturateOnIntegerOverflow','off', 'Position',[120 260 160 300]);

% --- AND / OR / XOR / NOT ---------------------------------------------------
add_block('simulink/Logic and Bit Operations/Bitwise Operator', [sys '/ANDop'], ...
    'Operator','AND', 'Inputs','2', 'Position',[120 320 170 360]);
add_block('simulink/Logic and Bit Operations/Bitwise Operator', [sys '/ORop'], ...
    'Operator','OR',  'Inputs','2', 'Position',[120 380 170 420]);
add_block('simulink/Logic and Bit Operations/Bitwise Operator', [sys '/XORop'], ...
    'Operator','XOR', 'Inputs','2', 'Position',[120 440 170 480]);
add_block('simulink/Logic and Bit Operations/Bitwise Operator', [sys '/NOTop'], ...
    'Operator','NOT', 'Inputs','1', 'Position',[120 500 170 540]);

% --- Variable shifter (documented MATLAB Function block) --------------------
add_block('simulink/User-Defined Functions/MATLAB Function', [sys '/SHIFT16'], ...
    'Position',[120 560 220 620]);
sv16_set_mlfb_script([sys '/SHIFT16'], sv16_shift16_source());

% --- MUL: exact uint32 product, mask to low 16 ------------------------------
add_block('simulink/Signal Attributes/Data Type Conversion', [sys '/A32'], ...
    'OutDataTypeStr','uint32', 'Position',[60 660 100 690]);
add_block('simulink/Signal Attributes/Data Type Conversion', [sys '/B32'], ...
    'OutDataTypeStr','uint32', 'Position',[60 700 100 730]);
add_block('simulink/Math Operations/Product', [sys '/MUL32'], 'Inputs','**', ...
    'OutDataTypeStr','uint32', 'Position',[160 665 200 725]);
add_block('simulink/Logic and Bit Operations/Bitwise Operator', [sys '/MULmask'], ...
    'Operator','AND', 'Inputs','2', 'Position',[240 665 290 725]);
add_block('simulink/Signal Attributes/Data Type Conversion', [sys '/MUL16'], ...
    'OutDataTypeStr','uint16', 'Position',[320 665 360 695]);

% --- DIV: guard B==0 -> 0xFFFF (decision D-011) ------------------------------
add_block('simulink/Math Operations/Divide', [sys '/DIVraw'], 'Inputs','*/', ...
    'OutDataTypeStr','uint16', 'Position',[160 780 200 840]);
add_block('simulink/Logic and Bit Operations/Compare To Constant', [sys '/Bnonzero'], ...
    'const','0', 'relop','~=', 'OutDataTypeStr','boolean', 'Position',[60 900 110 940]);
add_block('simulink/Signal Routing/Switch', [sys '/DIVguard'], ...
    'Criteria','u2 ~= 0', 'Position',[260 780 300 860]);

% --- Operation mux + reserved guard ------------------------------------------
add_block('simulink/Math Operations/MinMax', [sys '/ClampOp'], 'Function','min', ...
    'Inputs','2', 'OutDataTypeStr','uint8', 'Position',[320 20 360 60]);
add_block('simulink/Logic and Bit Operations/Compare To Constant', [sys '/OpValid'], ...
    'const','11', 'relop','<=', 'OutDataTypeStr','boolean', 'Position',[320 900 370 940]);
add_block('simulink/Signal Routing/Multiport Switch', [sys '/OpMux'], ...
    'Inputs','12', 'Position',[420 80 460 860]);
try
    set_param([sys '/OpMux'], 'ControlPortOrder', 'First input port is control');
catch
    % first-port control is the default in current releases
end
add_block('simulink/Signal Routing/Switch', [sys '/ReservedGuard'], ...
    'Criteria','u2 ~= 0', 'Position',[540 100 580 200]);

% --- FLAGS (documented MATLAB Function block) ---------------------------------
add_block('simulink/User-Defined Functions/MATLAB Function', [sys '/FLAGS'], ...
    'Position',[640 240 760 420]);
sv16_set_mlfb_script([sys '/FLAGS'], sv16_flags_source());

% --- Wiring -------------------------------------------------------------------
phA  = get_param([sys '/A'],     'PortHandles');
phB  = get_param([sys '/B'],     'PortHandles');
phOp = get_param([sys '/ALUOp'], 'PortHandles');

w = @(s, sp, d, dp) wireOne(sys, s, sp, d, dp);

w('ADD',1,  'A',1);  w('ADD',2,  'B',1);
w('SUB',1,  'A',1);  w('SUB',2,  'B',1);
w('INC',1,  'A',1);  w('ONE',1,  'INC',2);
w('DEC',1,  'A',1);  w('ONE',1,  'DEC',2);
w('ANDop',1,'A',1);  w('ANDop',2,'B',1);
w('ORop',1, 'A',1);  w('ORop',2, 'B',1);
w('XORop',1,'A',1);  w('XORop',2,'B',1);
w('NOTop',1,'A',1);
w('SHIFT16',1,'A',1); w('SHIFT16',2,'B',1);
w('A32',1,'A',1);     w('B32',1,'B',1);
w('MUL32',1,'A32',1); w('MUL32',2,'B32',1);
w('MULmask',1,'MUL32',1); w('MASK16',1,'MULmask',2); w('MUL16',1,'MULmask',1);
w('DIVraw',1,'A',1);  w('DIVraw',2,'B',1);
w('Bnonzero',1,'B',1);
w('DIVguard',1,'DIVraw',1); w('DIVZ',1,'DIVguard',3); w('Bnonzero',1,'DIVguard',2);
w('ClampOp',1,'ALUOp',1); w('OP11',1,'ClampOp',2);
w('OpValid',1,'ALUOp',1);
w('OpMux',1,'ClampOp',1);   % mux control = clamped ALUOp

% mux data ports: 1 ADD, 2 SUB, 3 AND, 4 OR, 5 XOR, 6 NOT, 7 SHL(Rl),
%                 8 SHR(Rh), 9 MUL, 10 DIV, 11 INC, 12 DEC
w('ADD',1,  'OpMux',2);  w('SUB',1,  'OpMux',3);
w('ANDop',1,'OpMux',4);  w('ORop',1, 'OpMux',5);
w('XORop',1,'OpMux',6);  w('NOTop',1,'OpMux',7);
w('SHIFT16',1,'OpMux',8);     % Rl
w('SHIFT16',3,'OpMux',9);     % Rh
w('MUL16',1,'OpMux',10);      w('DIVguard',1,'OpMux',11);
w('INC',1,'OpMux',12);        w('DEC',1,'OpMux',13);

w('ReservedGuard',1,'OpMux',1); w('RSV',1,'ReservedGuard',3);
w('OpValid',1,'ReservedGuard',2);
w('ReservedGuard',1,'R',1);

% FLAGS inputs: A, B, ALUOp, R, Cl (SHL carry), Ch (SHR carry)
w('FLAGS',1,'A',1);   w('FLAGS',2,'B',1);   w('FLAGS',3,'ALUOp',1);
w('FLAGS',4,'ReservedGuard',1);
w('FLAGS',5,'SHIFT16',2);   % Cl
w('FLAGS',6,'SHIFT16',4);   % Ch
w('FLAGS',1,'Z',1); w('FLAGS',2,'N',1); w('FLAGS',3,'C',1); w('FLAGS',4,'V',1);

% --- Structural self-check: no unconnected ports anywhere in the ALU -------
auditSubsystemPorts(sys);

h = struct();
h.sys = sys;
h.in = struct('A', phA.Outport(1), 'B', phB.Outport(1), 'ALUOp', phOp.Outport(1));
phO = cell(1,5);
for k = 1:5
    p = get_param([sys '/' outNames{k}], 'PortHandles');
    phO{k} = p.Outport(1);
end
h.out = struct('R',phO{1},'Z',phO{2},'N',phO{3},'C',phO{4},'V',phO{5});
end

% ---------------------------------------------------------------------------
function wireOne(sys, s, sp, d, dp)
phs = get_param([sys '/' s], 'PortHandles');
phd = get_param([sys '/' d], 'PortHandles');
add_line(sys, phs.Outport(sp), phd.Inport(dp), 'autorouting','on');
end

function auditSubsystemPorts(sys)
% Fail fast if any block inside sys has an unconnected standard data port.
blks = find_system(sys, 'SearchDepth', 1, 'Type','Block');
for k = 1:numel(blks)
    bt = get_param(blks{k}, 'BlockType');
    if strcmp(bt, 'SubSystem')
        continue  % child subsystems are audited by their own builders
    end
    ph = get_param(blks{k}, 'PortHandles');
    f = fieldnames(ph);
    for iF = 1:numel(f)
        for iP = 1:numel(ph.(f{iF}))
            if get_param(ph.(f{iF})(iP), 'Line') == -1
                error('SV16:alu:wiring', ...
                    'Unconnected port %s:%d on %s inside %s', f{iF}, iP, blks{k}, sys);
            end
        end
    end
end
end

% ---------------------------------------------------------------------------
function src = sv16_shift16_source()
src = [ ...
'function [Rl, Cl, Rh, Ch] = sv16_shift16(A, B)' char(10) ...
'% SV16_SHIFT16 -- variable 16-bit barrel shifter (decision D-018).' char(10) ...
'% Documented scope: SHL/SHR only. k = B[3:0] (0..15).' char(10) ...
'% Rl/Cl : left-shifted result and last bit shifted out (carry).' char(10) ...
'% Rh/Ch : logical right-shifted result and last bit shifted out.' char(10) ...
'k = uint8(bitand(double(B), 15));' char(10) ...
'a = double(A);' char(10) ...
'Rl = uint16(bitshift(a, k));' char(10) ...
'if k == 0' char(10) ...
'    Cl = false;' char(10) ...
'else' char(10) ...
'    Cl = bitget(a, 17 - k);' char(10) ...
'end' char(10) ...
'Rh = uint16(bitshift(a, -k));' char(10) ...
'if k == 0' char(10) ...
'    Ch = false;' char(10) ...
'else' char(10) ...
'    Ch = bitget(a, k);' char(10) ...
'end' char(10)];
end

function src = sv16_flags_source()
src = [ ...
'function [Z, N, C, V] = sv16_flags(A, B, ALUOp, R, Cl, Ch)' char(10) ...
'% SV16_FLAGS -- Z/N/C/V for the SV-16 Rev A ALU (spec section 9).' char(10) ...
'% Documented scope: flag computation only; data path is native blocks.' char(10) ...
'% ALUOp: 0 ADD 1 SUB 2 AND 3 OR 4 XOR 5 NOT 6 SHL 7 SHR 8 MUL 9 DIV' char(10) ...
'%        10 INC 11 DEC (flags for INC/DEC identical to ADD/SUB with 1).' char(10) ...
'a = double(A); b = double(B); r = double(R);' char(10) ...
'Z = (r == 0);' char(10) ...
'N = bitget(r, 16);   % twos-complement sign of the 16-bit result' char(10) ...
'C = false; V = false;' char(10) ...
'switch ALUOp' char(10) ...
'    case 0   % ADD' char(10) ...
'        C = (a + b) > 65535;' char(10) ...
'        V = (bitget(a,16) == bitget(b,16)) && (bitget(r,16) ~= bitget(a,16));' char(10) ...
'    case 1   % SUB' char(10) ...
'        C = a >= b;          % no-borrow convention' char(10) ...
'        V = (bitget(a,16) ~= bitget(b,16)) && (bitget(a,16) ~= bitget(r,16));' char(10) ...
'    case 6   % SHL' char(10) ...
'        C = Cl;' char(10) ...
'    case 7   % SHR' char(10) ...
'        C = Ch;' char(10) ...
'    case 10  % INC' char(10) ...
'        C = (a + 1) > 65535;' char(10) ...
'        V = (a == 32767);' char(10) ...
'    case 11  % DEC' char(10) ...
'        C = a >= 1;' char(10) ...
'        V = (a == 32768);' char(10) ...
'    otherwise % AND OR XOR NOT MUL DIV: C=0, V=0 per spec' char(10) ...
'        C = false; V = false;' char(10) ...
'end' char(10)];
end
