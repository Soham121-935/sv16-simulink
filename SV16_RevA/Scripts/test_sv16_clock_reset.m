function res = test_sv16_clock_reset()
%TEST_SV16_CLOCK_RESET Stage 2 tests (TC-CR-01..03).
% Expected values computed independently below -- never from the DUT.

isa = sv16_isa();
N = 12;
dutMaker = @(mdl) sv16_build_clock_reset(mdl);
r = sv16_make_harness('clock_reset', struct(), {'CLK','RST'}, dutMaker, N);

expRst = [ones(isa.resetCycles,1); zeros(N-isa.resetCycles,1)] > 0;

% TC-CR-01: reset asserted exactly the first resetCycles cycles
tc01 = isequal(logical(r.out.RST(:)), expRst);

% TC-CR-02: clock is a strict square wave with period 2 samples (either phase)
clk = logical(r.out.CLK(:));
tc02 = true;
for k = 3:N
    if clk(k) == clk(k-2)
        tc02 = false;  % period must be exactly 2 -> value flips every sample
    end
end
duty = mean(clk);
tc02 = tc02 && abs(duty - 0.5) <= 1/N;

% TC-CR-03: nothing floats -- audit responsibility; signal sanity here
tc03 = all(isfinite(r.out.CLK)) && all(isfinite(r.out.RST));

res = struct();
res.name = 'CLOCK_RESET';
res.cases = {
    'TC-CR-01', 'reset window 2 cycles', tc01
    'TC-CR-02', 'clock period/duty',     tc02
    'TC-CR-03', 'signal sanity',         tc03
    };
res.passed = tc01 && tc02 && tc03;
end
