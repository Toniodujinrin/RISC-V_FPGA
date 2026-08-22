SIM ?= icarus
TOPLEVEL_LANG ?= verilog 
export PYTHONPATH := $(PWD)/..:$(PYTHONPATH)
VERILOG_SOURCES += $(PWD)/../../../rtl/register_file.v 

TOPLEVEL = register_file
MODULE = register_file_ctb

include $(shell cocotb-config --makefiles)/Makefile.sim
