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
simulator) go after the structure, or in `ARGS="…"` with make.

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
and contacts `Ctot`/`Cint`/`Cext`. `Nint`/`Next`/`Ntot` are always 0 in our runs
and can be ignored.
hb-lattice also has hydrogen bonds `Hint`/`Hext`/`Htot`.

## Output files

### How a run is structured

```
-W rounds
 └─ each round: -S Monte Carlo steps
      └─ each step: pick a random chain, try one small move
```

`STEPS=500 ROUNDS=20` is 10,000 steps. In each step the simulator picks a random
chain and tries a move of one residue.

### Files in a run folder

`<rank>` is the MPI rank: `0` for a single process.

| File | Written by | Contents |
|---|---|---|
| `result.json` | fork (`-resultJson`) | Summary, see above |
| `statsTable<rank>.txt` | simulator | One row per round: a snapshot of the current state. See below |
| `stats_N<rank>.tab` | simulator | Tally of one quantity over **every** step. See below |
| `eMap_N<rank>.tab` | simulator | The same kind of tally, over total energy |
| `clusterSizeN<rank>.tab` | simulator (LatticeWater) | Cluster sizes. Only filled in grand-canonical mode, so it's empty in normal runs |
| `outN<rank>.pdb` | simulator | Final conformation |
| `lattice-trajectory-N<rank>.tsv`, `lattice-viewer.html` | fork (`-visualise`) | Trajectory and viewer |
| `stdout.txt` | `run.sh` | The simulator's terminal output, including the initial and final stats |
| `version.txt` | `run.sh` | Simulator commit and binary build time |

### statsTable<rank>.txt

| Column | Meaning |
|---|---|
| `step` | Round number, from 0. Row 0 is the state after the first round, not the input structure |
| `T`, `beta` | Temperature and 1/T |
| `weight` | 1, except in grand-canonical mode |
| `Eint` | Energy of contacts **within** a chain |
| `Eext` | Energy of contacts **between** chains |
| `Esol` | Energy of residues touching water. Water is any empty lattice site |
| `Etot` | `Eint + Eext + Esol` |
| `Cint`, `Cext`, `Ctot` | Number of contacts within chains, between chains, and in total |
| `Hint`, `Hext`, `Htot` | hb-lattice with `-hbondStats`: hydrogen bonds within, between, total |

LatticeWater adds water columns. Its "hydrophobic" residues are those with a
positive water interaction in the matrix.

| Column | Meaning |
|---|---|
| `solvHN` | Hydrophobic residues with at least one water neighbour |
| `solvN` | All residues with at least one water neighbour |
| `wcHN` | Hydrophobic–water contacts (up to 6 per residue) |
| `Corr_E`, `E0` | Energy with a temperature-dependent potential; equal to `Etot` unless one is enabled |
| `fsolvHN` | Hydrophobic residues fully surrounded by water |
| `surfHN` | Hydrophobic residues partly surrounded by water |

`fsolvHN + surfHN = solvHN`. The header labels the last two columns `fsolvHN` and
`surfHN`; the code writes `solvatedHN` and `surfaceHN` (`EnergyMap.cpp`, `WaterStats.hpp`).

### stats_N<rank>.tab

```
BETA  3.33333      ← 1/T (one block per temperature)
54    120.5        ← value  weight
55    310.2
```

For every attempted move, the simulator adds a total weight of 1, split between
the current state and the proposed one in proportion to the acceptance
probability. Each row's weight is therefore the time spent at that value.
Dividing by the sum gives the probability P(x). Values with zero weight are left
out.

x is `Cext`, the number of contacts between chains.


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
