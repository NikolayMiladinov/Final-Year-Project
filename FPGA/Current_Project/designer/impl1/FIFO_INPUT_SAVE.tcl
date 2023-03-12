# Created by Microsemi Libero Software 11.9.6.7
# Fri Mar 10 13:28:42 2023

# (NEW DESIGN)

# create a new design
new_design -name "FIFO_INPUT_SAVE" -family "IGLOO"
set_device -die {AGL250V2} -package {100 VQFP} -speed {STD} -voltage {1.2~1.5} -IO_DEFT_STD {LVCMOS 3.3V} -RESERVEMIGRATIONPINS {1} -RESTRICTPROBEPINS {1} -RESTRICTSPIPINS {0} -TARGETDEVICESFORMIGRATION {IS4X4M1LPLV} -TEMPR {IND} -UNUSED_MSS_IO_RESISTOR_PULL {None} -VCCI_1.2_VOLTR {COM} -VCCI_1.5_VOLTR {COM} -VCCI_1.8_VOLTR {COM} -VCCI_2.5_VOLTR {COM} -VCCI_3.3_VOLTR {COM} -VOLTR {IND}


# set default back-annotation base-name
set_defvar "BA_NAME" "FIFO_INPUT_SAVE_ba"
set_defvar "IDE_DESIGNERVIEW_NAME" {Impl1}
set_defvar "IDE_DESIGNERVIEW_COUNT" "1"
set_defvar "IDE_DESIGNERVIEW_REV0" {Impl1}
set_defvar "IDE_DESIGNERVIEW_REVNUM0" "1"
set_defvar "IDE_DESIGNERVIEW_ROOTDIR" {C:\Users\nikol\Documents\FinalYearProject\Final-Year-Project\FPGA\Current_Project\designer}
set_defvar "IDE_DESIGNERVIEW_LASTREV" "1"

# set working directory
set_defvar "DESDIR" "C:/Users/nikol/Documents/FinalYearProject/Final-Year-Project/FPGA/Current_Project/designer/impl1"

# set back-annotation output directory
set_defvar "BA_DIR" "C:/Users/nikol/Documents/FinalYearProject/Final-Year-Project/FPGA/Current_Project/designer/impl1"

# enable the export back-annotation netlist
set_defvar "BA_NETLIST_ALSO" "1"

# set EDIF options
set_defvar "EDNINFLAVOR" "GENERIC"

# set HDL options
set_defvar "NETLIST_NAMING_STYLE" "VERILOG"

# setup status report options
set_defvar "EXPORT_STATUS_REPORT" "1"
set_defvar "EXPORT_STATUS_REPORT_FILENAME" "FIFO_INPUT_SAVE.rpt"

# legacy audit-mode flags (left here for historical reasons)
set_defvar "AUDIT_NETLIST_FILE" "1"
set_defvar "AUDIT_DCF_FILE" "1"
set_defvar "AUDIT_PIN_FILE" "1"
set_defvar "AUDIT_ADL_FILE" "1"

# import of input files
import_source  \
-format "edif" -edif_flavor "GENERIC" -netlist_naming "VERILOG" {../../synthesis/FIFO_INPUT_SAVE.edn}

# save the design database
save_design {FIFO_INPUT_SAVE.adb}


compile
report -type "status" {FIFO_INPUT_SAVE_compile_report.txt}
report -type "pin" -listby "name" {FIFO_INPUT_SAVE_report_pin_byname.txt}
report -type "pin" -listby "number" {FIFO_INPUT_SAVE_report_pin_bynumber.txt}

save_design
