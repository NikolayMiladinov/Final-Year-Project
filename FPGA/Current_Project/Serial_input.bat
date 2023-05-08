@ECHO OFF
ECHO Starting serial communication and inputting file
plink -serial COM7 -sercfg 9600,8,1,N,N < "C:\Users\nikol\Documents\FinalYearProject\Final-Year-Project\FPGA\Current_Project\Test.txt"
ECHO Done!
PAUSE