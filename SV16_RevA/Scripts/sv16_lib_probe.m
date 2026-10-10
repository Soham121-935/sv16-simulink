function p = sv16_lib_probe()
%SV16_LIB_PROBE Verify the installed MATLAB/Simulink supports every block the
%SV-16 Rev A builders use -- BEFORE any model is built (master prompt section 11).
%
%   p = sv16_lib_probe()   throws if anything required is missing.
%
% Checks: Simulink license, MATLAB release string, and concrete add_block
% instantiation of every library path used by the SV-16 builders. A block
% that cannot be instantiated in THIS release is reported by exact path.

p = struct();
p.release = version('-release');
p.ok = false;
p.items = {};

if license('test', 'Simulink') ~= 1
    error('SV16:probe:license', 'Simulink license is not available in this MATLAB session.');
end

% Scratch model used purely to instantiate each library block once.
scratch = ['sv16_probe_scratch_' datestr(now,'HHMMSSFFF')]; %#ok<DTDATELOOSE>
new_system(scratch);
closeOk = onCleanup(@() close_system(scratch, 0));

blocks = {
    'simulink/Sources/Constant'                     'CONSTANT'
    'simulink/Sources/In1'                          'INPORT'
    'simulink/Sinks/Out1'                           'OUTPORT'
    'simulink/Sources/Pulse Generator'              'PULSEGEN'
    'simulink/Sources/Digital Clock'                'DIGCLOCK'
    'simulink/Signal Routing/Multiport Switch'      'MPORTSW'
    'simulink/Signal Routing/Switch'                'SWITCH'
    'simulink/Signal Routing/Mux'                   'MUX'
    'simulink/Signal Routing/Demux'                 'DEMUX'
    'simulink/Discrete/Unit Delay'                  'UNITDELAY'
    'simulink/Math Operations/Sum'                  'SUM'
    'simulink/Math Operations/Product'              'PRODUCT'
    'simulink/Math Operations/Divide'               'DIVIDE'
    'simulink/Math Operations/Gain'                 'GAIN'
    'simulink/Math Operations/MinMax'               'MINMAX'
    'simulink/Logic and Bit Operations/Logical Operator'      'LOGIC'
    'simulink/Logic and Bit Operations/Bitwise Operator'      'BITWISE'
    'simulink/Logic and Bit Operations/Compare To Constant'   'CMPCONST'
    'simulink/Logic and Bit Operations/Shift Arithmetic'      'SHIFT'
    'simulink/Signal Attributes/Data Type Conversion'         'DTC'
    'simulink/User-Defined Functions/MATLAB Function'         'MLFB'
    'simulink/Sinks/To Workspace'                   'TOWS'
    'simulink/Sources/From Workspace'               'FROMWS'
    'simulink/Sinks/Terminator'                     'TERM'
    'simulink/Sources/Ground'                       'GROUND'
    'simulink/Sinks/Display'                        'DISPLAY'
    };

allOk = true;
for k = 1:size(blocks, 1)
    libPath = blocks{k,1};
    tag     = blocks{k,2};
    item = struct('tag',tag, 'libPath',libPath, 'exists',false, 'error','');
    try
        h = add_block(libPath, [scratch '/' tag '_1'], 'MakeNameUnique','on');
        if h <= 0
            error('add_block returned an invalid handle');
        end
        item.exists = true;
    catch err
        item.error = err.message;
        allOk = false;
    end
    p.items{end+1} = item; %#ok<AGROW>
end

fprintf('sv16_lib_probe -- MATLAB %s, Simulink license OK\n', p.release);
for k = 1:numel(p.items)
    it = p.items{k};
    if it.exists
        fprintf('  [ OK ] %-9s %s\n', it.tag, it.libPath);
    else
        fprintf('  [MISS] %-9s %s  (%s)\n', it.tag, it.libPath, it.error);
    end
end

if ~allOk
    error('SV16:probe:missingBlocks', ...
        'One or more required Simulink library blocks are unavailable in %s. See table above.', p.release);
end
p.ok = true;
end
