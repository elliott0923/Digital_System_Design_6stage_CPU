# Default target
all: 
	make run

# RTL simulation
run:
	vcs -f 01_rtl.f -full64 -R +v2k | tee vcs_sim.log

clean:
	-rm novas*
	-rm ucli.key
	-rm simv
	-rm -rf csrc/
	-rm -rf *.fsdb
	-rm -rf nWaveLog/
	-rm -rf simv.daidir/
	
help:
	@echo "Usage:"
	@echo "make all/run: run rtl code with pattern defined in 01_rtl.f"

.PHONY: all run
