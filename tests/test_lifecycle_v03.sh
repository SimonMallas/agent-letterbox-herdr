#!/usr/bin/env bash
# Public-safe v0.3 lifecycle safety fixtures: one-shot result|nack on
# requires_ack:false letters, structural rule C (--read for path-form terminal
# replies), reply body read before any lifecycle lock (TTY/empty fail-fast),
# and lifecycle errors that name the correct next action. Neutral identities only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
PASS=0
FAIL=0
BLOCK_FAILED=0
EXPECTED_PASS=10
SUITE_DONE=0
FOOTER_MARK='lifecycle v0.3: PASS'

# fail marks the current block; pass must not green-wash a failed block.
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
lifecycle_exit_gate() {
  local rc=$?
  cleanup
  if [[ "$SUITE_DONE" == 1 ]]; then
    return 0
  fi
  echo "lifecycle v0.3: FAIL (early abort or incomplete: pass=${PASS:-0} expected=${EXPECTED_PASS} fail=${FAIL:-0}; missing '${FOOTER_MARK}')" >&2
  exit 1
}
trap lifecycle_exit_gate EXIT

new_box() {
  cleanup
  box="$(mktemp -d "${TMPDIR:-/tmp}/lb-v03.XXXXXX")"
  LETTERBOX_DIR="$box" "$letterbox" init planner reviewer >/dev/null
}

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" "$letterbox" "$@"
}

send_request() { # requires_ack:false request (low-ceremony)
  printf '%s\n' 'small request body' | lb planner send reviewer request small-item >/dev/null
  req="$(find "$box/reviewer/inbox" -name '*.md' -type f -print -quit)"
  req_id="$(basename "$req" .md)"
}

send_task() {
  printf '%s\n' 'task body' | lb planner send reviewer delegate task-item --ack >/dev/null
  task="$(find "$box/reviewer/inbox" -name '*.md' -type f -print -quit)"
  task_id="$(basename "$task" .md)"
}

write_letter() { # to from type req_ack id [dir]
  local dir="${6:-inbox}"
  cat > "$box/$1/$dir/${5}.md" <<EOF
---
id: $5
from: $2
to: $1
type: $3
re:
priority: next
requires_ack: $4
deadline:
---
body for $5
EOF
}

# Mutation harness: copy the helper, patch one exact line, prove a fixture catches it.
make_mutant() { # $1=name → prints mutant helper path
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

echo "=== V1 one-shot close on requires_ack:false ==="

begin_block
new_box; send_request
printf 'done small\n' | lb reviewer reply "$req_id" result small-done >/dev/null
[[ -f "$box/reviewer/processed/$(basename "$req")" ]] || fail V1-result-archived
[[ -n "$(find "$box/planner/inbox" -name '*--reviewer--result.md' -print -quit)" ]] || fail V1-result-published
new_box; send_request
printf 'declined\n' | lb reviewer reply "$req_id" nack small-nack >/dev/null
[[ -f "$box/reviewer/processed/$(basename "$req")" ]] || fail V1-nack-archived
[[ -n "$(find "$box/planner/inbox" -name '*--reviewer--nack.md' -print -quit)" ]] || fail V1-nack-published
pass V1-one-shot-result-nack

# Mutation hook (test-only): fires right after the first completed assertion.
case "${LETTERBOX_MUTATE_EARLY_ABORT:-}" in
  exit0) echo "MUTATION: early exit 0 after first v0.3 assertion" >&2; exit 0;;
  abort) echo "MUTATION: set -e abort after first v0.3 assertion" >&2; false;;
esac

begin_block
new_box; send_request
if printf 'nope\n' | lb reviewer reply "$req_id" ack taking 2>"$box/err"; then
  fail V1-ack-on-nontask-accepted
else
  grep -q 'ack is only for requires_ack:true tasks' "$box/err" || fail "V1-ack-message: $(cat "$box/err")"
  grep -q 'letterbox file <id>' "$box/err" || fail "V1-ack-next-action: $(cat "$box/err")"
  [[ -f "$req" ]] || fail V1-ack-moved-letter
fi
pass V1-ack-refused-for-info-letter-names-next-action

echo "=== V2 lifecycle errors name the next action ==="

begin_block
new_box; send_task
if lb reviewer file "$task_id" 2>"$box/err"; then
  fail V2-file-on-task-accepted
else
  grep -q 'letterbox reply <id> result|nack' "$box/err" || fail "V2-file-message: $(cat "$box/err")"
fi
if printf 'x\n' | lb reviewer reply "$task_id" bogus verb-slug 2>"$box/err"; then
  fail V2-wrong-verb-accepted
else
  grep -q 'reply type must be ack, nack, or result' "$box/err" || fail "V2-verb-message: $(cat "$box/err")"
fi
if lb reviewer read "2026-01-01T000000 · ffffffff" 2>"$box/err"; then
  fail V2-unknown-id-accepted
else
  grep -q 'not found' "$box/err" || fail "V2-unknown-message: $(cat "$box/err")"
fi
# terminal parent without a published reply names check, not send
write_letter reviewer planner delegate true "2026-08-10T000000-planner-delegate-closed-aaaa1111" processed
if printf 'x\n' | lb reviewer reply "2026-08-10T000000-planner-delegate-closed-aaaa1111" result done 2>"$box/err"; then
  fail V2-terminal-parent-accepted
else
  grep -q 'already closed without your result reply' "$box/err" || fail "V2-terminal-message: $(cat "$box/err")"
  grep -q 'use letterbox check' "$box/err" || fail "V2-terminal-next-action: $(cat "$box/err")"
fi
pass V2-errors-name-next-action

echo "=== V3 structural rule C: path-form terminal replies require --read ==="

begin_block
new_box
write_letter reviewer planner result false "2026-08-10T010000-planner-result-peer-dddd4444"
rpath="$box/reviewer/inbox/2026-08-10T010000-planner-result-peer-dddd4444.md"
if lb reviewer file "$rpath" 2>"$box/err"; then
  fail V3-path-result-filed-unread
else
  grep -q 'letterbox file <path> --read' "$box/err" || fail "V3-message: $(cat "$box/err")"
  [[ -f "$rpath" ]] || fail V3-path-result-moved
fi
lb reviewer file "$rpath" --read >/dev/null
[[ -f "$box/reviewer/processed/2026-08-10T010000-planner-result-peer-dddd4444.md" ]] || fail V3-read-did-not-file
write_letter reviewer planner nack false "2026-08-10T010100-planner-nack-peer-eeee5555"
if lb reviewer file "$box/reviewer/inbox/2026-08-10T010100-planner-nack-peer-eeee5555.md" 2>"$box/err"; then
  fail V3-path-nack-filed-unread
else
  grep -q 'unread inbound nack' "$box/err" || fail "V3-nack-message: $(cat "$box/err")"
fi
lb reviewer file "2026-08-10T010100-planner-nack-peer-eeee5555" >/dev/null
[[ -f "$box/reviewer/processed/2026-08-10T010100-planner-nack-peer-eeee5555.md" ]] || fail V3-id-nack-not-filed
write_letter reviewer planner result false "2026-08-10T010200-planner-result-byid-dddd4445"
lb reviewer file "2026-08-10T010200-planner-result-byid-dddd4445" >/dev/null
[[ -f "$box/reviewer/processed/2026-08-10T010200-planner-result-byid-dddd4445.md" ]] || fail V3-id-result-not-filed
# control: an info letter by path files without --read
write_letter reviewer planner info false "2026-08-10T010300-planner-info-fyi-ffff6666"
lb reviewer file "$box/reviewer/inbox/2026-08-10T010300-planner-info-fyi-ffff6666.md" >/dev/null
[[ -f "$box/reviewer/processed/2026-08-10T010300-planner-info-fyi-ffff6666.md" ]] || fail V3-info-path-not-filed
# a bare filename while cwd=inbox is the conservative path branch
write_letter reviewer planner result false "2026-08-10T010400-planner-result-cwd-33330000"
if ( cd "$box/reviewer/inbox" && lb reviewer file "2026-08-10T010400-planner-result-cwd-33330000.md" ) 2>"$box/err"; then
  fail V3-cwd-result-filed-unread
else
  grep -q 'letterbox file <path> --read' "$box/err" || fail "V3-cwd-message: $(cat "$box/err")"
  [[ -f "$box/reviewer/inbox/2026-08-10T010400-planner-result-cwd-33330000.md" ]] || fail V3-cwd-moved
fi
pass V3-structural-rule-C

echo "=== V4 reply body read before any lifecycle lock ==="

begin_block
new_box; send_request
if lb reviewer reply "$req_id" result empty </dev/null 2>"$box/err"; then
  fail V4-empty-stdin-accepted
else
  grep -Eq 'empty reply body|usage: pipe the reply body' "$box/err" || fail "V4-empty-message: $(cat "$box/err")"
  [[ -f "$req" ]] || fail V4-empty-moved-letter
  [[ ! -d "$req.lifecycle.lock" ]] || fail V4-empty-left-lock
fi
pass V4-empty-stdin-fail-fast-no-lock

# A non-TTY pipe that never reaches EOF may still block in cat (accepted limit,
# no timeout) — but it must never hold the lifecycle lock while blocked.
begin_block
new_box; send_request
( sleep 30 | LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer "$letterbox" \
  reply "$req_id" result x >/dev/null 2>&1 ) &
hp=$!
disown
sleep 0.5
if [[ -d "$req.lifecycle.lock" ]]; then
  fail V4-hang-pipe-took-lock
else
  pass V4-hang-pipe-holds-no-lock
fi
kill -9 "$hp" 2>/dev/null || true
pkill -9 -P "$hp" 2>/dev/null || true

# TTY stdin must fail fast with usage instead of hanging. A python3 pty gives
# the child a real terminal stdin (script(1) needs a TTY itself on macOS).
pty_probe() { # $1=timeout-secs, rest=cmd → child output on stdout; rc 0=exited, 4=hang(killed)
  python3 - "$1" "${@:2}" <<'PY'
import os, pty, select, signal, sys, time
timeout = float(sys.argv[1])
cmd = sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
deadline = time.time() + timeout
out = b""
exited = False
while time.time() < deadline:
    done, _ = os.waitpid(pid, os.WNOHANG)
    if done:
        exited = True
        break
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            out += os.read(fd, 4096)
        except OSError:
            pass
while True:  # drain anything written at exit
    r, _, _ = select.select([fd], [], [], 0.05)
    if not r:
        break
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
if not exited:
    done, _ = os.waitpid(pid, os.WNOHANG)
    exited = bool(done)
sys.stdout.buffer.write(out)
sys.stdout.flush()
if exited:
    sys.exit(0)
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
os.waitpid(pid, 0)
sys.exit(4)
PY
}

begin_block
new_box; send_request
if command -v python3 >/dev/null 2>&1; then
  set +e
  tty_out="$(pty_probe 3 env LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer "$letterbox" reply "$req_id" result x)"
  tty_rc=$?
  set -e
  if [[ "$tty_rc" == 4 ]]; then
    fail V4-tty-hung
  elif [[ "$tty_rc" == 0 ]] && printf '%s' "$tty_out" | grep -q 'pipe the reply body via stdin' && \
       [[ -f "$req" ]] && [[ ! -d "$req.lifecycle.lock" ]]; then
    pass V4-tty-fail-fast-no-lock
  else
    fail "V4-tty-output rc=$tty_rc: $tty_out"
  fi
else
  echo "SKIP: V4 TTY fail-fast (python3 unavailable)"
fi

echo "=== v0.3 lifecycle named mutations (fixtures must be able to fail) ==="

# M-ack-nontask-guard: dropping the non-task ACK refusal must break V1.
begin_block
new_box; send_request
mut="$(make_mutant ack-nontask-guard)"
if mutate_line "$mut" '      if [[ "$type" == "ack" ]]; then' '      if false; then'; then
  if printf 'x\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer "$mut" reply "$req_id" ack taking >/dev/null 2>&1; then
    pass "M-ack-nontask-guard caught (mutant ACKed a non-task letter; V1 would fail)"
  else
    fail "M-ack-nontask-guard SURVIVED (mutant still refuses)"
  fi
else
  fail "M-ack-nontask-guard mutation pattern missing"
fi

# M-file-read-guard: dropping the --read refusal must break V3.
begin_block
new_box
write_letter reviewer planner result false "2026-08-10T020000-planner-result-mut-aaaa9999"
mut="$(make_mutant file-read-guard)"
if mutate_line "$mut" '      if [[ "$arg_is_path" == true && "$assert_read" != true ]]; then' '      if false; then'; then
  if LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer "$mut" file \
    "$box/reviewer/inbox/2026-08-10T020000-planner-result-mut-aaaa9999.md" >/dev/null 2>&1; then
    pass "M-file-read-guard caught (mutant filed unread path RESULT; V3 would fail)"
  else
    fail "M-file-read-guard SURVIVED (mutant still refuses)"
  fi
else
  fail "M-file-read-guard mutation pattern missing"
fi

# M-tty-guard: dropping the TTY fail-fast must turn V4's fast usage error into a hang.
begin_block
new_box; send_request
if command -v python3 >/dev/null 2>&1; then
  mut="$(make_mutant tty-guard)"
  if mutate_line "$mut" '  if [[ -t 0 ]]; then' '  if false; then'; then
    set +e
    pty_probe 3 env LETTERBOX_DIR="$box" LETTERBOX_AGENT=reviewer "$mut" reply "$req_id" result x >/dev/null
    mut_rc=$?
    set -e
    if [[ "$mut_rc" == 4 ]]; then
      pass "M-tty-guard caught (mutant hangs on TTY stdin; V4 would fail)"
    else
      fail "M-tty-guard SURVIVED (mutant still fails fast, rc=$mut_rc)"
    fi
  else
    fail "M-tty-guard mutation pattern missing"
  fi
else
  echo "SKIP: M-tty-guard mutation (python3 unavailable)"
fi

echo
echo "lifecycle v0.3: $PASS passed, $FAIL failed (expected $EXPECTED_PASS passes)"
if [[ "$FAIL" -ne 0 ]]; then
  echo "lifecycle v0.3: FAIL (failures=$FAIL)" >&2
  exit 1
fi
if [[ "$PASS" -ne "$EXPECTED_PASS" ]]; then
  echo "lifecycle v0.3: FAIL (pass count $PASS != expected $EXPECTED_PASS — possible early abort)" >&2
  exit 1
fi
echo "$FOOTER_MARK"
SUITE_DONE=1
exit 0
