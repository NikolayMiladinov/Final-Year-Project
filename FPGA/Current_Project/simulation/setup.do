quietly set ACTELLIBNAME IGLOO
quietly set PROJECT_DIR "C:/Users/nikol/Documents/FinalYearProject/Final-Year-Project/FPGA/Current_Project"
onerror { quit -f }

if {[file exists presynth/_info]} {
   echo "INFO: Simulation library presynth already exists"
} else {
   file delete -force presynth 
   vlib presynth
}
vmap presynth presynth
vmap igloo "C:/Microsemi/Libero_SoC_v11.9/Designer/lib/modelsim/precompiled/vlog/igloo"

vlog "+incdir+${PROJECT_DIR}/hdl" -sv -work presynth "${PROJECT_DIR}/hdl/clk_div.v"
vlog "+incdir+${PROJECT_DIR}/hdl" -sv -work presynth "${PROJECT_DIR}/smartgen/FIFO_INPUT_SAVE/FIFO_INPUT_SAVE.v"
vlog "+incdir+${PROJECT_DIR}/hdl" -sv -work presynth "${PROJECT_DIR}/smartgen/FIFO_OUTPUT_SEND/FIFO_OUTPUT_SEND.v"
vlog "+incdir+${PROJECT_DIR}/hdl" -sv -work presynth "${PROJECT_DIR}/hdl/spi_master.v"
vlog "+incdir+${PROJECT_DIR}/hdl" -sv -work presynth "${PROJECT_DIR}/hdl/SPI_Master_With_Single_CS.v"
vlog "+incdir+${PROJECT_DIR}/hdl" -sv -work presynth "${PROJECT_DIR}/hdl/mem_command.v"
vlog "+incdir+${PROJECT_DIR}/hdl" -sv -work presynth "${PROJECT_DIR}/hdl/top.v"
vlog "+incdir+${PROJECT_DIR}/hdl" "+incdir+${PROJECT_DIR}/stimulus" -sv -work presynth "${PROJECT_DIR}/stimulus/tb_top.v"

vsim -L igloo -L presynth  -t 1ps presynth.tb_top

log -r /*
wave zoom out
wave zoom out
wave zoom out
wave zoom out
wave zoom out
wave zoom out
wave zoom out
wave zoom out
wave zoom out
wave zoom out
add wave /tb_top/*
add wave /tb_top/top_0/*
add wave tb_top/top_0/MEM_COMMAND_CONTROLLER/*
run -all