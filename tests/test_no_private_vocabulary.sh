#!/usr/bin/env bash
# Mandatory private-vocabulary sweep (public product cleanliness).
# Separate from personal-data privacy tests. Baseline identical across
# agent-letterbox-{cmux,tmux,herdr,zellij} public v0.3 ports.
#
# Fails make test with offending file:line for internal/private porting residue.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
self_name="$(basename "$0")"

# Paths scanned (product surface only). This script is excluded from hits.
paths=(
  bin
  adapters
  docs
  Makefile
  SPEC.md
  README.md
  skills
)
for opt in CHANGELOG.md ROADMAP.md SECURITY.md CONTRIBUTING.md VERSION; do
  [[ -e "$opt" ]] && paths+=("$opt")
done
# tests/ except this gate file (patterns live here by necessity)
shopt -s nullglob
for t in tests/*; do
  base="$(basename "$t")"
  [[ "$base" == "$self_name" ]] && continue
  paths+=("$t")
done
shopt -u nullglob

# Forbidden tokens (fixed baseline — do not weaken per-port).
# Built from parts so this file is not a self-hit if ever scanned.
patterns=(
  "shared""-brain"
  "bus ""doorbell"
  "BUS_""AGENT"
  "BUS_""DIR"
  "tele""gram"
  "launch""d"
  "kimik""357"
  "utc_""now"
)

search() {
  local pat="$1"
  shift
  # grep only: rg -I means --no-filename (hits would lack the required
  # file:line) and rg skips hidden files by default (dotfile residue would
  # escape). grep -RFnI covers both: filename:line output, hidden files included.
  grep -RFnI -- "$pat" "$@" 2>/dev/null || true
}

fails=0
echo "private-vocabulary sweep: scanning product paths..."

for pat in "${patterns[@]}"; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Skip this gate file if it appears
    case "$line" in
      *"/tests/$self_name:"*|"tests/$self_name:"*) continue;;
    esac
    echo "FAIL: private vocabulary '$pat' at $line" >&2
    fails=$((fails+1))
  done < <(search "$pat" "${paths[@]}")
done

if (( fails > 0 )); then
  printf 'private-vocabulary: FAIL (%d hit(s))\n' "$fails" >&2
  exit 1
fi

echo "private-vocabulary: PASS (no forbidden tokens in product paths)"
exit 0
