function sv16_report()
%SV16_REPORT Assemble the end-of-session report (master prompt section 17)
%from the artifacts actually present in the workspace -- it NEVER invents
%results. Anything not found is reported NOT TESTED / NOT IMPLEMENTED.
%
%   sv16_report()

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
verif = fullfile(root, 'SV16_RevA', 'Verification');
miles = fullfile(root, 'SV16_RevA', 'Milestones');

lines = {};

add('# SV-16 Rev A — Session Report');
add('Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<DTDATELOOSE>

% A. implemented, B. files, C. subsystems
add('\n## A/B/C — Implemented, files, subsystems');
add('- Environment gate + port-handle wiring proof: `sv16_api_check` (status below).');
add('- Connection-integrity auditor: `sv16_audit`.');
add('- Clean-model builder: `sv16_new_model`; stage builders 2–6 (CLOCK_RESET, REGISTER_BANK, PROGRAM_COUNTER, ALU, STATUS_REGISTER).');
add('- Test suites TC-CR/RF/PC/AL/SR with independent reference models.');
add('- Stages 7–13: NOT IMPLEMENTED (control unit, datapath integration, memory system, full-CPU execution, peripherals).');

% audit evidence
auditFile = fullfile(verif, 'connection_audit.txt');
if exist(auditFile, 'file')
    add('\n## E/G — Latest audit evidence (from Verification/connection_audit.txt)');
    add('```');
    add('%s', strtrim(fileread(auditFile)));
    add('```');
else
    add('\n## E/G — Connection-integrity audit: NOT TESTED (no audit artifact yet; run sv16_build_all in MATLAB).');
end

% test evidence
testFile = fullfile(verif, 'test_results.md');
if exist(testFile, 'file')
    add('\n## D/E — Latest test evidence (from Verification/test_results.md)');
    add('%s', fileread(testFile));
else
    add('\n## D/E — Functional tests: NOT TESTED (no test artifact yet).');
end

% milestones
add('\n## C — Milestones');
if exist(miles, 'dir')
    d = dir(fullfile(miles, '*.slx'));
    if isempty(d)
        add('- None yet.');
    end
    for k = 1:numel(d)
        add('- %s (%d bytes)', d(k).name, d(k).bytes);
    end
else
    add('- None yet.');
end

% H/I/J/K/L honest defaults
add('\n## H–L — Open items');
add('- H (unconnected required ports): see audit artifact; stages 2–6 models intentionally document pending-integration boundary ports per rule M until stage 8–9 wiring.');
add('- I (dangling lines): must be zero per audit; a nonzero audit is a build-stopping failure by construction.');
add('- J (warnings/errors): compile diagnostics are captured in the audit artifact.');
add('- K (known limitations): sandbox has no MATLAB; every MATLAB-executed check here is NOT TESTED until run on the user''s R2026a installation.');
add('- L (next task): run `sv16_api_check`, then `sv16_build_all`, then stages 7–9 per Architecture docs.');

fid = fopen(fullfile(verif, 'session_report.md'), 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
fprintf('sv16_report: wrote %s\n', fullfile(verif, 'session_report.md'));

    function add(fmt, varargin)
        lines{end+1} = sprintf(fmt, varargin{:}); %#ok<AGROW>
    end
end
