# Simulators

Two Monte Carlo lattice simulators, both forks of the Abeln et al. HB-Lattice
model. They're git submodules, built together, and run the same way with a
standard result file.

`run.sh` is a thin layer over the two simulators: an **adapter** per simulator
maps one set of inputs onto each simulator's own flags, and `run.sh` / `make run`
is the **facade**. 
```
simulators/
├── CMakeLists.txt, Makefile   build both, run, visualise, test
├── run.sh                     run one simulation → runs/<name>/result.json
├── external/
│   ├── hb-lattice/            submodule: H-bonds, cluster moves      → build/bin/hblattice
│   └── LatticeWater/          submodule: potential variants, water   → build/bin/grancan
├── structures/                every PDB in use + manifest.yaml (format, chains, which simulator runs it)
├── matrices/                  interaction matrices + manifest.yaml (water index, origin)
├── configs/                   default run parameters per simulator, read by run.sh
├── visualise/                 trajectory viewer for both simulators + visualise.sh
└── tests/fork_checks.sh       checks that the flags added to the forks change nothing
```

## Setup

You need MPI (`mpicxx`/`mpirun`), CMake ≥ 3.16 and a C++14 compiler, all on
PATH. From the repository root:

```bash
brew install cmake open-mpi    # macOS; Debian/Ubuntu: sudo apt install cmake libopenmpi-dev build-essential
git submodule update --init    # fetch external/hb-lattice and external/LatticeWater
cd simulators
make build
make test
```

To use a cmake that isn't on PATH, pass `CMAKE=/path/to/cmake`.

## Running

Exmaple:
```bash
make run SIM=hb-lattice PDB=structures/seeds/sd10_pAA7.pdb SEED=1 STEPS=500 ROUNDS=20
```

That calls `./run.sh SIM STRUCTURE [extra flags]`. Each run:

- gets its own folder, `runs/<sim>-<structure>-<seed>-<time>/`, or `OUT=…`;
- writes the simulator's usual output plus `result.json`;
- prints the path of `result.json`.

Override the defaults in `configs/<sim>.yaml` with these variables:

| Variable | Default | Simulator flag | Meaning |
|---|---|---|---|
| `SEED` | random | `-seed N` | random seed; MPI rank *r* uses `N + r` |
| `STEPS` | 1000 | `-S N` | Monte Carlo steps per round |
| `ROUNDS` | 100 | `-W N` | rounds; statistics are sampled once per round |
| `TEMPERATURE` | 0.3 | `-minT T -maxT T -noSwap` | single temperature, reduced units |
| `NP` | 1 | `mpirun -np N` | MPI processes, one replica each |
| `TMIN`, `TMAX` | `TEMPERATURE` | `-minT -maxT` | temperature range for parallel tempering; needs `NP>1` |
| `MPIRUN` | `mpirun` | – | MPI launcher used when `NP>1` |
| `MATRIX` | `aa_water2` | `-aa path` | name in `matrices/` or a path |
| `WATER_INDEX` | 20 | `-indxWater N` | water row in the matrix; `none` omits the flag |
| `OUT` | `runs/<sim>-<structure>-<seed>-<time>/` | – | output folder |

With `NP>1` and `TMIN` ≠ `TMAX`, the replicas run at evenly spaced temperatures
and swap after every round (parallel tempering); otherwise `-noSwap` is passed by default.
Each replica writes its own result, and `run.sh` merges them into one
`result.json` with a `replicas` list (needs `jq`). A replica's statistics follow
the process, not the temperature, so after swaps they mix temperatures.

```bash
make run SIM=hb-lattice PDB=structures/seeds/sd10_pAA7.pdb NP=4 TMIN=0.25 TMAX=0.45
```

Other simulator flags (`-movie`, `-getCext`, …; see `source/App.cpp` in each
simulator) go after the structure, or in `ARGS="…"` with make. For LatticeWater,
`run.sh` adds `-native <structure>`, because LatticeWater crashes at the end of a
run without one.

Example of multi-run:

```bash
for s in $(seq 1 32); do SEED=$s ./run.sh latticewater structures/lw/P1_Fixed.pdb & done; wait
```

Parallel tempering across MPI ranks still works by calling the executable
yourself with `mpirun -np N`. With `-resultJson out.json`, each rank writes
`out_N<rank>.json`, and `-seed K` seeds rank r with `K + r`.

### result.json

- `final`: the counters at the end of the run.
- `mean` and `var`: the counters sampled once per round (`sampled_rounds` samples).
- `lowest`: the lowest `Etot` seen and the round it was in.
- `chains`: the final residues of each chain.
- Provenance: `seed`, `rank`, `num_procs`, `temperature`, `steps_per_round`,
  `rounds`, `argv` and `wall_seconds`.

The counters are `Etot`, `Eint` (within a chain), `Eext` (between chains), `Esol`,
contacts `Ctot`/`Cint`/`Cext`, and native contacts `Nint`/`Next`/`Ntot`.
hb-lattice also has hydrogen bonds `Hint`/`Hext`/`Htot`.


## Flags added to the forks

All three are opt-in. Without them, the output is byte-identical to the
original code. `tests/fork_checks.sh` checks this for single-rank and
multi-rank (`NP=4`) runs.

- `-seed K` makes runs reproducible. hb-lattice used to seed every run with the
  rank, so every run was identical. LatticeWater used the process id, so runs
  couldn't be repeated.
- `-resultJson PATH` writes `result.json` as described above.
- `-visualise` writes `lattice-trajectory-N<rank>.tsv`. LatticeWater now supports
  it too; its spin columns are 0 because its residues have no side-chain spin.

## Visualising

```bash
make visualise SIM=latticewater PDB=structures/lw/P1_Fixed.pdb
```

This does a short run (`STEPS=50`, `ROUNDS=2` unless you set them), embeds every
step into a copy of `visualise/lattice-viewer.html`, and opens it in your browser.

## Structures

`structures/manifest.yaml` lists each file's format, chains and lengths, plus
which simulators complete a short run on it. Things to know:

- LatticeWater structures (`lw/`) have backbone (CA) lines only, so only
  LatticeWater runs them.
- hb-lattice stops on `random_35` with a stats-consistency error; the original
  binary does too.
- `matrices/Betancourt_hb.txt` and `Betancourt_lw.txt` differ in three Lys/Glu
  entries. See `matrices/manifest.yaml`.

When you add a structure, add an entry to the manifest.
