########################################################
# TESTBED                                              #
########################################################
../00_TESTBED/testbench/Final_tb.v

########################################################
# Memory                                               #
########################################################
../00_MEMORY/slow_memory_random_latency.v
../00_MEMORY/slow_memory.v
../00_MEMORY/fast_memory.v

########################################################
# Flush Instruction Definition                         #
########################################################
../00_TESTBED/testbench/flush_inst_define.v

########################################################
# DUT                                                  #
########################################################
CHIP.v


########################################################
# Standard cell library                                #
########################################################
-y /usr/cad/synopsys/synthesis/cur/dw/sim_ver +libext+.v
+incdir+/usr/cad/synopsys/synthesis/cur/dw/sim_ver/+

########################################################
# Dump FSDB                                            #
########################################################
// +define+FSDB

########################################################
# Defines for debug                                    #
########################################################
+define+MAX_CYCLES=6000000

########################################################
# Branch Prediction choice                             #
########################################################
+define+USE_LFSR_CONV_PERFECT
// +define+USE_CONV_PERFECT
// +define+USE_LFSR_PERFECT
// +define+USE_GSHARE

########################################################
# Pattern Definition                                   #
########################################################
// +define+noHazard
// +define+hasHazard

// +define+BrPred
// +define+Scaling
// +define+compression
// +define+compression_uncompressed

// +define+QSort_uncompressed
//+define+QSort
 +define+Conv
// +define+Conv_uncompressed
// +define+Mul

// +define+LFSR_HIST
// +define+LFSR_HIST_short
