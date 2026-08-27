module cocotb_iverilog_dump();
initial begin
    $dumpfile("sim_build/data_path.fst");
    $dumpvars(0, data_path);
end
endmodule
