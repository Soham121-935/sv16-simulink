function summary = sv16_run_tests()
%SV16_RUN_TESTS Run all implemented SV-16 Rev A subsystem test suites and
%write Verification/test_results.md.
%
%   summary = sv16_run_tests()
%
% Only suites whose subsystems exist are run; everything else is reported
% NOT IMPLEMENTED (never skipped silently). A suite FAIL is a FAIL.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
suites = {
    @test_sv16_clock_reset,      'CLOCK_RESET',      2
    @test_sv16_register_bank,    'REGISTER_BANK',    3
    @test_sv16_program_counter,  'PROGRAM_COUNTER',  4
    @test_sv16_alu,              'ALU',              5
    @test_sv16_status_register,  'STATUS_REGISTER',  6
    };

summary = struct('suites', {}, 'passed', false);
lines = {};
lines{end+1} = '# SV-16 Rev A — Test Results'; %#ok<AGROW>
lines{end+1} = sprintf('Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<DTDATELOOSE>

anyFail = false;
for k = 1:size(suites, 1)
    fun = suites{k,1}; name = suites{k,2}; stage = suites{k,3};
    try
        res = fun();
        status = tern(res.passed, 'PASS', 'FAIL');
        if ~res.passed, anyFail = true; end
        cases = res.cases;
    catch err
        status = 'FAIL';
        anyFail = true;
        cases = {'EXCEPTION', err.message, false};
        res = struct('name', name, 'passed', false, 'cases', cases);
    end
    summary.suites{end+1} = res; %#ok<AGROW>
    lines{end+1} = sprintf('## Stage %d — %s: **%s**', stage, name, status); %#ok<AGROW>
    for c = 1:size(cases, 1)
        lines{end+1} = sprintf('- %s (%s): %s', cases{c,1}, cases{c,2}, ...
            tern(cases{c,3}, 'PASS', 'FAIL')); %#ok<AGROW>
    end
    lines{end+1} = '';
end

% Later stages: explicit NOT IMPLEMENTED (never silently skipped)
later = {7, 'INSTRUCTION_REGISTER_DECODER'; 8, 'DATAPATH'; 9, 'CONTROL_UNIT'; ...
         10, 'MEMORY_SYSTEM'; 11, 'CPU_INTEGRATION'; 12, 'PERIPHERALS'};
for k = 1:size(later, 1)
    lines{end+1} = sprintf('## Stage %d — %s: **NOT IMPLEMENTED**', later{k,2}, later{k,1}); %#ok<AGROW>
end

vdir = fullfile(root, 'SV16_RevA', 'Verification');
fid = fopen(fullfile(vdir, 'test_results.md'), 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);

summary.passed = ~anyFail;
fprintf('sv16_run_tests: overall %s\n', tern(~anyFail, 'PASS', 'FAIL'));
end

function t = tern(c, a, b)
if c, t = a; else, t = b; end
end
