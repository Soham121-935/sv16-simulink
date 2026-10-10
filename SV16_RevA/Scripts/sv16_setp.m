function sv16_setp(block, nameCandidates, value)
%SV16_SETP Set a Simulink block parameter trying several documented names.
%   sv16_setp(blk, {'Operator','bitwiseOperator'}, 'AND')
%
% The Rev A rules forbid assuming API behavior. This helper tries each
% candidate parameter name and fails LOUDLY naming the block and every
% candidate when none works, so an R2026a API rename can never silently
% produce a misconfigured model.

ok = false;
lastErr = '';
for k = 1:numel(nameCandidates)
    try
        set_param(block, nameCandidates{k}, value);
        ok = true;
        return
    catch err
        lastErr = err.message;
    end
end
if ~ok
    error('SV16:setp:failed', ...
        ['Could not set parameter on block "%s".\nTried: %s\nLast error: %s\n' ...
         'Run sv16_lib_probe to identify the parameter name in this ' ...
         'MATLAB release and update the candidate list.'], ...
        block, strjoin(nameCandidates, ', '), lastErr);
end
end
