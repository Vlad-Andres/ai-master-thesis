#!/usr/bin/env bash
# Checks for the opt-in flags added to the simulator forks (-seed, -resultJson, -visualise).
#
#   tests/fork_checks.sh hb|lw
#
# 1. the same -seed gives an identical result file
# 2. different seeds give different results
# 3. the new flags do not change the simulation (stats_N0.tab byte-identical)
# 4. multi-rank MPI runs (parallel tempering) are unaffected and write one result per rank
# 5. -visualise writes a trajectory in the viewer's format
#
# Env: BIN_DIR (default build/bin), MPIRUN (default mpirun; multi-rank check skipped if absent),
#      NP (ranks for check 4, default 2).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="${BIN_DIR:-$here/build/bin}"
mpirun="${MPIRUN:-mpirun}"
np="${NP:-2}"
ext="$here/external"

case "${1:-}" in
  hb)
    exe="$bin_dir/hblattice"
    common=(-i "$ext/hb-lattice/seeds/sd10_pAA7.pdb" -aa "$ext/hb-lattice/matrices/aa_water2.txt" -indxWater 20)
    ;;
  lw)
    exe="$bin_dir/grancan"
    pdb="$ext/LatticeWater/LatticeFiles/PDB/P1_Fixed.pdb"
    common=(-i "$pdb" -aa "$ext/LatticeWater/LatticeFiles/input/aa_water2.txt" -indxWater 20)
    ;;
  *) echo "usage: $0 hb|lw" >&2; exit 2 ;;
esac
[ -x "$exe" ] || { echo "missing $exe; run 'make build' first" >&2; exit 1; }

single=(-minT 0.3 -maxT 0.3 -S 500 -W 10 -noSwap)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
pass() { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=1; }

# run NAME ARGS... : run the simulator in its own directory $work/NAME
run() {
  local name="$1"; shift
  mkdir -p "$work/$name"
  (cd "$work/$name" && "$exe" "$@" > stdout.txt 2>&1) || { echo "run $name failed:"; tail -5 "$work/$name/stdout.txt"; return 1; }
}

# strip wall-clock time so result files can be compared
norm() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("wall_seconds"); print(json.dumps(d, sort_keys=True))' "$1"; }

valid_json() {
  python3 - "$@" <<'EOF'
import json, sys
path, rank, nprocs, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
d = json.load(open(path))
assert d["schema"] == 1, "schema"
assert d["rank"] == rank and d["num_procs"] == nprocs, "rank/num_procs"
assert d["seed"] == seed, f"seed {d['seed']} != {seed}"
assert set(d["final"]) == set(d["mean"]) == set(d["var"]), "field sets"
assert d["sampled_rounds"] == d["rounds"] == 10, "rounds"
assert d["chains"] and all(c["residues"] for c in d["chains"]), "chains"
assert d["argv"], "provenance"
EOF
}

# 1. determinism
run seed7a "${common[@]}" "${single[@]}" -seed 7 -resultJson r.json
run seed7b "${common[@]}" "${single[@]}" -seed 7 -resultJson r.json
if [ "$(norm "$work/seed7a/r.json")" = "$(norm "$work/seed7b/r.json")" ] && valid_json "$work/seed7a/r.json" 0 1 7; then
  pass "same seed -> identical result"
else
  bad "same seed -> identical result"
fi

# 2. different seeds differ
run seed8 "${common[@]}" "${single[@]}" -seed 8 -resultJson r.json
if [ "$(norm "$work/seed7a/r.json")" != "$(norm "$work/seed8/r.json")" ]; then
  pass "different seeds -> different results"
else
  bad "different seeds -> different results"
fi

# 3. new flags do not change the simulation
run plain7 "${common[@]}" "${single[@]}" -seed 7
if cmp -s "$work/plain7/stats_N0.tab" "$work/seed7a/stats_N0.tab"; then
  pass "-resultJson leaves stats_N0.tab unchanged"
else
  bad "-resultJson leaves stats_N0.tab unchanged"
fi
run vis7 "${common[@]}" "${single[@]}" -seed 7 -visualise
if cmp -s "$work/plain7/stats_N0.tab" "$work/vis7/stats_N0.tab"; then
  pass "-visualise leaves stats_N0.tab unchanged"
else
  bad "-visualise leaves stats_N0.tab unchanged"
fi
if [ "$1" = hb ]; then
  # hb-lattice's default seed is the rank, so "-seed 0" must reproduce a run without -seed exactly
  run default "${common[@]}" "${single[@]}"
  run seed0 "${common[@]}" "${single[@]}" -seed 0 -resultJson r.json
  if cmp -s "$work/default/stats_N0.tab" "$work/seed0/stats_N0.tab"; then
    pass "default seeding unchanged"
  else
    bad "default seeding unchanged"
  fi
fi

# 4. multi-rank parallel tempering
if command -v "$mpirun" > /dev/null; then
  pt=(-minT 0.2 -maxT 0.4 -S 500 -W 10 -lT)
  mpi() { local name="$1"; shift; mkdir -p "$work/$name"
    (cd "$work/$name" && "$mpirun" -np "$np" "$exe" "$@" > stdout.txt 2>&1) || { echo "mpi run $name failed:"; tail -5 "$work/$name/stdout.txt"; return 1; }; }
  mpi pt_plain "${common[@]}" "${pt[@]}" -seed 7
  mpi pt_json "${common[@]}" "${pt[@]}" -seed 7 -resultJson r.json
  ok=1
  for ((r = 0; r < np; r++)); do
    cmp -s "$work/pt_plain/stats_N$r.tab" "$work/pt_json/stats_N$r.tab" || ok=0
    valid_json "$work/pt_json/r_N$r.json" "$r" "$np" "$((7 + r))" || ok=0
  done
  [ ! -e "$work/pt_json/r.json" ] || ok=0
  if [ "$ok" = 1 ]; then pass "$np-rank run unchanged, one result per rank"; else bad "$np-rank run unchanged, one result per rank"; fi
else
  echo "SKIP multi-rank check ($mpirun not found)"
fi

# 5. trajectory format
if python3 - "$work/vis7/lattice-trajectory-N0.tsv" <<'EOF'
import sys
lines = open(sys.argv[1]).read().splitlines()
assert lines[0] == "frame\t0", lines[0]
rows = [l.split("\t") for l in lines if not l.startswith("frame\t")]
assert rows and all(len(r) == 10 and r[9] in ("coil", "strand") for r in rows)
assert all(int(v) is not None for r in rows for v in (r[0], r[1], *r[3:9]))
EOF
then pass "-visualise trajectory format"; else bad "-visualise trajectory format"; fi

exit "$fail"
