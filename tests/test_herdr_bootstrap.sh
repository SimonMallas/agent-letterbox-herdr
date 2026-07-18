#!/usr/bin/env bash
# Isolated live Herdr proof: disposable config + named session only.
# Never touches the user's default Herdr server/workspaces.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
adapter="$root/adapters/herdr.sh"

command -v herdr >/dev/null 2>&1 || {
  echo 'herdr bootstrap test: SKIP (herdr unavailable)'
  exit 0
}
command -v python3 >/dev/null 2>&1 || {
  echo 'herdr bootstrap test: FAIL (python3 required for isolation harness)'
  exit 1
}

# Short paths required: Unix socket sun_path is small.
tmp="/tmp/lbh$$"
rm -rf "$tmp"
mkdir -p "$tmp"
sess="s$$"
herdr_pid=""
export XDG_CONFIG_HOME="$tmp/x"
export HERDR_CONFIG_PATH="$tmp/x/h"
mkdir -p "$HERDR_CONFIG_PATH"
# Never inherit the caller's Herdr session/socket.
unset HERDR_SOCKET_PATH HERDR_SESSION || true

cleanup() {
  set +e
  if [[ -n "${sess:-}" ]]; then
    herdr --session "$sess" session stop "$sess" >/dev/null 2>&1
    herdr --session "$sess" session delete "$sess" >/dev/null 2>&1
  fi
  if [[ -n "${herdr_pid:-}" ]]; then
    kill "$herdr_pid" >/dev/null 2>&1
    wait "$herdr_pid" 2>/dev/null
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

h() {
  # All herdr CLI traffic is forced onto the disposable session.
  herdr --session "$sess" "$@"
}

# Start disposable Herdr server/TUI under a real PTY with isolated config.
python3 - "$sess" "$HERDR_CONFIG_PATH" "$XDG_CONFIG_HOME" <<'PY' &
import os, pty, sys, pathlib
sess, config, xdg = sys.argv[1], sys.argv[2], sys.argv[3]
env = os.environ.copy()
env["XDG_CONFIG_HOME"] = xdg
env["HERDR_CONFIG_PATH"] = config
env["TERM"] = "xterm-256color"
env.pop("HERDR_SOCKET_PATH", None)
env.pop("HERDR_SESSION", None)
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/tmp")
    os.execvpe("herdr", ["herdr", "--session", sess], env)
# parent: keep PTY open by reading forever until killed
try:
    while True:
        try:
            os.read(fd, 1024)
        except OSError:
            break
except KeyboardInterrupt:
    pass
os.waitpid(pid, 0)
PY
herdr_pid=$!

# Wait for isolated server
ready=0
for _ in $(seq 1 80); do
  if h pane list >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo 'herdr bootstrap test: FAIL (could not start isolated Herdr session/server)' >&2
  h status >&2 || true
  exit 1
fi

# Capture the auto-created root workspace/pane IDs only (no hard-coded w1).
pane_json="$(h pane list)"
pane_id="$(printf '%s\n' "$pane_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["result"]["panes"][0]["pane_id"])')"
ws_id="$(printf '%s\n' "$pane_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["result"]["panes"][0]["workspace_id"])')"
test -n "$pane_id"
test -n "$ws_id"
socket_path="$(h status 2>/dev/null | awk -F': ' '/socket:/{print $2; exit}' | tr -d '[:space:]')"
test -n "$socket_path"
# Socket must live under our temp config, never the user default home config.
# Isolated config root (Herdr uses $XDG_CONFIG_HOME/herdr for named sessions)
iso_root="$XDG_CONFIG_HOME/herdr"
case "$socket_path" in
  "$iso_root"/*|"$HERDR_CONFIG_PATH"/*) ;;
  *)
    echo "herdr bootstrap test: FAIL (socket not under isolated config: $socket_path)" >&2
    exit 1
    ;;
esac
printf '%s\n' "isolated session ready: sess=$sess pane=$pane_id ws=$ws_id"

box="$tmp/box"

# --- setup (also isolated HOME for links) ---
HOME="$tmp/home" \
LETTERBOX_BIN_DIR="$tmp/bin" \
LETTERBOX_SKILLS_DIR="$tmp/skills" \
"$letterbox" herdr setup --agents alpha,beta --dir "$box" --automatic-doorbells >/dev/null

test -f "$box/env.sh"
test -f "$box/herdr-agents.tsv"
grep -q 'adapters/herdr.sh' "$box/env.sh"
grep -q 'LETTERBOX_HERDR_SUBMIT=1' "$box/env.sh"
grep -q 'LETTERBOX_HERDR_REGISTRY=' "$box/env.sh"
if grep -qiE 'tmux|cmux' "$box/env.sh"; then
  echo 'setup env mentions tmux/cmux' >&2
  exit 1
fi
printf '%s\n' 'herdr setup: PASS'

# --- live register via letterbox herdr run inside the isolated pane ---
: > "$box/herdr-patterns.tsv"
cmd="export PATH='$root/bin:'\"\$PATH\" LETTERBOX_DIR='$box' LETTERBOX_HERDR_REGISTRY='$box/herdr-agents.tsv'; letterbox herdr run alpha -- cat"
# Ensure herdr CLI inside pane uses the same isolated session socket via env already injected by Herdr.
h pane run "$pane_id" "$cmd" >/dev/null

registered=0
for _ in $(seq 1 50); do
  if grep -q $'^alpha\t' "$box/herdr-agents.tsv" 2>/dev/null; then
    registered=1
    break
  fi
  sleep 0.15
done
if [[ "$registered" != 1 ]]; then
  echo 'letterbox herdr run did not register alpha' >&2
  cat "$box/herdr-agents.tsv" >&2 || true
  h pane read "$pane_id" --source recent-unwrapped --lines 50 >&2 || true
  exit 1
fi
printf '%s\n' 'herdr run live register: PASS'

reg_line="$(awk -F '\t' '$1=="alpha"{print; exit}' "$box/herdr-agents.tsv")"
# agent, pane, socket
printf '%s\n' "$reg_line" | awk -F '\t' -v sock="$socket_path" '
  NF>=3 && $2 != "" && index($3, "herdr.sock")>0 { exit 0 }
  { exit 1 }
' || { echo "bad registry line: $reg_line" >&2; exit 1; }
# Registered socket must be the isolated session socket (or under isolated config)
reg_sock="$(printf '%s\n' "$reg_line" | awk -F '\t' '{print $3}')"
case "$reg_sock" in
  "$iso_root"/*|"$HERDR_CONFIG_PATH"/*) ;;
  *)
    echo "registry socket not isolated: $reg_sock" >&2
    exit 1
    ;;
esac
printf '%s\n' 'registry pane+socket: PASS'

out="$(LETTERBOX_DIR="$box" LETTERBOX_HERDR_REGISTRY="$box/herdr-agents.tsv" "$letterbox" herdr status)"
printf '%s\n' "$out" | grep -q 'alpha' || { echo "status missing alpha: $out" >&2; exit 1; }
printf '%s\n' 'herdr status: PASS'

reg_pane="$(awk -F '\t' '$1=="alpha"{print $2; exit}' "$box/herdr-agents.tsv")"
# Must match the captured disposable pane (no accidental default-server pane)
[[ "$reg_pane" == "$pane_id" ]] || {
  echo "registered pane $reg_pane != isolated pane $pane_id" >&2
  exit 1
}

# --- registry-first doorbell (patterns empty) ---
LETTERBOX_DIR="$box" \
LETTERBOX_HERDR_REGISTRY="$box/herdr-agents.tsv" \
LETTERBOX_HERDR_PATTERNS="$box/herdr-patterns.tsv" \
LETTERBOX_HERDR_SUBMIT=1 \
HERDR_SOCKET_PATH="$socket_path" \
"$adapter" alpha delegate boot-test

sleep 0.6
received="$(h pane read "$reg_pane" --source recent-unwrapped --lines 60 2>/dev/null || true)"
if ! printf '%s\n' "$received" | grep -Fq "unacked delegate in $box/alpha/inbox/"; then
  text="$(printf '%s\n' "$received" | python3 -c 'import sys,json
raw=sys.stdin.read()
try:
  d=json.loads(raw); r=d.get("result",d)
  print(r.get("text") or r.get("content") or raw)
except Exception:
  print(raw)
' 2>/dev/null || true)"
  printf '%s\n' "$text" | grep -Fq "unacked delegate in $box/alpha/inbox/" || {
    echo "doorbell not found. pane read:" >&2
    printf '%s\n' "$received" >&2
    exit 1
  }
fi
printf '%s\n' 'registry-first live doorbell: PASS'

LETTERBOX_DIR="$box" LETTERBOX_HERDR_REGISTRY="$box/herdr-agents.tsv" \
  "$letterbox" herdr unregister alpha >/dev/null
if grep -q $'^alpha\t' "$box/herdr-agents.tsv" 2>/dev/null; then
  echo 'unregister failed' >&2
  exit 1
fi
printf '%s\n' 'herdr unregister: PASS'

if "$letterbox" tmux status 2>/dev/null; then
  echo 'tmux subcommand still present' >&2
  exit 1
fi
if "$letterbox" cmux status 2>/dev/null; then
  echo 'cmux subcommand still present' >&2
  exit 1
fi
if "$letterbox" 2>&1 | grep -qiE 'tmux|cmux'; then
  echo 'usage still mentions tmux/cmux' >&2
  exit 1
fi
printf '%s\n' 'no tmux/cmux CLI: PASS'

# Close only the captured disposable workspace ID (never a hard-coded w1).
h workspace close "$ws_id" >/dev/null

printf '%s\n' 'herdr bootstrap suite: PASS'
