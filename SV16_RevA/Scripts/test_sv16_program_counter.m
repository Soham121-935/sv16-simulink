function res = test_sv16_program_counter()
%TEST_SV16_PROGRAM_COUNTER Stage 4 tests (TC-PC-01..07).
% Independent reference: simple PC state machine mirroring the spec
% (reset -> 0, EN-gated update, PCSrc selects +4 / branch / jump / register).

N = 26;
EN   = zeros(N,1); SEL = zeros(N,1);
BT   = zeros(N,1); JT = zeros(N,1); RS = zeros(N,1);
RST  = false(N,1);

RST(1:2) = true;                       % TC-PC-01
EN(3)=1;                                % TC-PC-02: +4 increments
EN(4)=1; EN(5)=1;                       % -> 4, 8, 12
EN(6)=0;                                % TC-PC-03: hold at 12
EN(7)=1; SEL(7)=1; BT(7)=100;           % TC-PC-04: branch target load
EN(8)=1; SEL(8)=2; JT(8)=hex2dec('40'); % TC-PC-05a: jump target
EN(9)=1; SEL(9)=3; RS(9)=hex2dec('12345678'); % TC-PC-05b/06: register + width
EN(10)=0;                               % hold large value
RST(12:13)=true;                        % TC-PC-07: re-reset from large value
EN(14)=1;                               % back to sequential 4, 8
EN(15)=1;

inSpecs = sv16_pc_specs(EN, SEL, BT, JT, RS, RST);
dutMaker = @mkPcDUT;
r = sv16_make_harness('program_counter', inSpecs, {'PC'}, dutMaker, N);

% --- Reference model --------------------------------------------------------
pc = uint32(0); expPC = zeros(N,1);
for n = 1:N
    if RST(n)
        expPC(n) = 0;
    else
        expPC(n) = double(pc);
        if EN(n) == 1
            switch SEL(n)
                case 0, pc = pc + 4;
                case 1, pc = uint32(BT(n));
                case 2, pc = uint32(JT(n));
                case 3, pc = uint32(RS(n));
            end
        end
    end
end

obs = r.out.PC(:);
tc01 = obs(1:2) == [0;0];
tc02 = isequal(obs(3:5), expPC(3:5)) && obs(5) == 12;
tc03 = obs(6) == 12;
tc04 = obs(7) == 100;
tc05 = obs(8) == hex2dec('40') && obs(9) == hex2dec('12345678');
tc06 = obs(10) == hex2dec('12345678');             % >= 2^16 preserved
tc07 = all(obs(12:13) == 0) && obs(14) == 0 && isequal(obs(14:15), expPC(14:15));
tcall = isequal(obs, expPC);

res = struct();
res.name = 'PROGRAM_COUNTER';
res.cases = {
    'TC-PC-01', 'reset value 0',                 tc01
    'TC-PC-02', 'sequential +4',                 tc02
    'TC-PC-03', 'hold when PCWrite=0',           tc03
    'TC-PC-04', 'branch target load',            tc04
    'TC-PC-05', 'jump/register loads',           tc05
    'TC-PC-06', '32-bit width integrity',        tc06
    'TC-PC-07', 're-reset',                      tc07
    'TC-PC-08', 'full stream vs reference',      tcall
    };
res.passed = all([tc01 tc02 tc03 tc04 tc05 tc06 tc07 tcall]);
end

function dut = mkPcDUT(mdl)
p = [mdl '/DUTaux'];
add_block('built-in/Subsystem', p);
dut = sv16_build_program_counter(mdl, p);
end

function specs = sv16_pc_specs(EN, SEL, BT, JT, RS, RST)
names = {'EN','PCSrc','BrTarget','JumpTarget','RsVal','RST'};
data  = {EN, SEL, BT, JT, RS, RST};
dtypes= {'boolean','uint8','uint32','uint32','uint32','boolean'};
specs = struct('name',{},'dtype',{},'data',{});
for k = 1:6
    specs(k).name = names{k};
    specs(k).dtype = dtypes{k};
    specs(k).data = data{k};
end
end
