#!/usr/bin/env bash
# test_private_vocabulary.sh — private-porting-residue gate (release blocker).
#
# Separate from test_no_private_data.sh (which catches personal data/secrets).
# This gate catches vocabulary that only ever belonged to the private
# implementation: if any of these strings appear in shipped product files, a
# private assumption leaked into the public product. Fails with file:line.
#
# Ships with GENERIC patterns only; keep this baseline identical across ports.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
self="tests/$(basename "$0")"

# Private-implementation residue. Case-insensitive: product names leak in any
# case, and a public tree must not mention them at all.
PATTERN='shared-brain|bus doorbell|BUS_AGENT|BUS_DIR|telegram|launchd|kimik357|utc_now'

# Product files in scope (tracked or not — a work-in-progress leak must fail too).
scope="bin adapters tests docs Makefile SPEC.md README.md skills"

fails=0
out="$(grep -rInE -- "$PATTERN" $scope 2>/dev/null | grep -v "^$self:" || true)"
if [[ -n "$out" ]]; then
  printf 'FAIL [private-vocabulary] residue found (file:line):\n%s\n' "$out" >&2
  fails=$((fails + 1))
fi

if (( fails > 0 )); then
  printf 'private-vocabulary: FAIL (%d pattern group(s) hit)\n' "$fails" >&2
  exit 1
fi
printf 'private-vocabulary: PASS\n'
