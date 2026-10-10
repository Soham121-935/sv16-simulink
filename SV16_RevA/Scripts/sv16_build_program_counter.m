function h = sv16_build_program_counter(mdl, parentPath)
%SV16_BUILD_PROGRAM_COUNTER Stage 4 -- PROGRAM_COUNTER: 32-bit PC.
%
%   h = sv16_build_program_counter(mdl)
%   h = sv16_build_program_counter(mdl, parentPath)
%
% Interface:
%   In  EN        : boolean  PCWrite strobe
%       PCSrc     : uint8    0 = sequential (+4), 1 = branch target,
%                            2 = jump target (TGT27<<2), 3 = register (JALR)
%       BrTarget  : uint32   branch target byte address (PC+4+IMM<<2)
%       JumpTarget: uint32   jump target byte address (TGT27<<2)
%       RsVal     : uint32   register value for JALR (bit 0 ignored upstream)
%       RST       : boolean  synchronous reset -> 0x0000_0000
%   Out PC        : uint32
%
% next = {PC+4, BrTarget, JumpTarget, RsVal}(PCSrc); PC updates only when
% EN is asserted (hold otherwise); synchronous reset forces 0.

if nargin < 2, parentPath = [mdl '/CPU_CORE']; end
isa = sv16_isa();
sys = [parentPath '/PROGRAM_COUNTER'];
add_block('built-in/Subsystem', sys, 'Position', [320 40 520 220]);

inNames = {'EN','PCSrc','BrTarget','JumpTarget','RsVal','RST'};
for k = 1:numel(inNames)
    add_block('simulink/Sources/In1', [sys '/' inNames{k}], 'Port', num2str(k));
end
add_block('simulink/Sinks/Out1', [sys '/PC'], 'Port','1');
sv16_setp([sys '/EN'],   {'OutDataTypeStr','DataType'}, 'boolean');
sv16_setp([sys '/PCSrc'],{'OutDataTypeStr','DataType'}, 'uint8');
sv16_setp([sys '/BrTarget'],  {'OutDataTypeStr','DataType'}, 'uint32');
sv16_setp([sys '/JumpTarget'],{'OutDataTypeStr','DataType'}, 'uint32');
sv16_setp([sys '/RsVal'],{'OutDataTypeStr','DataType'}, 'uint32');
sv16_setp([sys '/RST'],  {'OutDataTypeStr','DataType'}, 'boolean');
sv16_setp([sys '/PC'],   {'OutDataTypeStr','DataType'}, 'uint32');

% --- Sequential increment: PC + 4 ----------------------------------------
add_block('simulink/Sources/Constant', [sys '/Four'], 'Value','uint32(4)', ...
    'SampleTime', num2str(isa.Ts), 'Position', [40 60 90 90]);
add_block('simulink/Math Operations/Sum', [sys '/IncPlus4'], 'Inputs','++', ...
    'OutDataTypeStr','uint32', 'SaturateOnIntegerOverflow','off', ...
    'Position', [140 60 180 100]);

phPCo = get_param([sys '/PC'], 'PortHandles');   % placeholder; feedback wired after flop

% --- Next-PC multiplexer --------------------------------------------------
add_block('simulink/Signal Routing/Multiport Switch', [sys '/NextMux'], ...
    'Inputs', '4', 'Position', [240 40 280 200]);
try
    set_param([sys '/NextMux'], 'ControlPortOrder', 'First input port is control');
catch
end

% --- Hold / write-enable switch ------------------------------------------
add_block('simulink/Signal Routing/Switch', [sys '/PCUpdate'], ...
    'Criteria', 'u2 ~= 0', 'Position', [340 60 380 140]);

% --- State flop -----------------------------------------------------------
reg = sv16_lib_register(sys, 'PCReg', 'uint32', 'uint32(0)', isa.Ts);

% --- Wiring ---------------------------------------------------------------
phFour = get_param([sys '/Four'], 'PortHandles');
phInc  = get_param([sys '/IncPlus4'], 'PortHandles');
phMux  = get_param([sys '/NextMux'], 'PortHandles');
phSw   = get_param([sys '/PCUpdate'], 'PortHandles');
phEN   = get_param([sys '/EN'], 'PortHandles');

add_line(sys, reg.out.Q, phInc.Inport(1), 'autorouting','on');      % PC feedback
add_line(sys, phFour.Outport(1), phInc.Inport(2), 'autorouting','on');
add_line(sys, phInc.Outport(1), phMux.Inport(2), 'autorouting','on'); % data 0: +4
phBr = get_param([sys '/BrTarget'], 'PortHandles');
phJp = get_param([sys '/JumpTarget'], 'PortHandles');
phRs = get_param([sys '/RsVal'], 'PortHandles');
phSel= get_param([sys '/PCSrc'], 'PortHandles');
add_line(sys, phBr.Outport(1),  phMux.Inport(3), 'autorouting','on'); % data 1
add_line(sys, phJp.Outport(1),  phMux.Inport(4), 'autorouting','on'); % data 2
add_line(sys, phRs.Outport(1),  phMux.Inport(5), 'autorouting','on'); % data 3
add_line(sys, phSel.Outport(1), phMux.Inport(1), 'autorouting','on'); % control

add_line(sys, phMux.Outport(1), phSw.Inport(1), 'autorouting','on');  % next (EN true)
add_line(sys, phEN.Outport(1),  phSw.Inport(2), 'autorouting','on');  % EN control
add_line(sys, reg.out.Q,        phSw.Inport(3), 'autorouting','on');  % hold

add_line(sys, phSw.Outport(1), reg.in.D,  'autorouting','on');
add_line(sys, phEN.Outport(1), reg.in.EN, 'autorouting','on');
phRST = get_param([sys '/RST'], 'PortHandles');
add_line(sys, phRST.Outport(1), reg.in.RST, 'autorouting','on');
add_line(sys, reg.out.Q, phPCo.Inport(1), 'autorouting','on');        % PC out

% --- Structural self-check ------------------------------------------------
lhM = get_param([sys '/NextMux'], 'LineHandles');
lhS = get_param([sys '/PCUpdate'], 'LineHandles');
if any(lhM.Inport == -1) || any(lhS.Inport == -1)
    error('SV16:pc:wiring', 'PROGRAM_COUNTER mux/switch has unconnected ports.');
end
lhR = get_param([sys '/PCReg/State'], 'LineHandles');
if any(lhR.Inport == -1) || any(lhR.Outport == -1)
    error('SV16:pc:wiring', 'PROGRAM_COUNTER state flop has unconnected ports.');
end

h = struct();
h.sys = sys;
h.in = struct();
for k = 1:numel(inNames)
    ph = get_param([sys '/' inNames{k}], 'PortHandles');
    h.in.(inNames{k}) = ph.Outport(1);
end
ph = get_param([sys '/PC'], 'PortHandles');
h.out.PC = ph.Outport(1);
end
