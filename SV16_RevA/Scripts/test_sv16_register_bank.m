function res = test_sv16_register_bank()
%TEST_SV16_REGISTER_BANK Stage 3 tests (TC-RF-01..08).
% A scripted 40-cycle operation stream drives all eight registers; expected
% RD1/RD2 come from the independent reference model below (old-value read
% semantics per register_map.md). Covers reset, per-address write decode,
% dual-port reads, hold, boundary values, overwrite, same-cycle read/write,
% and mid-run reset.

N = 40;
ops = zeros(N, 10);  % [RA(3) RB(3) WA(3) WE]
wd  = zeros(N, 1);
rst = false(N, 1);

% helper closure-ish: fill rows manually for clarity
% --- cycle 0..1: reset asserted ---
rst(1:2) = true;
% --- TC-RF-01 reads during reset ---
ops(1,1:10) = [0 0 0 7 7 7 0 0 0 0];
ops(2,1:10) = [3 3 3 5 5 5 0 0 0 0];
% --- TC-RF-07 write cycle: WA=1 WD=0x1234, read RA=1 same cycle (old value) ---
ops(3,1:10) = [1 1 1 0 0 0 1 0 0 1]; wd(3) = hex2dec('1234');
% --- value visible now; TC-RF-02 start: write each register ---
ops(4,1:10) = [1 1 1 1 1 1 2 0 0 1]; wd(4) = hex2dec('FFFF');   % boundary value
ops(5,1:10) = [2 2 2 1 1 1 3 0 0 1]; wd(5) = hex2dec('0F0F');
ops(6,1:10) = [3 3 3 2 2 2 4 0 0 1]; wd(6) = hex2dec('8000');
ops(7,1:10) = [4 4 4 3 3 3 5 0 0 1]; wd(7) = hex2dec('7FFF');
ops(8,1:10) = [5 5 5 4 4 4 6 0 0 1]; wd(8) = hex2dec('0000');   % boundary zero
ops(9,1:10) = [6 6 6 5 5 5 7 0 0 1]; wd(9) = hex2dec('C3C3');
ops(10,1:10)= [7 7 7 6 6 6 0 0 0 1]; wd(10)= hex2dec('3C3C');
% --- TC-RF-03 read every register on both ports ---
for i = 0:7
    row = 11 + i;
    ops(row,1:10) = [i i i mod(i+3,8) mod(i+3,8) mod(i+3,8) 0 0 0 0];
end
% --- TC-RF-04 hold: WE=0 while address/data active ---
ops(19,1:10) = [3 3 3 4 4 4 4 0 0 0]; wd(19) = hex2dec('5555');
% --- TC-RF-06 overwrite: same address twice ---
ops(20,1:10) = [4 4 4 0 0 0 4 0 0 1]; wd(20) = hex2dec('1111');
ops(21,1:10) = [4 4 4 0 0 0 4 0 0 1]; wd(21) = hex2dec('2222');
% --- TC-RF-05 second boundary sweep on reg 6 ---
ops(22,1:10) = [6 6 6 0 0 0 6 0 0 1]; wd(22) = hex2dec('0000');
% --- TC-RF-08 mid-run reset ---
rst(24:25) = true;
ops(24,1:10) = [2 2 2 2 2 2 2 0 0 1]; wd(24) = hex2dec('9999');
ops(25,1:10) = [2 2 2 2 2 2 2 0 0 0];
% --- post-reset reads ---
ops(26,1:10) = [4 4 4 4 4 4 0 0 0 0];
ops(27,1:10) = [1 1 1 6 6 6 0 0 0 0];

inSpecs = sv16_regbank_specs(ops, wd, rst);
dutMaker = @mkRegBankDUT;
r = sv16_make_harness('register_bank', inSpecs, {'RD1','RD2'}, dutMaker, N);

% --- Independent reference model -------------------------------------------
R = zeros(1,8);  % MATLAB-side shadow of the architectural registers
exp1 = zeros(N,1); exp2 = zeros(N,1);
for n = 1:N
    ra = ops(n,1)*1 + ops(n,2)*2 + ops(n,3)*4;
    rb = ops(n,4)*1 + ops(n,5)*2 + ops(n,6)*4;
    wa = ops(n,7)*1 + ops(n,8)*2 + ops(n,9)*4;
    we = ops(n,10) > 0;
    if rst(n)
        exp1(n) = 0; exp2(n) = 0;
    else
        exp1(n) = R(ra+1);
        exp2(n) = R(rb+1);
        if we
            R(wa+1) = wd(n);
        end
    end
end

tc01 = all(r.out.RD2(rst(:)) == 0) && all(r.out.RD1(rst(:)) == 0);
tc03 = isequal(r.out.RD1(11:18), exp1(11:18)) && isequal(r.out.RD2(11:18), exp2(11:18));
tc04 = r.out.RD1(19) == exp1(19) && r.out.RD1(20) == exp1(20) ...
    && r.out.RD1(20) == hex2dec('8000');            % held: 0x5555 write ignored
tc05 = r.out.RD1(5) == hex2dec('FFFF') && r.out.RD1(9) == 0;
tc06 = r.out.RD1(21) == hex2dec('1111') && r.out.RD1(22) == hex2dec('2222');
tc07 = r.out.RD1(3) == 0;                            % same-cycle read = old value
tc08 = r.out.RD1(26) == 0 && r.out.RD1(27) == 0 && r.out.RD2(27) == 0;

tc02 = isequal(r.out.RD1(:), exp1) && isequal(r.out.RD2(:), exp2); % full-stream decode check

res = struct();
res.name = 'REGISTER_BANK';
res.cases = {
    'TC-RF-01', 'reset state zeros',                 tc01
    'TC-RF-02', 'write-enable decode all addresses', tc02
    'TC-RF-03', 'dual-port reads correct',           tc03
    'TC-RF-04', 'hold without WE',                   tc04
    'TC-RF-05', 'boundary values 0x0000/0xFFFF',     tc05
    'TC-RF-06', 'overwrite last-wins',               tc06
    'TC-RF-07', 'same-cycle read returns old value', tc07
    'TC-RF-08', 'mid-run reset re-zeroes',           tc08
    };
res.passed = all([tc01 tc02 tc03 tc04 tc05 tc06 tc07 tc08]);
end

% ---------------------------------------------------------------------------
function dut = mkRegBankDUT(mdl)
% Parent subsystem created first, then the real stage-3 builder fills it.
p = [mdl '/DUTaux'];
add_block('built-in/Subsystem', p);
dut = sv16_build_register_bank(mdl, p);
end

function specs = sv16_regbank_specs(ops, wd, rst)
names = {'RA0','RA1','RA2','RB0','RB1','RB2','WA0','WA1','WA2','RegWrite','WD','RST'};
cols  = {1,2,3,4,5,6,7,8,9,10,[],[]};
vals  = zeros(40,12);
for k = 1:10
    vals(:,k) = ops(:,k);
end
vals(:,11) = wd; vals(:,12) = double(rst);
dtypes = {'uint8','uint8','uint8','uint8','uint8','uint8','uint8','uint8','uint8','boolean','uint16','boolean'};
specs = struct('name',{},'dtype',{},'data',{});
for k = 1:12
    specs(k).name = names{k};
    specs(k).dtype = dtypes{k};
    specs(k).data = vals(:,k);
end
end
