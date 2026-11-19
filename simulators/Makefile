# Simulators: build both lattice simulators, run them, watch a run.
#
#   make build
#   make run SIM=hb-lattice PDB=structures/seeds/sd10_pAA7.pdb [SEED=1 STEPS=500 ROUNDS=20] [ARGS="-hbondStats"]
#   make visualise SIM=latticewater PDB=structures/lw/P1_Fixed.pdb
#   make test        checks that the fork flags change nothing (single and multi-rank)
#   make clean
#
# SEED, STEPS, ROUNDS, TEMPERATURE, MATRIX, WATER_INDEX and OUT are passed to run.sh.

CLION_CMAKE := /Applications/CLion.app/Contents/bin/cmake/mac/aarch64/bin/cmake
CMAKE ?= $(shell command -v cmake 2>/dev/null || echo $(CLION_CMAKE))
BUILD_DIR ?= build
JOBS ?= 8

export SEED STEPS ROUNDS TEMPERATURE MATRIX WATER_INDEX OUT

.PHONY: build run visualise test clean

build:
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
