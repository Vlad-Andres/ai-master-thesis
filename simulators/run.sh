#!/usr/bin/env bash
# Run one simulation in its own folder and print the path of its result.json.
#
#   ./run.sh SIM STRUCTURE [extra simulator flags...]
#
#   SIM        hb-lattice | latticewater
#   STRUCTURE  a .pdb file, e.g. structures/seeds/sd10_pAA7.pdb
#
# Defaults come from configs/SIM.yaml. Override them with environment variables:
#   MATRIX       matrix name in matrices/ (e.g. aa_water2) or a path
#   WATER_INDEX  value for -indxWater; "none" leaves the flag out
#   TEMPERATURE  STEPS (per round, -S)  ROUNDS (-W)
#   SEED         random if unset
#   OUT          output folder (default runs/SIM-STRUCTURE-SEED-TIME)
#   NP           MPI processes (replicas), default 1; NP>1 runs under $MPIRUN (default mpirun)
#   TMIN TMAX    temperature range for parallel tempering (default: both TEMPERATURE)
#
# Every run writes into its own folder, so any number can run at the same time.
# These are defaults only: extra flags are passed to the simulator unchanged.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || usage
sim="$1"; structure="$2"; shift 2

case "$sim" in
  hb-lattice)   exe="$here/build/bin/hblattice"; src="$here/external/hb-lattice" ;;
  latticewater) exe="$here/build/bin/grancan";   src="$here/external/LatticeWater" ;;
  *) echo "unknown simulator: $sim (use hb-lattice or latticewater)" >&2; exit 2 ;;
esac
[ -x "$exe" ] || { echo "$exe not found; run 'make build' first" >&2; exit 1; }
[ -f "$structure" ] || { echo "structure not found: $structure" >&2; exit 1; }

# read "key: value" from configs/SIM.yaml
config() { sed -n "s/^$1:[[:space:]]*\([^#]*\).*/\1/p" "$here/configs/$sim.yaml" | xargs; }
absolute() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }

matrix="${MATRIX:-$(config matrix)}"
[ -f "$matrix" ] || matrix="$here/matrices/$matrix.txt"
[ -f "$matrix" ] || { echo "matrix not found: $matrix" >&2; exit 1; }
water_index="${WATER_INDEX:-$(config water_index)}"
temperature="${TEMPERATURE:-$(config temperature)}"
steps="${STEPS:-$(config steps)}"
rounds="${ROUNDS:-$(config rounds)}"
tmin="${TMIN:-$temperature}"
tmax="${TMAX:-$temperature}"
np="${NP:-1}"
mpirun="${MPIRUN:-mpirun}"
seed="${SEED:-$RANDOM$RANDOM}"
name="$(basename "$structure" .pdb)"
out="${OUT:-$here/runs/$sim-$name-$seed-$(date +%Y%m%d-%H%M%S)}"

if [ "$np" -le 1 ] && [ "$tmin" != "$tmax" ]; then
  echo "a temperature range (TMIN=$tmin TMAX=$tmax) needs NP>1, one process per temperature" >&2; exit 2
fi
if [ "$np" -gt 1 ]; then
  command -v "$mpirun" > /dev/null || { echo "$mpirun not found; install MPI or set MPIRUN" >&2; exit 1; }
  command -v jq > /dev/null || { echo "jq not found; needed to merge per-replica results" >&2; exit 1; }
fi

structure="$(absolute "$structure")"
matrix="$(absolute "$matrix")"
mkdir -p "$out"

# Record which simulator source this run came from (the submodule is not pinned, see .gitmodules).
# "dirty" means the checkout had uncommitted changes; rebuild with 'make build' after 'make update'.
{
  echo "simulator: $sim"
  echo "commit: $(git -C "$src" rev-parse HEAD 2>/dev/null || echo unknown)"
  git -C "$src" diff --quiet HEAD 2>/dev/null || echo "dirty: true"
  echo "binary_built: $(date -r "$exe" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
} > "$out/version.txt"

args=(-i "$structure" -aa "$matrix"
      -minT "$tmin" -maxT "$tmax" -S "$steps" -W "$rounds"
      -seed "$seed" -resultJson result.json)
# Temperature swaps only make sense between replicas at different temperatures.
if [ "$np" -le 1 ] || [ "$tmin" = "$tmax" ]; then
  args+=(-noSwap)
fi
if [ -n "$water_index" ] && [ "$water_index" != none ]; then
  args+=(-indxWater "$water_index")
fi
# LatticeWater crashes at the end of a run without a native structure.
if [ "$sim" = latticewater ] && [[ " $* " != *" -native "* ]]; then
  args+=(-native "$structure")
fi

launch=("$exe")
[ "$np" -gt 1 ] && launch=("$mpirun" -np "$np" "$exe")

if ! (cd "$out" && "${launch[@]}" "${args[@]}" "$@" > stdout.txt 2>&1); then
  echo "simulation failed; see $out/stdout.txt" >&2
  tail -5 "$out/stdout.txt" >&2
  exit 1
fi
# With several replicas each rank writes result_N<rank>.json; merge them into one file.
if [ "$np" -gt 1 ]; then
  jq -s '{schema: 1, simulator: .[0].simulator, seed: .[0].seed, num_procs: length,
          replicas: sort_by(.rank)}' "$out"/result_N*.json > "$out/result.json"
  rm "$out"/result_N*.json
fi
echo "$out/result.json"
