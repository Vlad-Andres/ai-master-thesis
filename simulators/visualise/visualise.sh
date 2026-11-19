#!/usr/bin/env bash
# Run a short simulation with -visualise and open the trajectory in the browser.
#
#   visualise/visualise.sh SIM STRUCTURE [extra simulator flags...]
#
# Every Monte Carlo step becomes a frame, so STEPS and ROUNDS default to small
# values (50 and 2). The other environment variables are the same as for run.sh.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 2 ] || { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

result="$(STEPS="${STEPS:-50}" ROUNDS="${ROUNDS:-2}" "$here/../run.sh" "$@" -visualise)"
out="$(dirname "$result")"
page="$out/lattice-viewer.html"

# Put the trajectory in place of the <!-- trajectory --> placeholder, escaping & and <.
awk -v trace="$out/lattice-trajectory-N0.tsv" '
  {
    i = index($0, "<!-- trajectory -->")
    if (!i) { print; next }
    printf "%s", substr($0, 1, i - 1)
    while ((getline line < trace) > 0) {
      gsub(/&/, "\\&amp;", line); gsub(/</, "\\&lt;", line)
      print line
    }
    print substr($0, i + length("<!-- trajectory -->"))
  }' "$here/lattice-viewer.html" > "$page"

echo "$page"
if command -v open > /dev/null; then
  open "$page"
elif command -v xdg-open > /dev/null; then
  xdg-open "$page"
fi
