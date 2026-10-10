function h = sv16_build_register_bank(mdl, parentPath)
%SV16_BUILD_REGISTER_BANK Stage 3 -- REGISTER_BANK: 8 x uint16, 2R/1W.
%
%   h = sv16_build_register_bank(mdl)
%   h = sv16_build_register_bank(mdl, parentPath)   % default <mdl>/CPU_CORE
%
% Interface (all control lines SCALAR per Rev A rule "no bit slicing"):
%   In  RA0 RA1 RA2 : uint8   read port A address bits (A2 is MSB)
%       RB0 RB1 RB2 : uint8   read port B address bits
%       WA0 WA1 WA2 : uint8   write address bits
%       RegWrite    : boolean write strobe
%       WD          : uint16  write data
%       RST         : boolean synchronous reset
%   Out RD1 RD2     : uint16  combinational read data (old-value semantics:
%                               a write during cycle t is visible at t+1)
%
% Write decode: explicit Compare-To-Constant per register ANDed with
% RegWrite (never packed-word bit masks). Read muxes: two 8-input
% Multiport Switch blocks indexed by the composed address scalar.

if nargin < 2, parentPath = [mdl '/CPU_CORE']; end
isa = sv16_isa();
sys = [parentPath '/REGISTER_BANK'];
add_block('built-in/Subsystem', sys, 'Position', [40 40 260 220]);

% --- Interface -----------------------------------------------------------
inNames = {'RA0','RA1','RA2','RB0','RB1','RB2','WA0','WA1','WA2','RegWrite','WD','RST'};
for k = 1:numel(inNames)
    add_block('simulink/Sources/In1', [sys '/' inNames{k}], 'Port', num2str(k));
end
add_block('simulink/Sinks/Out1', [sys '/RD1'], 'Port','1');
add_block('simulink/Sinks/Out1', [sys '/RD2'], 'Port','2');
for k = 1:11
    dt = 'uint8'; if k == 10, dt = 'boolean'; end
    sv16_setp([sys '/' inNames{k}], {'OutDataTypeStr','DataType'}, dt);
end
sv16_setp([sys '/WD'],  {'OutDataTypeStr','DataType'}, 'uint16');
sv16_setp([sys '/RST'], {'OutDataTypeStr','DataType'}, 'boolean');
sv16_setp([sys '/RD1'], {'OutDataTypeStr','DataType'}, 'uint16');
sv16_setp([sys '/RD2'], {'OutDataTypeStr','DataType'}, 'uint16');

% --- Address composition: addr = 4*A2 + 2*A1 + A0 -------------------------
hA = sv16_composeAddress(sys, 'A');
hB = sv16_composeAddress(sys, 'B');
phWA = cell(1,3);
for b = 1:3
    phWA{b} = get_param([sys '/' sprintf('WA%d', b-1)], 'PortHandles');
    add_line(sys, phWA{b}.Outport(1), hA.src{b}, 'autorouting','on');
    phWB = get_param([sys '/' sprintf('WB%d', b-1)], 'PortHandles');
    add_line(sys, phWB.Outport(1), hB.src{b}, 'autorouting','on');
end

% --- Eight register primitives -------------------------------------------
regs = cell(1, isa.gprCount);
for i = 1:isa.gprCount
    regs{i} = sv16_lib_register(sys, sprintf('REG%d', i-1), 'uint16', 'uint16(0)', isa.Ts);
    % WD -> D
    phWD = get_param([sys '/WD'], 'PortHandles');
    add_line(sys, phWD.Outport(1), regs{i}.in.D, 'autorouting','on');
    % RST -> RST
    phRST = get_param([sys '/RST'], 'PortHandles');
    add_line(sys, phRST.Outport(1), regs{i}.in.RST, 'autorouting','on');
    % Write decode: (WA == i-1) AND RegWrite -> EN
    cmp = [sys '/' sprintf('SEL%d', i-1)];
    add_block('simulink/Logic and Bit Operations/Compare To Constant', cmp, ...
        'const', num2str(i-1), 'relop', '==', 'OutDataTypeStr','boolean', ...
        'Position', [40 300+40*i 90 330+40*i]);
    and = [sys '/' sprintf('WE%d', i-1)];
    add_block('simulink/Logic and Bit Operations/Logical Operator', and, ...
        'Operator','AND', 'Inputs','2', 'OutDataTypeStr','boolean', ...
        'Position', [140 300+40*i 180 330+40*i]);
    phCMP = get_param(cmp, 'PortHandles');
    phAND = get_param(and, 'PortHandles');
    phRGW = get_param([sys '/RegWrite'], 'PortHandles');
    add_line(sys, hA.out, phCMP.Inport(1), 'autorouting','on');
    add_line(sys, phCMP.Outport(1), phAND.Inport(1), 'autorouting','on');
    add_line(sys, phRGW.Outport(1), phAND.Inport(2), 'autorouting','on');
    add_line(sys, phAND.Outport(1), regs{i}.in.EN, 'autorouting','on');
end

% --- Read muxes: 8-input Multiport Switch, data port k = register k-1 ----
muxSpecs = {hA, 'RD1', 'ReadMuxA'; hB, 'RD2', 'ReadMuxB'};
for m = 1:2
    mAdr = muxSpecs{m,1}; outName = muxSpecs{m,2}; muxName = muxSpecs{m,3};
    add_block('simulink/Signal Routing/Multiport Switch', [sys '/' muxName], ...
        'Inputs', num2str(isa.gprCount), 'Position', [320 60 360 320]);
    try
        set_param([sys '/' muxName], 'ControlPortOrder', 'First input port is control');
    catch
        % first-port control is the default in current releases
    end
    phM = get_param([sys '/' muxName], 'PortHandles');
    add_line(sys, mAdr.out, phM.Inport(1), 'autorouting','on');   % control
    for i = 1:isa.gprCount
        add_line(sys, regs{i}.out.Q, phM.Inport(i+1), 'autorouting','on');
    end
    phO = get_param([sys '/' outName], 'PortHandles');
    add_line(sys, phM.Outport(1), phO.Inport(1), 'autorouting','on');
end

% --- Structural self-check before returning ------------------------------
for i = 1:isa.gprCount
    lh = get_param([sys '/' sprintf('REG%d', i-1) '/State'], 'LineHandles');
    if any(lh.Inport == -1) || any(lh.Outport == -1)
        error('SV16:regbank:wiring', 'REGISTER_BANK REG%d State block port unconnected.', i-1);
    end
end
lh1 = get_param([sys '/ReadMuxA'], 'LineHandles');
lh2 = get_param([sys '/ReadMuxB'], 'LineHandles');
if any(lh1.Inport == -1) || any(lh2.Inport == -1)
    error('SV16:regbank:wiring', 'REGISTER_BANK read mux has an unconnected data/control port.');
end

h = struct();
h.sys = sys;
h.inNames = inNames;
h.in = struct();
for k = 1:numel(inNames)
    ph = get_param([sys '/' inNames{k}], 'PortHandles');
    h.in.(inNames{k}) = ph.Outport(1);
end
ph = get_param([sys '/RD1'], 'PortHandles'); h.out.RD1 = ph.Outport(1);
ph = get_param([sys '/RD2'], 'PortHandles'); h.out.RD2 = ph.Outport(1);
end

% ---------------------------------------------------------------------------
function c = sv16_composeAddress(sys, tag)
% Compose addr = 4*A2 + 2*A1 + A0 with explicit weighted sums (no slicing).
% Returns c.src{1..3} = destination port handles for A0/A1/A2, c.out = addr.
add_block('simulink/Math Operations/Gain', [sys '/' tag 'W1'], 'Gain','2', ...
    'Position', [40 420 80 450]);
add_block('simulink/Math Operations/Gain', [sys '/' tag 'W2'], 'Gain','4', ...
    'Position', [40 470 80 500]);
add_block('simulink/Math Operations/Sum', [sys '/' tag 'Sum'], 'Inputs','+++', ...
    'OutDataTypeStr','uint8', 'Position', [140 430 180 500]);
sv16_setp([sys '/' tag 'W1'], {'OutDataTypeStr','OutputDataTypeName','DataType'}, 'uint8');
sv16_setp([sys '/' tag 'W2'], {'OutDataTypeStr','OutputDataTypeName','DataType'}, 'uint8');
sv16_setp([sys '/' tag 'Sum'], {'OutDataTypeStr','OutputDataTypeName','DataType'}, 'uint8');

phS = get_param([sys '/' tag 'Sum'], 'PortHandles');
phG1 = get_param([sys '/' tag 'W1'], 'PortHandles');
phG2 = get_param([sys '/' tag 'W2'], 'PortHandles');
c = struct();
c.src = {phS.Inport(1), phG1.Inport(1), phG2.Inport(1)};
add_line(sys, phG1.Outport(1), phS.Inport(2), 'autorouting','on');
add_line(sys, phG2.Outport(1), phS.Inport(3), 'autorouting','on');
c.out = phS.Outport(1);
end
