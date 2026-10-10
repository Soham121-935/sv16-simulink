function h = sv16_lib_register(parentSys, name, dataTypeStr, resetValStr, Ts)
%SV16_LIB_REGISTER Build one enabled register primitive (decision D-010).
%
%   h = sv16_lib_register(parentSys, name, dataTypeStr, resetValStr, Ts)
%
% Creates subsystem  <parentSys>/<name>  with interface:
%   In : D   (dataTypeStr, e.g. 'uint16')  -- data to store
%        EN  (boolean)                      -- write enable
%        RST (boolean, active high)         -- synchronous reset (2 cycles)
%   Out: Q   (dataTypeStr)
%
% Semantics (documented, tested by TC-RF-*):
%   Q(t+1) = reset             if RST rising at t   (synchronous, forced)
%   Q(t+1) = D(t)              if EN(t) == true
%   Q(t+1) = Q(t)              otherwise
% i.e. an enable flop: a value written during cycle t is visible from t+1.
%
% Implementation uses ONLY core simulink library blocks (no hdlsllib):
%   Switch(EN) selects D vs held feedback Q, followed by one Unit Delay with
%   external synchronous reset and initial condition resetValStr.

sys = [parentSys '/' name];
add_block('built-in/Subsystem', sys, 'Position', [40 40 220 140]);

% --- Interface ports -----------------------------------------------------
add_block('simulink/Sources/In1', [sys '/D'],   'Port','1');
add_block('simulink/Sources/In1', [sys '/EN'],  'Port','2');
add_block('simulink/Sources/In1', [sys '/RST'], 'Port','3');
add_block('simulink/Sinks/Out1',  [sys '/Q'],   'Port','1');
sv16_setp([sys '/D'],  {'OutDataTypeStr','DataType'}, dataTypeStr);
sv16_setp([sys '/Q'],  {'OutDataTypeStr','DataType'}, dataTypeStr);
sv16_setp([sys '/EN'], {'OutDataTypeStr','DataType'}, 'boolean');
sv16_setp([sys '/RST'],{'OutDataTypeStr','DataType'}, 'boolean');

% --- Internal logic ------------------------------------------------------
add_block('simulink/Signal Routing/Switch', [sys '/HoldSwitch'], ...
    'Criteria', 'u2 ~= 0', 'Position', [120 60 160 120]);
add_block('simulink/Discrete/Unit Delay', [sys '/State'], ...
    'InitialCondition', resetValStr, 'ExternalReset', 'rising', ...
    'SampleTime', num2str(Ts), 'Position', [210 70 250 110]);

% --- Wiring with real port handles (master prompt step 4) ----------------
phD   = get_param([sys '/D'],   'PortHandles');
phEN  = get_param([sys '/EN'],  'PortHandles');
phRST = get_param([sys '/RST'], 'PortHandles');
phSW  = get_param([sys '/HoldSwitch'], 'PortHandles');
phUD  = get_param([sys '/State'], 'PortHandles');
phQ   = get_param([sys '/Q'],   'PortHandles');

add_line(sys, phSW.Outport(1),  phUD.Inport(1), 'autorouting','on');  % switched -> flop
add_line(sys, phD.Outport(1),   phSW.Inport(1), 'autorouting','on');  % D (criteria true)
add_line(sys, phEN.Outport(1),  phSW.Inport(2), 'autorouting','on');  % EN control
add_line(sys, phUD.Outport(1),  phSW.Inport(3), 'autorouting','on');  % held feedback
add_line(sys, phRST.Outport(1), phUD.Reset,     'autorouting','on');  % synchronous reset
add_line(sys, phUD.Outport(1),  phQ.Inport(1),  'autorouting','on');  % Q out

% --- Self-check: every created line must be recognized by Simulink --------
lhUD = get_param([sys '/State'], 'LineHandles');
if any(lhUD.Inport == -1) || any(lhUD.Outport == -1)
    error('SV16:register:wiring', 'Register primitive %s has an unconnected State block port.', sys);
end
lhSW = get_param([sys '/HoldSwitch'], 'LineHandles');
if any(lhSW.Inport == -1) || any(lhSW.Outport == -1)
    error('SV16:register:wiring', 'Register primitive %s has an unconnected HoldSwitch port.', sys);
end

h = struct();
h.sys = sys;
h.in  = struct('D', phD.Outport(1), 'EN', phEN.Outport(1), 'RST', phRST.Outport(1));
h.out = struct('Q', phUD.Outport(1));
end
