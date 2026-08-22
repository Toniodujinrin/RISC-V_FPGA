import numpy as np 
import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Event, ReadOnly
from cocotb.queue import Queue 
from cocotb.clock import Clock
from cocotb.types import LogicArray 

def make_program(rng, settings): 
    program = [] 
    ADDR_WIDTH = settings.addr_width 
    TEST_N = settings.tests 
    DATA_WIDTH = settings.data_width
    random_read_addrs_1 = rng.integers(low=0, high=1<<ADDR_WIDTH, size=TEST_N)
    random_read_addrs_2 = rng.integers(low=0, high=1<<ADDR_WIDTH, size=TEST_N)
    random_write_data = rng.integers(low=-(1 << (DATA_WIDTH-1)), high=(1<<(DATA_WIDTH-1)) , size=TEST_N)
    random_write_addr = rng.integers(low=0, high=1<<ADDR_WIDTH, size=TEST_N)
    random_write_en = rng.integers(low=0, high=2,size=TEST_N)

    for i in range(TEST_N): 
        tr = Transaction_Input(random_read_addrs_1[i],random_read_addrs_2[i],random_write_addr[i],random_write_en[i],random_write_data[i])
        print(tr)
        program.append(tr)
   
    return program


class Transaction_Input: 
    def __init__(self, read_addr_1:int, read_addr_2:int, write_addr:int, write_en:int, write_data:int):
        self.read_addr_1 = int(read_addr_1)
        self.read_addr_2 = int(read_addr_2) 
        self.write_addr = int(write_addr)
        self.write_data = int(write_data)
        self.write_en = int(write_en) 

    def __str__(self): 
        return f"read_addr_1:{self.read_addr_1}, read_addr_2:{self.read_addr_2}, \
                write_addr:{self.write_addr}, write_en:{self.write_en}, write_data:{self.write_data}"


class Transaction_Output: 
    def __init__(self, read_data_1:int, read_data_2:int):
        self.read_data_1 = int(read_data_1)
        self.read_data_2 = int(read_data_2)

    def __eq__(self, value) -> bool:
        return self.read_data_1 == value.read_data_1 and \
               self.read_data_2 == value.read_data_2 
    def __str__(self): 
        return f"read_data_1:{self.read_data_1} read_data_2:{self.read_data_2}"

async def drive_program(dut,settings,program, golden_queue:Queue, start_event):
    golden = Golden_Model(settings.addr_width, settings.data_width)
    start_event.set()
    for i in range(len(program)): 
        tr = program[i]
        await FallingEdge(dut.clk)
        dut.write_en.value = tr.write_en 
        dut.read_addr_1.value = tr.read_addr_1  
        dut.read_addr_2.value = tr.read_addr_2
        dut.write_addr.value =  tr.write_addr
        dut.write_data.value =  tr.write_data

        golden_queue.put_nowait(golden.perform_transaction(tr))
    golden.print_state()


class RF_Monitor: 
    def __init__(self,dut,mon_sb_queue, start_event):
        super().__init__()
        self.dut = dut
        self.queue = mon_sb_queue 
        self.start_event = start_event
        self._coro = cocotb.start_soon(self._run())

    async def _run(self):
        await self.start_event.wait()
        while True:
            # sample mid-cycle, before the write edge. read_data is combinational
            # and always@(*) is sensitive to the whole file array, so sampling in
            # ReadOnly after the rising edge would show this cycle's write -- which
            # is not what a pipeline register latching read_data at that edge sees.
            await FallingEdge(self.dut.clk)
            await ReadOnly() 
            tr = Transaction_Output(int(self.dut.read_data_1.value.signed_integer), int(self.dut.read_data_2.value.signed_integer))              
            self.queue.put_nowait(tr)



class RF_Scoreboard:
    def __init__(self,golden_queue, mon_sb_queue):
        self.golden_queue = golden_queue
        self.mon_sb_queue = mon_sb_queue 
        self._coro = cocotb.start_soon(self._run())
        self.transactions_checked = 0
        self.error = 0 
        
    async def _run(self):
        while True: 
            dut_data = await self.mon_sb_queue.get() 
            golden_data = await self.golden_queue.get() 
            if dut_data != golden_data: 
                cocotb.log.error(f"""\n\nTransaction {self.transactions_checked}!\n
                --- Expected (Golden): ---\n{golden_data}\n
                --- Got from Silicon: ---\n{dut_data}\n """
                )
                self.error += 1 
            else: 
                cocotb.log.info(f"""\n\nTransaction {self.transactions_checked}!\n
                --- Expected (Golden): ---\n{golden_data}\n
                --- Got from Silicon: ---\n{dut_data}\n """
)
            cocotb.log.debug(f"Transaction {self.transactions_checked} passed.")
            self.transactions_checked += 1



class Golden_Model: 
    def __init__(self, addr_width, data_width):
        self.addr_width = addr_width
        self.data_width = data_width 
        self.file = [0]*(1<<addr_width)

    def get(self,addr): 
        return self.file[addr] 

    def write(self,addr, data, write_en):
        if(write_en and addr != 0):
            self.file[addr] = data
    
    def perform_transaction(self, tr: Transaction_Input) -> Transaction_Output: 
        read_data_1 = self.get(tr.read_addr_1)
        read_data_2 = self.get(tr.read_addr_2)
        self.write(tr.write_addr, tr.write_data, tr.write_en)
        return Transaction_Output(read_data_1,read_data_2)


    def print_state(self): 
        print(self.file)
        





        
async def setup(dut,settings):
    golden_queue, dut_queue = Queue(), Queue()
    start_event = Event() 
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    rng = np.random.default_rng(seed=42)

    program = make_program(rng,settings)
    monitor = RF_Monitor(dut,dut_queue,start_event)
    scoreboard = RF_Scoreboard(golden_queue,dut_queue)


    return scoreboard, start_event, program, golden_queue


class Settings: 
    def __init__(self, addr_width, data_width, tests): 
        self.addr_width = addr_width 
        self.data_width = data_width
        self.tests = tests

async def finish(dut, sb, expected):
    t = 0
    while sb.transactions_checked < expected:
        await RisingEdge(dut.clk)
        t += 1
        assert t < 200_000, f"timeout: {sb.transactions_checked}/{expected} fills checked"
    print(f"report: fills={sb.transactions_checked} errors={sb.error}")
    assert sb.error == 0, f"{sb.error} mismatches"



@cocotb.test()
async def test_random(dut):
    settings = Settings(5,32,100)
    scoreboard, start_event, program, golden_queue = await setup(dut,settings)
    await drive_program(dut,settings,program,golden_queue,start_event)
    await finish(dut, scoreboard, len(program))




"""
module register_file
#(
  DATA_WIDTH = 32, 
  ADDR_WIDTH = 3,
)
(
  input clk, reset, 
  input write_en, 
  input read_addr_1, 
  input read_addr_2, 
  input write_addr,
  input write_data, 
  output reg read_data_1, 
  output reg read_data_2, 
)
"""
