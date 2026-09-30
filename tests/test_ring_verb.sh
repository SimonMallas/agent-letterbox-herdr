#!/usr/bin/env bash
# letterbox ring <to> <type> <id>: the bus-helper-shaped ring that Agent
# Letter Bridge's integrated mode calls. Two halves:
#   1) the verb itself, against a fake herdr and the real adapter;
#   2) the contract: the released bridge's own _bus_ring runs this binary and
#      its own parser judges the output. ALB_PYTHON must be an interpreter with
#      agent-letter-bridge installed; without one this prints SKIP, which CI
#      refuses.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="$(mktemp -d /tmp/lb-ring-test.XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/bin" "$ROOT/box/agent/inbox" "$ROOT/box/agent/processed"
printf 'agent\tpane:7\t/tmp/fake.sock\t2026-09-27T00:00:00Z\n' > "$ROOT/registry.tsv"

cat > "$ROOT/bin/herdr" <<'HERDR'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${HERDR_FAKE_LOG:?}"
[[ "${1:-} ${2:-}" == "pane get" && "${HERDR_FAKE_GET:-ok}" == fail ]] && exit 1
exit 0
HERDR
chmod +x "$ROOT/bin/herdr"

ID="2026-09-27T120000-chat-bridge-info-hello-0a1b2c3d"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: agent\ntype: info\n---\nhello\n' "$ID" \
  > "$ROOT/box/agent/inbox/$ID.md"

# A wrapper the bridge can exec as ALB_BUS_BINARY: env in, letterbox out.
cat > "$ROOT/lb" <<SH
#!/usr/bin/env bash
export PATH="$ROOT/bin:\$PATH" HERDR_FAKE_LOG="$ROOT/herdr.log"
export LETTERBOX_DIR="$ROOT/box" LETTERBOX_DOORBELL="$EDITION/adapters/herdr.sh"
export LETTERBOX_HERDR_REGISTRY="$ROOT/registry.tsv" LETTERBOX_HERDR_PATTERNS=
export LETTERBOX_DOORBELL_TIMEOUT=3
exec "$EDITION/bin/letterbox" "\$@"
SH
chmod +x "$ROOT/lb"

pass=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; shift; printf '  %s\n' "$@"; exit 1; }

expect_line() { # $1=name $2=expected, rest=env for this run
  local name="$1" want="$2" got; shift 2
  got="$(env "$@" "$ROOT/lb" ring agent info "$ID" 2>/dev/null)"
  [[ "$got" == "$want" ]] && ok "$name" || bad "$name" "want: $want" "got:  $got"
}

expect_line "submitted to the registered pane" \
  'doorbell-outcome v=1 outcome=submitted reason=- target=pane:7' LETTERBOX_HERDR_SUBMIT=1
expect_line "without submit it is a toast, never a ring" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=notify_only target=-' LETTERBOX_HERDR_SUBMIT=0
expect_line "dead pane is surface_not_found" \
  'doorbell-outcome v=1 outcome=no_live_surface reason=surface_not_found target=-' \
  LETTERBOX_HERDR_SUBMIT=1 HERDR_FAKE_GET=fail

refused() { # $1=name, rest=args; must exit nonzero, print no contract line, touch no pane
  local name="$1" out rc=0; shift
  : > "$ROOT/herdr.log"
  out="$(LETTERBOX_HERDR_SUBMIT=1 "$ROOT/lb" ring "$@" 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || bad "$name" "exit 0"
  [[ "$out" != *doorbell-outcome* ]] || bad "$name" "printed a contract line: $out"
  [[ ! -s "$ROOT/herdr.log" ]] || bad "$name" "herdr was called: $(cat "$ROOT/herdr.log")"
  ok "$name"
}
refused "a letter that does not exist is not announced" agent info "2026-09-27T120001-nope-0a1b2c3e"
# Both traversals below resolve to the REAL letter, so only the shape
# guards can refuse them; the existence check would let them through.
[[ -f "$ROOT/box/agent/inbox/../../agent/inbox/$ID.md" && -f "$ROOT/box/agent/./inbox/$ID.md" ]] \
  || bad "traversal fixtures must resolve to the real letter"
refused "a path-shaped id is refused" agent info "../../agent/inbox/$ID"
refused "an invalid type is refused" agent bogus "$ID"
refused "a path-shaped recipient is refused" "agent/." info "$ID"
refused "a letter in another inbox is not rung for" other info "$ID"

# Admission is the letter's own envelope, not its filename. Each fixture below
# has the right filename in the right inbox; only what it IS is wrong.
mkdir -p "$ROOT/outside" "$ROOT/box/sym/processed" "$ROOT/box/other/inbox"
envelope() { # $1=file $2=id $3=to $4=type
  printf -- '---\nid: %s\nfrom: chat-bridge\nto: %s\ntype: %s\n---\nx\n' "$2" "$3" "$4" > "$1"
}
X="2026-09-27T120002-chat-bridge-info-x-0a1b2c3f"
envelope "$ROOT/box/agent/inbox/$X.md" "$X" other info
refused "an envelope addressed to someone else is not rung for" agent info "$X"
envelope "$ROOT/box/agent/inbox/$X.md" "$X" agent request
refused "an envelope of another type is not rung for" agent info "$X"
envelope "$ROOT/box/agent/inbox/$X.md" "2026-09-27T120003-someone-else-0a1b2c40" agent info
refused "an envelope with another id is not rung for" agent info "$X"
rm -f "$ROOT/box/agent/inbox/$X.md"
envelope "$ROOT/outside/$X.md" "$X" agent info
ln -s "$ROOT/outside/$X.md" "$ROOT/box/agent/inbox/$X.md"
refused "a symlinked letter is not rung for" agent info "$X"
rm -f "$ROOT/box/agent/inbox/$X.md"
envelope "$ROOT/outside/$X.md" "$X" sym info
ln -s "$ROOT/outside" "$ROOT/box/sym/inbox"
refused "a symlinked inbox is not rung for" sym info "$X"

# The injected line carries the token derived from THIS letter id.
: > "$ROOT/herdr.log"
LETTERBOX_HERDR_SUBMIT=1 "$ROOT/lb" ring agent info "$ID" >/dev/null
grep -Eq "pane send-text pane:7 .*unacked info from chat-bridge in .*/agent/inbox/ — please check · [0-9a-f]{8}$" "$ROOT/herdr.log" \
  && ok "line names the letter's sender and carries a token" \
  || bad "line names the letter's sender and carries a token" "$(cat "$ROOT/herdr.log")"

# --- contract: the released bridge judges this binary -------------------------
if [[ -z "${ALB_PYTHON:-}" ]] || ! "$ALB_PYTHON" -c 'import alb.bridge.run' 2>/dev/null; then
  echo "test: SKIP bridge contract (set ALB_PYTHON to a python with agent-letter-bridge)"
  echo "ring verb suite: $pass passed (contract skipped)"
  exit 0
fi

contract() { # $1=name $2=python assertion on (exc) ; rest=env
  local name="$1" check="$2"; shift 2
  env "$@" "$ALB_PYTHON" -I - "$ROOT/lb" "$ID" "$check" <<'PY' || bad "$name"
import sys
from alb.bridge import run
binary, lid, check = sys.argv[1:4]
exc = None
try:
    run._bus_ring("agent", "info", lid, binary=binary)
except Exception as e:  # noqa: BLE001
    exc = e
reason = None if exc is None else run._ring_failure_reason(exc)
assert eval(check), f"exc={exc!r} reason={reason!r}"
PY
  ok "$name"
}
contract "bridge: submitted counts as delivered" "exc is None" LETTERBOX_HERDR_SUBMIT=1
contract "bridge: a toast is not delivered (notify_only)" \
  "isinstance(exc, run.RingNotDelivered) and reason == 'notify_only'" LETTERBOX_HERDR_SUBMIT=0
contract "bridge: dead pane is not delivered (surface_not_found)" \
  "isinstance(exc, run.RingNotDelivered) and reason == 'surface_not_found'" \
  LETTERBOX_HERDR_SUBMIT=1 HERDR_FAKE_GET=fail

echo "ring verb suite: PASS ($pass)"
