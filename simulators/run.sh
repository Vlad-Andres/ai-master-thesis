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
#
# Every run writes into its own folder, so any number can run at the same time.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || usage
sim="$1"; structure="$2"; shift 2

case "$sim" in
  hb-lattice)   exe="$here/build/bin/hblattice" ;;
  latticewater) exe="$here/build/bin/grancan" ;;
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
seed="${SEED:-$RANDOM$RANDOM}"
name="$(basename "$structure" .pdb)"
out="${OUT:-$here/runs/$sim-$name-$seed-$(date +%Y%m%d-%H%M%S)}"

structure="$(absolute "$structure")"
matrix="$(absolute "$matrix")"
mkdir -p "$out"

args=(-i "$structure" -aa "$matrix"
      -minT "$temperature" -maxT "$temperature" -S "$steps" -W "$rounds" -noSwap
      -seed "$seed" -resultJson result.json)
if [ -n "$water_index" ] && [ "$water_index" != none ]; then
  args+=(-indxWater "$water_index")
fi
# LatticeWater crashes at the end of a run without a native structure.
if [ "$sim" = latticewater ] && [[ " $* " != *" -native "* ]]; then
  args+=(-native "$structure")
fi

if ! (cd "$out" && "$exe" "${args[@]}" "$@" > stdout.txt 2>&1); then
  echo "simulation failed; see $out/stdout.txt" >&2
  tail -5 "$out/stdout.txt" >&2
  exit 1
fi
echo "$out/result.json"
