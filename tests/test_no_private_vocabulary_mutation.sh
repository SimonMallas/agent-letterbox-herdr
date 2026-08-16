#!/usr/bin/env bash
# Mutation: the private-vocabulary gate must catch residue wherever it lands —
# visible file, hidden dotfile, and .github workflow — failing with file:line —
# and must PASS a clean tree. All expected-failure sub-run output is prefixed
# [mut] so a clean outer `make test` log is never mistaken for a real failure.
#
# Worktree-cleanliness contract: this harness must leave the REAL worktree
# index and tree untouched. The temp repo is built from `git archive HEAD` +
# a fresh `git init` — NEVER copy a worktree's .git (a linked worktree's .git
# is a pointer file; git commands in the copy then mutate the REAL index).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
gate_name="test_no_private_vocabulary.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/vocab-mut.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Record real-worktree state before doing anything.
before="$(git -C "$root" status --porcelain)"

# Independent throwaway repo: committed tree only, fresh .git directory.
mkdir -p "$tmp/repo"
git -C "$root" archive HEAD | tar -x -C "$tmp/repo"
git -C "$tmp/repo" init -q
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.name="mutation-harness" -c user.email="mutation-harness@local" \
  commit -qm "seed" --no-verify

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

# 5. Worktree/index cleanliness: the real worktree must be byte-identical
#    before and after — no staged, modified, or untracked accumulation.
after="$(git -C "$root" status --porcelain)"
if [[ "$after" == "$before" ]]; then
  echo "PASS: real worktree/index untouched by harness"
else
  echo "FAIL: worktree/index changed by harness:" >&2
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
  fails=$((fails+1))
fi
if printf '%s\n' "$after" | grep -q "residue"; then
  echo "FAIL: residue path present in real worktree status" >&2
  fails=$((fails+1))
fi

if [[ "$fails" -ne 0 ]]; then
  echo "vocabulary-gate mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "vocabulary-gate mutation: PASS"
exit 0
