#!/usr/bin/env bash
# Release 2 W2 — herdr edition end-to-end: bin/letterbox send --now with a fake
# herdr and the real adapter, plus wrapper classifier edge cases. Everything
# faked inside this temp dir; no real herdr, no real letterbox state.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="$(mktemp -d /tmp/r2herdr-test.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/bin" "$ROOT/box/agent/inbox" "$ROOT/box/agent/processed" \
         "$ROOT/box/tester/inbox" "$ROOT/box/tester/processed"

printf 'agent\tpane:7\t/tmp/fake.sock\t2026-09-16T00:00:00Z\n' > "$ROOT/registry.tsv"
printf 'agent\tpane:9\n' > "$ROOT/patterns.tsv"

export BOX="$ROOT/box" LETTERBOX_DIR="$ROOT/box" LETTERBOX_AGENT=tester
export LETTERBOX_DOORBELL_TIMEOUT=3

# Fake herdr (behavior by env) -------------------------------------------------
cat > "$ROOT/bin/herdr" <<'HERDR'
#!/usr/bin/env bash
set -uo pipefail
log="${HERDR_FAKE_LOG:?}"
printf '%s\n' "$*" >> "$log"
if [[ "${1:-}" == "pane" ]]; then
  case "${2:-}" in
    get)
      case "${HERDR_FAKE_GET:-ok}" in
        ok) exit 0;; fail) exit 1;; sleep) sleep "${HERDR_FAKE_SLEEP:-5}";;
      esac
      exit 0;;
    send-text)
      case "${HERDR_FAKE_SEND:-ok}" in
        ok) exit 0;; fail) exit 1;; sleep) sleep "${HERDR_FAKE_SLEEP:-5}";;
      esac
      exit 0;;
    send-keys)
      case "${HERDR_FAKE_ENTER:-ok}" in
        ok) exit 0;; fail) exit 1;; sleep) sleep "${HERDR_FAKE_SLEEP:-5}";;
      esac
      exit 0;;
  esac
fi
exit 0
HERDR
chmod +x "$ROOT/bin/herdr"
export PATH="$ROOT/bin:$PATH"
export HERDR_FAKE_LOG="$ROOT/herdr.log"
export LETTERBOX_DOORBELL="$EDITION/adapters/herdr.sh"
export LETTERBOX_HERDR_SUBMIT=1

# Misbehaving doorbells for wrapper classifier edge cases.
cat > "$ROOT/sleeper.sh" <<'SH'
#!/usr/bin/env bash
sleep 30
SH
cat > "$ROOT/garbage.sh" <<'SH'
#!/usr/bin/env bash
echo 'not a contract line'
SH
cat > "$ROOT/double.sh" <<'SH'
#!/usr/bin/env bash
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7'
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7'
SH
cat > "$ROOT/valid-exit1.sh" <<'SH'
#!/usr/bin/env bash
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7'
exit 1
SH
chmod +x "$ROOT/sleeper.sh" "$ROOT/garbage.sh" "$ROOT/double.sh" "$ROOT/valid-exit1.sh"

# PATH farm WITH the fake herdr but WITHOUT python3: a missing runner must be
# adapter_unavailable (non-retryable), never helper_timeout.
mkdir -p "$ROOT/bin-nopython"
for t in bash grep awk sed shasum od tr date mktemp ln rm cat \
         dirname basename env sleep; do
  src="$(command -v "$t" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$ROOT/bin-nopython/$t"
done
ln -sf "$ROOT/bin/herdr" "$ROOT/bin-nopython/herdr"

send_now() { # $1.. = env overrides (must trail base assignments to win)
  env BOX="$BOX" LETTERBOX_AGENT=tester LETTERBOX_DIR="$BOX" \
    LETTERBOX_DOORBELL="$LETTERBOX_DOORBELL" LETTERBOX_HERDR_SUBMIT="$LETTERBOX_HERDR_SUBMIT" \
    LETTERBOX_DOORBELL_TIMEOUT="$LETTERBOX_DOORBELL_TIMEOUT" \
    LETTERBOX_HERDR_REGISTRY="$ROOT/registry.tsv" LETTERBOX_HERDR_PATTERNS= \
    PATH="$PATH" HERDR_FAKE_LOG="$HERDR_FAKE_LOG" "$@" \
    bash -c 'printf "test body\n" | "$0" send agent info testslug --now' "$EDITION/bin/letterbox" 2>/dev/null
}

one_line() {
  local out="$1" n
  n="$(printf '%s\n' "$out" | grep -c '^doorbell-outcome ' || true)"
  [[ "$n" == "1" ]] || { echo "SOLE-EMISSION FAIL ($n lines): $out"; exit 1; }
}

craft_letter() { # $1=from $2=id — hand-write a durable letter into agent's inbox
  cat > "$BOX/agent/inbox/$2.md" <<EOF
---
id: $2
from: $1
to: agent
type: info
re:
priority: later
requires_ack: false
deadline:
---
crafted body
EOF
}

nudge() { # $1=id — re-ring an existing letter through the full wrapper path
  env BOX="$BOX" LETTERBOX_AGENT=tester LETTERBOX_DIR="$BOX" \
    LETTERBOX_DOORBELL="$LETTERBOX_DOORBELL" LETTERBOX_HERDR_SUBMIT=1 \
    LETTERBOX_DOORBELL_TIMEOUT="$LETTERBOX_DOORBELL_TIMEOUT" \
    LETTERBOX_HERDR_REGISTRY="$ROOT/registry.tsv" LETTERBOX_HERDR_PATTERNS= \
    PATH="$PATH" HERDR_FAKE_LOG="$HERDR_FAKE_LOG" \
    "$EDITION/bin/letterbox" nudge "$1" 2>/dev/null
}

pass=0
check() { # $1=name $2=env-string $3=expected
  local name="$1" envs="$2" expected="$3" out
  out="$(send_now $envs)"
  one_line "$out"
  out="$(printf '%s\n' "$out" | grep '^doorbell-outcome ')"
  if [[ "$out" == "$expected" ]]; then
    echo "PASS: $name"; pass=$((pass+1))
  else
    echo "FAIL: $name"; echo "  expected: $expected"; echo "  got:      $out"; exit 1
  fi
}

check "submitted via registry pane"      "" \
  'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7'
# The injected line carries the v0.3 opaque token derived from the letter id,
# and names the durable letter's sender (from tester).
if grep -Eq "pane send-text pane:7 📬 letterbox ""doorbell: unacked info from tester in .*/agent/inbox/ — please check · [0-9a-f]{8}" "$HERDR_FAKE_LOG"; then
  echo "PASS: injected line carries sender + v0.3 token"; pass=$((pass+1))
else
  echo "FAIL: injected line carries sender + v0.3 token"; cat "$HERDR_FAKE_LOG"; exit 1
fi
check "pane get timeout → helper_timeout" "HERDR_FAKE_GET=sleep HERDR_FAKE_SLEEP=5" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=helper_timeout target=-'
check "pane dead → surface_not_found"    "HERDR_FAKE_GET=fail" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=surface_not_found target=-'
check "patterns fallback → submitted"    "LETTERBOX_HERDR_REGISTRY=$ROOT/missing.tsv LETTERBOX_HERDR_PATTERNS=$ROOT/patterns.tsv" \
  'doorbell-outcome v=1 outcome=submitted reason=- target=pane:9'
check "send-text reported fail → send_failed" "HERDR_FAKE_SEND=fail" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=send_failed target=-'
check "send-text timeout → unconfirmed"  "HERDR_FAKE_SEND=sleep HERDR_FAKE_SLEEP=5" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "enter reported fail → pasted"     "HERDR_FAKE_ENTER=fail" \
  'doorbell-outcome v=1 outcome=pasted_not_submitted reason=enter_failed target=pane:7'
check "enter timeout → unconfirmed"      "HERDR_FAKE_ENTER=sleep HERDR_FAKE_SLEEP=5" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "notify-only (SUBMIT=0)"           "LETTERBOX_HERDR_SUBMIT=0" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=notify_only target=-'
check "adapter: herdr missing"           "HERDR_BIN_PATH=/nonexistent/herdr" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=adapter_unavailable target=-'
check "missing python3 → adapter_unavailable (not helper_timeout)" "PATH=$ROOT/bin-nopython" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=adapter_unavailable target=-'
check "wrapper: doorbell env unset"      "LETTERBOX_DOORBELL=" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=adapter_unavailable target=-'
check "wrapper: doorbell not executable" "LETTERBOX_DOORBELL=/etc/hosts" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=adapter_unavailable target=-'
check "wrapper: backstop kill → unconfirmed" "LETTERBOX_DOORBELL=$ROOT/sleeper.sh LETTERBOX_DOORBELL_TIMEOUT=1" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "wrapper: garbage child → unconfirmed" "LETTERBOX_DOORBELL=$ROOT/garbage.sh" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "wrapper: double line → unconfirmed" "LETTERBOX_DOORBELL=$ROOT/double.sh" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=unconfirmed target=-'
check "wrapper: valid line + exit 1 forwards" "LETTERBOX_DOORBELL=$ROOT/valid-exit1.sh" \
  'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7'

# Ruling 5 provenance: the from clause names the durable letter's sender,
# never the calling process identity (ME=tester, letter from relaybot).
craft_letter relaybot 2026-09-16T000000-relaybot-info-crafted-a1b2c3d4
out="$(nudge 2026-09-16T000000-relaybot-info-crafted-a1b2c3d4)"
one_line "$out"
out="$(printf '%s\n' "$out" | grep '^doorbell-outcome ')"
if [[ "$out" == 'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7' ]] \
  && grep -q 'unacked info from relaybot in ' "$HERDR_FAKE_LOG"; then
  echo "PASS: from clause names the letter's sender, not ME"; pass=$((pass+1))
else
  echo "FAIL: from clause names the letter's sender, not ME"; echo "$out"; cat "$HERDR_FAKE_LOG"; exit 1
fi

# Ruling 5 safety: an invalid sender value omits the clause (never "from -").
craft_letter 'bad/../x' 2026-09-16T000001-badsend-info-crafted-b2c3d4e5
: > "$HERDR_FAKE_LOG"
out="$(nudge 2026-09-16T000001-badsend-info-crafted-b2c3d4e5)"
one_line "$out"
out="$(printf '%s\n' "$out" | grep '^doorbell-outcome ')"
if [[ "$out" == 'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7' ]] \
  && ! grep -q ' from ' "$HERDR_FAKE_LOG" \
  && grep -q 'unacked info in ' "$HERDR_FAKE_LOG"; then
  echo "PASS: invalid sender omits the from clause"; pass=$((pass+1))
else
  echo "FAIL: invalid sender omits the from clause"; echo "$out"; cat "$HERDR_FAKE_LOG"; exit 1
fi

echo "──"
echo "herdr edition e2e: $pass/20 PASS"
