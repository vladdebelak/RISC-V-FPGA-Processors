#!/usr/bin/env python3
"""
asm2hex.py — RV64I assembler producing $readmemh hex output.

Supports: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU,
          ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI,
          ADDW, SUBW, SLLW, SRLW, SRAW,
          ADDIW, SLLIW, SRLIW, SRAIW,
          LB, LH, LW, LD, LBU, LHU, LWU,
          SB, SH, SW, SD,
          LUI, AUIPC, JAL, JALR,
          BEQ, BNE, BLT, BGE, BLTU, BGEU,
          NOP

Labels, comments (#), register names x0-x31 and 'zero'.

Usage: python asm2hex.py input.s output.hex
"""

import sys
import re

# ── Register mapping ──────────────────────────────────────────────
REG_MAP = {f"x{i}": i for i in range(32)}
REG_MAP["zero"] = 0
REG_MAP["ra"] = 1
REG_MAP["sp"] = 2
REG_MAP["gp"] = 3
REG_MAP["tp"] = 4
REG_MAP["t0"] = 5
REG_MAP["t1"] = 6
REG_MAP["t2"] = 7
REG_MAP["s0"] = 8
REG_MAP["fp"] = 8
REG_MAP["s1"] = 9
for _i in range(8):
    REG_MAP[f"a{_i}"] = 10 + _i
for _i in range(2, 12):
    REG_MAP[f"s{_i}"] = 18 + (_i - 2)
REG_MAP["t3"] = 28
REG_MAP["t4"] = 29
REG_MAP["t5"] = 30
REG_MAP["t6"] = 31


def reg(name: str) -> int:
    name = name.strip().lower().rstrip(",")
    if name not in REG_MAP:
        raise ValueError(f"Unknown register: {name}")
    return REG_MAP[name]


def imm(tok: str, bits: int, signed: bool = True) -> int:
    """Parse an immediate value, accepting decimal, hex (0x…), and negative."""
    tok = tok.strip().rstrip(",")
    val = int(tok, 0)
    mask = (1 << bits) - 1
    return val & mask


def sext(val: int, bits: int) -> int:
    """Sign-extend a `bits`-wide value to Python int."""
    if val & (1 << (bits - 1)):
        val -= 1 << bits
    return val


# ── Encoding helpers ──────────────────────────────────────────────

def enc_r(opcode, rd, f3, rs1, rs2, f7):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opcode


def enc_i(opcode, rd, f3, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opcode


def enc_s(opcode, f3, rs1, rs2, imm12):
    imm12 &= 0xFFF
    return ((imm12 >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm12 & 0x1F) << 7) | opcode


def enc_b(opcode, f3, rs1, rs2, imm13):
    imm13 &= 0x1FFF
    b12  = (imm13 >> 12) & 1
    b10_5 = (imm13 >> 5) & 0x3F
    b4_1  = (imm13 >> 1) & 0xF
    b11   = (imm13 >> 11) & 1
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode


def enc_u(opcode, rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(opcode, rd, imm21):
    imm21 &= 0x1FFFFF
    b20    = (imm21 >> 20) & 1
    b10_1  = (imm21 >> 1)  & 0x3FF
    b11    = (imm21 >> 11) & 1
    b19_12 = (imm21 >> 12) & 0xFF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | opcode


# ── Assembler ─────────────────────────────────────────────────────

# R-type  {mnemonic: (funct3, funct7, opcode)}
R_TYPE = {
    "add":  (0, 0x00, 0x33), "sub":  (0, 0x20, 0x33),
    "and":  (7, 0x00, 0x33), "or":   (6, 0x00, 0x33), "xor":  (4, 0x00, 0x33),
    "sll":  (1, 0x00, 0x33), "srl":  (5, 0x00, 0x33), "sra":  (5, 0x20, 0x33),
    "slt":  (2, 0x00, 0x33), "sltu": (3, 0x00, 0x33),
    # RV64 W-suffix R-type (opcode 0x3B)
    "addw": (0, 0x00, 0x3B), "subw": (0, 0x20, 0x3B),
    "sllw": (1, 0x00, 0x3B), "srlw": (5, 0x00, 0x3B), "sraw": (5, 0x20, 0x3B),
}

# I-type  {mnemonic: (funct3, opcode)}
I_TYPE = {
    "addi":  (0, 0x13), "andi":  (7, 0x13), "ori":   (6, 0x13), "xori":  (4, 0x13),
    "slti":  (2, 0x13), "sltiu": (3, 0x13),
    # RV64 W-suffix I-type (opcode 0x1B)
    "addiw": (0, 0x1B),
}

# Shift-immediate (I-type with special encoding)
# RV64I: SLLI/SRLI/SRAI have 6-bit shamt, funct6 in [31:26]
SHIFT_IMM = {
    "slli": (1, 0x00, 0x13),  # (funct3, funct6, opcode)
    "srli": (5, 0x00, 0x13),
    "srai": (5, 0x10, 0x13),  # funct6 = 010000
}

# RV64 W-suffix shift-immediate: 5-bit shamt, funct7 in [31:25]
SHIFT_IMM_W = {
    "slliw": (1, 0x00, 0x1B),  # (funct3, funct7, opcode)
    "srliw": (5, 0x00, 0x1B),
    "sraiw": (5, 0x20, 0x1B),  # funct7 = 0100000
}

# Load  {mnemonic: (funct3, opcode)}
LOAD = {
    "lb":  (0, 0x03), "lh":  (1, 0x03), "lw":  (2, 0x03), "ld":  (3, 0x03),
    "lbu": (4, 0x03), "lhu": (5, 0x03), "lwu": (6, 0x03),
}

# Store {mnemonic: (funct3, opcode)}
STORE = {
    "sb": (0, 0x23), "sh": (1, 0x23), "sw": (2, 0x23), "sd": (3, 0x23),
}

# Branch {mnemonic: funct3}
BRANCH = {
    "beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7,
}


def parse_mem_operand(tok: str):
    """Parse 'offset(reg)' → (imm_val, reg_num)."""
    m = re.match(r'(-?\w+)\((\w+)\)', tok.strip())
    if not m:
        raise ValueError(f"Bad memory operand: {tok}")
    return int(m.group(1), 0), reg(m.group(2))


def assemble(lines):
    """Two-pass assembler. Returns list of 32-bit machine words."""
    # Pass 1: collect labels, count addresses
    labels = {}
    clean = []  # (addr, mnemonic, operands_str)
    addr = 0
    for line in lines:
        line = line.split("#")[0].strip()
        if not line:
            continue
        # label?
        if ":" in line:
            parts = line.split(":", 1)
            label = parts[0].strip()
            labels[label] = addr
            line = parts[1].strip()
            if not line:
                continue
        tokens = line.split(None, 1)
        mnemonic = tokens[0].lower()
        operands = tokens[1].strip() if len(tokens) > 1 else ""
        clean.append((addr, mnemonic, operands))
        addr += 4

    # Pass 2: encode
    code = []
    for (pc, mn, ops) in clean:
        parts = [p.strip() for p in ops.split(",")]  if ops else []

        if mn == "nop":
            code.append(enc_i(0x13, 0, 0, 0, 0))  # addi x0, x0, 0

        elif mn in R_TYPE:
            f3, f7, opc = R_TYPE[mn]
            code.append(enc_r(opc, reg(parts[0]), f3, reg(parts[1]), reg(parts[2]), f7))

        elif mn in I_TYPE:
            f3, opc = I_TYPE[mn]
            code.append(enc_i(opc, reg(parts[0]), f3, reg(parts[1]), imm(parts[2], 12)))

        elif mn in SHIFT_IMM:
            f3, f6, opc = SHIFT_IMM[mn]
            shamt = imm(parts[2], 6)
            imm12 = (f6 << 6) | shamt  # funct6 in bits [11:6], shamt in [5:0]
            code.append(enc_i(opc, reg(parts[0]), f3, reg(parts[1]), imm12))

        elif mn in SHIFT_IMM_W:
            f3, f7, opc = SHIFT_IMM_W[mn]
            shamt = imm(parts[2], 5)
            imm12 = (f7 << 5) | shamt  # funct7 in bits [11:5], shamt in [4:0]
            code.append(enc_i(opc, reg(parts[0]), f3, reg(parts[1]), imm12))

        elif mn in LOAD:
            f3, opc = LOAD[mn]
            offset, base = parse_mem_operand(parts[1])
            code.append(enc_i(opc, reg(parts[0]), f3, base, offset & 0xFFF))

        elif mn in STORE:
            f3, opc = STORE[mn]
            offset, base = parse_mem_operand(parts[1])
            code.append(enc_s(opc, f3, base, reg(parts[0]), offset & 0xFFF))

        elif mn == "lui":
            code.append(enc_u(0x37, reg(parts[0]), imm(parts[1], 20)))

        elif mn == "auipc":
            code.append(enc_u(0x17, reg(parts[0]), imm(parts[1], 20)))

        elif mn == "jal":
            target_str = parts[1].strip()
            if target_str in labels:
                offset = labels[target_str] - pc
            else:
                offset = int(target_str, 0)
            code.append(enc_j(0x6F, reg(parts[0]), offset & 0x1FFFFF))

        elif mn == "jalr":
            # jalr rd, offset(rs1)
            offset, base = parse_mem_operand(parts[1])
            code.append(enc_i(0x67, reg(parts[0]), 0, base, offset & 0xFFF))

        elif mn in BRANCH:
            f3 = BRANCH[mn]
            target_str = parts[2].strip()
            if target_str in labels:
                offset = labels[target_str] - pc
            else:
                offset = int(target_str, 0)
            code.append(enc_b(0x63, f3, reg(parts[0]), reg(parts[1]), offset & 0x1FFF))

        else:
            raise ValueError(f"Unknown instruction: {mn}")

    return code


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.s output.hex", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], "r") as f:
        lines = f.readlines()

    code = assemble(lines)

    with open(sys.argv[2], "w") as f:
        for word in code:
            f.write(f"{word:08X}\n")

    print(f"Assembled {len(code)} instructions -> {sys.argv[2]}")


if __name__ == "__main__":
    main()
