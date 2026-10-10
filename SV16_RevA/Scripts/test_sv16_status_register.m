function res = test_sv16_status_register()
%TEST_SV16_STATUS_REGISTER Stage 6 tests (TC-SR-01..03).
% Independent reference: four 1-bit enable flops with sync reset, identical
% documented semantics to the register primitive (write visible t+1).

N = 24;
Zin = zeros(N,1); Nin = zeros(N,1); Cin = zeros(N,1); Vin = zeros(N,1);
SW  = zeros(N,1); RST = false(N,1);

RST(1:2) = true;
SW(3)=1; Zin(3)=1; Cin(3)=1;             % Z=1 C=1 from tick 4
SW(4)=0; Zin(4)=1; Nin(4)=1;             % TC-SR-03: no strobe -> hold (Z stays 1, N ignored)
SW(5)=1; Nin(5)=1; Zin(5)=0;             % N=1, Z=0 from tick 6
SW(6)=1; Vin(6)=1;                        % V=1 from tick 7
SW(7)=0; SW(8)=0;                         % hold across idle
SW(9)=1; Zin(9)=1; Nin(9)=1; Cin(9)=1; Vin(9)=1;  % all set tick 10
SW(10)=1;                                 % all inputs 0 -> all clear tick 11
RST(13:14)=true;                          % TC-SR-01: reset -> zeros
SW(15)=1; Zin(15)=1;                      % write again tick 16

inSpecs = sv16_sr_specs(Zin, Nin, Cin, Vin, SW, RST);
dutMaker = @mkSrDUT;
r = sv16_make_harness('status_register', inSpecs, {'Z','N','C','V'}, dutMaker, N);

Zl = zeros(N,1); Nl = Zl; Cl = Zl; Vl = Zl; z=0; n=0; c=0; v=0;
for k = 1:N
    if RST(k)
        z=0;n=0;c=0;v=0;
    else
        if SW(k)
            z=Zin(k); n=Nin(k); c=Cin(k); v=Vin(k);
        end
    end
    Zl(k)=z; Nl(k)=n; Cl(k)=c; Vl(k)=v;
end

tc01 = all(r.out.Z(RST(:))==0) && all(r.out.N(RST(:))==0) && ...
       all(r.out.C(RST(:))==0) && all(r.out.V(RST(:))==0) && ...
       all(r.out.Z(15:16)==0);
tc02 = r.out.Z(4)==1 && r.out.C(4)==1;                       % strobed write lands
tc03 = r.out.Z(5)==1 && r.out.N(5)==0 && r.out.Z(8)==1 && r.out.N(8)==1; % hold
tcall = isequal(logical(r.out.Z(:)), logical(Zl)) && ...
        isequal(logical(r.out.N(:)), logical(Nl)) && ...
        isequal(logical(r.out.C(:)), logical(Cl)) && ...
        isequal(logical(r.out.V(:)), logical(Vl));

res = struct();
res.name = 'STATUS_REGISTER';
res.cases = {
    'TC-SR-01', 'reset clears all flags',        tc01
    'TC-SR-02', 'update only on SRWrite',        tc02
    'TC-SR-03', 'hold across non-update cycles', tc03
    'TC-SR-04', 'full stream vs reference',      tcall
    };
res.passed = all([tc01 tc02 tc03 tcall]);
end

function dut = mkSrDUT(mdl)
p = [mdl '/DUTaux'];
add_block('built-in/Subsystem', p);
dut = sv16_build_status_register(mdl, p);
end

function specs = sv16_sr_specs(Zin, Nin, Cin, Vin, SW, RST)
names = {'Zin','Nin','Cin','Vin','SRWrite','RST'};
data = {Zin, Nin, Cin, Vin, SW, RST};
specs = struct('name',{},'dtype',{},'data',{});
for k = 1:6
    specs(k).name = names{k};
    specs(k).dtype = 'boolean';
    specs(k).data = data{k};
end
end
