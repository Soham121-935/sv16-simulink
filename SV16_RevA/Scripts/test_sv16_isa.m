function res = test_sv16_isa()
%TEST_SV16_ISA Stage 1 test: assembler/decoder self-consistency vs the
%documented encodings in Architecture/instruction_set.md (which were
%independently verified). Pure MATLAB -- no Simulink model required.

% Documented encoding examples
w1 = sv16_isa('asm', {'ADD R3, R1, R2'});
w2 = sv16_isa('asm', {'LDI R1, 5'});
w3 = sv16_isa('asm', {'BEQ R1, R2, 12'});
w4 = sv16_isa('asm', {'JMP 0x40'});
w5 = sv16_isa('asm', {'HALT'});

tc01 = isequal(w1, uint32(hex2dec('23280000')));
tc02 = isequal(w2, uint32(hex2dec('09000005')));
tc03 = isequal(w3, uint32(hex2dec('A0050003')));
tc04 = isequal(w4, uint32(hex2dec('C0000010')));
tc05 = isequal(w5, uint32(hex2dec('F8000000')));

% Decode round-trip on every defined opcode with nontrivial fields
isa = sv16_isa();
names = fieldnames(isa.op);
tc06 = true;
rng(7); %#ok<RNGOK> % deterministic samples
for k = 1:numel(names)
    nm = names{k};
    switch true
        case any(strcmp(isa.class.R, nm)) && ~strcmp(nm,'NOP')
            [a, b, c] = deal(randi([0 7]), randi([0 7]), randi([0 7]));
            w = sv16_isa('asm', {sprintf('%s R%d, R%d, R%d', nm, a, b, c)});
        case any(strcmp(isa.class.I, nm))
            a = randi([0 7]); bb = randi([0 7]); v = randi([0 hex2dec('FFFF')]);
            if any(strcmp({'LDI','LDIS'}, nm))
                w = sv16_isa('asm', {sprintf('%s R%d, %d', nm, a, v)});
            else
                w = sv16_isa('asm', {sprintf('%s R%d, R%d, %d', nm, a, bb, v)});
            end
        case any(strcmp(isa.class.B, nm))
            a = randi([0 7]); bb = randi([0 7]); v = 4*randi([1 1000]);
            w = sv16_isa('asm', {sprintf('%s R%d, R%d, %d', nm, a, bb, v)});
        case any(strcmp(isa.class.J, nm))
            v = 4*randi([0 1000]);
            w = sv16_isa('asm', {sprintf('%s %d', nm, v)});
        otherwise % NOP / HALT
            w = sv16_isa('asm', {nm});
    end
    s = sv16_isa('decode', w(1));
    if uint32(isa.op.(nm)) ~= s.op, tc06 = false; end
end

% Builtin programs assemble and are nontrivial
tc07 = all(arrayfun(@(p) numel(sv16_isa('prog', p)) >= 4, ...
    {'ADDTEN','LOADSTORE','LOOPDOWN','ILLEGAL'}));

% Illegal-instruction vector is reserved opcode 0x1D
p = sv16_isa('prog', 'ILLEGAL');
tc08 = bitshift(p(2), -27) == hex2dec('1D');

res = struct();
res.name = 'ISA_ASSEMBLER';
res.cases = {
    'TC-ISA-01', 'documented encodings (5)', tc01 && tc02 && tc03 && tc04 && tc05
    'TC-ISA-02', 'decode round-trip all opcodes', tc06
    'TC-ISA-03', 'builtin programs assemble', tc07
    'TC-ISA-04', 'reserved opcode vector', tc08
    };
res.passed = tc01 && tc02 && tc03 && tc04 && tc05 && tc06 && tc07 && tc08;
end
