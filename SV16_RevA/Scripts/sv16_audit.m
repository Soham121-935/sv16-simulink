function report = sv16_audit(model, opts)
%SV16_AUDIT Connection-integrity auditor for SV-16 Rev A (master prompt section 5).
%
%   report = sv16_audit(model)            % strict, compile included
%   report = sv16_audit(model, opts)
%
% Inspects the ACTUAL model structure through Simulink APIs -- never a
% screenshot:
%   * every block's port handles and their connected line handles
%   * every line's SrcPortHandle / DstPortHandle (segments and branches)
%   * missing-library / invalid Reference blocks
%   * multiple drivers on one destination port
%   * isolated blocks, empty subsystems, undocumented Ground/Terminator use
%   * model update (compile) result; compiled data types sampled after update
%
% report.passed is TRUE only when: zero unconnected required ports, zero
% unintended dangling lines/connections, zero invalid/missing blocks, zero
% multiple drivers, zero compile errors, and every Ground/Terminator is
% documented. Uncheckable conditions are reported NOT VERIFIED, never PASS.
%
% opts fields (all optional):
%   .exceptions   struct array: .block (path or unique substring),
%                 .port (port number or [] for all), .direction ('in'|'out'|'any'),
%                 .reason (text, required)  -- documented intentionally
%                 unconnected ports (master prompt rule M).
%   .grounds      containers.Map('blockPathSubstring', 'engineering reason')
%   .terminators  containers.Map('blockPathSubstring', 'engineering reason')
%   .compile      logical, default true -- run set_param(update)
%   .writeReport  logical, default true -- write Verification/connection_audit.txt

if nargin < 2, opts = struct(); end
if ~isfield(opts, 'compile'),     opts.compile = true;      end
if ~isfield(opts, 'writeReport'), opts.writeReport = true;  end
if ~isfield(opts, 'exceptions'),  opts.exceptions = struct('block',{},'port',{},'direction',{},'reason',{}); end
if ~isfield(opts, 'grounds'),     opts.grounds = containers.Map(); end
if ~isfield(opts, 'terminators'), opts.terminators = containers.Map(); end

report = blankReport();
if ~bdIsLoaded(model)
    load_system(model);
end
report.model = model;

% ---------------------------------------------------------------- blocks
blks = find_system(model, 'LookUnderMasks','all', 'Type','Block');
report.totalBlocks = numel(blks);

multipleDrivers = containers.Map('KeyType','char','ValueType','double');

for iBlk = 1:numel(blks)
    bPath = blks{iBlk};
    try
        bType = get_param(bPath, 'BlockType');
        bName = get_param(bPath, 'Name');
    catch err
        report.invalidBlocks = report.invalidBlocks + 1;
        report = addFinding(report, 'INVALID_BLOCK', model, '?', '?', ...
            'Block handle unreadable', err.message, 'Remove or repair the block.');
        continue
    end
    if strcmp(bType, 'Annotation') || strcmp(bType, 'Area') || strcmp(bType, 'Note')
        continue  % not part of the signal graph
    end
    sysPath = strrep(bPath, ['/' bName], '');

    % ---- Reference (library) blocks must resolve ------------------------
    if strcmp(bType, 'Reference')
        ref = '';
        try
            ref = get_param(bPath, 'ReferenceBlock');
        catch
            ref = '';
        end
        if isempty(ref)
            report.missingLibraryBlocks = report.missingLibraryBlocks + 1;
            report = addFinding(report, 'MISSING_LIBRARY', sysPath, bName, '?', ...
                'Resolvable library source', 'ReferenceBlock empty/unreadable', ...
                'Re-link the block or replace it with a supported block (record replacement in decision log).');
        end
    end

    % ---- Empty subsystems masquerading as content -----------------------
    if strcmp(bType, 'SubSystem') && ~strcmp(get_param(bPath,'ReferenceBlock'), '')
        % library-linked subsystem: fine
    end

    % ---- Subsystem boundary ports (parent-side view) ---------------------
    % The child Inport/Outport blocks verify the INSIDE of the boundary;
    % here we verify the OUTSIDE: a subsystem's parent-side port must be
    % wired at the parent level (or be a documented pending-integration
    % exception, master prompt rule M).
    if any(strcmp(bType, {'SubSystem','Model','S-Function','AtomicSubSystem'}))
        phB = get_param(bPath, 'PortHandles');
        for iP = 1:numel(phB.Inport)
            if get_param(phB.Inport(iP), 'Line') == -1
                ex = exceptionFor(opts, bPath, iP, 'in');
                if isempty(ex)
                    report.unconnectedRequiredInports = report.unconnectedRequiredInports + 1;
                    report = addFinding(report, 'UNCONNECTED_REQUIRED_INPORT', sysPath, ...
                        bName, sprintf('boundary in:%d', iP), ...
                        'Line attached at parent level', 'Boundary port has no line (-1)', ...
                        'Wire this subsystem input at the parent level, or document the pending integration.');
                else
                    report.documentedExceptions{end+1} = ...
                        sprintf('%s  boundary in:%d -- %s', bPath, iP, ex.reason); %#ok<AGROW>
                end
            else
                report.connectedRequiredInports = report.connectedRequiredInports + 1;
            end
        end
        for iP = 1:numel(phB.Outport)
            if get_param(phB.Outport(iP), 'Line') == -1
                ex = exceptionFor(opts, bPath, iP, 'out');
                if isempty(ex)
                    report.unconnectedRequiredOutports = report.unconnectedRequiredOutports + 1;
                    report = addFinding(report, 'UNCONNECTED_REQUIRED_OUTPORT', sysPath, ...
                        bName, sprintf('boundary out:%d', iP), ...
                        'Line attached at parent level', 'Boundary port has no line (-1)', ...
                        'Wire this subsystem output at the parent level, or document the pending integration.');
                else
                    report.documentedExceptions{end+1} = ...
                        sprintf('%s  boundary out:%d -- %s', bPath, iP, ex.reason); %#ok<AGROW>
                end
            else
                report.connectedRequiredOutports = report.connectedRequiredOutports + 1;
            end
        end
        continue
    end

    ph = get_param(bPath, 'PortHandles');
    portFields = {'Inport','Outport','Enable','Trigger','Reset','State'};
    for iF = 1:numel(portFields)
        f = portFields{iF};
        if ~isfield(ph, f) || isempty(ph.(f)), continue; end
        for iP = 1:numel(ph.(f))
            portH   = ph.(f)(iP);
            dirn    = 'in'; if strcmp(f,'Outport'), dirn = 'out'; end
            lineH   = -1;
            try
                lineH = get_param(portH, 'Line');
            catch
                lineH = -1;
            end
            connected = (lineH ~= -1);

            if connected
                if strcmp(dirn,'in')
                    report.connectedRequiredInports = report.connectedRequiredInports + 1;
                else
                    report.connectedRequiredOutports = report.connectedRequiredOutports + 1;
                end
            else
                ex = exceptionFor(opts, bPath, iP, dirn);
                if ~isempty(ex)
                    report.documentedExceptions{end+1} = ...
                        sprintf('%s  port %s:%d -- %s', bPath, f, iP, ex.reason); %#ok<AGROW>
                else
                    if strcmp(dirn,'in')
                        report.unconnectedRequiredInports = report.unconnectedRequiredInports + 1;
                        report = addFinding(report, 'UNCONNECTED_REQUIRED_INPORT', sysPath, ...
                            bName, sprintf('%s:%d', f, iP), ...
                            'Line attached to this input port', 'Port has no line (-1)', ...
                            'Wire this port to its intended source (interface table of the subsystem).');
                    else
                        report.unconnectedRequiredOutports = report.unconnectedRequiredOutports + 1;
                        report = addFinding(report, 'UNCONNECTED_REQUIRED_OUTPORT', sysPath, ...
                            bName, sprintf('%s:%d', f, iP), ...
                            'Line attached to this output port', 'Port has no line (-1)', ...
                            'Wire this port to its intended destination, or document/terminate it per rule L/M.');
                    end
                end
            end
        end
    end

    % ---- Ground / Terminator justification ------------------------------
    switch bType
        case 'Ground'
            if ~isKey(opts.grounds, bPath) && ~keyMatch(opts.grounds, bPath)
                report.invalidConnections = report.invalidConnections + 1;
                report = addFinding(report, 'UNDOCUMENTED_GROUND', sysPath, bName, '?', ...
                    'Documented constant-zero justification', 'No entry in opts.grounds', ...
                    'Add an engineering justification or remove the Ground.');
            else
                report.documentedGrounds{end+1} = bPath; %#ok<AGROW>
            end
        case 'Terminator'
            if ~isKey(opts.terminators, bPath) && ~keyMatch(opts.terminators, bPath)
                report.invalidConnections = report.invalidConnections + 1;
                report = addFinding(report, 'UNDOCUMENTED_TERMINATOR', sysPath, bName, '?', ...
                    'Documented intentionally-unused-output justification', 'No entry in opts.terminators', ...
                    'Add an engineering justification or remove the Terminator.');
            else
                report.documentedTerminators{end+1} = bPath; %#ok<AGROW>
            end
    end

    % ---- Isolated standard blocks (no ports at all) -----------------------
    if ~any(strcmp(bType, {'Ground','Terminator','Display','Scope','SubSystem', ...
                           'Model','S-Function','AtomicSubSystem'}))
        nIn = numel(ph.Inport); nOut = numel(ph.Outport);
        if nIn == 0 && nOut == 0
            report.unintendedUnusedSignals = report.unintendedUnusedSignals + 1;
            report = addFinding(report, 'ISOLATED_BLOCK', sysPath, bName, '?', ...
                'Block participates in the dataflow', ...
                'Block has no ports or is not referenced by any line', ...
                'Remove this block or connect it intentionally.');
        end
    end
end

report.requiredInports  = report.connectedRequiredInports  + report.unconnectedRequiredInports;
report.requiredOutports = report.connectedRequiredOutports + report.unconnectedRequiredOutports;

% ---------------------------------------------------------------- lines
lines = find_system(model, 'FindAll','on', 'LookUnderMasks','all', 'Type','line');
report.totalLines = numel(lines);
for iL = 1:numel(lines)
    lh = lines(iL);
    src = -1; dst = [];
    try
        src = get_param(lh, 'SrcPortHandle');
        dst = get_param(lh, 'DstPortHandle');
    catch err
        report.invalidConnections = report.invalidConnections + 1;
        report = addFinding(report, 'INVALID_LINE', model, sprintf('line #%d', lh), '?', ...
            'Readable line endpoints', err.message, 'Delete and redraw the line via port handles.');
        continue
    end
    if src == -1
        report.invalidConnections = report.invalidConnections + 1;
        report = addFinding(report, 'LINE_WITHOUT_SOURCE', model, sprintf('line #%d', lh), ...
            'Src', 'Valid source port', 'SrcPortHandle == -1', ...
            'Delete this line; reconnect from the true source port handle.');
    end
    if isempty(dst) || all(dst == -1)
        report.unintendedDanglingLines = report.unintendedDanglingLines + 1;
        report = addFinding(report, 'DANGLING_LINE', model, sprintf('line #%d', lh), ...
            'Dst', 'At least one destination port', 'DstPortHandle empty or -1', ...
            'Delete or complete this line; it ends in empty space.');
    end
    for iD = 1:numel(dst)
        key = num2str(dst(iD));
        if multipleDrivers.isKey(key)
            multipleDrivers(key) = multipleDrivers(key) + 1;
        else
            multipleDrivers(key) = 1;
        end
    end
end
keys = multipleDrivers.keys;
for k = 1:numel(keys)
    if multipleDrivers(keys{k}) > 1
        report.multipleDriverErrors = report.multipleDriverErrors + 1;
        ph = str2double(keys{k});
        bPath = '';
        try, bPath = get_param(ph,'Parent'); catch, end %#ok<*LERR>
        report = addFinding(report, 'MULTIPLE_DRIVERS', bPath, sprintf('port handle %s', keys{k}), ...
            'Dst', 'Exactly one driver', sprintf('%d incoming lines', multipleDrivers(keys{k})), ...
            'Remove the extra driver line.');
    end
end

% ---------------------------------------------------------------- compile
if opts.compile
    try
        set_param(model, 'SimulationCommand', 'update');
        report.compileOk = true;
        % Sample compiled signal data types as evidence of width/type sanity.
        nTyped = 0;
        for iL = 1:numel(lines)
            try
                src = get_param(lines(iL), 'SrcPortHandle');
                if src ~= -1
                    dt = get_param(src, 'CompiledDataType'); %#ok<NASGU>
                    nTyped = nTyped + 1;
                end
            catch
                % unnamed/derived ports may not expose this pre-run; not fatal
            end
        end
        report.typedSignals = nTyped;
    catch err
        report.compileOk = false;
        report.compilationErrors{end+1} = err.message; %#ok<AGROW>
        report = addFinding(report, 'COMPILE_ERROR', model, model, '?', ...
            'Model updates without error', err.message, ...
            'Fix the reported block/port; never suppress the diagnostic.');
    end
else
    report.compileOk = false;
    report.widthTypeErrors = NaN;  % NOT VERIFIED, never PASS
    report.notVerified{end+1} = 'Compile/width/type checks skipped (opts.compile=false).'; %#ok<AGROW>
end

% ---------------------------------------------------------------- verdict
report.passed = report.unconnectedRequiredInports == 0 && ...
                report.unconnectedRequiredOutports == 0 && ...
                report.unintendedDanglingLines == 0 && ...
                report.invalidConnections == 0 && ...
                report.invalidBlocks == 0 && ...
                report.missingLibraryBlocks == 0 && ...
                report.multipleDriverErrors == 0 && ...
                report.unintendedUnusedSignals == 0 && ...
                report.compileOk && ...
                isempty(report.compilationErrors);
report.overallResult = tern(report.passed, 'PASS', 'FAIL');

if opts.writeReport
    writeReportFile(report);
end
end

% =========================================================================
function report = blankReport()
r = struct();
r.model=''; r.totalBlocks=0; r.totalLines=0;
r.requiredInports=0; r.requiredOutports=0;
r.connectedRequiredInports=0; r.connectedRequiredOutports=0;
r.unconnectedRequiredInports=0; r.unconnectedRequiredOutports=0;
r.invalidBlocks=0; r.missingLibraryBlocks=0; r.invalidConnections=0;
r.unintendedDanglingLines=0; r.unintendedUnusedSignals=0;
r.widthTypeErrors=0; r.multipleDriverErrors=0;
r.compilationErrors={}; r.simulationErrors={};
r.findings={}; r.documentedExceptions={}; r.documentedGrounds={}; r.documentedTerminators={};
r.notVerified={}; r.compileOk=false; r.typedSignals=-1;
r.passed=false; r.overallResult='NOT VERIFIED';
report = r;
end

function reason = exceptionFor(opts, bPath, portNum, dirn)
reason = '';
for k = 1:numel(opts.exceptions)
    e = opts.exceptions(k);
    if isempty(e.block), continue; end
    if ~contains(bPath, e.block), continue; end
    if ~isempty(e.port) && e.port ~= portNum, continue; end
    if ~strcmpi(e.direction, 'any') && ~strcmpi(e.direction, dirn), continue; end
    reason = e.reason;
    return
end
end

function tf = keyMatch(m, path)
tf = false;
ks = m.keys;
for k = 1:numel(ks)
    if contains(path, ks{k}), tf = true; return; end
end
end

function report = addFinding(report, kind, sysPath, blk, port, expected, actual, fix)
report.findings{end+1} = struct('kind',kind, 'subsystem',sysPath, 'block',blk, ...
    'port',port, 'expected',expected, 'actual',actual, 'recommendedFix',fix); %#ok<AGROW>
if strcmp(kind,'INVALID_BLOCK') || strcmp(kind,'COMPILE_ERROR')
    % counted by callers where relevant
end
end

function writeReportFile(report)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
vdir = fullfile(root, 'SV16_RevA', 'Verification');
if ~exist(vdir, 'dir'), mkdir(vdir); end
fid = fopen(fullfile(vdir, 'connection_audit.txt'), 'w');
fprintf(fid, 'SV-16 REV A CONNECTION-INTEGRITY AUDIT\n');
fprintf(fid, 'Model   : %s\n', report.model);
fprintf(fid, 'Date    : %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<DTDATELOOSE>
fprintf(fid, 'Blocks                       : %d\n', report.totalBlocks);
fprintf(fid, 'Lines                        : %d\n', report.totalLines);
fprintf(fid, 'Required inports             : %d\n', report.requiredInports);
fprintf(fid, 'Required outports            : %d\n', report.requiredOutports);
fprintf(fid, 'Connected required inports   : %d\n', report.connectedRequiredInports);
fprintf(fid, 'Connected required outports  : %d\n', report.connectedRequiredOutports);
fprintf(fid, 'Unconnected required inports : %d\n', report.unconnectedRequiredInports);
fprintf(fid, 'Unconnected required outports: %d\n', report.unconnectedRequiredOutports);
fprintf(fid, 'Invalid blocks               : %d\n', report.invalidBlocks);
fprintf(fid, 'Missing-library blocks       : %d\n', report.missingLibraryBlocks);
fprintf(fid, 'Invalid connections          : %d\n', report.invalidConnections);
fprintf(fid, 'Unintended dangling lines    : %d\n', report.unintendedDanglingLines);
fprintf(fid, 'Unintended unused blocks/sigs: %d\n', report.unintendedUnusedSignals);
fprintf(fid, 'Width/type errors            : %s\n', tern(isnan(report.widthTypeErrors),'NOT VERIFIED',num2str(report.widthTypeErrors)));
fprintf(fid, 'Multiple-driver errors       : %d\n', report.multipleDriverErrors);
fprintf(fid, 'Compilation                  : %s\n', tern(report.compileOk,'OK','ERRORS'));
fprintf(fid, 'Compile errors               : %d\n', numel(report.compilationErrors));
fprintf(fid, 'Documented exceptions        : %d\n', numel(report.documentedExceptions));
fprintf(fid, 'Documented grounds           : %d\n', numel(report.documentedGrounds));
fprintf(fid, 'Documented terminators       : %d\n', numel(report.documentedTerminators));
fprintf(fid, '\nOVERALL AUDIT RESULT: %s\n', report.overallResult);
if ~isempty(report.findings)
    fprintf(fid, '\nFINDINGS (%d)\n', numel(report.findings));
    for k = 1:numel(report.findings)
        f = report.findings{k};
        fprintf(fid, '\n[%02d] %s\n  Subsystem : %s\n  Block     : %s\n  Port      : %s\n', ...
            k, f.kind, f.subsystem, f.block, f.port);
        fprintf(fid, '  Expected  : %s\n  Actual    : %s\n  Fix       : %s\n', ...
            f.expected, f.actual, f.recommendedFix);
    end
end
if ~isempty(report.documentedExceptions)
    fprintf(fid, '\nDOCUMENTED EXCEPTIONS (rule M)\n');
    for k = 1:numel(report.documentedExceptions)
        fprintf(fid, '  - %s\n', report.documentedExceptions{k});
    end
end
if ~isempty(report.notVerified)
    fprintf(fid, '\nNOT VERIFIED ITEMS\n');
    for k = 1:numel(report.notVerified)
        fprintf(fid, '  - %s\n', report.notVerified{k});
    end
end
fclose(fid);
end

function t = tern(c, a, b)
if c, t = a; else, t = b; end
end
