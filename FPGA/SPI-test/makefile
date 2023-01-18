connect:
	export DISPLAY=localhost:12.0
# source /usr/local/mentor/QUESTA-CORE-PRIME_10.7c/settings.sh
# source /usr/local/cadence/JASPER_2018.06.002/settings.sh
#compile the necessary files
comp-opt:
	vlog -work work +cover +fcover +acc=blnr -noincr -timescale 1ns/1ps tbench/tb_top.sv rtl/spi-master.sv
	vopt -work work tb_top -o work_opt
#Apply optimisation if no error

#If no error open QuestaSim
open-sim:
# vsim -coverage -voptargs="+cover=bcefst" -onfinish stop work_opt -gui
	vsim -onfinish stop work_opt -do setup.do -gui
