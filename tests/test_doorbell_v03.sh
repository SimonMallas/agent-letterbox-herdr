#!/usr/bin/env bash
# Public-safe v0.3 doorbell fixtures: additive token in the knock line (v0.2
# byte-prefix preserved, both shapes accepted), canary-slug negative fixtures,
# outcome vocabulary (submitted | pasted_not_submitted | no_live_surface —
# never read/turn_started), nudge re-ring, bounded adapter timeout, and the
# token resolution verb. Neutral identities only; herdr is mocked.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
adapter="$root/adapters/herdr.sh"
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

box="$(mktemp -d "${TMPDIR:-/tmp}/lb-doorbell.XXXXXX")"
LETTERBOX_DIR="$box" "$letterbox" init alpha beta gamma >/dev/null

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

CANARY="canaryslugxyz-leaky-task"
V02_PREFIX='📬 letterbox doorbell: unacked '
V02_TAIL=' — please check'

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
body $CANARY for $5
EOF
}

str_sha8() { # portable sha256[:8] of a string
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print substr($1,1,8)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print substr($1,1,8)}'
  else
    printf '%s' "$1" | openssl dgst -sha256 | awk '{print substr($NF,1,8)}'
  fi
}

# Mock adapter: records argv, one line per ring.
ADAPTER_LOG="$box/adapter.log"
: > "$ADAPTER_LOG"
cat > "$box/mock-adapter.sh" <<'SH'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" >> "${ADAPTER_LOG:?}"
SH
chmod +x "$box/mock-adapter.sh"

# Mock herdr: records calls; pane get succeeds; send-text/send-keys fail on demand.
MOCK_LOG="$box/herdr.log"
: > "$MOCK_LOG"
cat > "$box/herdr-mock" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
if [[ "$1" == "pane" && "$2" == "get" ]]; then exit 0; fi
if [[ "${MOCK_SEND_TEXT_FAIL:-0}" == 1 && "$1 $2" == "pane send-text" ]]; then exit 1; fi
if [[ "${MOCK_ENTER_FAIL:-0}" == 1 && "$1 $2" == "pane send-keys" ]]; then exit 1; fi
exit 0
SH
chmod +x "$box/herdr-mock"
printf 'reviewer\t%%1\n' > "$box/herdr-patterns.tsv"

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

echo "=== D1 helper passes the letter token to the adapter ==="

begin_block
: > "$ADAPTER_LOG"
sent="$(printf 'body %s\n' "$CANARY" | LETTERBOX_DOORBELL="$box/mock-adapter.sh" ADAPTER_LOG="$ADAPTER_LOG" \
  lb alpha send beta info "$CANARY" --now)"
sent_id="$(basename "${sent#sent: }" .md)"
ring1="$(tail -1 "$ADAPTER_LOG")"
[[ "${ring1%%|*}" == "beta" ]] || fail "D1-recipient: $ring1"
tok1="$(printf '%s' "$ring1" | awk -F'|' '{print $4}')"
[[ "$tok1" == "${sent_id##*-}" ]] || fail "D1-token-tail: $tok1 vs ${sent_id##*-}"
[[ "$tok1" =~ ^[0-9a-f]{8}$ ]] || fail "D1-token-shape: $tok1"
# a task letter with a canary slug rings for ack with the REPLY id's sha256 token
printf 'task body\n' | lb alpha send beta delegate "$CANARY" --ack >/dev/null
task_id="$(basename "$(find "$box/beta/inbox" -name "*-delegate-$CANARY*.md" -print -quit)" .md)"
: > "$ADAPTER_LOG"
printf 'accepted\n' | LETTERBOX_DOORBELL="$box/mock-adapter.sh" ADAPTER_LOG="$ADAPTER_LOG" \
  lb beta reply "$task_id" ack reply-slug --now >/dev/null
reply_file="$(find "$box/alpha/inbox" -name '*--beta--ack.md' -print -quit)"
reply_id="$(awk -F': ' '$1 == "id" { print $2; exit }' "$reply_file")"
tok2="$(tail -1 "$ADAPTER_LOG" | awk -F'|' '{print $4}')"
[[ "$tok2" == "$(str_sha8 "$reply_id")" ]] || fail "D1-derived-token: $tok2 vs $(str_sha8 "$reply_id")"
if tail -1 "$ADAPTER_LOG" | awk -F'|' '{print $4}' | grep -q "$CANARY"; then
  fail D1-token-leaked-canary
fi
pass D1-token-flows-through-adapter

echo "=== D2 knock line grammar: additive token, v0.2 prefix preserved ==="

begin_block
: > "$MOCK_LOG"
HERDR_BIN_PATH="$box/herdr-mock" MOCK_LOG="$MOCK_LOG" \
  LETTERBOX_DIR="$box" LETTERBOX_HERDR_PATTERNS="$box/herdr-patterns.tsv" \
  LETTERBOX_HERDR_SUBMIT=1 \
  "$adapter" reviewer delegate "$CANARY" abcd1234 >/dev/null
line="$(sed -n 's/^pane send-text [^ ]* //p' "$MOCK_LOG")"
want="$V02_PREFIX"'delegate'" in $box/reviewer/inbox/$V02_TAIL"' · abcd1234'
[[ "$line" == "$want" ]] || fail "D2-line-shape: $line"
if [[ "$line" == *"$CANARY"* ]]; then
  fail "D2-canary-in-line: $line"
fi
# tokenless call emits exactly the v0.2 line (old peers see no change)
: > "$MOCK_LOG"
HERDR_BIN_PATH="$box/herdr-mock" MOCK_LOG="$MOCK_LOG" \
  LETTERBOX_DIR="$box" LETTERBOX_HERDR_PATTERNS="$box/herdr-patterns.tsv" \
  LETTERBOX_HERDR_SUBMIT=1 \
  "$adapter" reviewer delegate "$CANARY" >/dev/null
line_v02="$(sed -n 's/^pane send-text [^ ]* //p' "$MOCK_LOG")"
want_v02="$V02_PREFIX"'delegate'" in $box/reviewer/inbox/$V02_TAIL"
[[ "$line_v02" == "$want_v02" ]] || fail "D2-v02-line-drift: $line_v02"
# old prefix/pattern guidance accepts the new token-bearing line (additive)
case "$line" in
  "$V02_PREFIX"*"$V02_TAIL"*) ;;
  *) fail "D2-old-pattern-rejects-v03: $line";;
esac
# hazard detector: an exact full-line equality rule would reject the new shape
[[ "$line" != "$want_v02" ]] || fail D2-hazard-undetectable
# a tokenless line still satisfies the same pattern (both shapes accepted)
case "$line_v02" in
  "$V02_PREFIX"*"$V02_TAIL"*) ;;
  *) fail "D2-pattern-rejects-v02: $line_v02";;
esac
# the skill guidance carries the dual-acceptance rule and names the hazard
grep -qi 'exact full-line equality' "$root/skills/agent-letterbox/SKILL.md" || fail D2-skill-hazard-wording
grep -q 'BLOCK' "$root/skills/agent-letterbox/SKILL.md" || fail D2-skill-block-wording
grep -q 'please check · ' "$root/skills/agent-letterbox/SKILL.md" || fail D2-skill-token-shape
pass D2-knock-grammar

echo "=== D3 outcome vocabulary ==="

begin_block
: > "$MOCK_LOG"
out="$(HERDR_BIN_PATH="$box/herdr-mock" MOCK_LOG="$MOCK_LOG" MOCK_ENTER_FAIL=1 \
  LETTERBOX_DIR="$box" LETTERBOX_HERDR_PATTERNS="$box/herdr-patterns.tsv" \
  LETTERBOX_HERDR_SUBMIT=1 "$adapter" reviewer delegate smoke-test abcd1234)"
[[ "$out" == *pasted_not_submitted* ]] || fail "D3-pasted: $out"
out2="$(HERDR_BIN_PATH="$box/herdr-mock" MOCK_LOG="$MOCK_LOG" MOCK_SEND_TEXT_FAIL=1 \
  LETTERBOX_DIR="$box" LETTERBOX_HERDR_PATTERNS="$box/herdr-patterns.tsv" \
  LETTERBOX_HERDR_SUBMIT=1 "$adapter" reviewer delegate smoke-test abcd1234)"
[[ "$out2" == *no_live_surface* && "$out2" == *send_failed* ]] || fail "D3-send-failed: $out2"
out3="$(HERDR_BIN_PATH="$box/no-such-herdr" LETTERBOX_DIR="$box" "$adapter" reviewer delegate smoke-test abcd1234 2>&1)"
[[ "$out3" == *'herdr is unavailable'* ]] || fail "D3-unavailable: $out3"
out4="$(HERDR_BIN_PATH="$box/herdr-mock" MOCK_LOG="$MOCK_LOG" \
  LETTERBOX_DIR="$box" LETTERBOX_HERDR_PATTERNS="$box/empty-patterns.tsv" \
  LETTERBOX_HERDR_SUBMIT=1 "$adapter" gamma delegate smoke-test abcd1234 2>&1)"
[[ "$out4" == *'no live herdr pane'* ]] || fail "D3-no-pane: $out4"
if printf '%s\n%s\n%s\n%s\n' "$out" "$out2" "$out3" "$out4" | grep -Eqw 'read|turn_started'; then
  fail D3-forbidden-vocabulary
fi
pass D3-outcome-vocabulary

echo "=== D4 nudge re-rings an open letter, creates nothing ==="

begin_block
: > "$ADAPTER_LOG"
NID="2026-08-15T090000-alpha-request-${CANARY}-bbbb2222"
write_letter beta alpha request true "$NID"
before="$(find "$box" -name '*.md' | wc -l | tr -d ' ')"
LETTERBOX_DOORBELL="$box/mock-adapter.sh" ADAPTER_LOG="$ADAPTER_LOG" lb gamma nudge "$NID"
after="$(find "$box" -name '*.md' | wc -l | tr -d ' ')"
[[ "$before" == "$after" ]] || fail D4-nudge-changed-count
[[ -f "$box/beta/inbox/${NID}.md" ]] || fail D4-nudge-moved-letter
ring="$(tail -1 "$ADAPTER_LOG")"
[[ "${ring%%|*}" == "beta" ]] || fail "D4-nudge-recipient: $ring"
[[ "$(printf '%s' "$ring" | awk -F'|' '{print $4}')" == "bbbb2222" ]] || fail "D4-nudge-token: $ring"
[[ "$(printf '%s' "$ring" | awk -F'|' '{print $3}')" == "" ]] || fail "D4-nudge-no-slug-arg: $ring"
mv "$box/beta/inbox/${NID}.md" "$box/beta/processed/"
if LETTERBOX_DOORBELL="$box/mock-adapter.sh" ADAPTER_LOG="$ADAPTER_LOG" lb gamma nudge "$NID" 2>"$box/err"; then
  fail D4-nudge-filed-accepted
else
  grep -q 'filed/terminal' "$box/err" || fail "D4-nudge-message: $(cat "$box/err")"
fi
pass D4-nudge

echo "=== D5 bounded adapter timeout (letter already durable) ==="

begin_block
if command -v python3 >/dev/null 2>&1; then
  cat > "$box/hang-adapter.sh" <<'SH'
#!/usr/bin/env bash
sleep 30
SH
  chmod +x "$box/hang-adapter.sh"
  start="$(date +%s)"
  out="$(printf 'durable body\n' | LETTERBOX_DOORBELL="$box/hang-adapter.sh" LETTERBOX_DOORBELL_TIMEOUT=1 \
    lb alpha send beta request hang-proof --now 2>&1)"
  end="$(date +%s)"
  [[ "$out" == *sent:* ]] || fail "D5-not-sent: $out"
  [[ "$out" == *'no_live_surface adapter_timeout'* ]] || fail "D5-timeout-outcome: $out"
  [[ -n "$(find "$box/beta/inbox" -name '*hang-proof*.md' -print -quit)" ]] || fail D5-letter-lost
  (( end - start < 6 )) || fail "D5-not-bounded: $((end - start))s"
  pass D5-bounded-timeout
else
  echo "SKIP: D5 bounded timeout (python3 unavailable)"
fi

echo "=== D6 token verb resolves a knock ==="

begin_block
TFRESH="2026-08-15T091000-alpha-info-${CANARY}-aaaa0001"
write_letter beta alpha info false "$TFRESH"
[[ "$(lb beta token aaaa0001)" == "unhandled — check" ]] || fail "D6-fresh: $(lb beta token aaaa0001)"
mv "$box/beta/inbox/${TFRESH}.md" "$box/beta/processed/"
[[ "$(lb beta token aaaa0001)" == "already filed — dismiss knock" ]] || fail "D6-filed: $(lb beta token aaaa0001)"
[[ "$(lb beta token ffffffff)" == "unknown-token — no letter; ignore" ]] || fail "D6-unknown: $(lb beta token ffffffff)"
TC1="2026-08-15T092000-alpha-request-${CANARY}-deadbeef"
TC2="2026-08-01T093000-gamma-info-${CANARY}-deadbeef"
write_letter beta alpha request false "$TC1"
write_letter gamma alpha info false "$TC2"
mv "$box/gamma/inbox/${TC2}.md" "$box/gamma/processed/"
set +e
coll="$(lb alpha token deadbeef 2>&1)"
coll_ec=$?
set -e
[[ "$coll_ec" -ne 0 ]] || fail D6-collision-exit
printf '%s\n' "$coll" | grep -q 'ambiguous-token — no dismiss, no ring' || fail "D6-collision-message: $coll"
printf '%s\n' "$coll" | grep -q '2026-08-15T092000 · deadbeef' || fail D6-collision-list-1
printf '%s\n' "$coll" | grep -q '2026-08-01T093000 · deadbeef' || fail D6-collision-list-2
if printf '%s\n' "$coll" | grep -q "$CANARY"; then
  fail D6-collision-leaked-canary
fi
pass D6-token-verb

echo "=== doorbell named mutations (fixtures must be able to fail) ==="

# M-token-drop: dropping the token argument must break D1.
begin_block
mut="$(make_mutant token-drop)"
if mutate_line "$mut" '  [[ -n "$id" ]] && token="$(doorbell_token_for_id "$id")"' '  token=""'; then
  : > "$ADAPTER_LOG"
  printf 'body\n' | LETTERBOX_DOORBELL="$box/mock-adapter.sh" ADAPTER_LOG="$ADAPTER_LOG" \
    LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" send beta info mut-drop --now >/dev/null
  if [[ -z "$(tail -1 "$ADAPTER_LOG" | awk -F'|' '{print $4}')" ]]; then
    pass "M-token-drop caught (mutant rang without a token; D1 would fail)"
  else
    fail "M-token-drop SURVIVED"
  fi
else
  fail "M-token-drop mutation pattern missing"
fi

# M-slug-leak: deriving the token from the full id must break the D1/D2 canary fixtures.
begin_block
mut="$(make_mutant slug-leak)"
if mutate_line "$mut" '    printf '"'%s\n'"' "$tail"' '    printf '"'%s\n'"' "$id"'; then
  : > "$ADAPTER_LOG"
  printf 'body\n' | LETTERBOX_DOORBELL="$box/mock-adapter.sh" ADAPTER_LOG="$ADAPTER_LOG" \
    LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" send beta info "$CANARY" --now >/dev/null
  if tail -1 "$ADAPTER_LOG" | awk -F'|' '{print $4}' | grep -q "$CANARY"; then
    pass "M-slug-leak caught (mutant leaked the canary slug into the token; D1 would fail)"
  else
    fail "M-slug-leak SURVIVED"
  fi
else
  fail "M-slug-leak mutation pattern missing"
fi

# M-nudge-creates-letter: a nudge that writes must break D4's no-new-letter assertion.
begin_block
mut="$(make_mutant nudge-creates)"
if mutate_line "$mut" '  ring_doorbell "$to" "$typ" "" "$id"' '  printf '"'"'mut\n'"'"' > "$BOX/$to/inbox/nudge-created.md"; ring_doorbell "$to" "$typ" "" "$id"'; then
  NID2="2026-08-15T095000-alpha-request-${CANARY}-cccc3333"
  write_letter beta alpha request true "$NID2"
  LETTERBOX_DOORBELL="$box/mock-adapter.sh" ADAPTER_LOG="$ADAPTER_LOG" \
    LETTERBOX_DIR="$box" LETTERBOX_AGENT=gamma "$mut" nudge "$NID2" >/dev/null
  if [[ -f "$box/beta/inbox/nudge-created.md" ]]; then
    rm -f "$box/beta/inbox/nudge-created.md"
    pass "M-nudge-creates-letter caught (mutant created a letter; D4 would fail)"
  else
    fail "M-nudge-creates-letter SURVIVED"
  fi
else
  fail "M-nudge-creates-letter mutation pattern missing"
fi

# M-token-first-match: dropping the collision guard must break D6.
begin_block
mut="$(make_mutant token-first-match)"
if mutate_line "$mut" '  if (( ${#matches[@]} > 1 )); then' '  if false && (( ${#matches[@]} > 1 )); then'; then
  mut_out="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" token deadbeef 2>&1 || true)"
  if [[ "$mut_out" != *'ambiguous-token'* ]]; then
    pass "M-token-first-match caught (mutant dismissed a collided token; D6 would fail)"
  else
    fail "M-token-first-match SURVIVED"
  fi
else
  fail "M-token-first-match mutation pattern missing"
fi

# M-timeout-removed: an unbounded adapter wait must break D5's bounded assertion.
begin_block
if command -v python3 >/dev/null 2>&1; then
  mut="$(make_mutant timeout-removed)"
  if mutate_line "$mut" '    sys.exit(p.wait(timeout=float(sys.argv[1])))' '    sys.exit(p.wait())'; then
    ( printf 'body\n' | LETTERBOX_DOORBELL="$box/hang-adapter.sh" LETTERBOX_DOORBELL_TIMEOUT=1 \
      LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" send beta request mut-hang --now >/dev/null 2>&1 ) &
    mut_pid=$!
    disown
    hung=0
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      kill -0 "$mut_pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -0 "$mut_pid" 2>/dev/null && hung=1
    if [[ "$hung" == 1 ]]; then
      kill -9 "$mut_pid" 2>/dev/null || true
      pkill -9 -P "$mut_pid" 2>/dev/null || true
      pass "M-timeout-removed caught (mutant hangs on a hung adapter; D5 would fail)"
    else
      fail "M-timeout-removed SURVIVED (mutant still bounded)"
    fi
  else
    fail "M-timeout-removed mutation pattern missing"
  fi
else
  echo "SKIP: M-timeout-removed mutation (python3 unavailable)"
fi

echo
echo "doorbell v0.3: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
