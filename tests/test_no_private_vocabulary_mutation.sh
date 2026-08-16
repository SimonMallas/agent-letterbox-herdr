#!/usr/bin/env bash
# Mutation: the private-vocabulary gate must catch residue wherever it lands —
# visible file, hidden dotfile, and .github workflow — failing with file:line.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gate_name="test_no_private_vocabulary.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/vocab-mut.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Self-contained copy of the repo (including .git so ls-files enumeration runs).
cp -R "$root"/. "$tmp/repo/"

plant_and_run() { # $1 relative residue path
  local rel="$1" out rc
  mkdir -p "$tmp/repo/$(dirname "$rel")"
  printf 'residue tele''gram here\n' > "$tmp/repo/$rel"
  git -C "$tmp/repo" add "$rel" 2>/dev/null
  out="$(mktemp)"
  set +e
  ( cd "$tmp/repo" && "./tests/$gate_name" ) >"$out" 2>&1
  rc=$?
  set -e
  echo "--- residue at $rel → gate rc=$rc ---"
  cat "$out"
  git -C "$tmp/repo" rm -q --cached "$rel" 2>/dev/null || true
  rm -f "$tmp/repo/$rel"
  rm -f "$out"
  return "$rc"
}

fails=0
for rel in "docs/visible-residue.md" ".github/workflows/residue-ci.yml" ".hidden-residuerc"; do
  if plant_and_run "$rel"; then
    echo "FAIL: gate passed with residue at $rel" >&2
    fails=$((fails+1))
  fi
done

# file:line evidence on a representative visible-residue case
mkdir -p "$tmp/repo/docs"
printf 'residue tele''gram here\n' > "$tmp/repo/docs/visible-residue.md"
git -C "$tmp/repo" add docs/visible-residue.md 2>/dev/null
hit="$(cd "$tmp/repo" && "./tests/$gate_name" 2>&1 || true)"
if [[ "$hit" == *"docs/visible-residue.md:1:"* ]]; then
  echo "PASS: hit carries file:line"
else
  echo "FAIL: hit missing file:line: $hit" >&2
  fails=$((fails+1))
fi

if [[ "$fails" -ne 0 ]]; then
  echo "vocabulary-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "vocabulary-gate mutation: PASS"
exit 0
