#!/usr/bin/env bash
# Mandatory private-vocabulary sweep (public product cleanliness).
# Separate from personal-data privacy tests. Baseline identical across
# agent-letterbox-{cmux,tmux,herdr,zellij} public v0.3 ports.
#
# Scans EVERY tracked file (git ls-files; find fallback outside git) —
# hidden files, dotted root dirs, and CI workflows included. Fails with
# file:line for internal/private porting residue.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
self_name="$(basename "$0")"

# Forbidden tokens (fixed baseline — do not weaken per-port).
# Built from parts so this file is not a self-hit when scanned.
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

# Every tracked file, null-delimited (spaces in names survive). Outside a git
# work tree, fall back to a find walk (still includes dotted/hidden files).
files=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do files+=("$f"); done < <(git ls-files -z)
else
  while IFS= read -r -d '' f; do files+=("${f#./}"); done \
    < <(find . -path ./.git -prune -o -type f -print0)
fi
if (( ${#files[@]} == 0 )); then
  echo "private-vocabulary: FAIL (no files enumerable)" >&2
  exit 1
fi

fails=0
echo "private-vocabulary sweep: scanning ${#files[@]} tracked file(s)..."
for f in "${files[@]}"; do
  [[ "$f" == "tests/$self_name" ]] && continue
  [[ -f "$f" ]] || continue
  for pat in "${patterns[@]}"; do
    # grep only, per file: -H keeps the filename on every hit (file:line),
    # -I skips binaries, hidden files are covered because enumeration is explicit.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "FAIL: private vocabulary '$pat' at $line" >&2
      fails=$((fails+1))
    done < <(grep -nFHI -- "$pat" "$f" 2>/dev/null || true)
  done
done

if (( fails > 0 )); then
  printf 'private-vocabulary: FAIL (%d hit(s))\n' "$fails" >&2
  exit 1
fi

echo "private-vocabulary: PASS (${#files[@]} files scanned, no forbidden tokens)"
exit 0
