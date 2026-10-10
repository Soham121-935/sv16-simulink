function summary = sv16_build_all(upTo)
%SV16_BUILD_ALL Incremental, gate-checked build of SV-16 Rev A (Stages 0-6).
%
%   summary = sv16_build_all()            % run all implemented stages
%   summary = sv16_build_all('ALU')       % stop after a named stage
%
% Implements the master prompt workflow AND the CRITICAL STOP CONDITION:
% after every stage the model must pass
%   (1) sv16_audit  (structural, incl. compile) and
%   (2) the stage's functional test suite,
% before the next subsystem is built. Any failure ABORTS the build with the
% exact finding; nothing is ever built on top of a failing model.
% Passing milestones are snapshotted into Milestones/.

if nargin < 1, upTo = ''; end

% ---- STAGE 0/GATE: environment + wiring API proof -------------------------
fprintf('=== SV16_BUILD_ALL: environment gate ===\n');
api = sv16_api_check();
if ~api.ok
    error('SV16:buildAll:api', 'sv16_api_check failed -- fix the wiring API issue before building.');
end

% ---- Clean model -----------------------------------------------------------
mdl = sv16_new_model();
load_system(mdl);

stages = { ...
    2, 'CLOCK_RESET',     @() sv16_build_clock_reset(mdl),      @test_sv16_clock_reset,     sv16_exc_clock_reset(mdl)
    3, 'REGISTER_BANK',   @() sv16_add_cpu_core_and(mdl, @() sv16_build_register_bank(mdl)), @test_sv16_register_bank, sv16_exc_regbank(mdl)
    4, 'PROGRAM_COUNTER', @() sv16_build_program_counter(mdl),  @test_sv16_program_counter, sv16_exc_pc(mdl)
    5, 'ALU',             @() sv16_build_alu(mdl),              @test_sv16_alu,             sv16_exc_alu(mdl)
    6, 'STATUS_REGISTER', @() sv16_build_status_register(mdl),  @test_sv16_status_register, sv16_exc_status(mdl)
    };

summary = struct('stages', {}, 'ok', true);
done = false(stages(end,1), 1);

for s = 1:size(stages, 1)
    num = stages{s,1}; name = stages{s,2}; builder = stages{s,3}; tester = stages{s,4}; excs = stages{s,5};

    fprintf('=== Stage %d: %s ===\n', num, name);
    builder();   % build subsystem into the model

    save_system(mdl);

    % ---- GATE 1: connection-integrity audit (structural + compile) ------
    audit = sv16_audit(mdl, struct('exceptions', excs));
    if ~audit.passed
        summary.ok = false;
        summary.stages{end+1} = struct('stage',num,'name',name,'status','FAIL','reason','connection-integrity audit'); %#ok<AGROW>
        error(['SV16:buildAll:audit:STOP\n' ...
            'CRITICAL STOP CONDITION at stage %d (%s): the model has real ' ...
            'connection problems. See SV16_RevA/Verification/connection_audit.txt ' ...
            'for the exact subsystem, block, and port. Repair before building anything else.'], num, name);
    end

    % ---- GATE 2: functional test ----------------------------------------
    try
        res = tester();
        testOk = res.passed;
    catch err
        testOk = false;
        warning('Stage %d test threw: %s', num, err.message);
    end
    if ~testOk
        summary.ok = false;
        summary.stages{end+1} = struct('stage',num,'name',name,'status','FAIL','reason','functional test'); %#ok<AGROW>
        error(['SV16:buildAll:test:STOP\n' ...
            'CRITICAL STOP CONDITION at stage %d (%s): functional tests failed. ' ...
            'See Verification/test_results.md.'], num, name);
    end

    % ---- Milestone snapshot ---------------------------------------------
    save_system(mdl);
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    mdir = fullfile(root, 'SV16_RevA', 'Milestones');
    if ~exist(mdir,'dir'), mkdir(mdir); end
    snap = fullfile(mdir, sprintf('SV16_RevA_%02d_%s.slx', num, name));
    copyfile(fullfile(fileparts(getfullname(mdl)), [mdl '.slx']), snap, 'f');

    summary.stages{end+1} = struct('stage',num,'name',name,'status','PASS','reason',''); %#ok<AGROW>
    done(num) = true;
    fprintf('Stage %d (%s): PASS -- milestone %s\n', num, name, snap);

    if strcmpi(name, upTo)
        break
    end
end

% Stages 7+ are NOT IMPLEMENTED and reported as such (never claimed).
fprintf(['\nStages 2-6 built and verified through this run.\n' ...
         'Stages 7-13 (IR/decoder, datapath, control unit, memory, ' ...
         'integration, peripherals): NOT IMPLEMENTED yet.\n']);
end

% ---------------------------------------------------------------------------
function parent = sv16_add_cpu_core_and(mdl, buildFn)
% REGISTER_BANK is the first CPU_CORE child: create CPU_CORE here.
add_block('built-in/Subsystem', [mdl '/CPU_CORE']);
buildFn();
parent = [mdl '/CPU_CORE']; %#ok<NASGU>
end

function e = sv16_exc_clock_reset(mdl) %#ok<INUSD>
% Stage-2 top level: CLK/RST are produced but not yet consumed (integration
% happens when CPU_CORE exists). Documented pending-integration exceptions.
e = struct('block',{'CLOCK_RESET'},'port',[],'direction',{'out'}, ...
           'reason',{['Pending integration: CLOCK_RESET outputs will drive ' ...
                      'CPU_CORE from stage 3 onward (master prompt rule M).']});
end

function e = sv16_exc_regbank(mdl) %#ok<INUSD>
e = struct( ...
  'block', {'CLOCK_RESET','REGISTER_BANK'}, 'port', [], ...
  'direction', {'out','any'}, ...
  'reason', {'Pending integration: CLK/RST consumed by CPU core datapath (stage 8).', ...
             ['Pending integration: REGISTER_BANK read/write ports are driven by ' ...
              'the datapath/control unit in stages 8-9; testbench exercises them now.']});
end

function e = sv16_exc_pc(mdl) %#ok<INUSD>
e = struct( ...
  'block', {'CLOCK_RESET','REGISTER_BANK','PROGRAM_COUNTER'}, 'port', [], ...
  'direction', {'out','any','any'}, ...
  'reason', {'Pending integration: stage 8.', ...
             'Pending integration: stage 8.', ...
             ['Pending integration: PC control inputs (EN/PCSrc/targets) come ' ...
              'from the control unit in stage 9; testbench exercises them now.']});
end

function e = sv16_exc_alu(mdl) %#ok<INUSD>
e = struct( ...
  'block', {'CLOCK_RESET','REGISTER_BANK','PROGRAM_COUNTER','ALU'}, 'port', [], ...
  'direction', {'out','any','any','any'}, ...
  'reason', {sprintf('Pending integration: stage 8.'), 'Pending integration: stage 8.', ...
             'Pending integration: stage 8.', ...
             'Pending integration: ALU operands/opcode driven by datapath (stage 8).'});
end

function e = sv16_exc_status(mdl) %#ok<INUSD>
e = struct( ...
  'block', {'CLOCK_RESET','REGISTER_BANK','PROGRAM_COUNTER','ALU','STATUS_REGISTER'}, ...
  'port', [], ...
  'direction', {'out','any','any','any','any'}, ...
  'reason', {sprintf('Pending integration: stage %d.',8), 'Pending integration: stage 8.', ...
             'Pending integration: stage 8.', 'Pending integration: stage 8.', ...
             'Pending integration: flag inputs driven by datapath/control (stages 8-9).'});
end
