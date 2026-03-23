#!/usr/bin/env python3
"""
RV64I Assembler — converts RV64I assembly to hex for $readmemh.
Phase 1: Integer instructions only.

Usage: python asm2hex.py input.s output.hex
"""

import sys
import re

# Register ABI names -> numbers
REG_MAP = {f'x{i}': i for i in range(32)}
REG_MAP.update({
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    'fp': 8, 's0': 8, 's1': 9,
    't0': 5, 't1': 6, 't2': 7,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22, 's7': 23,
    's8': 24, 's9': 25, 's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31,
})

# FP register names -> numbers
FP_REG_MAP = {f'f{i}': i for i in range(32)}
FP_REG_MAP.update({
    'ft0': 0, 'ft1': 1, 'ft2': 2, 'ft3': 3, 'ft4': 4, 'ft5': 5, 'ft6': 6, 'ft7': 7,
    'fs0': 8, 'fs1': 9,
    'fa0': 10, 'fa1': 11, 'fa2': 12, 'fa3': 13, 'fa4': 14, 'fa5': 15,
    'fa6': 16, 'fa7': 17,
    'fs2': 18, 'fs3': 19, 'fs4': 20, 'fs5': 21, 'fs6': 22, 'fs7': 23,
    'fs8': 24, 'fs9': 25, 'fs10': 26, 'fs11': 27,
    'ft8': 28, 'ft9': 29, 'ft10': 30, 'ft11': 31,
})

# Rounding mode names
RM_MAP = {
    'rne': 0b000, 'rtz': 0b001, 'rdn': 0b010, 'rup': 0b011,
    'rmm': 0b100, 'dyn': 0b111,
}


def reg(name):
    name = name.strip().lower()
    if name not in REG_MAP:
        raise ValueError(f"Unknown register: {name}")
    return REG_MAP[name]


def fpreg(name):
    """Parse an FP register name, return register number."""
    name = name.strip().lower()
    if name not in FP_REG_MAP:
        raise ValueError(f"Unknown FP register: {name}")
    return FP_REG_MAP[name]


def parse_rm(s):
    """Parse an optional rounding mode string. Default is DYN (0b111)."""
    s = s.strip().lower()
    if s in RM_MAP:
        return RM_MAP[s]
    raise ValueError(f"Unknown rounding mode: {s}")


def parse_imm(s):
    """Parse an immediate value (decimal or hex)."""
    s = s.strip()
    if s.startswith('0x') or s.startswith('0X'):
        return int(s, 16)
    elif s.startswith('-0x') or s.startswith('-0X'):
        return -int(s[1:], 16)
    else:
        return int(s)


def sext(value, bits):
    """Sign extend a value to `bits` width, return as signed Python int."""
    mask = (1 << bits) - 1
    value &= mask
    if value & (1 << (bits - 1)):
        value -= (1 << bits)
    return value


def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i(imm, rs1, funct3, rd, opcode):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(imm, rs2, rs1, funct3, opcode):
    imm12 = imm & 0xFFF
    imm_11_5 = (imm12 >> 5) & 0x7F
    imm_4_0 = imm12 & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode


def encode_b(imm, rs2, rs1, funct3, opcode):
    imm13 = imm & 0x1FFF
    bit12 = (imm13 >> 12) & 1
    bit11 = (imm13 >> 11) & 1
    bits10_5 = (imm13 >> 5) & 0x3F
    bits4_1 = (imm13 >> 1) & 0xF
    return (bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | opcode


def encode_u(imm, rd, opcode):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | opcode


def encode_j(imm, rd, opcode):
    imm21 = imm & 0x1FFFFF
    bit20 = (imm21 >> 20) & 1
    bits10_1 = (imm21 >> 1) & 0x3FF
    bit11 = (imm21 >> 11) & 1
    bits19_12 = (imm21 >> 12) & 0xFF
    return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | (rd << 7) | opcode


def parse_mem_operand(s):
    """Parse 'offset(reg)' -> (imm, reg_num)"""
    m = re.match(r'\s*(-?\w+)\s*\(\s*(\w+)\s*\)', s)
    if not m:
        raise ValueError(f"Bad memory operand: {s}")
    return parse_imm(m.group(1)), reg(m.group(2))


def encode_r4(rs3, funct2, rs2, rs1, rm, rd, opcode):
    """R4-type encoding for FMA instructions."""
    return (rs3 << 27) | (funct2 << 25) | (rs2 << 20) | (rs1 << 15) | (rm << 12) | (rd << 7) | opcode


def assemble(lines):
    """Two-pass assembler. Returns list of 32-bit integers."""
    # Pass 1: collect labels, strip comments
    labels = {}
    cleaned = []
    pc = 0
    for line in lines:
        # Strip comments
        line = line.split('#')[0].strip()
        if not line:
            continue
        # Check for label
        if ':' in line:
            parts = line.split(':', 1)
            label = parts[0].strip()
            labels[label] = pc
            rest = parts[1].strip()
            if not rest:
                continue
            line = rest
        cleaned.append((pc, line))
        pc += 4

    # Pass 2: encode
    code = []
    for pc, line in cleaned:
        # Tokenize
        parts = re.split(r'[,\s]+', line.strip(), maxsplit=1)
        mnemonic = parts[0].upper()
        operands = parts[1] if len(parts) > 1 else ''

        instr = assemble_instruction(mnemonic, operands, pc, labels)
        code.append(instr)

    return code


def assemble_instruction(mnemonic, operands, pc, labels):
    """Assemble a single instruction, return 32-bit int."""

    def ops():
        """Split operands by comma, stripping whitespace."""
        return [x.strip() for x in operands.split(',')]

    # === NOP ===
    if mnemonic == 'NOP':
        return encode_i(0, 0, 0, 0, 0x13)  # addi x0, x0, 0

    # === R-type (RV64I) ===
    r_type = {
        'ADD':  (0x00, 0x0), 'SUB':  (0x20, 0x0), 'SLL':  (0x00, 0x1),
        'SLT':  (0x00, 0x2), 'SLTU': (0x00, 0x3), 'XOR':  (0x00, 0x4),
        'SRL':  (0x00, 0x5), 'SRA':  (0x20, 0x5), 'OR':   (0x00, 0x6),
        'AND':  (0x00, 0x7),
    }
    if mnemonic in r_type:
        f7, f3 = r_type[mnemonic]
        o = ops()
        return encode_r(f7, reg(o[2]), reg(o[1]), f3, reg(o[0]), 0x33)

    # === R-type W (RV64I word ops) ===
    rw_type = {
        'ADDW': (0x00, 0x0), 'SUBW': (0x20, 0x0), 'SLLW': (0x00, 0x1),
        'SRLW': (0x00, 0x5), 'SRAW': (0x20, 0x5),
    }
    if mnemonic in rw_type:
        f7, f3 = rw_type[mnemonic]
        o = ops()
        return encode_r(f7, reg(o[2]), reg(o[1]), f3, reg(o[0]), 0x3B)

    # === I-type ALU ===
    i_type = {
        'ADDI': 0x0, 'SLTI': 0x2, 'SLTIU': 0x3,
        'XORI': 0x4, 'ORI':  0x6, 'ANDI':  0x7,
    }
    if mnemonic in i_type:
        f3 = i_type[mnemonic]
        o = ops()
        imm = parse_imm(o[2])
        return encode_i(imm, reg(o[1]), f3, reg(o[0]), 0x13)

    # === I-type ALU W ===
    if mnemonic == 'ADDIW':
        o = ops()
        imm = parse_imm(o[2])
        return encode_i(imm, reg(o[1]), 0x0, reg(o[0]), 0x1B)

    # === Shift immediate (special I-type, 6-bit shamt for RV64) ===
    shift_imm = {
        'SLLI': (0x00, 0x1), 'SRLI': (0x00, 0x5), 'SRAI': (0x10, 0x5),
    }
    if mnemonic in shift_imm:
        f6, f3 = shift_imm[mnemonic]
        o = ops()
        shamt = parse_imm(o[2]) & 0x3F
        imm12 = (f6 << 6) | shamt
        return encode_i(imm12, reg(o[1]), f3, reg(o[0]), 0x13)

    # === Shift immediate W (5-bit shamt) ===
    shift_imm_w = {
        'SLLIW': (0x00, 0x1), 'SRLIW': (0x00, 0x5), 'SRAIW': (0x20, 0x5),
    }
    if mnemonic in shift_imm_w:
        f7, f3 = shift_imm_w[mnemonic]
        o = ops()
        shamt = parse_imm(o[2]) & 0x1F
        imm12 = (f7 << 5) | shamt
        return encode_i(imm12, reg(o[1]), f3, reg(o[0]), 0x1B)

    # === Load instructions ===
    load_map = {
        'LB': 0x0, 'LH': 0x1, 'LW': 0x2, 'LD': 0x3,
        'LBU': 0x4, 'LHU': 0x5, 'LWU': 0x6,
    }
    if mnemonic in load_map:
        f3 = load_map[mnemonic]
        o = ops()
        imm, rs1 = parse_mem_operand(o[1])
        return encode_i(imm, rs1, f3, reg(o[0]), 0x03)

    # === Store instructions ===
    store_map = {
        'SB': 0x0, 'SH': 0x1, 'SW': 0x2, 'SD': 0x3,
    }
    if mnemonic in store_map:
        f3 = store_map[mnemonic]
        o = ops()
        imm, rs1 = parse_mem_operand(o[1])
        return encode_s(imm, reg(o[0]), rs1, f3, 0x23)

    # === LUI ===
    if mnemonic == 'LUI':
        o = ops()
        imm = parse_imm(o[1])
        return encode_u(imm, reg(o[0]), 0x37)

    # === AUIPC ===
    if mnemonic == 'AUIPC':
        o = ops()
        imm = parse_imm(o[1])
        return encode_u(imm, reg(o[0]), 0x17)

    # === JAL ===
    if mnemonic == 'JAL':
        o = ops()
        rd_val = reg(o[0])
        target = o[1].strip()
        if target in labels:
            offset = labels[target] - pc
        else:
            offset = parse_imm(target)
        return encode_j(offset, rd_val, 0x6F)

    # === JALR ===
    if mnemonic == 'JALR':
        o = ops()
        if len(o) == 3:
            rd_val = reg(o[0])
            rs1_val = reg(o[1])
            imm = parse_imm(o[2])
        elif '(' in operands:
            # jalr rd, offset(rs1)
            rd_val = reg(o[0])
            imm, rs1_val = parse_mem_operand(o[1])
        else:
            # jalr rs1  (rd=ra, imm=0)
            rd_val = 1
            rs1_val = reg(o[0])
            imm = 0
        return encode_i(imm, rs1_val, 0x0, rd_val, 0x67)

    # === Branch instructions ===
    branch_map = {
        'BEQ': 0x0, 'BNE': 0x1, 'BLT': 0x4, 'BGE': 0x5,
        'BLTU': 0x6, 'BGEU': 0x7,
    }
    if mnemonic in branch_map:
        f3 = branch_map[mnemonic]
        o = ops()
        rs1_val = reg(o[0])
        rs2_val = reg(o[1])
        target = o[2].strip()
        if target in labels:
            offset = labels[target] - pc
        else:
            offset = parse_imm(target)
        return encode_b(offset, rs2_val, rs1_val, f3, 0x63)

    # === FP Load (FLD) ===
    if mnemonic == 'FLD':
        o = ops()
        rd_val = fpreg(o[0])
        imm, rs1_val = parse_mem_operand(o[1])
        return encode_i(imm, rs1_val, 0x3, rd_val, 0x07)

    # === FP Store (FSD) ===
    if mnemonic == 'FSD':
        o = ops()
        rs2_val = fpreg(o[0])
        imm, rs1_val = parse_mem_operand(o[1])
        return encode_s(imm, rs2_val, rs1_val, 0x3, 0x27)

    # === FP R-type arithmetic (2-source, opcode=0x53) ===
    # Format: MNEMONIC fd, fs1, fs2[, rm]
    fp_arith_2src = {
        # mnemonic: (funct7, funct3_default_or_None)
        # funct3=None means use rm field
        'FADD.D':  (0b0000001, None),
        'FSUB.D':  (0b0000101, None),
        'FMUL.D':  (0b0001001, None),
        'FDIV.D':  (0b0001101, None),
    }
    if mnemonic in fp_arith_2src:
        f7, f3_fixed = fp_arith_2src[mnemonic]
        o = ops()
        rd_val = fpreg(o[0])
        rs1_val = fpreg(o[1])
        rs2_val = fpreg(o[2])
        if f3_fixed is not None:
            rm_val = f3_fixed
        elif len(o) > 3:
            rm_val = parse_rm(o[3])
        else:
            rm_val = 0b111  # DYN
        return encode_r(f7, rs2_val, rs1_val, rm_val, rd_val, 0x53)

    # === FSQRT.D fd, fs1[, rm] ===
    if mnemonic == 'FSQRT.D':
        o = ops()
        rd_val = fpreg(o[0])
        rs1_val = fpreg(o[1])
        rm_val = parse_rm(o[2]) if len(o) > 2 else 0b111
        return encode_r(0b0101101, 0, rs1_val, rm_val, rd_val, 0x53)

    # === FP sign-inject (FSGNJ.D, FSGNJN.D, FSGNJX.D) ===
    fp_sgnj = {
        'FSGNJ.D':  0b000,
        'FSGNJN.D': 0b001,
        'FSGNJX.D': 0b010,
    }
    if mnemonic in fp_sgnj:
        f3 = fp_sgnj[mnemonic]
        o = ops()
        return encode_r(0b0010001, fpreg(o[2]), fpreg(o[1]), f3, fpreg(o[0]), 0x53)

    # === FMIN.D, FMAX.D ===
    fp_minmax = {'FMIN.D': 0b000, 'FMAX.D': 0b001}
    if mnemonic in fp_minmax:
        f3 = fp_minmax[mnemonic]
        o = ops()
        return encode_r(0b0010101, fpreg(o[2]), fpreg(o[1]), f3, fpreg(o[0]), 0x53)

    # === FP compare: FEQ.D, FLT.D, FLE.D — result to integer rd ===
    fp_cmp = {'FEQ.D': 0b010, 'FLT.D': 0b001, 'FLE.D': 0b000}
    if mnemonic in fp_cmp:
        f3 = fp_cmp[mnemonic]
        o = ops()
        return encode_r(0b1010001, fpreg(o[2]), fpreg(o[1]), f3, reg(o[0]), 0x53)

    # === FCVT.W.D, FCVT.WU.D, FCVT.L.D, FCVT.LU.D — FP to int ===
    fp_cvt_f2i = {
        'FCVT.W.D':  0b00000,
        'FCVT.WU.D': 0b00001,
        'FCVT.L.D':  0b00010,
        'FCVT.LU.D': 0b00011,
    }
    if mnemonic in fp_cvt_f2i:
        rs2_enc = fp_cvt_f2i[mnemonic]
        o = ops()
        rd_val = reg(o[0])       # integer rd
        rs1_val = fpreg(o[1])    # FP rs1
        rm_val = parse_rm(o[2]) if len(o) > 2 else 0b111
        return encode_r(0b1100001, rs2_enc, rs1_val, rm_val, rd_val, 0x53)

    # === FCVT.D.W, FCVT.D.WU, FCVT.D.L, FCVT.D.LU — int to FP ===
    fp_cvt_i2f = {
        'FCVT.D.W':  0b00000,
        'FCVT.D.WU': 0b00001,
        'FCVT.D.L':  0b00010,
        'FCVT.D.LU': 0b00011,
    }
    if mnemonic in fp_cvt_i2f:
        rs2_enc = fp_cvt_i2f[mnemonic]
        o = ops()
        rd_val = fpreg(o[0])    # FP rd
        rs1_val = reg(o[1])     # integer rs1
        rm_val = parse_rm(o[2]) if len(o) > 2 else 0b111
        return encode_r(0b1101001, rs2_enc, rs1_val, rm_val, rd_val, 0x53)

    # === FMV.X.D — FP to integer (bitwise move) ===
    if mnemonic == 'FMV.X.D':
        o = ops()
        return encode_r(0b1110001, 0, fpreg(o[1]), 0b000, reg(o[0]), 0x53)

    # === FMV.D.X — integer to FP (bitwise move) ===
    if mnemonic == 'FMV.D.X':
        o = ops()
        return encode_r(0b1111001, 0, reg(o[1]), 0b000, fpreg(o[0]), 0x53)

    # === FCLASS.D ===
    if mnemonic == 'FCLASS.D':
        o = ops()
        return encode_r(0b1110001, 0, fpreg(o[1]), 0b001, reg(o[0]), 0x53)

    # === FMA instructions (R4-type) ===
    fp_fma = {
        'FMADD.D':  0b1000011,
        'FMSUB.D':  0b1000111,
        'FNMSUB.D': 0b1001011,
        'FNMADD.D': 0b1001111,
    }
    if mnemonic in fp_fma:
        opcode_val = fp_fma[mnemonic]
        o = ops()
        rd_val = fpreg(o[0])
        rs1_val = fpreg(o[1])
        rs2_val = fpreg(o[2])
        rs3_val = fpreg(o[3])
        rm_val = parse_rm(o[4]) if len(o) > 4 else 0b111
        return encode_r4(rs3_val, 0b01, rs2_val, rs1_val, rm_val, rd_val, opcode_val)

    raise ValueError(f"Unknown instruction: {mnemonic} {operands}")


def main():
    if len(sys.argv) < 3:
        print("Usage: python asm2hex.py input.s output.hex")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    with open(input_file, 'r') as f:
        lines = f.readlines()

    code = assemble(lines)

    with open(output_file, 'w') as f:
        for word in code:
            f.write(f'{word & 0xFFFFFFFF:08x}\n')

    print(f"Assembled {len(code)} instructions -> {output_file}")


if __name__ == '__main__':
    main()
