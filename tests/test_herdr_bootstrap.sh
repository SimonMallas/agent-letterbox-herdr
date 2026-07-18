#!/usr/bin/env bash
# Live Herdr proof: setup, letterbox herdr run registration, registry-first doorbell.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
adapter="$root/adapters/herdr.sh"
tmp="$(mktemp -d)"
ws_label="lb-herdr-$$"
trap 'herdr workspace list 2>/dev/null | grep -q "$ws_label" && {
  # best-effort cleanup of test workspace if still present
  wid="$(herdr workspace list 2>/dev/null | python3 -c "import sys,json,re;
try:
  d=json.load(sys.stdin);
  print(next((w[\"workspace_id\"] for w in d[\"result\"][\"workspaces\"] if w.get(\"label\")==sys.argv[1]),\"\"))
except Exception:
  print(\"\")
" "$ws_label" 2>/dev/null || true)"
  [[ -n "${wid:-}" ]] && herdr workspace close "$wid" >/dev/null 2>&1 || true
}; rm -rf "$tmp"' EXIT

command -v herdr >/dev/null 2>&1 || { echo 'herdr bootstrap test: SKIP (herdr unavailable)'; exit 0; }
if ! herdr status 2>/dev/null | grep -E 'status:[[:space:]]*running' >/dev/null; then
  # also accept JSON-ish / alternate formats
  if ! herdr pane list >/dev/null 2>&1; then
    echo 'herdr bootstrap test: SKIP (herdr server not running; start herdr first)'
    exit 0
  fi
fi

box="$tmp/box"

# --- setup ---
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

# --- create disposable workspace + pane, launch via letterbox herdr run ---
: > "$box/herdr-patterns.tsv"
create_json="$(herdr workspace create --cwd "$tmp" --label "$ws_label")"
pane_id="$(printf '%s\n' "$create_json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')"
test -n "$pane_id"

# Type letterbox herdr run into the pane shell (pane already has HERDR_* env)
cmd="export PATH='$root/bin:'\"\$PATH\" LETTERBOX_DIR='$box' LETTERBOX_HERDR_REGISTRY='$box/herdr-agents.tsv'; letterbox herdr run alpha -- cat"
herdr pane run "$pane_id" "$cmd" >/dev/null

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
  herdr pane read "$pane_id" --source recent-unwrapped --lines 40 >&2 || true
  exit 1
fi
printf '%s\n' 'herdr run live register: PASS'

# registry must record pane + socket
reg_line="$(awk -F '\t' '$1=="alpha"{print; exit}' "$box/herdr-agents.tsv")"
printf '%s\n' "$reg_line" | awk -F '\t' 'NF>=3 && $2 ~ /^w[0-9]+:p[0-9]+$/ && $3 ~ /herdr\.sock/ { exit 0 } { exit 1 }' \
  || { echo "bad registry line: $reg_line" >&2; exit 1; }
printf '%s\n' 'registry pane+socket: PASS'

out="$(LETTERBOX_DIR="$box" LETTERBOX_HERDR_REGISTRY="$box/herdr-agents.tsv" "$letterbox" herdr status)"
printf '%s\n' "$out" | grep -q 'alpha' || { echo "status missing alpha: $out" >&2; exit 1; }
printf '%s\n' 'herdr status: PASS'

reg_pane="$(awk -F '\t' '$1=="alpha"{print $2; exit}' "$box/herdr-agents.tsv")"

# --- registry-first doorbell ---
LETTERBOX_DIR="$box" \
LETTERBOX_HERDR_REGISTRY="$box/herdr-agents.tsv" \
LETTERBOX_HERDR_PATTERNS="$box/herdr-patterns.tsv" \
LETTERBOX_HERDR_SUBMIT=1 \
"$adapter" alpha delegate boot-test

sleep 0.6
received="$(herdr pane read "$reg_pane" --source recent-unwrapped --lines 40 2>/dev/null || true)"
# pane read returns JSON; also try plain extraction
if ! printf '%s\n' "$received" | grep -Fq "unacked delegate in $box/alpha/inbox/"; then
  # parse JSON text field if present
  text="$(printf '%s\n' "$received" | python3 -c 'import sys,json,re
raw=sys.stdin.read()
try:
  d=json.loads(raw)
  r=d.get("result",d)
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

# cleanup test workspace
herdr workspace close w1 >/dev/null 2>&1 || true

printf '%s\n' 'herdr bootstrap suite: PASS'
