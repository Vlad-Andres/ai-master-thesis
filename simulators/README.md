# Simulators

Two Monte Carlo lattice simulators, both forks of the Abeln et al. HB-Lattice
model. They're git submodules, built together, and run the same way with a
standard result file.

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

You need MPI (`mpicxx`/`mpirun`), CMake ≥ 3.16 and a C++14 compiler.

```bash
git submodule update --init
```

```bash
make -C simulators build
```

```bash
make -C simulators test
```

If `cmake` isn't on PATH, the Makefile falls back to the copy bundled with
CLion. To use a different one, pass `CMAKE=/path/to/cmake`.

## Running

```bash
make -C simulators run SIM=hb-lattice PDB=structures/seeds/sd10_pAA7.pdb SEED=1 STEPS=500 ROUNDS=20
```

That calls `./run.sh SIM STRUCTURE [extra flags]`. Each run:

- gets its own folder, `runs/<sim>-<structure>-<seed>-<time>/`, or `OUT=…`;
- writes the simulator's usual output plus `result.json`;
- prints the path of `result.json`.

Defaults are in `configs/<sim>.yaml`. To override them, set `MATRIX`,
`WATER_INDEX`, `TEMPERATURE`, `STEPS`, `ROUNDS`, `SEED` or `OUT`. Extra simulator
flags go after the structure (or in `ARGS="…"` with make). Runs are
single-temperature: `-noSwap -minT T -maxT T`. For LatticeWater, `run.sh` adds
`-native <structure>`, because LatticeWater crashes at the end of a run without one.

Every run writes to its own folder, so you can start as many in parallel as you
have cores:

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

There is no binding ΔG yet. How binding is defined in the model is still open,
so only raw quantities are stored.

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
make -C simulators visualise SIM=latticewater PDB=structures/lw/P1_Fixed.pdb
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
