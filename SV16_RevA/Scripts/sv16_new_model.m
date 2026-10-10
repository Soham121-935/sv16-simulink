function mdl = sv16_new_model()
%SV16_NEW_MODEL Create the clean SV-16 Rev A Simulink model from scratch.
%
%   mdl = sv16_new_model()
%
% Creates SV16_RevA/Simulink/SV16_RevA.slx with fixed-step discrete solver
% at isa.Ts. Subsystems are added by their stage builders in order
% (see sv16_build_all). Never copies anything from the legacy SV16.slx.

isa = sv16_isa();
mdl = 'SV16_RevA';

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
modelDir = fullfile(root, 'SV16_RevA', 'Simulink');
if ~exist(modelDir, 'dir'), mkdir(modelDir); end
modelFile = fullfile(modelDir, [mdl '.slx']);

if bdIsLoaded(mdl)
    close_system(mdl, 0);
end

new_system(mdl);
set_param(mdl, ...
    'SolverType',   'Fixed-step', ...
    'Solver',       'FixedStepDiscrete', ...
    'FixedStep',    num2str(isa.Ts), ...
    'StopTime',     num2str(20 * isa.Ts), ...
    'SaveFormat',   'slx');

save_system(mdl, modelFile);
fprintf('sv16_new_model: created %s (Ts=%g)\n', modelFile, isa.Ts);
end
