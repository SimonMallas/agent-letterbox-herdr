#!/usr/bin/env bash
# Mock-backed proof that adapters/herdr.sh never injects input into a live pane
# unless the caller explicitly opts in via LETTERBOX_HERDR_SUBMIT=1.
#
# Runs anywhere: Herdr itself is never required. The adapter resolves its binary
# through HERDR_BIN_PATH, so we point that at a mock that logs every call.
set -euo pipefail

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

# --- Default (LETTERBOX_HERDR_SUBMIT unset): must never inject ---
unset LETTERBOX_HERDR_SUBMIT || true
run_adapter
if injected; then
  echo 'FAIL: herdr pane send-text/send-keys called without LETTERBOX_HERDR_SUBMIT=1' >&2
  cat "$MOCK_LOG" >&2
  exit 1
fi
grep -q '^notification show ' "$MOCK_LOG" || {
  echo 'FAIL: expected the safe notification to still be attempted' >&2
  cat "$MOCK_LOG" >&2
  exit 1
}
echo 'PASS: no input injection without opt-in'

# --- LETTERBOX_HERDR_SUBMIT=0: same as unset, must still refuse ---
LETTERBOX_HERDR_SUBMIT=0 run_adapter
if injected; then
  echo 'FAIL: herdr injected with LETTERBOX_HERDR_SUBMIT=0' >&2
  cat "$MOCK_LOG" >&2
  exit 1
fi
echo 'PASS: explicit 0 also refuses'

# --- LETTERBOX_HERDR_SUBMIT=1: MUST inject. ---
# This is the control. Without it the two checks above could both pass because the
# adapter never reached the gate at all, and the test would be green for a reason
# unrelated to what it claims to prove.
LETTERBOX_HERDR_SUBMIT=1 run_adapter
injected || {
  echo 'FAIL: opt-in did not inject — the mock never reached the submit gate, so the' >&2
  echo '      refusal checks above prove nothing. Fix the mock, not the adapter.' >&2
  cat "$MOCK_LOG" >&2
  exit 1
}
grep -q '^pane send-keys .* enter$' "$MOCK_LOG" || {
  echo 'FAIL: opt-in sent text but never sent the enter key' >&2
  cat "$MOCK_LOG" >&2
  exit 1
}
echo 'PASS: explicit opt-in injects'

echo 'herdr-doorbell-safety test: PASS'
