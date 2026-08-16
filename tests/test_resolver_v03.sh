#!/usr/bin/env bash
# Public-safe v0.3 action-reference resolver fixtures: full id, display-id, and
# unique bare 8-hex token resolve across verbs; an ambiguous token lists
# display-ids and takes NO action (first-match resolution forbidden); the full
# id is always an escape hatch. Neutral identities only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
PASS=0
FAIL=0
BLOCK_FAILED=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
  BLOCK_FAILED=1
  return 0
}
pass() {
  if [[ "$BLOCK_FAILED" == 1 ]]; then
    echo "BLOCK FAILED: $*" >&2
    BLOCK_FAILED=0
    return 0
  fi
  echo "PASS: $*"
  PASS=$((PASS + 1))
}
begin_block() { BLOCK_FAILED=0; }

box=""
cleanup() {
  if [[ -n "${box:-}" && -d "$box" ]]; then
    rm -rf "$box"
  fi
  return 0
}
trap cleanup EXIT

box="$(mktemp -d "${TMPDIR:-/tmp}/lb-resolver.XXXXXX")"
LETTERBOX_DIR="$box" "$letterbox" init alpha beta gamma >/dev/null

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

write_letter() { # to from type req_ack id
  cat > "$box/$1/inbox/${5}.md" <<EOF
---
id: $5
from: $2
to: $1
type: $3
re:
priority: now
requires_ack: $4
deadline:
---
body for $5
EOF
}

make_mutant() {
  local dst="$box/mut-$1"
  mkdir -p "$dst"
  cp "$letterbox" "$dst/letterbox"
  chmod +x "$dst/letterbox"
  printf '%s\n' "$dst/letterbox"
}

mutate_line() { # $1=file $2=old-exact-line $3=new-exact-line
  local f="$1"
  OLD="$2" NEW="$3" awk '
    $0 == ENVIRON["OLD"] && !done { print ENVIRON["NEW"]; done=1; next }
    { print }
    END { if (!done) exit 3 }
  ' "$f" > "$f.muttmp" || { rm -f "$f.muttmp"; return 3; }
  mv "$f.muttmp" "$f"
  chmod +x "$f"
}

echo "=== R1 reference forms resolve across verbs ==="

begin_block
LID="2026-08-15T070000-beta-info-leaky-slug-abcd1234"
DISP="2026-08-15T070000 · abcd1234"
write_letter alpha beta info false "$LID"
printf 'ack_id: a\nacked_at: 2026-08-15T07:00:00Z\nby: alpha\n' > "$box/alpha/inbox/${LID}.md.ack"
lb alpha read "$LID" | grep -q "^id: $LID$" || fail R1-full-id-read
lb alpha read "$DISP" | grep -q "^id: $LID$" || fail R1-display-id-read
lb alpha read abcd1234 | grep -q "^id: $LID$" || fail R1-token-read
[[ "$(lb alpha progress "$LID" via-full)" == "progress: $DISP" ]] || fail R1-full-id-progress
[[ "$(lb alpha progress "$DISP" via-disp)" == "progress: $DISP" ]] || fail R1-display-id-progress
[[ "$(lb alpha progress abcd1234 via-tok)" == "progress: $DISP" ]] || fail R1-token-progress
lb alpha file "$DISP" >/dev/null
[[ -f "$box/alpha/processed/${LID}.md" ]] || fail R1-display-id-file
pass R1-reference-forms

begin_block
REQ="2026-08-15T070100-beta-request-leaky-slug-eeee5555"
write_letter alpha beta request false "$REQ"
printf 'ok\n' | lb alpha reply "2026-08-15T070100 · eeee5555" result r1 >/dev/null
[[ -f "$box/alpha/processed/${REQ}.md" ]] || fail R1-display-id-reply
REQ2="2026-08-15T070130-beta-request-leaky-slug-cccc3333"
write_letter alpha beta request false "$REQ2"
printf 'ok2\n' | lb alpha reply cccc3333 result r2 >/dev/null
[[ -f "$box/alpha/processed/${REQ2}.md" ]] || fail R1-token-reply
pass R1-display-id-and-token-reply

echo "=== R2 scope and path rules ==="

begin_block
PEER="2026-08-15T081000-alpha-request-leaky-slug-bbbb2222"
write_letter beta alpha request true "$PEER"
if lb alpha read bbbb2222 2>"$box/err"; then
  fail R2-own-inbox-read-leaked-peer
else
  grep -q 'not found in your inbox' "$box/err" || fail "R2-peer-message: $(cat "$box/err")"
fi
TARGET="2026-08-15T081100-beta-info-leaky-slug-ffff0001"
write_letter alpha beta info false "$TARGET"
if lb alpha read "$box/alpha/inbox/${TARGET}.md" 2>"$box/err"; then
  fail R2-read-accepted-path
else
  grep -q 'not a path' "$box/err" || fail "R2-path-message: $(cat "$box/err")"
fi
pass R2-read-scope

echo "=== R3 collision: no first-match resolution, no state change ==="

begin_block
C1="2026-08-15T080000-beta-info-leaky-slug-deadbeef"
C2="2026-08-01T090000-gamma-info-leaky-slug-deadbeef"
write_letter alpha beta info false "$C1"
write_letter alpha gamma info false "$C2"
before="$(find "$box/alpha" -type f | sort | cksum)"
set +e
lb alpha read deadbeef >/dev/null 2>"$box/err.read"; ec_read=$?
lb alpha file deadbeef >/dev/null 2>"$box/err.file"; ec_file=$?
printf 'x\n' | lb alpha reply deadbeef result x >/dev/null 2>"$box/err.reply"; ec_reply=$?
lb alpha progress deadbeef no >/dev/null 2>"$box/err.progress"; ec_progress=$?
lb alpha nudge deadbeef >/dev/null 2>"$box/err.nudge"; ec_nudge=$?
set -e
after="$(find "$box/alpha" -type f | sort | cksum)"
ok=1
for ec in "$ec_read" "$ec_file" "$ec_reply" "$ec_progress" "$ec_nudge"; do
  [[ "$ec" -ne 0 ]] || ok=0
done
[[ "$ok" == 1 ]] || fail "R3 collision exit codes: $ec_read $ec_file $ec_reply $ec_progress $ec_nudge"
[[ "$before" == "$after" ]] || fail R3-collision-changed-state
grep -q 'ambiguous reference' "$box/err.read" || fail "R3-collision-message: $(cat "$box/err.read")"
grep -q '2026-08-15T080000 · deadbeef' "$box/err.read" || fail R3-collision-list-missing-1
grep -q '2026-08-01T090000 · deadbeef' "$box/err.read" || fail R3-collision-list-missing-2
if grep -q 'leaky-slug' "$box/err.read" "$box/err.file" "$box/err.reply" "$box/err.progress" "$box/err.nudge"; then
  fail R3-collision-leaked-slug
fi
pass R3-collision-refuses-all-verbs

# full id is always an escape hatch
begin_block
lb alpha file "$C1" >/dev/null
[[ -f "$box/alpha/processed/${C1}.md" ]] || fail R4-escape-not-filed
pass R4-full-id-escape-hatch

echo "=== R5 nudge scope: any participant open letter; terminal refuses ==="

begin_block
# PEER sits in beta's inbox; alpha may re-ring it (no adapter configured → silent no-op ring)
before="$(find "$box" -name '*.md' | wc -l | tr -d ' ')"
lb alpha nudge bbbb2222 >/dev/null
after="$(find "$box" -name '*.md' | wc -l | tr -d ' ')"
[[ "$before" == "$after" ]] || fail R5-nudge-changed-count
[[ -f "$box/beta/inbox/${PEER}.md" ]] || fail R5-nudge-moved-letter
if lb alpha nudge "$C1" 2>"$box/err"; then
  fail R5-nudge-filed-accepted
else
  grep -q 'filed/terminal' "$box/err" || fail "R5-nudge-message: $(cat "$box/err")"
fi
pass R5-nudge-scope

echo "=== resolver named mutation ==="

# M-first-match: dropping the ambiguity refusal must let `read deadbeef` take
# the first hit — the R3 fixture assertions would then fail.
begin_block
write_letter alpha beta info false "$C1"
mut="$(make_mutant first-match)"
if mutate_line "$mut" '  if (( ${#hits[@]} > 1 )); then' '  if false && (( ${#hits[@]} > 1 )); then'; then
  set +e
  LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" read deadbeef >/dev/null 2>&1
  mut_ec=$?
  set -e
  if [[ "$mut_ec" -eq 0 ]]; then
    pass "M-first-match caught (mutant resolved a collided token; R3 would fail)"
  else
    fail "M-first-match SURVIVED (mutant still refuses, ec=$mut_ec)"
  fi
else
  fail "M-first-match mutation pattern missing"
fi

echo
echo "resolver v0.3: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
