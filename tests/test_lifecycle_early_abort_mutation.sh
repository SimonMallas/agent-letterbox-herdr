#!/usr/bin/env bash
# Mutation: an early-aborted lifecycle suite must never green-wash.
# For BOTH lifecycle suites (v0.2 + v0.3) and BOTH abort shapes:
#   exit0 — silent early success exit (catches the Makefile footer gate)
#   abort — set -e death after assertion 1 (catches the suite EXIT trap gate)
# Each must produce a non-zero, explicit incomplete/count/footer failure.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

fails=0
check_suite() { # $1 suite path, $2 version tag, $3 footer
  local suite="$1" ver="$2" footer="$3" mode out rc
  for mode in exit0 abort; do
    out="$(mktemp)"
    set +e
    LETTERBOX_MUTATE_EARLY_ABORT="$mode" "$suite" >"$out" 2>&1
    rc=$?
    set -e
    echo "--- $ver mutation ($mode) rc=$rc ---"

    if [[ "$rc" -eq 0 ]]; then
      # Silent early exit: the suite alone cannot fail here — the footer gate must.
      if grep -qxF "$footer" "$out"; then
        echo "FAIL: $ver $mode printed success footer despite early exit" >&2
        fails=$((fails+1))
      else
        echo "PASS: $ver $mode silent exit carries no success footer (footer gate catches it)"
      fi
    else
      # Trap gate converted the abort into an explicit non-zero incomplete failure.
      if grep -qxF "$footer" "$out"; then
        echo "FAIL: $ver $mode printed success footer" >&2
        fails=$((fails+1))
      elif ! grep -qE "lifecycle ${ver}: FAIL \(early abort|pass count|incomplete" "$out"; then
        echo "FAIL: $ver $mode missing explicit count/footer failure" >&2
        fails=$((fails+1))
      else
        echo "PASS: $ver $mode abort → explicit non-zero incomplete failure"
      fi
    fi

    # Must not have run past the first assertion block.
    if grep -qF "V2-" "$out" || grep -qF "B2-" "$out"; then
      echo "FAIL: $ver $mode mutation ran past first assertion block" >&2
      fails=$((fails+1))
    fi
    # Mutation hook must have fired.
    if ! grep -qF "MUTATION:" "$out"; then
      echo "FAIL: $ver $mode mutation hook did not fire" >&2
      fails=$((fails+1))
    fi
    rm -f "$out"
  done
}

check_suite "$root/tests/test_lifecycle_v02.sh" "v0.2" "lifecycle v0.2: PASS"
check_suite "$root/tests/test_lifecycle_v03.sh" "v0.3" "lifecycle v0.3: PASS"

if [[ "$fails" -ne 0 ]]; then
  echo "lifecycle early-abort mutation: FAIL ($fails)" >&2
  exit 1
fi
echo "lifecycle early-abort mutation: PASS"
exit 0
