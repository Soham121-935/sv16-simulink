function h = sv16_build_clock_reset(mdl)
%SV16_BUILD_CLOCK_RESET Stage 2 -- CLOCK_RESET subsystem (spec section 13).
%
%   h = sv16_build_clock_reset(mdl)
%
% Creates  <mdl>/CLOCK_RESET  with:
%   Out CLK : boolean, 50% duty square wave of period 2*Ts (reference clock)
%   Out RST : boolean, active-high synchronous reset, asserted during the
%             first isa.resetCycles sample steps, then deasserted.
% Note: the discrete sample time Ts IS the hardware clock for registered
% blocks (they self-clock at Ts); CLK exists as an explicit reference signal
% and for testbench timing checks.

isa = sv16_isa();
sys = [mdl '/CLOCK_RESET'];
add_block('built-in/Subsystem', sys, 'Position', [40 40 200 140]);

add_block('simulink/Sinks/Out1', [sys '/CLK'], 'Port','1');
add_block('simulink/Sinks/Out1', [sys '/RST'], 'Port','2');
sv16_setp([sys '/CLK'], {'OutDataTypeStr','DataType'}, 'boolean');
sv16_setp([sys '/RST'], {'OutDataTypeStr','DataType'}, 'boolean');

% Clock: sample-based pulse generator, period 2 samples, width 1 -> 50% duty.
add_block('simulink/Sources/Pulse Generator', [sys '/ClockGen'], ...
    'PulseType', 'Sample based', ...
    'Period',    '2', ...
    'PulseWidth','1', ...    % sample-based: number of samples high (1 of 2 = 50%)
    'SampleTime',num2str(isa.Ts), ...
    'Position',  [40 40 90 80]);

% Reset: (digital step counter < resetCycles) for the first N cycles.
add_block('simulink/Sources/Digital Clock', [sys '/StepCount'], ...
    'SampleTime', num2str(isa.Ts), 'Position', [40 140 90 180]);
add_block('simulink/Logic and Bit Operations/Compare To Constant', [sys '/InResetWindow'], ...
    'const', num2str(isa.resetCycles), ...
    'relop', '<', ...
    'OutDataTypeStr', 'boolean', ...
    'Position', [140 140 190 180]);

phCLK = get_param([sys '/ClockGen'], 'PortHandles');
phCNT = get_param([sys '/StepCount'], 'PortHandles');
phCMP = get_param([sys '/InResetWindow'], 'PortHandles');
phO1  = get_param([sys '/CLK'], 'PortHandles');
phO2  = get_param([sys '/RST'], 'PortHandles');

add_line(sys, phCLK.Outport(1), phO1.Inport(1), 'autorouting','on');
add_line(sys, phCNT.Outport(1), phCMP.Inport(1), 'autorouting','on');
add_line(sys, phCMP.Outport(1), phO2.Inport(1), 'autorouting','on');

% Self-check wiring
lh = get_param([sys '/InResetWindow'], 'LineHandles');
if any(lh.Inport == -1) || any(lh.Outport == -1)
    error('SV16:clockReset:wiring', 'CLOCK_RESET has an unconnected port on InResetWindow.');
end

h = struct();
h.sys = sys;
h.out = struct('CLK', phO1.Outport(1), 'RST', phO2.Outport(1));
end
