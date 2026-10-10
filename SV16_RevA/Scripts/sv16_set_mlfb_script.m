function sv16_set_mlfb_script(blkPath, code)
%SV16_SET_MLFB_SCRIPT Set the source of a MATLAB Function block programmatically.
%   sv16_set_mlfb_script('<model>/X/Y', 'function z = f(x) ... ')
%
% Tries the documented MATLABFunctionConfiguration interface first, then the
% Stateflow.EMChart interface. Fails loudly if neither works in this release.

try
    cfg = get_param(blkPath, 'MATLABFunctionConfiguration');
    cfg.FunctionScript = code;
    return
catch
    % fall through to the Stateflow API
end

try
    rt = sfroot;
    ch = rt.find('-isa', 'Stateflow.EMChart', 'Path', blkPath);
    if isempty(ch)
        error('SV16:mlfb:nochart', 'No EMChart found for %s', blkPath);
    end
    ch.Script = code;
    return
catch err
    error('SV16:mlfb:script', ...
        ['Could not set MATLAB Function script on %s in this release.\n' ...
         'Run sv16_api_check / sv16_lib_probe and record the working API ' ...
         'in the decision log. Underlying error: %s'], blkPath, err.message);
end
end
