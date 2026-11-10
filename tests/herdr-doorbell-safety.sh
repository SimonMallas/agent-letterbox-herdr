#!/usr/bin/env bash
# Mock-backed proof that adapters/herdr.sh sends the doorbell into the resolved
# pane by default, and that only LETTERBOX_HERDR_SUBMIT=0 stops it.
#
# Runs anywhere: Herdr itself is never required. The adapter resolves its binary
# through HERDR_BIN_PATH, so we point that at a mock that logs every call.
set -euo pipefail
unset LETTERBOX_HERDR_SUBMIT # each case below sets it on purpose; an inherited value must not decide one

root="$(cd "$(dirname "$0")/.." && pwd)"
adapter="$root/adapters/herdr.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Mock `herdr`: logs every invocation and answers `pane get` successfully, so the
# adapter's pane lookup succeeds and execution reaches the LETTERBOX_HERDR_SUBMIT
# gate — rather than deferring earlier for an unrelated reason (herdr missing, no
# live pane). A test that passes because the adapter bailed out early would prove
# nothing about the gate.
mock="$work/herdr-mock"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
# Herdr 0.9.1's answers to the shell guard's read-only questions (not logged):
# no recognised agent, and an app, not a shell, in front.
case "${1:-} ${2:-}" in
  "status server") echo '{"running":true,"version":"0.9.1"}'; exit 0;;
  "agent get") echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1;;
  "pane process-info") echo '{"result":{"process_info":{"shell_pid":1,"foreground_process_group_id":2}}}'; exit 0;;
esac
echo "$*" >> "$MOCK_LOG"
if [[ "$1" == "pane" && "$2" == "get" ]]; then exit 0; fi
exit 0
MOCK
chmod +x "$mock"

box="$work/box"
mkdir -p "$box/reviewer/inbox"
patterns="$box/herdr-patterns.tsv"
printf 'reviewer\t%%1\n' > "$patterns"

MOCK_LOG="$work/herdr-calls.log"
export MOCK_LOG

run_adapter() {
  : > "$MOCK_LOG"
  HERDR_BIN_PATH="$mock" \
    LETTERBOX_DIR="$box" \
    LETTERBOX_HERDR_PATTERNS="$patterns" \
    MOCK_LOG="$MOCK_LOG" \
    "$adapter" reviewer delegate smoke-test >/dev/null
}

injected() { grep -qE '^pane (send-text|send-keys) ' "$MOCK_LOG"; }

# --- Default (LETTERBOX_HERDR_SUBMIT unset): the doorbell is sent, then enter ---
unset LETTERBOX_HERDR_SUBMIT || true
run_adapter
injected && grep -q '^pane send-keys .* enter$' "$MOCK_LOG" || {
  echo 'FAIL: the default did not send the doorbell and enter' >&2
  cat "$MOCK_LOG" >&2
  exit 1
}
echo 'PASS: the doorbell is sent by default'

# --- LETTERBOX_HERDR_SUBMIT=0: the only way to stop typing; the notice still fires ---
LETTERBOX_HERDR_SUBMIT=0 run_adapter
if injected; then
  echo 'FAIL: herdr injected with LETTERBOX_HERDR_SUBMIT=0' >&2
  cat "$MOCK_LOG" >&2
  exit 1
fi
grep -q '^notification show ' "$MOCK_LOG" || {
  echo 'FAIL: expected the notification with typing off' >&2
  cat "$MOCK_LOG" >&2
  exit 1
}
echo 'PASS: explicit 0 stops typing'

# --- LETTERBOX_HERDR_SUBMIT=1: MUST inject. ---
# This is the control. Without it the two checks above could both pass because the
# adapter never reached the gate at all, and the test would be green for a reason
# unrelated to what it claims to prove.
LETTERBOX_HERDR_SUBMIT=1 run_adapter
injected || {
  echo 'FAIL: explicit 1 did not inject — the mock never reached the submit gate, so the' >&2
  echo '      refusal checks above prove nothing. Fix the mock, not the adapter.' >&2
  cat "$MOCK_LOG" >&2
  exit 1
}
grep -q '^pane send-keys .* enter$' "$MOCK_LOG" || {
  echo 'FAIL: explicit 1 sent text but never sent the enter key' >&2
  cat "$MOCK_LOG" >&2
  exit 1
}
echo 'PASS: explicit 1 injects'

echo 'herdr-doorbell-safety test: PASS'
