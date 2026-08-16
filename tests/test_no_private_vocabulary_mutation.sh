#!/usr/bin/env bash
# Mutation: the private-vocabulary gate must catch residue wherever it lands —
# visible file, hidden dotfile, and .github workflow — failing with file:line —
# and must PASS a clean tree. All expected-failure sub-run output is prefixed
# [mut] so a clean outer `make test` log is never mistaken for a real failure.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gate_name="test_no_private_vocabulary.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/vocab-mut.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Self-contained copy of the repo (including .git so ls-files enumeration runs).
cp -R "$root"/. "$tmp/repo/"

run_gate() { # prints gate output with [mut] prefix; returns gate rc
  local out rc
  out="$(mktemp)"
  set +e
  ( cd "$tmp/repo" && "./tests/$gate_name" ) >"$out" 2>&1
  rc=$?
  set -e
  sed 's/^/[mut] | /' "$out"
  rm -f "$out"
  return "$rc"
}

fails=0

# 0. Clean tree must PASS (explicit assertion — a gate that fails green trees
#    is as broken as one that passes residue).
if run_gate; then
  echo "PASS: clean tree passes the gate"
else
  echo "FAIL: gate fails on a clean tree" >&2
  fails=$((fails+1))
fi

plant_and_run() { # $1 relative residue path
  local rel="$1" rc
  mkdir -p "$tmp/repo/$(dirname "$rel")"
  # Forbidden token built from parts so THIS file is not itself a residue hit.
  printf 'residue tele''gram here\n' > "$tmp/repo/$rel"
  git -C "$tmp/repo" add -f "$rel" 2>/dev/null || true
  set +e
  run_gate
  rc=$?
  set -e
  git -C "$tmp/repo" rm -q --cached "$rel" 2>/dev/null || true
  rm -f "$tmp/repo/$rel"
  return "$rc"
}

# 1-3. Residue mutations: visible / .github workflow / hidden dotfile.
for rel in "docs/visible-residue.md" ".github/workflows/residue-ci.yml" ".hidden-residuerc"; do
  if plant_and_run "$rel"; then
    echo "FAIL: gate passed with residue at $rel" >&2
    fails=$((fails+1))
  else
    echo "PASS: gate failed on residue at $rel"
  fi
done

# 4. Hits must carry file:line (representative visible-residue case).
mkdir -p "$tmp/repo/docs"
printf 'residue tele''gram here\n' > "$tmp/repo/docs/visible-residue.md"
git -C "$tmp/repo" add -f docs/visible-residue.md 2>/dev/null || true
hit="$(cd "$tmp/repo" && "./tests/$gate_name" 2>&1 || true)"
if [[ "$hit" == *"docs/visible-residue.md:1:"* ]]; then
  echo "PASS: hit carries file:line"
else
  printf '%s\n' "$hit" | sed 's/^/[mut] | /'
  echo "FAIL: hit missing file:line" >&2
  fails=$((fails+1))
fi

if [[ "$fails" -ne 0 ]]; then
  echo "vocabulary-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "vocabulary-gate mutation: PASS"
exit 0
