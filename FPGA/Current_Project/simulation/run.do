quietly set ACTELLIBNAME IGLOO
quietly set PROJECT_DIR "C:/Users/nikol/Documents/FinalYearProject/Final-Year-Project/FPGA/Current_Project"

if {[file exists presynth/_info]} {
   echo "INFO: Simulation library presynth already exists"
} else {
   file delete -force presynth 
   vlib presynth
}
vmap presynth presynth
vmap igloo "C:/Microsemi/Libero_SoC_v11.9/Designer/lib/modelsim/precompiled/vlog/igloo"

vlog -sv -work presynth "${PROJECT_DIR}/hdl/spi_master.v"
vlog -sv -work presynth "${PROJECT_DIR}/hdl/SPI_Master_With_Single_CS.v"
vlog -sv -work presynth "${PROJECT_DIR}/hdl/clk_div.v"
vlog -sv -work presynth "${PROJECT_DIR}/hdl/top.v"
vlog "+incdir+${PROJECT_DIR}/stimulus" -sv -work presynth "${PROJECT_DIR}/stimulus/top_test.v"

vsim -L igloo -L presynth  -t 1ps presynth.top_test
add wave /top_test/*
run 1000ns
