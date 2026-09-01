SIM ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES ?= 1
# the loader helpers live with the datapath testbench rather than being copied
export PYTHONPATH := $(PWD)/../datapath:$(PYTHONPATH)

RTL = $(PWD)/../../../rtl

VERILOG_SOURCES += $(RTL)/datapath.v
VERILOG_SOURCES += $(RTL)/inst_mem.v
VERILOG_SOURCES += $(RTL)/data_mem.v
VERILOG_SOURCES += $(RTL)/program_counter.v
VERILOG_SOURCES += $(RTL)/pc_controller.v
VERILOG_SOURCES += $(RTL)/btb.v
VERILOG_SOURCES += $(RTL)/branch_predictor.v
VERILOG_SOURCES += $(RTL)/branch_logic.v
VERILOG_SOURCES += $(RTL)/IF_ID_reg.v
VERILOG_SOURCES += $(RTL)/instruction_decoder.v
VERILOG_SOURCES += $(RTL)/control.v
VERILOG_SOURCES += $(RTL)/alu_controller.v
VERILOG_SOURCES += $(RTL)/alu.v
VERILOG_SOURCES += $(RTL)/register_file.v
VERILOG_SOURCES += $(RTL)/ID_EX_reg.v
VERILOG_SOURCES += $(RTL)/EX_MEM_reg.v
VERILOG_SOURCES += $(RTL)/MEM_WB_reg.v
VERILOG_SOURCES += $(RTL)/forwarding_unit.v
VERILOG_SOURCES += $(RTL)/hazard_detector.v
VERILOG_SOURCES += $(RTL)/lsu.v
VERILOG_SOURCES += $(RTL)/BE_logic.v
VERILOG_SOURCES += $(RTL)/l1.v
VERILOG_SOURCES += $(RTL)/mmio.v
VERILOG_SOURCES += $(RTL)/io_apb_bridge.v
VERILOG_SOURCES += $(RTL)/io/uart.v
VERILOG_SOURCES += $(RTL)/io/sim_exit.v

# riscv_defs.vh is `include-d by control.v
COMPILE_ARGS += -I$(RTL)

# an RTL $finish kills cocotb before the assertion runs, so sim_exit only raises
# exit_valid here and the test awaits it
COMPILE_ARGS += -Pdata_path.SIM_EXIT_FINISH=0

TOPLEVEL = data_path
MODULE = c_ctb

include $(shell cocotb-config --makefiles)/Makefile.sim
