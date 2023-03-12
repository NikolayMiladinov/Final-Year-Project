# Created by Microsemi Libero Software 11.9.6.7
# Fri Mar 10 19:35:50 2023

# (OPEN DESIGN)

open_design "top.adb"

# set default back-annotation base-name
set_defvar "BA_NAME" "top_ba"
set_defvar "IDE_DESIGNERVIEW_NAME" {Impl1}
set_defvar "IDE_DESIGNERVIEW_COUNT" "1"
set_defvar "IDE_DESIGNERVIEW_REV0" {Impl1}
set_defvar "IDE_DESIGNERVIEW_REVNUM0" "1"
set_defvar "IDE_DESIGNERVIEW_ROOTDIR" {C:\Users\nikol\Documents\FinalYearProject\Final-Year-Project\FPGA\Current_Project\designer}
set_defvar "IDE_DESIGNERVIEW_LASTREV" "1"
set_design  -name "top" -family "IGLOO"
set_device -die {AGLN250V2} -package {100 VQFP} -speed {STD} -voltage {1.2} -IO_DEFT_STD {LVCMOS 3.3V} -RESERVEMIGRATIONPINS {1} -RESTRICTPROBEPINS {1} -RESTRICTSPIPINS {0} -TARGETDEVICESFORMIGRATION {UM4X4M1NLPLV} -TEMPR {COM} -UNUSED_MSS_IO_RESISTOR_PULL {None} -VCCI_1.2_VOLTR {COM} -VCCI_1.5_VOLTR {COM} -VCCI_1.8_VOLTR {COM} -VCCI_2.5_VOLTR {COM} -VCCI_3.3_VOLTR {COM} -VOLTR {COM}



# import of input files
import_source  \
-format "edif" -edif_flavor "GENERIC" -netlist_naming "VERILOG" {../../synthesis/top.edn} -merge_physical "yes" -merge_timing "yes"
compile
report -type "status" {top_compile_report.txt}
report -type "pin" -listby "name" {top_report_pin_byname.txt}
report -type "pin" -listby "number" {top_report_pin_bynumber.txt}

save_design
