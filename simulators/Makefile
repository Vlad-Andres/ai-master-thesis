# Simulators: build both lattice simulators, run them, watch a run.
#
#   make build
#   make run SIM=hb-lattice PDB=structures/seeds/sd10_pAA7.pdb [SEED=1 STEPS=500 ROUNDS=20] [ARGS="-hbondStats"]
#   make visualise SIM=latticewater PDB=structures/lw/P1_Fixed.pdb
#   make test        checks that the fork flags change nothing (single and multi-rank)
#   make clean
#
# SEED, STEPS, ROUNDS, TEMPERATURE, MATRIX, WATER_INDEX, OUT, NP, TMIN, TMAX and MPIRUN are passed to run.sh.

CMAKE ?= cmake
BUILD_DIR ?= build
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

export SEED STEPS ROUNDS TEMPERATURE MATRIX WATER_INDEX OUT NP TMIN TMAX MPIRUN

.PHONY: build run visualise test clean

build:
	@command -v "$(CMAKE)" >/dev/null || { echo "cmake not found: install it (brew install cmake / apt install cmake) or pass CMAKE=/path/to/cmake"; exit 127; }
	"$(CMAKE)" -S . -B "$(BUILD_DIR)"
	"$(CMAKE)" --build "$(BUILD_DIR)" -j $(JOBS)

run:
	@test -n "$(SIM)" -a -n "$(PDB)" || { echo "usage: make run SIM=hb-lattice|latticewater PDB=structures/... [ARGS=...]"; exit 2; }
	@./run.sh "$(SIM)" "$(PDB)" $(ARGS)

visualise:
	@test -n "$(SIM)" -a -n "$(PDB)" || { echo "usage: make visualise SIM=hb-lattice|latticewater PDB=structures/... [ARGS=...]"; exit 2; }
	@visualise/visualise.sh "$(SIM)" "$(PDB)" $(ARGS)

test:
	tests/fork_checks.sh hb
	tests/fork_checks.sh lw

clean:
	rm -rf "$(BUILD_DIR)"
