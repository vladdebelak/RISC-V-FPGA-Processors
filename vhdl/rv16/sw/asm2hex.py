#!/usr/bin/env python3
"""
Simple RV32I subset assembler.
Reads an assembly file and outputs a hex file compatible with Verilog $readmemh.

Usage: python asm2hex.py input.s output.hex

Supported instructions: ADD, SUB, AND, OR, XOR, ADDI, LW, SW, LUI, JAL, BEQ, BNE, NOP
"""

import sys
import re

# Register name mapping
REG_MAP = {f"x{i}": i for i in range(32)}
REG_MAP["zero"] = 0

def parse_reg(s):
    """Parse a register name and return its number."""
    s = s.strip().lower()
    if s in REG_MAP:
        return REG_MAP[s]
    raise ValueError(f"Unknown register: {s}")

def imm_bits(value, bits):
    """Convert a signed integer to an unsigned value with the given bit width."""
    mask = (1 << bits) - 1
    return value & mask

def encode_r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_i_type(imm12, rs1, funct3, rd, opcode):
    imm = imm_bits(imm12, 12)
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s_type(imm12, rs2, rs1, funct3, opcode):
    imm = imm_bits(imm12, 12)
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode

def encode_b_type(imm13, rs2, rs1, funct3, opcode):
    """imm13 is the signed byte offset (must be even). Bit 0 is always 0."""
    imm = imm_bits(imm13, 13)
    bit12   = (imm >> 12) & 1
    bit10_5 = (imm >> 5) & 0x3F
    bit4_1  = (imm >> 1) & 0xF
    bit11   = (imm >> 11) & 1
    imm_hi = (bit12 << 6) | bit10_5
    imm_lo = (bit4_1 << 1) | bit11
    return (imm_hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_lo << 7) | opcode

def encode_u_type(imm20, rd, opcode):
    """imm20 is the upper 20 bits (already shifted by caller or raw value)."""
    imm = imm_bits(imm20, 20)
    return (imm << 12) | (rd << 7) | opcode

def encode_j_type(imm21, rd, opcode):
    """imm21 is the signed byte offset (must be even). Bit 0 is always 0."""
    imm = imm_bits(imm21, 21)
    bit20    = (imm >> 20) & 1
    bit10_1  = (imm >> 1) & 0x3FF
    bit11    = (imm >> 11) & 1
    bit19_12 = (imm >> 12) & 0xFF
    imm_field = (bit20 << 19) | (bit10_1 << 9) | (bit11 << 8) | bit19_12
    return (imm_field << 12) | (rd << 7) | opcode

def parse_mem_operand(s):
    """Parse 'offset(reg)' and return (offset, reg_num)."""
    m = re.match(r'\s*(-?\d+)\s*\(\s*(\w+)\s*\)', s)
    if not m:
        raise ValueError(f"Bad memory operand: {s}")
    return int(m.group(1)), parse_reg(m.group(2))

def assemble(lines):
    """Two-pass assembler. Returns list of 32-bit integers."""
    # --- Pass 1: collect labels ---
    labels = {}
    pc = 0  # byte address
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
            line = parts[1].strip()
            if not line:
                continue
        # This line is an instruction, advance PC
        pc += 4

    # --- Pass 2: encode instructions ---
    instructions = []
    pc = 0
    for line in lines:
        line = line.split('#')[0].strip()
        if not line:
            continue
        # Strip label
        if ':' in line:
            line = line.split(':', 1)[1].strip()
            if not line:
                continue

        # Tokenize
        # Replace commas with spaces, then split
        tokens = line.replace(',', ' ').split()
        mnemonic = tokens[0].upper()

        if mnemonic == 'NOP':
            instructions.append(0x00000013)

        elif mnemonic == 'ADD':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            rs2 = parse_reg(tokens[3])
            instructions.append(encode_r_type(0b0000000, rs2, rs1, 0b000, rd, 0b0110011))

        elif mnemonic == 'SUB':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            rs2 = parse_reg(tokens[3])
            instructions.append(encode_r_type(0b0100000, rs2, rs1, 0b000, rd, 0b0110011))

        elif mnemonic == 'AND':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            rs2 = parse_reg(tokens[3])
            instructions.append(encode_r_type(0b0000000, rs2, rs1, 0b111, rd, 0b0110011))

        elif mnemonic == 'OR':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            rs2 = parse_reg(tokens[3])
            instructions.append(encode_r_type(0b0000000, rs2, rs1, 0b110, rd, 0b0110011))

        elif mnemonic == 'XOR':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            rs2 = parse_reg(tokens[3])
            instructions.append(encode_r_type(0b0000000, rs2, rs1, 0b100, rd, 0b0110011))

        elif mnemonic == 'ADDI':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            imm = int(tokens[3])
            instructions.append(encode_i_type(imm, rs1, 0b000, rd, 0b0010011))

        elif mnemonic == 'LW':
            rd = parse_reg(tokens[1])
            offset, rs1 = parse_mem_operand(' '.join(tokens[2:]))
            instructions.append(encode_i_type(offset, rs1, 0b010, rd, 0b0000011))

        elif mnemonic == 'SW':
            rs2 = parse_reg(tokens[1])
            offset, rs1 = parse_mem_operand(' '.join(tokens[2:]))
            instructions.append(encode_s_type(offset, rs2, rs1, 0b010, 0b0100011))

        elif mnemonic == 'LUI':
            rd = parse_reg(tokens[1])
            imm = int(tokens[2])
            instructions.append(encode_u_type(imm, rd, 0b0110111))

        elif mnemonic == 'BEQ':
            rs1 = parse_reg(tokens[1])
            rs2 = parse_reg(tokens[2])
            target = tokens[3]
            if target in labels:
                offset = labels[target] - pc
            else:
                offset = int(target)
            instructions.append(encode_b_type(offset, rs2, rs1, 0b000, 0b1100011))

        elif mnemonic == 'BNE':
            rs1 = parse_reg(tokens[1])
            rs2 = parse_reg(tokens[2])
            target = tokens[3]
            if target in labels:
                offset = labels[target] - pc
            else:
                offset = int(target)
            instructions.append(encode_b_type(offset, rs2, rs1, 0b001, 0b1100011))

        elif mnemonic == 'JAL':
            rd = parse_reg(tokens[1])
            target = tokens[2]
            if target in labels:
                offset = labels[target] - pc
            else:
                offset = int(target)
            instructions.append(encode_j_type(offset, rd, 0b1101111))

        else:
            raise ValueError(f"Unknown instruction: {mnemonic} at PC=0x{pc:04X}")

        pc += 4

    return instructions

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.s output.hex", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    with open(input_file, 'r') as f:
        lines = f.readlines()

    instructions = assemble(lines)

    with open(output_file, 'w') as f:
        for instr in instructions:
            f.write(f"{instr:08X}\n")

    print(f"Assembled {len(instructions)} instructions -> {output_file}")

if __name__ == '__main__':
    main()
