# DSD Final Project

This repository contains the RTL design and synthesized netlist for the final project of the Digital System Design course.

## Project Structure

- `01_RTL/`
  - `01_rtl.f` - Verilog file list for RTL simulation.
  - `ALU.v` - Arithmetic Logic Unit.
  - `Branch_Predictor_Conv_Perfect.v` - Branch predictor module (conventional perfect model).
  - `Branch_Predictor_Gshare.v` - Gshare branch predictor.
  - `Branch_Predictor_LFSR_Conv_Perfect.v` - LFSR-based perfect branch predictor.
  - `Branch_Predictor_LFSR_Perfect.v` - LFSR-based perfect predictor.
  - `Branch_Predictor.v` - Branch predictor top-level module.
  - `CHIP.v` - Top-level design.
  - `Control.v` - Control unit.
  - `Cope_with_Hazard.v` - Hazard handling logic.
  - `D_cache.v` - Data cache module.
  - `Decompressor.v` - Instruction decompressor.
  - `FSM.v` - Finite state machine.
  - `I_cache.v` - Instruction cache module.
  - `Pipeline_reg.v` - Pipeline registers.
  - `Makefile` - Simulation targets and cleanup commands.

- `02_SYN/`
  - `Netlist/CHIP_syn.v` - Synthesized Verilog netlist.
  - `Netlist/CHIP_syn.sdf` - Standard delay format file for timing annotation.
  - `Netlist/CHIP_syn.ddc` - DDC file for synthesis metadata.

## How to Run

From the repository root, run the RTL simulation using the provided make target:

```bash
cd 01_RTL
make run
```

This uses Synopsys VCS with the file list from `01_rtl.f` and writes simulation output to `vcs_sim.log`.

## Clean Up

To remove generated simulation files, run:

```bash
cd 01_RTL
make clean
```

## Notes

- The RTL directory contains the source files used for simulation and verification.
- The synthesis directory contains the generated netlist and timing files from the synthesis flow.
