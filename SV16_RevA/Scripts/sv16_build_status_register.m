function h = sv16_build_status_register(mdl, parentPath)
%SV16_BUILD_STATUS_REGISTER Stage 6 -- STATUS_REGISTER: V,C,N,Z storage.
%
%   h = sv16_build_status_register(mdl)
%   h = sv16_build_status_register(mdl, parentPath)
%
% Interface:
%   In  Zin Nin Cin Vin : boolean  new flag values from the ALU
%       SRWrite         : boolean  update strobe (asserted only by the
%                                  control unit for SR-updating opcodes)
%       RST             : boolean  synchronous reset -> all flags false
%   Out Z N C V         : boolean  current architectural flags
%
% Flags change ONLY when SRWrite is asserted (TC-SR-02/03).

if nargin < 2, parentPath = [mdl '/CPU_CORE']; end
isa = sv16_isa();
sys = [parentPath '/STATUS_REGISTER'];
add_block('built-in/Subsystem', sys, 'Position', [900 40 1080 200]);

inNames = {'Zin','Nin','Cin','Vin','SRWrite','RST'};
for k = 1:numel(inNames)
    add_block('simulink/Sources/In1', [sys '/' inNames{k}], 'Port', num2str(k));
end
outNames = {'Z','N','C','V'};
for k = 1:4
    add_block('simulink/Sinks/Out1', [sys '/' outNames{k}], 'Port', num2str(k));
end
for k = 1:numel(inNames)
    dt = 'boolean';
    sv16_setp([sys '/' inNames{k}], {'OutDataTypeStr','DataType'}, dt);
end
for k = 1:4
    sv16_setp([sys '/' outNames{k}], {'OutDataTypeStr','DataType'}, 'boolean');
end

phSW = get_param([sys '/SRWrite'], 'PortHandles');
phRST= get_param([sys '/RST'], 'PortHandles');

bitMap = {'Zin','Z'; 'Nin','N'; 'Cin','C'; 'Vin','V'};
for k = 1:4
    reg = sv16_lib_register(sys, sprintf('FLAG_%s', bitMap{k,2}), ...
        'boolean', 'false', isa.Ts);
    phIn = get_param([sys '/' bitMap{k,1}], 'PortHandles');
    add_line(sys, phIn.Outport(1), reg.in.D,  'autorouting','on');
    add_line(sys, phSW.Outport(1), reg.in.EN, 'autorouting','on');
    add_line(sys, phRST.Outport(1),reg.in.RST,'autorouting','on');
    phO = get_param([sys '/' bitMap{k,2}], 'PortHandles');
    add_line(sys, reg.out.Q, phO.Inport(1), 'autorouting','on');

    lh = get_param([sys '/' sprintf('FLAG_%s', bitMap{k,2}) '/State'], 'LineHandles');
    if any(lh.Inport == -1) || any(lh.Outport == -1)
        error('SV16:status:wiring', 'STATUS_REGISTER flag %s flop unconnected.', bitMap{k,2});
    end
end

h = struct();
h.sys = sys;
h.in = struct();
for k = 1:numel(inNames)
    ph = get_param([sys '/' inNames{k}], 'PortHandles');
    h.in.(inNames{k}) = ph.Outport(1);
end
h.out = struct();
for k = 1:4
    ph = get_param([sys '/' outNames{k}], 'PortHandles');
    h.out.(outNames{k}) = ph.Outport(1);
end
end
