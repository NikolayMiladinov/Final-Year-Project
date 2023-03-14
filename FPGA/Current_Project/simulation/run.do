quietly set ACTELLIBNAME IGLOO
quietly set PROJECT_DIR "C:/Users/nikol/Documents/FinalYearProject/Final-Year-Project/FPGA/Current_Project"
quietly set ROOTDIR_UART_CORE "C:/Users/nikol/Documents/FinalYearProject/Final-Year-Project/FPGA/Current_Project/component/work/UART_CORE"

if {[file exists presynth/_info]} {
   echo "INFO: Simulation library presynth already exists"
} else {
   file delete -force presynth 
   vlib presynth
}
vmap presynth presynth
vmap igloo "C:/Microsemi/Libero_SoC_v11.9/Designer/lib/modelsim/precompiled/vlog/igloo"

vlog -sv -work presynth "${PROJECT_DIR}/component/work/UART_CORE/UART_CORE_0/rtl/vlog/core/Clock_gen.v"
vlog -sv -work presynth "${PROJECT_DIR}/component/work/UART_CORE/UART_CORE_0/rtl/vlog/core/Rx_async.v"
vlog -sv -work presynth "${PROJECT_DIR}/component/work/UART_CORE/UART_CORE_0/rtl/vlog/core/Tx_async.v"
vlog -sv -work presynth "${PROJECT_DIR}/component/work/UART_CORE/UART_CORE_0/rtl/vlog/core/fifo_256x8_igloo.v"
vlog -sv -work presynth "${PROJECT_DIR}/component/work/UART_CORE/UART_CORE_0/rtl/vlog/core/CoreUART.v"
vlog -sv -work presynth "${PROJECT_DIR}/component/work/UART_CORE/UART_CORE.v"
vlog "+incdir+${PROJECT_DIR}/stimulus" -sv -work presynth "${PROJECT_DIR}/stimulus/uart_tb.v"

vsim -L igloo -L presynth  -t 1ps presynth.uart_tb
add wave /uart_tb/*
run 1000ns
