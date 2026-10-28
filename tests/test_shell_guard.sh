#!/usr/bin/env bash
# A doorbell must never be typed into a shell: run there, its line is a command.
# Herdr 0.9.1+ says which agent occupies a pane and submits text with Enter
# only while that agent is in front (agent prompt; a blocked agent is refused).
# Anything else is checked with pane process-info: a shell at its prompt owns
# the foreground process group. Below 0.9.1, or when Herdr cannot say, the
# doorbell is typed as before, without the check, as every edition types it
# (28 Oct). The mock answers in the shapes Herdr 0.9.1 gave live.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
work="$(mktemp -d /tmp/lb-shell-guard.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state" "$work/box/reviewer/inbox" "$work/box/reviewer/processed"
printf 'reviewer\tw1:p1\n' > "$work/box/herdr-patterns.tsv"
export MOCK_STATE="$work/state"

cat > "$work/bin/herdr" <<'MOCK'
#!/usr/bin/env bash
S="$MOCK_STATE"
printf '%s\n' "$*" >> "$S/calls.log"
case "$1 ${2:-}" in
  "status server")
    v="$(cat "$S/version")"
    [[ "$v" == down ]] && { echo '{"status":"not running","running":false}'; exit 0; }
    printf '{"status":"running","running":true,"version":"%s","protocol":22}\n' "$v";;
  "pane get") echo '{"result":{"type":"pane_info"}}';;
  "agent get")
    if [[ -f "$S/agent" ]]; then
      printf '{"id":"cli:agent:get","result":{"agent":{"agent":"example","agent_status":"%s","pane_id":"%s"},"type":"agent_info"}}\n' "$(cat "$S/agent")" "$3"
    else
      echo '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:get"}' >&2; exit 1
    fi;;
  "agent prompt")
    case "$(cat "$S/agent" 2>/dev/null || echo none)" in
      none) echo '{"error":{"code":"agent_not_found","message":"not found"},"id":"cli:agent:prompt"}' >&2; exit 1;;
      blocked) echo '{"error":{"code":"agent_blocked","message":"blocked"},"id":"cli:agent:prompt"}' >&2; exit 1;;
      gone) echo '{"error":{"code":"agent_not_ready","message":"no longer the pane foreground process"},"id":"cli:agent:prompt"}' >&2; exit 1;;
    esac
    echo '{"id":"cli:agent:prompt","result":{"agent":{"agent":"example","agent_status":"working"},"type":"agent_prompted"}}';;
  "pane process-info")
    # What is in front, one entry per call; the last entry repeats.
    front="$(head -n 1 "$S/front")"
    if [[ "$(wc -l < "$S/front")" -gt 1 ]]; then tail -n +2 "$S/front" > "$S/front.next"; mv "$S/front.next" "$S/front"; fi
    case "$front" in
      shell) group=100;; app) group=200;;
      unknown) echo '{"id":"cli:pane:process_info","result":{"process_info":{"pane_id":"w1:p1"},"type":"pane_process_info"}}'; exit 0;;
      error) echo '{"error":{"code":"pane_not_found","message":"gone"}}' >&2; exit 1;;
    esac
    printf '{"id":"cli:pane:process_info","result":{"process_info":{"foreground_process_group_id":%s,"foreground_processes":[{"name":"x","pid":%s}],"pane_id":"%s","shell_pid":100},"type":"pane_process_info"}}\n' "$group" "$group" "$4";;
esac
exit 0
MOCK
chmod +x "$work/bin/herdr"

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; cat "$MOCK_STATE/calls.log" >&2 2>/dev/null; exit 1; }
# version, agent occupant (none|idle|blocked|gone), what is in front per process-info call
scene() {
  rm -f "$MOCK_STATE"/*
  printf '%s\n' "$1" > "$MOCK_STATE/version"
  [[ "$2" == none ]] || printf '%s\n' "$2" > "$MOCK_STATE/agent"
  printf '%s\n' "${@:3}" > "$MOCK_STATE/front"
  : > "$MOCK_STATE/calls.log"
}
ring() {
  env LETTERBOX_DIR="$work/box" HERDR_BIN_PATH="$work/bin/herdr" \
    LETTERBOX_HERDR_PATTERNS="$work/box/herdr-patterns.tsv" LETTERBOX_HERDR_SUBMIT=1 \
    LETTERBOX_DOORBELL_ENTER_DELAY=0 "$@" "$EDITION/adapters/herdr.sh" reviewer info smoke 2>/dev/null
}
typed() { grep -qE '^(pane send-text|pane send-keys|agent prompt)' "$MOCK_STATE/calls.log"; }
typed_as_before() { # text then Enter, the way 0.6.4 typed every doorbell
  grep -q '^pane send-text w1:p1 ' "$MOCK_STATE/calls.log" && grep -q '^pane send-keys w1:p1 enter$' "$MOCK_STATE/calls.log"
}
expect() { # outcome-line-suffix label
  local out; out="$(ring)"
  [[ "$out" == "doorbell-outcome v=1 outcome=$1" ]] || bad "$2: got '$out'"
}

# The three fixtures the spec names.
scene 0.9.1 none shell
expect "no_live_surface reason=shell_foreground target=-" "a shell at its prompt"
typed && bad "nothing is typed into a shell"
ok "shell-foreground pane: shell_foreground, nothing typed"

scene 0.9.1 none shell app
expect "no_live_surface reason=shell_foreground target=-" "shell at check, agent app at Enter"
typed && bad "nothing is typed when a shell was in front at the check"
ok "shell at check, agent app at Enter: nothing typed"

scene 0.9.1 blocked app
expect "no_live_surface reason=agent_blocked target=-" "an agent blocked at an approval"
grep -qE '^(pane send-text|pane send-keys)' "$MOCK_STATE/calls.log" && bad "no keys reach a blocked agent"
ok "agent blocked at an approval: agent_blocked, no typed answer"

# A recognised agent gets text and Enter in one Herdr submission.
scene 0.9.1 idle app
expect "submitted reason=- target=w1:p1" "a recognised idle agent"
[[ "$(grep -c '^agent prompt w1:p1 .* unacked info in .*/reviewer/inbox/ — please check$' "$MOCK_STATE/calls.log")" == 1 ]] || bad "one agent prompt with the doorbell line"
grep -qE '^(pane send-text|pane send-keys)' "$MOCK_STATE/calls.log" && bad "no separate text or Enter for a recognised agent"
ok "recognised agent: one agent prompt, no separate Enter"

scene 0.9.1 gone shell
expect "no_live_surface reason=agent_not_ready target=-" "an agent that left the foreground"
ok "agent no longer in front: agent_not_ready"

# An app Herdr does not recognise: typed as before, Enter only while it is still in front.
scene 0.9.1 none app
expect "submitted reason=- target=w1:p1" "an unrecognised app"
grep -q '^pane send-text w1:p1 ' "$MOCK_STATE/calls.log" && grep -q '^pane send-keys w1:p1 enter$' "$MOCK_STATE/calls.log" \
  || bad "text then Enter for an unrecognised app"
ok "unrecognised app: text, then Enter"

scene 0.9.1 none app shell
expect "pasted_not_submitted reason=- target=w1:p1" "app at check, shell at Enter"
grep -q '^pane send-keys' "$MOCK_STATE/calls.log" && bad "no Enter once a shell is in front"
ok "app at check, shell at Enter: Enter withheld"

scene 0.9.1 none app unknown
expect "submitted reason=- target=w1:p1" "app at check, unknown at Enter"
typed_as_before || bad "Enter as before when the second check cannot say"
ok "second check cannot say: Enter as before"

# When the check cannot be made, the doorbell is typed as before.
for v in 0.9.0 0.7.3 down garbage; do
  scene "$v" idle shell
  expect "submitted reason=- target=w1:p1" "Herdr '$v'"
  typed_as_before || bad "typed as before when Herdr is '$v'"
  grep -qE '^(agent |pane process-info)' "$MOCK_STATE/calls.log" && bad "no check is asked of Herdr '$v'"
done
ok "below 0.9.1 or no version: typed as before, no check"

for f in unknown error; do
  scene 0.9.1 none "$f"
  expect "submitted reason=- target=w1:p1" "process-info '$f'"
  typed_as_before || bad "typed as before when process-info is '$f'"
done
ok "process-info cannot say: typed as before"

scene 1.0.0-preview.2 idle app
expect "submitted reason=- target=w1:p1" "a newer pre-release"
ok "newer and pre-release versions pass the floor"

# check says when the guard is unavailable for this agent, and is quiet otherwise.
check() {
  env LETTERBOX_DIR="$work/box" LETTERBOX_AGENT=reviewer HERDR_BIN_PATH="$work/bin/herdr" \
    LETTERBOX_HERDR_PATTERNS="$work/box/herdr-patterns.tsv" LETTERBOX_HERDR_SUBMIT=1 \
    LETTERBOX_DOORBELL="$EDITION/adapters/herdr.sh" "$EDITION/bin/letterbox" check 2>&1
}
scene 0.9.0 none app
out="$(check)"
[[ "$out" == *"shell-guard: unavailable"* ]] || bad "check names an unavailable guard ($out)"
typed && bad "check types nothing"
scene 0.9.1 none app
out="$(check)"
[[ "$out" != *"shell-guard"* ]] || bad "check is quiet when the guard works ($out)"
ok "check prints shell-guard: unavailable only when it is"

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/custom.log"\n' "$work" > "$work/custom.sh"
chmod +x "$work/custom.sh"
env LETTERBOX_DIR="$work/box" LETTERBOX_AGENT=reviewer LETTERBOX_DOORBELL="$work/custom.sh" \
  LETTERBOX_HERDR_SUBMIT=1 "$EDITION/bin/letterbox" check >/dev/null 2>&1
[[ ! -e "$work/custom.log" ]] || bad "check never calls a custom adapter ($(cat "$work/custom.log"))"
ok "check asks only the bundled Herdr adapter"

printf 'shell guard suite: PASS (%s)\n' "$pass"
