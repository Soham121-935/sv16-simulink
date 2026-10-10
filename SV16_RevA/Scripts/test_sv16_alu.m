function res = test_sv16_alu()
%TEST_SV16_ALU Stage 5 tests (TC-AL-01..14). Combinational DUT: output at
% cycle n equals f(input n). Expected values come from sv16_alu_ref, an
% independently written reference model (never from the DUT).

isa = sv16_isa(); %#ok<NASGU>
u16 = @(v) bitand(v, 65535);

% --- Stimulus: every TC covered --------------------------------------------
A = []; B = []; OP = [];
addOp = @(a,b,o) struct('a',{a},'b',{b},'o',{o}); %#ok<NASGU>
% TC-AL-01 ADD
cs = {[5 10 0], [hex2dec('FFF0') hex2dec('0020') 0], [0 0 0], [hex2dec('FFFF') 1 0]};
% TC-AL-02 SUB
cs = [cs, {[10 4 1], [3 5 1], [0 1 1], [hex2dec('8000') 1 1]}];
% TC-AL-03..06 AND/OR/XOR/NOT
cs = [cs, {[hex2dec('0F0F') hex2dec('F0F0') 2], [hex2dec('FFFF') hex2dec('0F0F') 2], ...
           [0 hex2dec('FFFF') 3], [hex2dec('AAAA') hex2dec('5555') 3], ...
           [hex2dec('0F0F') hex2dec('FF00') 4], [hex2dec('AAAA') hex2dec('AAAA') 4], ...
           [hex2dec('8000') 0 5], [0 0 5]}];
% TC-AL-07/08 SHL/SHR k = 0..15 (and k inputs 16, 255 -> clamp to 0)
for k = 0:15
    cs = [cs, {[hex2dec('8001') k 6], [hex2dec('1234') k 7]}]; %#ok<AGROW>
end
cs = [cs, {[hex2dec('8001') 16 6], [hex2dec('8001') 255 7]}];
% TC-AL-09 MUL / TC-AL-10 DIV
cs = [cs, {[300 300 8], [123 456 8], [hex2dec('FFFF') hex2dec('FFFF') 8], ...
           [100 7 9], [7 100 9], [12345 123 9], [5 0 9], [0 3 9]}];
% TC-AL-11/12 INC/DEC
cs = [cs, {[0 0 10], [hex2dec('FFFF') 0 10], [hex2dec('7FFF') 0 10], ...
           [0 0 11], [1 0 11], [hex2dec('8000') 0 11]}];
% TC-AL-13 flag boundaries
cs = [cs, {[hex2dec('7FFF') 1 0], [hex2dec('FFFF') 1 0], [0 0 1], ...
           [hex2dec('8000') hex2dec('8000') 1]}];
% TC-AL-14 reserved ops -> 0
cs = [cs, {[1 2 12], [1 2 15]}];

N = numel(cs);
A = zeros(N,1); B = zeros(N,1); OP = zeros(N,1);
for k = 1:N
    A(k) = cs{k}(1); B(k) = cs{k}(2); OP(k) = cs{k}(3);
end

inSpecs = struct('name',{},'dtype',{},'data',{});
inSpecs(1).name='A';     inSpecs(1).dtype='uint16'; inSpecs(1).data=A;
inSpecs(2).name='B';     inSpecs(2).dtype='uint16'; inSpecs(2).data=B;
inSpecs(3).name='ALUOp'; inSpecs(3).dtype='uint8';  inSpecs(3).data=OP;

dutMaker = @mkAluDUT;
r = sv16_make_harness('alu', inSpecs, {'R','Z','N','C','V'}, dutMaker, N);

% --- Independent expected values --------------------------------------------
[expR, expZ, expN, expC, expV] = sv16_alu_ref(A, B, OP);

tc.R   = isequal(u16(r.out.R(:)), expR);
tc.Z   = isequal(logical(r.out.Z(:)), expZ);
tc.N   = isequal(logical(r.out.N(:)), expN);
tc.C   = isequal(logical(r.out.C(:)), expC);
tc.V   = isequal(logical(r.out.V(:)), expV);

% individual highlights
iADD  = find(OP==0 & A==5 & B==10, 1);
iADDw = find(OP==0 & A==hex2dec('FFF0'), 1);
iADDv = find(OP==0 & A==hex2dec('7FFF'), 1);
iADDc = find(OP==0 & A==hex2dec('FFFF'), 1);
iSUBn = find(OP==1 & A==3, 1);
iSHL  = find(OP==6 & A==hex2dec('8001') & B==1, 1);
iDIV0 = find(OP==9 & A==5 & B==0, 1);
iRES  = find(OP==12, 1);

tc01 = r.out.R(iADD)==15;
tc02 = r.out.R(iADDw)==hex2dec('10') && r.out.R(iSUBn)==hex2dec('FFFE');
tc07 = r.out.R(iSHL)==2 && logical(r.out.C(iSHL))==true;   % 0x8001<<1 -> C=1
tc10 = r.out.R(iDIV0)==hex2dec('FFFF');
tc13 = logical(r.out.V(iADDv))==true && logical(r.out.C(iADDc))==true ...
    && logical(r.out.Z(iADDc))==true && logical(r.out.N(iSUBn))==true;
tc14 = r.out.R(iRES)==0;

res = struct();
res.name = 'ALU';
res.cases = {
    'TC-AL-01', 'ADD normal/wrap',                 tc01 && tc02
    'TC-AL-02', 'SUB normal/borrow',               tc02
    'TC-AL-03', 'AND',                             tc.R
    'TC-AL-04', 'OR',                              tc.R
    'TC-AL-05', 'XOR',                             tc.R
    'TC-AL-06', 'NOT',                             tc.R
    'TC-AL-07', 'SHL 0..15 + clamp + carry',       tc07 && tc.R
    'TC-AL-08', 'SHR 0..15 + clamp + carry',       tc.R
    'TC-AL-09', 'MUL low16',                       tc.R
    'TC-AL-10', 'DIV exact/truncate/div0',         tc10 && tc.R
    'TC-AL-11', 'INC wrap',                        tc.R
    'TC-AL-12', 'DEC wrap',                        tc.R
    'TC-AL-13', 'flag boundaries Z/N/C/V',         tc13 && tc.V && tc.N && tc.C && tc.Z
    'TC-AL-14', 'reserved ops -> 0',               tc14
    };
res.passed = all(structfun(@logical, tc)) && tc01 && tc02 && tc07 && tc10 && tc13 && tc14;
end

function dut = mkAluDUT(mdl)
p = [mdl '/DUTaux'];
add_block('built-in/Subsystem', p);
dut = sv16_build_alu(mdl, p);
end
