function r = sv16_api_check()
%SV16_API_CHECK Prove programmatic port-handle wiring works in THIS MATLAB,
%before SV-16 Rev A is built (master prompt section 16 step 5).
%
%   r = sv16_api_check()     throws on failure, returns evidence struct.
%
% Demonstrates and verifies, on a throwaway model:
%   1. Every required library block instantiates (sv16_lib_probe).
%   2. add_line(model, srcPortHandle, dstPortHandle) creates a REAL line.
%   3. The created line's SrcPortHandle/DstPortHandle round-trip exactly.
%   4. Multiport Switch port counts follow the 'Inputs' parameter.
%   5. Unit Delay exposes an external-reset port handle after configuration.
%   6. The model updates (compiles) with zero errors.
% Nothing about SV-16 is built until this passes.

r = struct();
r.steps = {};

% --- Step 1: library availability ---------------------------------------
p = sv16_lib_probe();
r.steps{end+1} = struct('name','Library probe', 'pass',p.ok); %#ok<AGROW>

% --- Scratch model -------------------------------------------------------
mdl = ['sv16_api_check_' datestr(now,'HHMMSSFFF')]; %#ok<DTDATELOOSE>
new_system(mdl);
cleanup = onCleanup(@() close_system(mdl, 0));
set_param(mdl, 'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', ...
               'FixedStep','1', 'StopTime','5');

Ts = sv16_isa();  Ts = Ts.Ts;

% --- Place representative blocks (same patterns the builders use) --------
add_block('simulink/Sources/Constant',   [mdl '/C'],  'Value','uint16(4660)', ...
          'OutDataTypeStr','uint16');
add_block('simulink/Sources/Constant',   [mdl '/EN'], 'Value','1', ...
          'OutDataTypeStr','boolean');
add_block('simulink/Sources/Constant',   [mdl '/IDX'],'Value','2', ...
          'OutDataTypeStr','uint8');
phIDX = get_param([mdl '/IDX'], 'PortHandles');
add_block('simulink/Signal Routing/Multiport Switch', [mdl '/MP'], 'Inputs','8');
try
    set_param([mdl '/MP'], 'ControlPortOrder', 'First input port is control');
catch
    % Default already is first-port control in every current release.
end
add_block('simulink/Signal Routing/Switch', [mdl '/SW'], 'Criteria','u2 ~= 0');
add_block('simulink/Discrete/Unit Delay', [mdl '/UD'], 'InitialCondition','uint16(0)', ...
          'ExternalReset','rising', 'SampleTime',num2str(Ts));
add_block('simulink/Sinks/Out1', [mdl '/OUT']);

% --- Step 5 evidence: Unit Delay reset port handle -----------------------
phUD = get_param([mdl '/UD'], 'PortHandles');
hasReset = isfield(phUD, 'Reset') && ~isempty(phUD.Reset);
r.steps{end+1} = struct('name','Unit Delay external reset port exists', 'pass',hasReset); %#ok<AGROW>
assertStep(r, hasReset, 'Unit Delay with ExternalReset=rising exposes no reset port handle');

% --- Step 4 evidence: Multiport Switch port count ------------------------
phMP = get_param([mdl '/MP'], 'PortHandles');
nInMP = numel(phMP.Inport);   % control + 8 data
r.steps{end+1} = struct('name','Multiport Switch port count (1 control + 8 data)', ...
    'pass', nInMP == 9, 'detail', sprintf('got %d inports', nInMP)); %#ok<AGROW>
assertStep(r, nInMP == 9, 'Multiport Switch Inputs=8 did not yield 9 input ports');

% --- Wire STRICTLY with port handles -------------------------------------
phC  = get_param([mdl '/C'],  'PortHandles');
phEN = get_param([mdl '/EN'], 'PortHandles');
phSW = get_param([mdl '/SW'], 'PortHandles');
phO  = get_param([mdl '/OUT'],'PortHandles');

l1 = add_line(mdl, phMP.Outport(1),  phSW.Inport(1), 'autorouting','on');  % mux -> switch data
l2 = add_line(mdl, phEN.Outport(1),  phSW.Inport(2), 'autorouting','on');  % enable -> switch ctrl
l3 = add_line(mdl, phSW.Outport(1),  phUD.Inport(1), 'autorouting','on');  % switch -> delay in
l4 = add_line(mdl, phUD.Outport(1),  phSW.Inport(3), 'autorouting','on');  % feedback (hold)
l5 = add_line(mdl, phUD.Outport(1),  phO.Inport(1),  'autorouting','on');  % branch to output
phUD2 = get_param([mdl '/UD'], 'PortHandles');
l6 = add_line(mdl, phEN.Outport(1),  phUD2.Reset,    'autorouting','on');  % reset line

% --- Step 2/3 evidence: lines are real and endpoints round-trip ----------
checks = {
    l1, phMP.Outport(1),  phSW.Inport(1), 'mux->switch'
    l2, phEN.Outport(1),  phSW.Inport(2), 'enable->switch-ctrl'
    l3, phSW.Outport(1),  phUD.Inport(1), 'switch->unitdelay'
    l4, phUD.Outport(1),  phSW.Inport(3), 'hold feedback'
    l5, phUD.Outport(1),  phO.Inport(1),  'output branch'
    l6, phEN.Outport(1),  phUD2.Reset,    'reset->unitdelay'
    };
wireOk = true;
for k = 1:size(checks, 1)
    lh = checks{k,1}; src = checks{k,2}; dst = checks{k,3};
    ls = get_param(lh, 'SrcPortHandle');
    ld = get_param(lh, 'DstPortHandle');
    if ls ~= src || ~any(ld == dst)
        wireOk = false;
        fprintf('  line %d (%s): src %d vs %d, dst %s vs %d\n', ...
            k, checks{k,4}, ls, src, mat2str(ld), dst);
    end
end
r.steps{end+1} = struct('name','Port-handle lines round-trip (6 lines, incl. feedback + branch)', ...
    'pass', wireOk); %#ok<AGROW>
assertStep(r, wireOk, 'Programmatic wiring did not produce exact port-to-port lines');

% --- Step 6 evidence: compile -------------------------------------------
try
    set_param(mdl, 'SimulationCommand', 'update');
    compileOk = true; compileMsg = '';
catch err
    compileOk = false; compileMsg = err.message;
end
r.steps{end+1} = struct('name','Scratch model compiles (update)', ...
    'pass', compileOk, 'detail', compileMsg); %#ok<AGROW>
assertStep(r, compileOk, 'Scratch wiring model failed to compile');

% --- Bonus evidence: 1-step simulation executes --------------------------
try
    set_param(mdl, 'StopTime', '5');
    simOut = sim(mdl, 'ReturnWorkspaceOutputs', 'on');
    simOk = ~isempty(simOut);
catch err
    simOk = false;
    r.steps{end}.detail = err.message;
end
r.steps{end+1} = struct('name','Scratch model simulates', 'pass', simOk); %#ok<AGROW>
assertStep(r, simOk, 'Scratch wiring model failed to simulate');

r.ok = all(cellfun(@(s) s.pass, r.steps));
fprintf('sv16_api_check: %s (%d/%d steps passed)\n', ...
    tern(r.ok,'PASS','FAIL'), sum(cellfun(@(s) s.pass, r.steps)), numel(r.steps));
end

function assertStep(r, cond, msg)
if ~cond
    error('SV16:apiCheck:fail', 'sv16_api_check failed: %s', msg);
end
end

function t = tern(c, a, b)
if c, t = a; else, t = b; end
end
