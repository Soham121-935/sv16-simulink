function r = sv16_make_harness(name, inSpecs, outNames, dutMaker, N)
%SV16_MAKE_HARNESS Build+run a fixed-step test harness around a DUT subsystem.
%
%   r = sv16_make_harness(name, inSpecs, outNames, dutMaker, N)
%
%   inSpecs : struct array with fields
%               .name  input signal name (must match a DUT inport name)
%               .dtype port data type string ('uint8','uint16','uint32','boolean')
%               .data  Nx1 (or scalar-expanded) stimulus, one value per cycle
%   outNames: cellstr of DUT outport names to log
%   dutMaker: @(mdl) -> struct with .in.<name> and .out.<name> PORT HANDLES
%             (it adds the real SV-16 builder subsystem into <mdl>)
%   N       : number of simulation cycles (fixed step = sv16_isa().Ts)
%
% The harness never computes DUT behavior: expected values come from
% independently written reference models in the calling test functions.
% Returns r with .out.<name> (Nx1 or NxW logged values) and .times.

isa = sv16_isa();
mdl = ['sv16_tb_' name '_' datestr(now,'HHMMSSFFF')]; %#ok<DTDATELOOSE>
tmp = tempname; mkdir(tmp);
cleanup = onCleanup(@() sv16_cleanup(mdl, tmp));

new_system(mdl);
set_param(mdl, 'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', ...
    'FixedStep', num2str(isa.Ts), 'StopTime', num2str((N-1)*isa.Ts), ...
    'SaveFormat','slx');

dut = dutMaker(mdl);

% --- Stimulus path: From Workspace -> Data Type Conversion -> DUT ---------
hasInputs = ~isempty(inSpecs) && isfield(inSpecs, 'name') && numel(inSpecs) > 0;
if hasInputs
for k = 1:numel(inSpecs)
    s = inSpecs(k);
    vname = ['sv16_in_' s.name];
    t = (0:N-1)' * isa.Ts;
    d = double(s.data(:));
    if numel(d) == 1, d = repmat(d, N, 1); end
    assignin('base', vname, timeseries(d, t, 'Name', vname));

    fw = [mdl '/' sprintf('IN_%s', s.name)];
    add_block('simulink/Sources/From Workspace', fw, 'Data', vname, ...
        'SampleTime', num2str(isa.Ts), 'Position', [40 40+70*k 120 70+70*k+30]);
    dtc = [mdl '/' sprintf('CVT_%s', s.name)];
    add_block('simulink/Signal Attributes/Data Type Conversion', dtc, ...
        'OutDataTypeStr', s.dtype, 'Position', [160 40+70*k 220 70+70*k+30]);
    phF = get_param(fw, 'PortHandles');
    phD = get_param(dtc, 'PortHandles');
    add_line(mdl, phF.Outport(1), phD.Inport(1), 'autorouting','on');
    add_line(mdl, phD.Outport(1), dut.in.(s.name), 'autorouting','on');
end
end  % if hasInputs

% --- Logging path: DUT -> To Workspace -------------------------------------
r = struct('name', name, 'N', N, 'out', struct(), 'times', []);
for k = 1:numel(outNames)
    nm = outNames{k};
    vname = ['sv16_out_' nm];
    tw = [mdl '/' sprintf('LOG_%s', nm)];
    add_block('simulink/Sinks/To Workspace', tw, 'VariableName', vname, ...
        'SaveFormat','Timeseries', 'SampleTime', num2str(isa.Ts), ...
        'Position', [400 40+70*k 480 70+70*k+30]);
    phO = get_param(tw, 'PortHandles');
    add_line(mdl, dut.out.(nm), phO.Inport(1), 'autorouting','on');
end

% --- Compile gate: the harness itself must update cleanly ------------------
set_param(mdl, 'SimulationCommand', 'update');

% --- Run --------------------------------------------------------------------
simOut = sim(mdl, 'ReturnWorkspaceOutputs','on');
for k = 1:numel(outNames)
    nm = outNames{k};
    ts = simOut.get(['sv16_out_' nm]);
    data = ts.Data;
    if ismatrix(data) && size(data,2) == 1
        data = data(:);
    else
        data = squeeze(data);
    end
    r.out.(nm) = data;
    if k == 1, r.times = ts.Time; end
end
end

function sv16_cleanup(mdl, tmp)
if bdIsLoaded(mdl)
    close_system(mdl, 0);
end
if exist(tmp, 'dir')
    rmdir(tmp, 's');
end
% Remove stimulus variables from the base workspace
vars = evalin('base', 'who');
for k = 1:numel(vars)
    if strncmp(vars{k}, 'sv16_in_', 8)
        evalin('base', sprintf('clear %s', vars{k}));
    end
end
end
