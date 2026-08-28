import os
import re
import subprocess

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly
from cocotb.queue import Queue
from cocotb.clock import Clock

HERE = os.path.dirname(os.path.abspath(__file__))
ASM_DIR = os.path.join(HERE, "asm")
BUILD_DIR = os.path.join(HERE, "build")

def to_signed(val):
    val = 0xFFFFFFFF & val
    return val - 0x100000000 if (val & 0x80000000) else val


def parse_imm(text):
    """decimal or 0x/0b prefixed immediate, with an optional sign"""
    return int(text.strip(), 0)


def sig_int(handle):
    """unsigned int view of a signal, None when it holds x/z. a vector comes back
       as a LogicArray but a 1 bit signal comes back as a scalar Logic, and the
       two share no accessor beyond int(), which is unsigned on both"""
    try:
        return int(handle.value)
    except ValueError:
        return None


def read_image(file_name):
    """raw little endian image, i.e what objcopy -O binary produces"""
    with open(file_name, "rb") as file:
        image = file.read()
    #a trailing partial word can only come from a truncated image
    assert len(image) % 4 == 0, f"{file_name} is not a whole number of words"
    return [int.from_bytes(image[i:i+4], "little") for i in range(0, len(image), 4)]


def write_mem_file(words, path):
    """$readmemb format: one word of binary digits per line. inst_mem reads this
       at time 0 and the array is overwritten by load_memories straight after, so
       in simulation it only keeps iverilog from reporting a missing file. it is
       the real init path for synthesis, which has no testbench to write the array"""
    with open(path, "w") as file:
        for word in words:
            file.write(f"{word:032b}\n")


def load_memories(dut, words):
    imem = dut.IMEM.mem #depth of instruction memory
    depth = len(imem)
    assert len(words) <= depth, f"program is {len(words)} words, imem holds {depth}"

    #zero fill past the end of the program.
    for i in range(depth):
        imem[i].value = words[i] if i < len(words) else 0


class Golden_Model:
    def __init__(self, settings, pc_queue, reg_queue):
        self.register_file = [0]*32
        self.instrs = []
        self.parsed_instrs = []
        self.pc = 0
        self.steps = []
        self.mem = []
        self.label_dic = {}
        self.data_mem = {}
        self.settings = settings
        self.pc_queue = pc_queue
        self.reg_queue = reg_queue
        self.retired = 0

    def decode_instr(self, instr, instr_idx):
        """
            desc: decodes an instruction based on the opcode, similar to what
                  instruction decode does
        """
        r_type_instr = ["add","sub","and","or","xor","sll","srl","sra","slt","sltu"]
        i_type_4_instr = ["addi","andi","ori","xori","slti","sltiu","slli","srli","srai"]
        i_type_3_instr = ["lb","lbu","lh","lhu","lw"]
        i_type_2_instr = ["jalr"]
        s_type_instr = ["sb","sh","sw"]
        b_type_instr = ["beq","bne","blt","bltu","bge","bgeu"]
        j_type_instr = ["jal"]
        u_type_instr = ["auipc","lui"]

        label_dic = self.label_dic

        instr_imm_value = 0   #raw immediate
        instr_r1_index = 0
        instr_r2_index = 0
        instr_rd_index = 0
        instr_b_offset = 0
        instr_j_offset = 0
        instr_class = "nop"
        instr_wrong = False
        instr_stop = False

        opcode = "nop"
        first_op = "rd"
        split_instr = instr.strip().split(",")
        if instr.strip():
            first_section = split_instr[0].strip().split()
            opcode = first_section[0]
            first_op = first_section[1] if (len(first_section) > 1) else "rd"
        match opcode:
            case x if x in r_type_instr:
                instr_class ="r_type"
                if(len(split_instr) != 3):
                    instr_wrong = True
                else:
                    instr_imm_value = 0
                    rs1 = split_instr[1].strip()
                    rs2 = split_instr[2].strip()
                    instr_r1_index = int(rs1[1:])
                    instr_r2_index = int(rs2[1:])
                    instr_rd_index = int(first_op[1:])

            case x if x in i_type_4_instr:
                instr_class = "i_type_4"
                if(len(split_instr) != 3):
                    instr_wrong = True
                else:
                    instr_r2_index = 0
                    rs1 = split_instr[1].strip()
                    imm = split_instr[2].strip()
                    instr_imm_value = parse_imm(imm)
                    instr_r1_index = int(rs1[1:])
                    instr_rd_index = int(first_op[1:])

            case x if x in b_type_instr:
                instr_class = "b_type"
                if(len(split_instr) != 3):
                    instr_wrong = True
                else:
                    label = split_instr[2].strip()
                    label_index = label_dic.get(label)
                    if(label_index is None):
                        instr_wrong = True
                    else:
                        instr_b_offset = label_index - (instr_idx*4)
                        rs2 = split_instr[1].strip()
                        instr_r2_index = int(rs2[1:])
                        instr_r1_index = int(first_op[1:])

            case x if x in j_type_instr:
                instr_class = "j_type"
                if(len(split_instr) != 2):
                    instr_wrong = True
                else:
                    label = split_instr[1].strip()
                    label_index = label_dic.get(label)
                    if(label_index is None):
                        instr_wrong =  True
                    else:
                        instr_j_offset = label_index - (instr_idx*4)
                        instr_rd_index = int(first_op[1:])

            case x if x in i_type_2_instr:
                instr_class = "i_type_2"
                #both forms an assembler takes: "jalr rd, rs1, imm" and "jalr rd, imm(rs1)"
                if(len(split_instr) == 3):
                    instr_rd_index = int(first_op[1:])
                    rs1 = split_instr[1].strip()
                    instr_r1_index = int(rs1[1:])
                    instr_imm_value = parse_imm(split_instr[2])
                elif(len(split_instr) == 2):
                    instr_rd_index = int(first_op[1:])
                    offset = re.split(r"[()]",split_instr[1].strip())
                    if(len(offset) < 2):
                        instr_wrong = True
                    else:
                        instr_imm_value = parse_imm(offset[0])
                        instr_r1_index = int(offset[1].strip()[1:])
                else:
                    instr_wrong = True

            case x if x in s_type_instr:
                instr_class = "s_type"
                if(len(split_instr) != 2):
                    instr_wrong = True
                else:
                    instr_r2_index = int(first_op[1:])
                    offset = re.split(r"[()]",split_instr[1].strip())
                    if(len(offset) < 2):
                        instr_wrong = True
                    else:
                        instr_imm_value = parse_imm(offset[0])
                        instr_r1_index = int(offset[1].strip()[1:])

            case x if x in i_type_3_instr:
                instr_class = "i_type_3"
                if(len(split_instr) != 2):
                    instr_wrong = True
                else:
                    instr_rd_index = int(first_op[1:])
                    offset = re.split(r"[()]",split_instr[1].strip())
                    if(len(offset) < 2):
                        instr_wrong = True
                    else:
                        instr_imm_value = parse_imm(offset[0])
                        instr_r1_index = int(offset[1].strip()[1:])

            case x if x in u_type_instr:
                instr_class = "u_type"
                if(len(split_instr) != 2):
                    instr_wrong = True
                else:
                    instr_rd_index = int(first_op[1:])
                    imm = split_instr[1]
                    instr_imm_value = parse_imm(imm)

            case "nop":
                #the assembler expands this to addi x0, x0, 0, so it retires
                #like any other instruction and still writes nothing
                instr_class = "nop_type"

            case "ebreak":
                #end of program marker, execution stops here
                instr_class = "stop"
                instr_stop = True

            case _:
                instr_wrong = True

        parsed_instr = (opcode,instr_class, instr_imm_value,instr_r1_index,instr_r2_index,\
                        instr_rd_index, instr_b_offset, instr_j_offset, instr_wrong,\
                        instr_stop)
        return parsed_instr



    def load_asm(self, file_name):
        """every line kept here has to assemble to exactly one word, otherwise the
           golden's instruction index stops matching the image fed to imem"""
        with open(file_name) as file:
            for raw in file:
                line = raw.split("#")[0].strip()
                if not line:
                    continue
                #a label may sit on its own line or in front of an instruction
                while ":" in line:
                    label, _, line = line.partition(":")
                    self.label_dic[label.strip()] = len(self.instrs)*4
                    line = line.strip()
                if not line:
                    continue
                #assembler directives emit no instruction word
                if line.startswith("."):
                    continue
                self.instrs.append(line)


    def parse_asm(self):
        for i in range(len(self.instrs)):
            parsed_instr = self.decode_instr(self.instrs[i],i)
            self.parsed_instrs.append(parsed_instr)

    def load_mem(self, addr, size):
        """data_mem is byte addressed, so a wide access is assembled here"""
        mem = self.data_mem
        val = 0
        for i in range(size):
            val |= mem.get(0xFFFFFFFF & (addr + i), 0) << (8*i)
        return val

    def store_mem(self, addr, val, size):
        mem = self.data_mem
        for i in range(size):
            mem[0xFFFFFFFF & (addr + i)] = (val >> (8*i)) & 0xFF

    def exec_instr(self):
        r = self.register_file
        pc_queue = self.pc_queue
        reg_queue = self.reg_queue
        while True:
            pc = self.pc
            if(pc//4 >= len(self.parsed_instrs)):
                break
            instr = self.parsed_instrs[pc//4]
            opcode, instr_class, instr_imm_value,instr_r1_index,instr_r2_index,\
            instr_rd_index, instr_b_offset, \
            instr_j_offset, instr_wrong, instr_stop = instr

            #ebreak marks the end of the program
            if instr_stop:
                break

            #a line the golden cannot decode still assembles, so the dut would
            #retire it and every later comparison would be off by one
            if instr_wrong:
                raise ValueError(f"golden cannot decode instruction {pc//4} "
                                 f"at pc {pc:#x}: '{self.instrs[pc//4]}'")

            #the register file holds unsigned words, so signed views are taken here
            u_r1 = r[instr_r1_index]
            u_r2 = r[instr_r2_index]
            r1 = to_signed(u_r1)
            r2 = to_signed(u_r2)
            res = r[instr_rd_index]
            u_imm = 0xFFFFFFFF & instr_imm_value
            b_pc = pc + 4
            addr = 0xFFFFFFFF & (r1 + instr_imm_value)

            match(opcode):
                case "add":
                    res = r1 + r2
                case "sub":
                    res = r1 - r2
                case "and":
                    res = r1 & r2
                case "or":
                    res = r1 | r2
                case "xor":
                    res = r1 ^ r2
                case "sll":
                    res = u_r1 << (u_r2 & 0x1F)
                case "srl":
                    res = u_r1 >> (u_r2 & 0x1F)
                case "sra":
                    res = r1 >> (u_r2 & 0x1F)
                case "slt":
                    res = 1 if (r1 < r2) else 0
                case "sltu":
                    res = 1 if (u_r1 < u_r2) else 0
                case "addi":
                    res = r1 + instr_imm_value
                case "andi":
                    res = r1 & instr_imm_value
                case "ori":
                    res = r1 | instr_imm_value
                case "xori":
                    res = r1 ^ instr_imm_value
                case "slti":
                    res = 1 if (r1 < instr_imm_value) else 0
                case "sltiu":
                    res = 1 if (u_r1 < u_imm) else 0
                case "slli":
                    res = u_r1 << (instr_imm_value & 0x1F)
                case "srli":
                    res = u_r1 >> (instr_imm_value & 0x1F)
                case "srai":
                    res = r1 >> (instr_imm_value & 0x1F)
                case "beq":
                    b_pc = pc + instr_b_offset if (r1 == r2) else b_pc
                case "bne":
                    b_pc = pc + instr_b_offset if (r1 != r2) else b_pc
                case "blt":
                    b_pc = pc + instr_b_offset if (r1 < r2) else b_pc
                case "bltu":
                    b_pc = pc + instr_b_offset if (u_r1 < u_r2) else b_pc
                case "bge":
                    b_pc = pc + instr_b_offset if (r1 >= r2) else b_pc
                case "bgeu":
                    b_pc = pc + instr_b_offset if (u_r1 >= u_r2) else b_pc
                case "jal":
                    res = pc + 4
                case "jalr":
                    res = pc + 4
                case "auipc":
                    res = pc + (instr_imm_value << 12)
                case "lui":
                    res = instr_imm_value << 12
                case "sw":
                    self.store_mem(addr, u_r2, 4)
                case "sh":
                    self.store_mem(addr, u_r2, 2)
                case "sb":
                    self.store_mem(addr, u_r2, 1)
                case "lb":
                    val = self.load_mem(addr, 1)
                    res = (val - 0x100) if (val & 0x80) else val
                case "lbu":
                    res = self.load_mem(addr, 1)
                case "lh":
                    val = self.load_mem(addr, 2)
                    res = (val - 0x10000) if (val & 0x8000) else val
                case "lhu":
                    res = self.load_mem(addr, 2)
                case "lw":
                    res = self.load_mem(addr, 4)


            if instr_class == "b_type":
                self.pc = 0xFFFFFFFF & b_pc
            elif instr_class == "j_type":
                self.pc = 0xFFFFFFFF & (pc + instr_j_offset)
            elif instr_class == "i_type_2":
                self.pc = 0xFFFFFFFE & (r1 + instr_imm_value)
            else:
                self.pc = 0xFFFFFFFF & (pc + 4)

            #writes to x0 are discarded
            if instr_rd_index:
                r[instr_rd_index] = 0xFFFFFFFF & res

            #capture register and pc state as of this instruction retiring. the
            #pc recorded is the instruction's own, which is what the dut carries
            #down to writeback
            reg_queue.put_nowait(r.copy())
            pc_queue.put_nowait(pc)
            self.retired += 1


    def _run(self,asm_filename):
        self.load_asm(asm_filename)
        self.parse_asm()
        self.exec_instr()
        return self.retired




class Monitor:
    def __init__(self,dut,dut_pc_queue, dut_reg_queue):
        self.dut = dut
        self.dut_pc_queue = dut_pc_queue
        self.dut_reg_queue = dut_reg_queue
        self._coro = cocotb.start_soon(self._run())

    async def _run(self):
        dut = self.dut
        dut_pc_queue = self.dut_pc_queue
        dut_reg_queue = self.dut_reg_queue
        #capture dut state at writeback
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            instr_valid = sig_int(dut.wb_instr_valid)
            if instr_valid:
                #record pc state
                pc = sig_int(dut.wb_pc)
                await FallingEdge(dut.clk) #writes are on falling edge
                await ReadOnly()           #and land in the nba region of it
                #probe dut register file state after possible write back
                r_snap = [0]*32
                for i in range(32):
                    r_snap[i] = sig_int(dut.REG_FILE.file[i])
                dut_pc_queue.put_nowait(pc)
                dut_reg_queue.put_nowait(r_snap)


class Settings:
    def __init__(self,bin_filename,asm_filename, obj_filename):
        self.bin_filename = bin_filename
        self.asm_filename = asm_filename
        self.obj_filename = obj_filename

class Scoreboard:
    def __init__(self,dut_reg_queue, dut_pc_queue, golden_reg_queue, golden_pc_queue):
        self.dut_reg_queue = dut_reg_queue
        self.dut_pc_queue = dut_pc_queue
        self.golden_reg_queue = golden_reg_queue
        self.golden_pc_queue = golden_pc_queue
        self.transactions_checked = 0
        self.error = 0
        self._coro = cocotb.start_soon(self._run())

    @staticmethod
    def _hex(val):
        return "xxxxxxxx" if val is None else format(val, "#010x")

    def _diff(self, golden_reg, dut_reg):
        """only the registers that disagree, so the log stays readable"""
        return " | ".join(f"x{i}: exp {self._hex(g)} got {self._hex(d)}"
                          for i, (g, d) in enumerate(zip(golden_reg, dut_reg)) if g != d)

    async def _run(self):
        dut_reg_queue = self.dut_reg_queue
        dut_pc_queue = self.dut_pc_queue
        golden_reg_queue = self.golden_reg_queue
        golden_pc_queue = self.golden_pc_queue
        while True:
            dut_pc = await dut_pc_queue.get()
            golden_pc = await golden_pc_queue.get()
            dut_reg = await dut_reg_queue.get()
            golden_reg = await golden_reg_queue.get()

            #compare
            if dut_pc != golden_pc or golden_reg != dut_reg:
                cocotb.log.error(f"""\n\nTransaction {self.transactions_checked}!\n
                --- Expected (Golden): ---\npc:{self._hex(golden_pc)}\n
                --- Got from Silicon: ---\npc:{self._hex(dut_pc)}\n
                --- Register diff: ---\n{self._diff(golden_reg, dut_reg)}\n """
                )
                self.error += 1
            else:
                cocotb.log.info(f"Transaction {self.transactions_checked} passed. "
                                f"pc:{self._hex(golden_pc)}")

            self.transactions_checked += 1


async def reset_dut(dut, cycles=4):
    dut.reset.value = 1
    dut.io_data_out.value = 0
    dut.io_ack.value = 0
    for _ in range(cycles):
        await FallingEdge(dut.clk)
    dut.reset.value = 0


def assemble(settings):
    os.makedirs(os.path.dirname(settings.obj_filename), exist_ok=True)
    subprocess.run(["riscv64-unknown-elf-as",
                    "-march=rv32i",
                    "-mabi=ilp32",
                    settings.asm_filename,
                    "-o",
                    settings.obj_filename]
                    ,check=True)

    subprocess.run([
    "riscv64-unknown-elf-objcopy",
    "-O", "binary",
    settings.obj_filename,
    settings.bin_filename
        ], check=True)


async def setup(dut, settings):
    golden_pc_queue = Queue()
    golden_reg_queue = Queue()
    dut_pc_queue = Queue()
    dut_reg_queue = Queue()
    assemble(settings)
    #golden runs full program first 
    golden_model = Golden_Model(settings, golden_pc_queue, golden_reg_queue)
    expected = golden_model._run(settings.asm_filename)
    assert expected, f"{settings.asm_filename} retired no instructions"
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    words = read_image(settings.bin_filename)
    #padded to the full rom depth so $readmemb has no gap to warn about. the pad is nop
    depth = len(dut.IMEM.mem)
    write_mem_file(words + [0]*(depth - len(words)),
                   os.path.join(BUILD_DIR, "test.mem"))
    load_memories(dut, words)
    monitor = Monitor(dut, dut_pc_queue, dut_reg_queue)
    scoreboard = Scoreboard(dut_reg_queue, dut_pc_queue, golden_reg_queue, golden_pc_queue)
    await reset_dut(dut)
    return scoreboard, expected


async def finish(dut, sb, expected):
    t = 0
    while sb.transactions_checked < expected:
        await RisingEdge(dut.clk)
        t += 1
        assert t < 200_000, f"timeout: {sb.transactions_checked}/{expected} instructions checked"
    print(f"report: retired={sb.transactions_checked} errors={sb.error}")
    assert sb.error == 0, f"{sb.error} mismatches"


@cocotb.test()
async def test_r_type(dut):
    settings = Settings(
        asm_filename=os.path.join(ASM_DIR, "r_type.s"),
        obj_filename=os.path.join(BUILD_DIR, "r_type.o"),
        bin_filename=os.path.join(BUILD_DIR, "r_type.bin"),
    )
    scoreboard, expected = await setup(dut, settings)
    await finish(dut, scoreboard, expected)
