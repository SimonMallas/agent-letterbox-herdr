#!/usr/bin/env bash
# Public-safe v0.3 confirmation/error privacy fixtures: every confirmation and
# error labels a letter by display-id (timestamp · token) — never a basename,
# slug, canary, or path. Includes the pre-mv label capture regression fixture
# (a post-move confirm would fall back to a filename-derived label). Neutral
# identities only.
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

box="$(mktemp -d "${TMPDIR:-/tmp}/lb-confirm.XXXXXX")"
LETTERBOX_DIR="$box" "$letterbox" init alpha beta >/dev/null

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

CANARY="canaryslugxyz-leaky-task"

write_letter() { # to from type req_ack id [filename-stem]
  local stem="${6:-$5}"
  cat > "$box/$1/inbox/${stem}.md" <<EOF
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
body $CANARY for $5
EOF
}

clean() { # name text — fail if the text leaks the canary or a .md filename
  local name="$1" text="$2"
  if [[ "$text" == *"$CANARY"* ]]; then
    fail "$name leaked canary: $text"
  elif [[ "$text" == *".md"* ]]; then
    fail "$name printed filename: $text"
  else
    pass "$name: no canary/filename"
  fi
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

echo "=== P1 file confirmations ==="

begin_block
FID="2026-08-15T080000-beta-info-${CANARY}-aaaa1111"
FDISP="2026-08-15T080000 · aaaa1111"
write_letter alpha beta info false "$FID"
fout="$(lb alpha file "$FID")"
[[ "$fout" == "filed: $FDISP → alpha/processed/" ]] || fail "P1-file-confirmation: $fout"
clean "P1 file confirmation" "$fout"
again="$(lb alpha file "$FID")"
[[ "$again" == "already filed: $FDISP" ]] || fail "P1-already-filed: $again"
clean "P1 already-filed" "$again"
set +e
fnf="$(lb alpha file "2026-08-15T080010-beta-info-${CANARY}-ffff0000" 2>&1)"
fec=$?
set -e
[[ "$fec" -ne 0 ]] || fail P1-not-found-exit
clean "P1 not-found error" "$fnf"
pass P1-file-confirmations

echo "=== P2 reply confirmations ==="

begin_block
RID="2026-08-15T080100-beta-delegate-${CANARY}-bbbb2222"
RDISP="2026-08-15T080100 · bbbb2222"
write_letter alpha beta delegate true "$RID"
aout="$(printf 'wip\n' | lb alpha reply "$RID" ack taking)"
[[ "$aout" == acked:\ "$RDISP"* ]] || fail "P2-ack-confirmation: $aout"
clean "P2 ack confirmation" "$aout"
cout="$(printf 'done\n' | lb alpha reply "$RID" result finished)"
[[ "$cout" == closed:\ "$RDISP"* ]] || fail "P2-closed-confirmation: $cout"
clean "P2 closed confirmation" "$cout"
ac="$(printf 'again\n' | lb alpha reply "$RID" result finished)"
[[ "$ac" == already\ closed:\ "$RDISP"* ]] || fail "P2-already-closed: $ac"
clean "P2 already-closed" "$ac"
pass P2-reply-confirmations

echo "=== P3 progress / nudge / done confirmations ==="

begin_block
PID="2026-08-15T080200-beta-request-${CANARY}-cccc3333"
PDISP="2026-08-15T080200 · cccc3333"
write_letter alpha beta request true "$PID"
printf 'ack_id: a\nacked_at: 2026-08-15T08:02:00Z\nby: alpha\n' > "$box/alpha/inbox/${PID}.md.ack"
pout="$(lb alpha progress "$PID" "mapping")"
[[ "$pout" == "progress: $PDISP" ]] || fail "P3-progress-confirmation: $pout"
clean "P3 progress confirmation" "$pout"
mv "$box/alpha/inbox/${PID}.md" "$box/alpha/processed/"
rm -f "$box/alpha/inbox/${PID}.md.ack"
set +e
perr="$(lb alpha progress "$PID" "too late" 2>&1)"
pec=$?
nerr="$(lb alpha nudge "$PID" 2>&1)"
nec=$?
set -e
[[ "$pec" -ne 0 ]] || fail P3-progress-terminal-exit
clean "P3 progress terminal error" "$perr"
[[ "$nec" -ne 0 ]] || fail P3-nudge-terminal-exit
clean "P3 nudge terminal error" "$nerr"
DID="2026-08-15T080300-beta-info-${CANARY}-dddd4444"
DDISP="2026-08-15T080300 · dddd4444"
write_letter alpha beta info false "$DID"
REPLY="${DID}--alpha--result"
cat > "$box/beta/inbox/${REPLY}.md" <<EOF
---
id: $REPLY
from: alpha
to: beta
type: result
re: $DID
priority: next
requires_ack: false
deadline:
---
legacy reply body
EOF
dout="$(lb alpha done "$DID" --reply "$box/beta/inbox/${REPLY}.md")"
[[ "$dout" == done:\ "$DDISP"* ]] || fail "P3-done-confirmation: $dout"
clean "P3 done confirmation" "$dout"
set +e
derr="$(lb alpha done "2026-08-15T080310-beta-info-${CANARY}-eeee5555" --reply missing 2>&1)"
dec=$?
set -e
[[ "$dec" -ne 0 ]] || fail P3-done-missing-exit
clean "P3 done not-found error" "$derr"
pass P3-operational-confirmations

echo "=== P4 pre-mv label capture (filename != frontmatter id) ==="

begin_block
WID="2026-08-15T090000-beta-info-${CANARY}-abc12345"
WDISP="2026-08-15T090000 · abc12345"
write_letter alpha beta info false "$WID" "handwritten-note"
wout="$(lb alpha file "$WID")"
[[ "$wout" == "filed: $WDISP → alpha/processed/" ]] || fail "P4-pre-mv-label: $wout"
clean "P4 pre-mv label" "$wout"
pass P4-label-captured-before-move

echo "=== confirm-privacy named mutations (fixtures must be able to fail) ==="

# M-confirm-basename: a basename-derived confirm label must break P1's canary fixture.
begin_block
mut="$(make_mutant confirm-basename)"
if mutate_line "$mut" '  display_id "$id"' '  basename "$f"'; then
  MID="2026-08-15T080400-beta-info-${CANARY}-abababab"
  write_letter alpha beta info false "$MID"
  mout="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" file "$MID")"
  if [[ "$mout" == *"$CANARY"* ]]; then
    pass "M-confirm-basename caught (mutant leaked the canary; P1 would fail)"
  else
    fail "M-confirm-basename SURVIVED: $mout"
  fi
else
  fail "M-confirm-basename mutation pattern missing"
fi

# M-postmv-label: capturing the label after the move must break P4 (the confirm
# falls back to a filename-derived label once the file is gone).
begin_block
mut="$(make_mutant postmv-label)"
if mutate_line "$mut" '  label="$(confirm_label "$msg")" # pre-move capture (post-move file is gone)' '  : # label capture removed' && \
   mutate_line "$mut" '  printf '"'"'filed: %s → %s/processed/\n'"'"' "$label" "$ME"' '  printf '"'"'filed: %s → %s/processed/\n'"'"' "$(confirm_label "$msg")" "$ME"'; then
  WID2="2026-08-15T090100-beta-info-${CANARY}-abc12346"
  WDISP2="2026-08-15T090100 · abc12346"
  write_letter alpha beta info false "$WID2" "handwritten-note-2"
  mout="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" file "$WID2")"
  if [[ "$mout" != "filed: $WDISP2 → alpha/processed/" ]]; then
    pass "M-postmv-label caught (mutant printed a post-move fallback label; P4 would fail)"
  else
    fail "M-postmv-label SURVIVED: $mout"
  fi
else
  fail "M-postmv-label mutation pattern missing"
fi

echo
echo "confirm-privacy v0.3: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
