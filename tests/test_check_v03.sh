#!/usr/bin/env bash
# Public-safe v0.3 operational-view fixtures: default check (open work, live
# first, stale last by last-activity; counts in header; loud STALE+age; never
# prints bodies), --recent with hidden-count footer, progress sidecar notes
# with age, read (exact durable letter, own inbox only), and read-only thread
# fan-out reporting lifecycle/silence, never attention. Neutral identities only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
PASS=0
FAIL=0
BLOCK_FAILED=0
PRINTED_SUMMARY=0

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

# Grep-miss safe line lookup: empty string, never pipefail-abort.
line_of() { # $1=haystack $2=needle
  awk -v n="$2" 'index($0,n){print NR; exit}' <<EOF
$1
EOF
}

box=""
cleanup() {
  if [[ "$PRINTED_SUMMARY" != 1 ]]; then
    printf 'FAIL: check v0.3 harness aborted before summary\n' >&2
  fi
  if [[ -n "${box:-}" && -d "$box" ]]; then
    rm -rf "$box"
  fi
  return 0
}
trap cleanup EXIT

box="$(mktemp -d "${TMPDIR:-/tmp}/lb-check.XXXXXX")"
LETTERBOX_DIR="$box" "$letterbox" init alpha beta gamma delta >/dev/null

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

CANARY="canaryslugxyz-leaky-task"

write_letter() { # to from type req_ack id [thread] [re]
  local th="${6:-}" re="${7:-}"
  cat > "$box/$1/inbox/${5}.md" <<EOF
---
id: $5
from: $2
to: $1
type: $3
re: $re
priority: now
requires_ack: $4
deadline:
${th:+thread: $th}
---
body $CANARY for $5
EOF
}

write_ack() { # letter-path
  printf 'ack_id: test-ack\nacked_at: %s\nby: test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$1.ack"
}

days_ago_id() { # $1=days → compact id timestamp N days ago (BSD or GNU date)
  date -u -v-"$1"d +%Y-%m-%dT%H%M%S 2>/dev/null || date -u -d "$1 days ago" +%Y-%m-%dT%H%M%S
}

hours_ago_iso() { # $1=hours → ISO UTC N hours ago
  date -u -v-"$1"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$1 hours ago" +%Y-%m-%dT%H:%M:%SZ
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

LIVE_TS="$(days_ago_id 1)"
STALE_TS="$(days_ago_id 20)"
LIVE="${LIVE_TS}-beta-request-${CANARY}-abcd1234"
NEWER="$(days_ago_id 0)-beta-request-${CANARY}-bbbb2222"
STALE="${STALE_TS}-beta-request-${CANARY}-eeee5555"
LIVE_DISP="${LIVE_TS} · abcd1234"
NEWER_DISP="${NEWER%-beta-request-*} · bbbb2222"
STALE_DISP="${STALE_TS} · eeee5555"

echo "=== W1 default check: live first, stale last, counts, no bodies ==="

begin_block
write_letter alpha beta request true "$LIVE"
write_letter alpha beta request true "$NEWER"
write_letter alpha beta request true "$STALE"
write_ack "$box/alpha/inbox/${LIVE}.md"
out="$(lb alpha check)"
printf '%s\n' "$out" | grep -q 'open: 2 live · 1 stale (>14d)' || fail "W1-counts: $out"
printf '%s\n' "$out" | grep -q 'inbox: 3 message(s)' || fail "W1-header-count: $out"
printf '%s\n' "$out" | grep "$STALE_DISP" | grep -q 'STALE 20d' || fail "W1-stale-age: $out"
live_line="$(line_of "$out" "$NEWER_DISP")"
stale_line="$(line_of "$out" "$STALE_DISP")"
[[ -n "$live_line" && -n "$stale_line" && "$live_line" -lt "$stale_line" ]] || \
  fail "W1-order live=${live_line:-missing} stale=${stale_line:-missing}"
if printf '%s\n' "$out" | grep -q "$CANARY" || printf '%s\n' "$out" | grep -q "${LIVE}.md"; then
  fail W1-leaked-canary-or-filename
fi
if printf '%s\n' "$out" | grep -q 'body '; then
  fail W1-printed-body
fi
printf '%s\n' "$out" | grep -q "$LIVE_DISP \[ACCEPTED\]" || fail "W1-accepted-label: $out"
printf '%s\n' "$out" | grep -q "$NEWER_DISP \[UNACKED\]" || fail "W1-unacked-label: $out"
pass W1-default-check

begin_block
rout="$(lb alpha check --recent)"
if printf '%s\n' "$rout" | grep -q "$STALE_DISP"; then
  fail "W1-recent-showed-stale: $rout"
fi
printf '%s\n' "$rout" | grep -q "$NEWER_DISP" || fail W1-recent-hid-live
printf '%s\n' "$rout" | grep -q '1 stale items hidden; run letterbox check to see all open work' || \
  fail "W1-recent-footer: $rout"
pass W1-recent-footer

echo "=== W2 progress sidecar ==="

begin_block
if lb alpha progress "$STALE" should-fail 2>"$box/err"; then
  fail W2-progress-without-ack-accepted
else
  grep -q 'ACK sidecar' "$box/err" || fail "W2-progress-message: $(cat "$box/err")"
fi
before="$(find "$box" -type f | wc -l | tr -d ' ')"
pconf="$(lb alpha progress "$LIVE" "still mapping")"
after="$(find "$box" -type f | wc -l | tr -d ' ')"
[[ "$pconf" == "progress: $LIVE_DISP" ]] || fail "W2-progress-confirmation: $pconf"
[[ "$before" == "$after" ]] || fail W2-progress-created-files
grep -q '^progress: still mapping$' "$box/alpha/inbox/${LIVE}.md.ack" || fail W2-progress-note
grep -q '^progress_at: ' "$box/alpha/inbox/${LIVE}.md.ack" || fail W2-progress-at
pout="$(lb alpha check)"
printf '%s\n' "$pout" | grep -q 'progress: still mapping' || fail "W2-progress-reader: $pout"
printf '%s\n' "$pout" | grep -q '(age ' || fail "W2-progress-age: $pout"
lb alpha progress "$LIVE" "maps next" >/dev/null
grep -q '^progress: maps next$' "$box/alpha/inbox/${LIVE}.md.ack" || fail W2-progress-overwrite
if grep -q 'still mapping' "$box/alpha/inbox/${LIVE}.md.ack"; then
  fail W2-progress-stale-note
fi
pass W2-progress

begin_block
# progress refuses terminal letters
mv "$box/alpha/inbox/${STALE}.md" "$box/alpha/processed/"
if lb alpha progress "$STALE" too-late 2>"$box/err"; then
  fail W2-progress-terminal-accepted
else
  grep -q 'filed/terminal' "$box/err" || fail "W2-terminal-message: $(cat "$box/err")"
  if grep -q "$CANARY" "$box/err"; then
    fail W2-terminal-error-leaked-canary
  fi
fi
mv "$box/alpha/processed/${STALE}.md" "$box/alpha/inbox/"
pass W2-progress-refuses-terminal

echo "=== W3 read: exact durable letter, own inbox only ==="

begin_block
snap1="$(find "$box/alpha" -type f | sort | cksum)"
rout="$(lb alpha read "$NEWER_DISP")"
snap2="$(find "$box/alpha" -type f | sort | cksum)"
[[ "$snap1" == "$snap2" ]] || fail W3-read-wrote-files
printf '%s\n' "$rout" | grep -q "^id: $NEWER$" || fail W3-read-id
printf '%s\n' "$rout" | grep -q "body $CANARY for $NEWER" || fail W3-read-body
lb alpha read "$LIVE" | grep -q "^id: $LIVE$" || fail W3-read-full-id
if lb alpha read "1999-01-01T000000 · ffffffff" 2>"$box/err"; then
  fail W3-read-unknown-accepted
else
  grep -q 'not found' "$box/err" || fail "W3-read-miss-message: $(cat "$box/err")"
fi
if lb alpha read "$box/alpha/inbox/${LIVE}.md" 2>"$box/err"; then
  fail W3-read-path-accepted
else
  grep -q 'not a path' "$box/err" || fail "W3-read-path-message: $(cat "$box/err")"
fi
pass W3-read

echo "=== W4 thread fan-out: read-only lifecycle view ==="

begin_block
THREAD="2026-08-14T100000-alpha-request-${CANARY}-1111aaaa"
write_letter beta alpha request true "$THREAD" "$THREAD"
write_letter beta alpha request true "2026-08-14T100002-alpha-request-${CANARY}-3333cccc" "$THREAD"
write_letter gamma alpha request true "2026-08-14T100001-alpha-request-${CANARY}-2222bbbb" "$THREAD"
write_ack "$box/gamma/inbox/2026-08-14T100001-alpha-request-${CANARY}-2222bbbb.md"
lb gamma progress "2026-08-14T100001-alpha-request-${CANARY}-2222bbbb" "gamma wip" >/dev/null
cat > "$box/delta/processed/${THREAD}--delta--result.md" <<EOF
---
id: ${THREAD}--delta--result
from: delta
to: alpha
type: result
re: $THREAD
priority: now
requires_ack: false
deadline:
thread: $THREAD
---
done
EOF
snap1="$(find "$box" -type f | sort | cksum)"
tout="$(lb alpha check --thread "$THREAD")"
snap2="$(find "$box" -type f | sort | cksum)"
[[ "$snap1" == "$snap2" ]] || fail W4-thread-wrote-files
printf '%s\n' "$tout" | grep -q 'beta  inbox  silent' || fail "W4-silent: $tout"
printf '%s\n' "$tout" | grep -q 'gamma  inbox  acked' || fail "W4-acked: $tout"
printf '%s\n' "$tout" | grep -q 'delta  processed  result' || fail "W4-result: $tout"
printf '%s\n' "$tout" | grep -q 'progress: gamma wip' || fail "W4-progress: $tout"
printf '%s\n' "$tout" | grep -q '2026-08-14T100000 · 1111aaaa' || fail W4-disp-1
printf '%s\n' "$tout" | grep -q '2026-08-14T100002 · 3333cccc' || fail W4-disp-2
if printf '%s\n' "$tout" | grep -Eqw 'read|turn_started|attention'; then
  fail W4-claimed-attention
fi
if printf '%s\n' "$tout" | grep -q "$CANARY"; then
  fail W4-leaked-canary
fi
pass W4-thread-fanout

echo "=== W5 last-activity staleness: fresh progress keeps an old letter live ==="

begin_block
OLD_TS="$(days_ago_id 20)"
OLD="${OLD_TS}-beta-request-${CANARY}-ffff0001"
OLD_DISP="${OLD_TS} · ffff0001"
write_letter alpha beta request true "$OLD"
printf 'ack_id: old\nacked_at: %s\nby: test\nprogress: still going\nprogress_at: %s\n' \
  "$(hours_ago_iso 500)" "$(hours_ago_iso 1)" > "$box/alpha/inbox/${OLD}.md.ack"
x2="$(lb alpha check --recent)"
printf '%s\n' "$x2" | grep -q "$OLD_DISP" || fail "W5-recent-hid-active-old: $x2"
x2d="$(lb alpha check)"
if printf '%s\n' "$x2d" | grep "$OLD_DISP" | grep -q 'STALE'; then
  fail "W5-active-old-marked-stale: $x2d"
fi
pass W5-last-activity

echo "=== check/read/thread named mutations (fixtures must be able to fail) ==="

# M-progress-display-removed: dropping the progress line from cards must break W2.
begin_block
mut="$(make_mutant progress-display)"
if mutate_line "$mut" '  print_progress_line "$f"' '  true # progress display removed'; then
  mout="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" check)"
  if ! printf '%s\n' "$mout" | grep -q 'progress:'; then
    pass "M-progress-display-removed caught (mutant hides progress; W2 would fail)"
  else
    fail "M-progress-display-removed SURVIVED"
  fi
else
  fail "M-progress-display-removed mutation pattern missing"
fi

# M-recent-footer-removed: dropping the hidden-count footer must break W1.
begin_block
mut="$(make_mutant recent-footer)"
if mutate_line "$mut" '    echo "$stale_n stale items hidden; run letterbox check to see all open work"' '    true # footer removed'; then
  mout="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" check --recent)"
  if ! printf '%s\n' "$mout" | grep -q 'hidden'; then
    pass "M-recent-footer-removed caught (mutant hides the footer; W1 would fail)"
  else
    fail "M-recent-footer-removed SURVIVED"
  fi
else
  fail "M-recent-footer-removed mutation pattern missing"
fi

# M-stale-ignore-progress: ignoring progress_at must break W5.
begin_block
mut="$(make_mutant stale-ignore-progress)"
if mutate_line "$mut" '    if cand="$(progress_epoch "$f.ack")"; then' '    if cand="0"; then'; then
  mout="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" check --recent)"
  if ! printf '%s\n' "$mout" | grep -q "$OLD_DISP"; then
    pass "M-stale-ignore-progress caught (mutant stales an active letter; W5 would fail)"
  else
    fail "M-stale-ignore-progress SURVIVED"
  fi
else
  fail "M-stale-ignore-progress mutation pattern missing"
fi

# M-thread-writes: a thread view that writes must break W4's zero-file assertion.
begin_block
mut="$(make_mutant thread-writes)"
if mutate_line "$mut" '  echo "── thread $(display_id "$want")"' '  echo "── thread $(display_id "$want")"; printf '"'"'mut\n'"'"' > "$BOX/.thread-write"'; then
  rm -f "$box/.thread-write"
  LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" check --thread "$THREAD" >/dev/null
  if [[ -f "$box/.thread-write" ]]; then
    rm -f "$box/.thread-write"
    pass "M-thread-writes caught (mutant wrote a file; W4 would fail)"
  else
    fail "M-thread-writes SURVIVED"
  fi
else
  fail "M-thread-writes mutation pattern missing"
fi

# M-read-body-in-check: printing bodies in cards must break W1's privacy assertion.
begin_block
mut="$(make_mutant read-in-check)"
if mutate_line "$mut" '  printf '"'"'    from: %s  type: %s\n'"'"' "$(frontmatter_value "$f" from)" "$(frontmatter_value "$f" type)"' '  printf '"'"'    from: %s  type: %s\n'"'"' "$(frontmatter_value "$f" from)" "$(frontmatter_value "$f" type)"; cat "$f"'; then
  mout="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$mut" check)"
  if printf '%s\n' "$mout" | grep -q "$CANARY"; then
    pass "M-read-body-in-check caught (mutant printed bodies; W1 would fail)"
  else
    fail "M-read-body-in-check SURVIVED"
  fi
else
  fail "M-read-body-in-check mutation pattern missing"
fi

echo
PRINTED_SUMMARY=1
echo "check v0.3: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
