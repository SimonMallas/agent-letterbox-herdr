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
h pane run "$p2" "$(runcmd alpha)" >/dev/null
h pane run "$first" "$(runcmd beta)" >/dev/null
for _ in $(seq 1 60); do
  grep -q $'^alpha\t' "$reg" 2>/dev/null && grep -q $'^beta\t' "$reg" 2>/dev/null && break; sleep 0.15
done
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
LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" progress "$id" "$(printf 'half \033]0;pwned\007done\033[31m')" >/dev/null
chk="$(LETTERBOX_DIR="$box" LETTERBOX_AGENT=alpha "$letterbox" check 2>&1)"
printf '%s' "$chk" | grep -q $'\033' && fail "letterbox check passed an escape sequence through"
printf '%s' "$chk" | grep -q 'progress: half' || fail "progress note missing from check: $chk"
printf '%s' "$(view "$p2")" | grep -q $'\033' && fail "popup passed an escape sequence through"
printf '%s\n' 'progress note control characters stripped: PASS'

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
h pane run "$p3" "$(runcmd alpha)" >/dev/null
for _ in $(seq 1 60); do grep -q $'^alpha\t'"$p3"$'\t' "$reg" && break; sleep 0.15; done
grep -q $'^alpha\t'"$p3"$'\t' "$reg" || fail "alpha did not re-register on $p3"
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

printf '%s\n' 'herdr plugin suite: PASS'
