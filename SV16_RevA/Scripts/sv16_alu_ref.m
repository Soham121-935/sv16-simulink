function [R, Z, N, C, V] = sv16_alu_ref(A, B, ALUOp)
%SV16_ALU_REF Independent reference model of the SV-16 Rev A ALU.
%
%   [R, Z, N, C, V] = sv16_alu_ref(A, B, ALUOp)
%
% Vectorized pure-MATLAB implementation used ONLY to compute expected
% results for TC-AL-* (never wired into any model). Semantics mirror
% Architecture/instruction_set.md and sv16_isa. Boundary arithmetic uses
% double precision to observe carry/overflow exactly.

sv16_isa();  % explicit linkage to the ISA single source of truth

A = double(A(:)); B = double(B(:)); op = double(ALUOp(:));
n = numel(A);
R = zeros(n,1); C = false(n,1); V = false(n,1);

for i = 1:n
    a = bitand(A(i), 65535); b = bitand(B(i), 65535); o = op(i);
    switch o
        case 0  % ADD
            full = a + b;
            r = bitand(full, 65535);
            c = full > 65535;
            sa = bitget(a,16); sb = bitget(b,16); sr = bitget(r,16);
            v = (sa == sb) && (sr ~= sa);
        case 1  % SUB
            c = a >= b;                 % no-borrow
            r = bitand(a - b, 65535);
            sa = bitget(a,16); sb = bitget(b,16); sr = bitget(r,16);
            v = (sa ~= sb) && (sr ~= sa);
        case 2, r = bitand(a,b);       c = false; v = false;
        case 3, r = bitor(a,b);        c = false; v = false;
        case 4, r = bitxor(a,b);       c = false; v = false;
        case 5, r = bitcmp(a, 'uint16'); r = double(r); c = false; v = false;
        case 6  % SHL
            k = bitand(b, 15);
            if k == 0
                r = a; c = false;
            else
                c = bitget(a, 17 - k);
                r = bitand(bitshift(a, k), 65535);
            end
            v = false;
        case 7  % SHR (logical)
            k = bitand(b, 15);
            if k == 0
                r = a; c = false;
            else
                c = bitget(a, k);
                r = bitshift(a, -k);
            end
            v = false;
        case 8  % MUL (low 16)
            r = bitand(a * b, 65535); c = false; v = false;
        case 9  % DIV unsigned, /0 -> 0xFFFF
            if b == 0
                r = 65535;
            else
                r = floor(a / b);
            end
            c = false; v = false;
        case 10 % INC
            full = a + 1;
            r = bitand(full, 65535);
            c = full > 65535;
            v = (a == 32767);
        case 11 % DEC
            c = a >= 1;
            r = bitand(a - 1, 65535);
            v = (a == 32768);
        otherwise % reserved
            r = 0; c = false; v = false;
    end
    R(i) = r; C(i) = c; V(i) = v;
end

Z = (R == 0);
N = logical(bitget(uint16(R), 16));
end
