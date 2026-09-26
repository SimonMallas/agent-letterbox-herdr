#!/usr/bin/env bash
# Live proof of the Agent Letterbox Herdr plugin on a disposable, fully isolated
# Herdr session (config AND state dirs). Never touches the user's Herdr.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"

command -v herdr >/dev/null 2>&1 || { echo 'herdr plugin test: SKIP (herdr unavailable)'; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo 'herdr plugin test: FAIL (python3 required)'; exit 1; }

tmp="/tmp/lbq$$"
rm -rf "$tmp"; mkdir -p "$tmp"
sess="q$$"; herdr_pid=""
export XDG_CONFIG_HOME="$tmp/x" XDG_STATE_HOME="$tmp/s" HERDR_CONFIG_PATH="$tmp/x/h"
mkdir -p "$HERDR_CONFIG_PATH" "$XDG_STATE_HOME"
unset HERDR_SOCKET_PATH HERDR_SESSION HERDR_PANE_ID HERDR_ENV || true

cleanup() {
  set +e
  herdr --session "$sess" session stop "$sess" >/dev/null 2>&1
  herdr --session "$sess" session delete "$sess" >/dev/null 2>&1
  [[ -n "$herdr_pid" ]] && { kill "$herdr_pid" >/dev/null 2>&1; wait "$herdr_pid" 2>/dev/null; }
  rm -rf "$tmp"
}
trap cleanup EXIT
h() { herdr --session "$sess" "$@"; }
fail() { echo "herdr plugin test: FAIL ($*)" >&2; exit 1; }

python3 - "$sess" <<'PY' &
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/tmp"); env = os.environ.copy(); env["TERM"] = "xterm-256color"
    os.execvpe("herdr", ["herdr", "--session", sys.argv[1]], env)
while True:
    try: os.read(fd, 1024)
    except OSError: break
os.waitpid(pid, 0)
PY
herdr_pid=$!
for _ in $(seq 1 80); do h pane list >/dev/null 2>&1 && break; sleep 0.1; done
h pane list >/dev/null 2>&1 || fail "isolated Herdr did not start"
socket="$(h status 2>/dev/null | awk -F': ' '/socket:/{print $2; exit}' | tr -d '[:space:]')"
case "$socket" in "$XDG_CONFIG_HOME"/*|"$HERDR_CONFIG_PATH"/*) ;; *) fail "socket not isolated: $socket";; esac
first="$(h pane list | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["panes"][0]["pane_id"])')"

box="$tmp/box"
HOME="$tmp/home" LETTERBOX_BIN_DIR="$tmp/bin" LETTERBOX_SKILLS_DIR="$tmp/skills" \
  "$letterbox" herdr setup --agents alpha,beta --dir "$box" >/dev/null
reg="$box/herdr-agents.tsv"

# --- link: the repository root is the plugin ---
h plugin link "$root" >/dev/null || fail "plugin link"
listing="$(h plugin list 2>&1)"
printf '%s\n' "$listing" | grep -q 'agent-letterbox .*enabled' || fail "plugin not listed as enabled: $listing"
printf '%s\n' 'plugin link: PASS'

# --- register alpha in a new pane, beta in the first pane ---
split="$(h pane split "$first" --direction right --no-focus)"
p2="$(printf '%s' "$split" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')"
runcmd() { printf "export PATH='%s/bin:'\"\$PATH\" LETTERBOX_DIR='%s' LETTERBOX_HERDR_REGISTRY='%s'; letterbox herdr run %s -- cat" "$root" "$box" "$reg" "$1"; }
# Start agents ONE AT A TIME: Herdr 0.9.1 can interleave the text of two back-to-back
# `pane run` calls into one pane. Wait for a prompt, run, then wait for the registration.
start_agent() { # $1 = agent, $2 = pane
  h pane wait-output "$2" --regex '[%$#>] ?$' --source visible --lines 3 --timeout 15000 >/dev/null 2>&1 || true
  h pane run "$2" "$(runcmd "$1")" >/dev/null
  for _ in $(seq 1 100); do grep -q "^$1"$'\t'"$2"$'\t' "$reg" 2>/dev/null && return 0; sleep 0.15; done
  h pane read "$2" --source recent-unwrapped --lines 20 >&2 || true
  fail "$1 did not register on $2"
}
start_agent alpha "$p2"
start_agent beta "$first"
grep -q $'^alpha\t'"$p2"$'\t' "$reg" || fail "alpha not registered on $p2"
grep -q $'^beta\t'"$first"$'\t' "$reg" || fail "beta not registered on $first"

# --- view: the focused agent's inbox and owed requests ---
printf 'Please review the parser.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$letterbox" send alpha request parser-review >/dev/null
view() { # $1 = focused pane; no LETTERBOX_DIR: the plugin must find the box setup recorded
  printf 'x' | env -u LETTERBOX_DIR HERDR_PLUGIN_ROOT="$root" HERDR_SOCKET_PATH="$socket" \
    HERDR_PLUGIN_CONTEXT_JSON="{\"focused_pane_id\":\"$1\"}" bash "$root/plugin/view.sh" 2>&1
}
out="$(view "$p2")"
printf '%s\n' "$out" | grep -q 'Agent Letterbox: alpha' || fail "view did not resolve alpha: $out"
box_real="$(cd "$box" && pwd -P)"
printf '%s\n' "$out" | grep -qF "(box $box_real)" || fail "view did not use the box setup recorded: $out"
printf '%s\n' "$out" | grep -q '^What I owe' || fail "view missing owed section"
printf '%s\n' "$out" | grep -qE '^  .* from beta +request +parser-review' || fail "owed line missing the open request: $out"
printf '%s\n' "$out" | grep -q '^Overdue' || fail "view missing overdue section"
[[ "$(printf '%s\n' "$out" | wc -l)" -le 30 ]] || fail "view too tall for the popup: $(printf '%s\n' "$out" | wc -l) lines"
printf '%s\n' 'plugin view (registered agent): PASS'
out="$(view "no-such-pane")"
printf '%s\n' "$out" | grep -q 'not registered as a Letterbox agent' || fail "unregistered pane message missing: $out"
printf '%s\n' 'plugin view (unregistered pane): PASS'
out="$(printf 'x' | env -u LETTERBOX_DIR XDG_CONFIG_HOME="$tmp/empty" HERDR_PLUGIN_ROOT="$root" HERDR_SOCKET_PATH="$socket" \
  HERDR_PLUGIN_CONTEXT_JSON="{\"focused_pane_id\":\"$p2\"}" bash "$root/plugin/view.sh" 2>&1)"
printf '%s\n' "$out" | grep -q 'No Letterbox found' || fail "no-box message missing: $out"
[[ ! -e "$root/.letterbox" && ! -e "$root/plugin/.letterbox" ]] || fail "plugin created a .letterbox in its own tree"
printf '%s\n' 'plugin view (no box): PASS'

# --- F2: untrusted progress notes never pass control sequences through ---
printf 'Tracked task.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$letterbox" send alpha request tracked-task --ack >/dev/null
id="$(ls "$box/alpha/inbox/" | grep 'tracked-task' | grep -v '\.ack$' | head -1 | sed 's/\.md$//')"
printf 'On it.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" reply "$id" ack tracked-task-ack >/dev/null
LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" progress "$id" "$(printf 'half \033]0;pwned\007done\033[31m \302\235osc\302\234 caf\303\251')" >/dev/null
chk="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" check 2>&1)"
printf '%s' "$chk" | grep -q $'\033' && fail "letterbox check passed an escape sequence through"
printf '%s' "$chk" | LC_ALL=C grep -q $'\xc2[\x80-\x9f]' && fail "letterbox check passed a C1 control through"
printf '%s' "$chk" | grep -q 'café' || fail "letterbox check mangled legitimate UTF-8: $chk"
printf '%s' "$chk" | grep -q 'progress: half' || fail "progress note missing from check: $chk"
printf '%s' "$(view "$p2")" | grep -q $'\033' && fail "popup passed an escape sequence through"
printf '%s\n' 'progress note control characters stripped: PASS'

# --- R2: an answer in the sender's mailbox keeps finished work out of "What I owe" ---
printf 'Check the lexer.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$letterbox" send alpha request lexer-check >/dev/null
lid="$(ls "$box/alpha/inbox/" | grep 'lexer-check' | head -1 | sed 's/\.md$//')"
printf 'Done.\n' | LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" reply "$lid" result lexer-done >/dev/null
# Simulate the archive step failing after the RESULT was published: parent back in the inbox.
[[ -f "$box/alpha/processed/$lid.md" ]] && mv "$box/alpha/processed/$lid.md" "$box/alpha/inbox/$lid.md"
owed="$(view "$p2" | sed -n '/^What I owe/,/^Overdue/p')"
printf '%s\n' "$owed" | grep -q '+[0-9]* more' && fail "R2 setup: owed list is capped, so the check would be vacuous: $owed"
printf '%s\n' "$owed" | grep -q 'lexer-check' && fail "R2: answered request shown as owed: $owed"
printf '%s\n' 'answered work stays out of what I owe (R2): PASS'

# --- F4: a busy inbox still fits, with an explicit "+N more" ---
for i in $(seq 1 25); do printf 'task %s\n' "$i" | LETTERBOX_DIR="$box" LETTERBOX_AGENT=beta "$letterbox" send alpha request "bulk-$i" >/dev/null; done
out="$(view "$p2")"
[[ "$(printf '%s\n' "$out" | wc -l)" -le 30 ]] || fail "busy popup too tall: $(printf '%s\n' "$out" | wc -l) lines"
printf '%s\n' "$out" | grep -qE '^  \+[0-9]+ more' || fail "busy popup hides letters without saying so"
printf '%s\n' 'plugin view (busy inbox capped): PASS'

# --- F5: a bad overdue setting is visible, never a silent all-clear ---
out="$(printf 'x' | env -u LETTERBOX_DIR LETTERBOX_PLUGIN_OVERDUE_HOURS=abc HERDR_PLUGIN_ROOT="$root" HERDR_SOCKET_PATH="$socket" \
  HERDR_PLUGIN_CONTEXT_JSON="{\"focused_pane_id\":\"$p2\"}" bash "$root/plugin/view.sh" 2>&1)"
printf '%s\n' "$out" | grep -q 'is not a positive number; using 24' || fail "bad hours not reported: $out"
printf '%s\n' 'plugin view (bad overdue hours): PASS'

# --- F1: a stale close event must not delete a live re-registration ---
p3="$(h pane split "$first" --direction down --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')"
start_agent alpha "$p3"
# Reproduce the race exactly: the hook's registry lookup sees the STALE row (alpha on
# $p2, read before the re-registration), while the registry already holds alpha on $p3.
race="$tmp/race"; mkdir -p "$race/bin"
cat > "$race/bin/letterbox" <<RACE
#!/usr/bin/env bash
if [[ "\$1 \$2" == "herdr status" ]]; then
  printf 'agent\tpane_id\tsocket_path\tregistered_at\n'
  printf 'alpha\t%s\t%s\t2026-01-01T00:00:00Z\n' "$p2" "$socket"
  exit 0
fi
exec "$letterbox" "\$@"
RACE
chmod +x "$race/bin/letterbox"
HERDR_PLUGIN_ROOT="$race" HERDR_SOCKET_PATH="$socket" HERDR_PLUGIN_EVENT=pane.closed \
  HERDR_PLUGIN_EVENT_JSON="{\"event\":\"pane_closed\",\"data\":{\"pane_id\":\"$p2\"}}" \
  env -u LETTERBOX_DIR bash "$root/plugin/on-pane-gone.sh" >/dev/null
grep -q $'^alpha\t'"$p3"$'\t' "$reg" || fail "stale close event for $p2 deleted alpha's live registration on $p3"
printf '%s\n' 'stale close event keeps a live re-registration: PASS'

# --- action: opens the popup without error ---
act="$(h plugin action invoke agent-letterbox.open 2>&1)" || fail "action invoke: $act"
printf '%s' "$act" | grep -q '"error"' && fail "action returned an error: $act"
printf '%s\n' 'plugin action open: PASS'

# --- event: closing alpha's pane removes ONLY alpha's registration ---
focused="$(h pane list | python3 -c 'import sys,json; print(next((p["pane_id"] for p in json.load(sys.stdin)["result"]["panes"] if p.get("focused")),""))')"
[[ -n "$focused" && "$focused" != "$p3" ]] || fail "expected a focused pane other than $p3 (focused=$focused)"
h pane close "$p3" >/dev/null || fail "pane close"
gone=0
for _ in $(seq 1 60); do grep -q $'^alpha\t' "$reg" || { gone=1; break; }; sleep 0.15; done
[[ "$gone" == 1 ]] || fail "alpha still registered after its pane closed: $(cat "$reg")"
grep -q $'^beta\t'"$first"$'\t' "$reg" || fail "beta registration was removed too"
printf '%s\n' 'plugin pane.closed cleanup: PASS'

# --- R1: registry writers are serialized (no lost update across cleanup + register) ---
p4="$(h pane split "$first" --direction down --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')"
printf 'alpha\t%s\t%s\t2026-01-01T00:00:00Z\n' "$p2" "$socket" >> "$reg"
shim="$tmp/shim"; mkdir -p "$shim"; real_mv="$(command -v mv)"
cat > "$shim/mv" <<SHIM
#!/usr/bin/env bash
# Pause the FIRST registry rename until released; every other mv passes straight through.
if [[ "\$(basename -- "\${@: -1}")" == "herdr-agents.tsv" && ! -e "$tmp/paused" ]]; then
  : > "$tmp/paused"
  for _ in \$(seq 1 200); do [[ -e "$tmp/release" ]] && break; sleep 0.05; done
fi
exec "$real_mv" "\$@"
SHIM
chmod +x "$shim/mv"
PATH="$shim:$PATH" LETTERBOX_DIR="$box" "$letterbox" herdr unregister alpha --pane "$p2" --socket "$socket" >/dev/null &
cleanup_pid=$!
for _ in $(seq 1 100); do [[ -e "$tmp/paused" ]] && break; sleep 0.05; done
[[ -e "$tmp/paused" ]] || fail "R1 setup: cleanup never reached its rename"
HERDR_ENV=1 HERDR_PANE_ID="$p4" HERDR_SOCKET_PATH="$socket" LETTERBOX_DIR="$box" \
  "$letterbox" herdr register alpha >/dev/null 2>&1 &
register_pid=$!
sleep 0.5
: > "$tmp/release"
wait "$cleanup_pid" || true
wait "$register_pid" || true
grep -q $'^alpha\t'"$p4"$'\t' "$reg" || fail "R1: registration on $p4 lost to an overlapping cleanup: $(cat "$reg")"
printf '%s\n' 'registry writers serialized (R1): PASS'

# --- R3: rows the query cannot classify are marked, not presented as established ---
cat > "$box/alpha/inbox/2026-01-01T000000-beta-request-legacy-undated-0badcafe.md" <<LEGACY
---
id: 2026-01-01T000000-beta-request-legacy-undated-0badcafe
from: beta
to: alpha
type: request
re:
priority: next
requires_ack: false
---
An older letter with no sent header.
LEGACY
overdue="$(view "$p4" | sed -n '/^Overdue/,$p')"
if printf '%s\n' "$overdue" | grep -q 'legacy-undated'; then
  printf '%s\n' "$overdue" | grep 'legacy-undated' | grep -q 'uncertain' || fail "R3: undated letter shown as established overdue: $overdue"
fi
printf '%s\n' 'uncertain rows are marked (R3): PASS'

# --- Stale lock: nobody clears it without the gate; the gate is shared per lock ---
box_real="$(cd "$box" && pwd -P)"; reg_real="$box_real/herdr-agents.tsv"; lock="$reg_real.lifecycle.lock"
gate="$box_real/.letterbox-stale-lock-gate"
box2="$tmp/box2"; mkdir -p "$box2/locks"
stale_case() { # $1 = label, $2 = agent, $3 = pane, $4 = LETTERBOX_DIR for the writer
  sh -c 'exit 0' & local dead=$!; wait "$dead" || true
  mkdir "$lock"; printf '%s\n' "$dead" > "$lock/pid"
  rm -f "$tmp/gate-held" "$tmp/gate-release"
  # Another breaker in the middle of its work: it holds the gate.
  perl -MFcntl=:flock -e 'open(my $g, ">>", $ARGV[0]) or die; flock($g, LOCK_EX) or die;
    open(my $m, ">", $ARGV[1]); close $m;
    for (1 .. 400) { last if -e $ARGV[2]; select(undef, undef, undef, 0.05) }' \
    "$gate" "$tmp/gate-held" "$tmp/gate-release" &
  local holder=$!
  for _ in $(seq 1 100); do [[ -e "$tmp/gate-held" ]] && break; sleep 0.05; done
  [[ -e "$tmp/gate-held" ]] || fail "$1: could not take the gate"
  HERDR_ENV=1 HERDR_PANE_ID="$3" HERDR_SOCKET_PATH="$socket" LETTERBOX_DIR="$4" LETTERBOX_HERDR_REGISTRY="$reg_real" \
    "$letterbox" herdr register "$2" >/dev/null 2>&1 &
  local writer=$!
  sleep 1.5
  [[ "$(cat "$lock/pid" 2>/dev/null)" == "$dead" ]] || fail "$1: the stale lock was cleared while another breaker held the gate"
  kill -0 "$writer" 2>/dev/null || fail "$1: the writer finished while the gate was held"
  : > "$tmp/gate-release"; wait "$holder" || true
  wait "$writer" || fail "$1: the writer failed after the gate was released"
  grep -q "^$2"$'\t'"$3"$'\t' "$reg" || fail "$1: $2's registration was lost: $(cat "$reg")"
  [[ ! -e "$lock" ]] || fail "$1: lock left behind"
  printf '%s\n' "$1: PASS"
}
p5="$(h pane split "$first" --direction right --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')"
p6="$(h pane split "$first" --direction down --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')"
stale_case 'stale lock waits for the gate' gamma "$p5" "$box"
stale_case 'stale lock across two roots sharing one registry' epsilon "$p6" "$box2"

# --- A lock held under another user's live pid is never broken, and never hangs ---
mkdir "$lock"; printf '1\n' > "$lock/pid"
start_s=$SECONDS
if LETTERBOX_DIR="$box" perl -e 'alarm 45; exec @ARGV' "$letterbox" herdr unregister nobody >/dev/null 2>&1; then
  fail "foreign live pid: unregister succeeded through a live owner's lock"
fi
rc=$?
[[ "$rc" -ne 142 ]] || fail "foreign live pid: unregister hung (killed by the 45 s alarm)"
[[ -d "$lock" ]] || fail "foreign live pid: a live owner's lock was removed"
rm -f "$lock/pid"; rmdir "$lock"
printf '%s\n' "foreign live pid fails loudly in $((SECONDS - start_s)) s: PASS"

printf '%s\n' 'herdr plugin suite: PASS'
