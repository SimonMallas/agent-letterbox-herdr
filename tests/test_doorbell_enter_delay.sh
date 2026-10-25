#!/usr/bin/env bash
# The doorbell's Enter waits LETTERBOX_DOORBELL_ENTER_DELAY seconds (default 2)
# after its text. An agent TUI that detects pastes swallowed an Enter sent with
# the text (Muse Code, 25 Oct). A bad value touches no terminal, and the ring
# wrapper's budget grows by the delay.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ED=herdr
work="$(mktemp -d /tmp/lb-enter-delay.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/box/reviewer/inbox" "$work/box/reviewer/processed"
export MOCK_LOG="$work/calls.log"
stamp='printf "%s %s\n" "$(python3 -c "import time; print(f\"{time.time():.3f}\")")" "$*" >> "$MOCK_LOG"'

case "$ED" in
  tmux)
    printf '#!/usr/bin/env bash\n%s\ncase "$1" in list-panes|display-message) echo "%%1";; esac\nexit 0\n' "$stamp" > "$work/bin/tmux"
    chmod +x "$work/bin/tmux"
    printf 'reviewer\t%%1\tsess\t0\n' > "$work/box/tmux-agents.tsv"
    run_env=(PATH="$work/bin:$PATH" LETTERBOX_TMUX_SUBMIT=1)
    text_re=' send-keys -t .* -l '; enter_re=' send-keys -t .* Enter$' ;;
  zellij)
    printf '#!/usr/bin/env bash\n%s\n[[ "${1:-}" == -s ]] && shift 2\n[[ "${1:-}" == action && "${2:-}" == list-panes ]] && echo "terminal_7 [Pane #7] running"\nexit 0\n' "$stamp" > "$work/bin/zellij"
    chmod +x "$work/bin/zellij"
    printf 'reviewer\t7\tsess\n' > "$work/box/zellij-patterns.tsv"
    run_env=(ZELLIJ_BIN_PATH="$work/bin/zellij" LETTERBOX_ZELLIJ_PATTERNS="$work/box/zellij-patterns.tsv" LETTERBOX_ZELLIJ_SUBMIT=1)
    text_re=' action write-chars '; enter_re=' action write --pane-id .* 13$' ;;
  herdr)
    printf '#!/usr/bin/env bash\n%s\nexit 0\n' "$stamp" > "$work/bin/herdr"
    chmod +x "$work/bin/herdr"
    printf 'reviewer\t%%1\n' > "$work/box/herdr-patterns.tsv"
    run_env=(HERDR_BIN_PATH="$work/bin/herdr" LETTERBOX_HERDR_PATTERNS="$work/box/herdr-patterns.tsv" LETTERBOX_HERDR_SUBMIT=1)
    text_re=' pane send-text '; enter_re=' pane send-keys .* enter$' ;;
esac

pass=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; cat "$MOCK_LOG" >&2 2>/dev/null; exit 1; }
adapter() { # [env assignments...]
  : > "$MOCK_LOG"
  env LETTERBOX_DIR="$work/box" "${run_env[@]}" "$@" "$EDITION/adapters/$ED.sh" reviewer info smoke 2>/dev/null
}
gap() {
  python3 - "$MOCK_LOG" "$text_re" "$enter_re" <<'PY'
import re, sys
log, text_re, enter_re = sys.argv[1:]
t = {}
for line in open(log):
    line = line.rstrip("\n"); stamp = float(line.split(" ", 1)[0])
    if re.search(enter_re, line): t.setdefault("enter", stamp)
    elif re.search(text_re, line): t.setdefault("text", stamp)
print(f"{t['enter'] - t['text']:.2f}")
PY
}

out="$(adapter)"
[[ "$out" == *"outcome=submitted"* ]] || bad "default ring submits ($out)"
g="$(gap)"; python3 -c "import sys; sys.exit(0 if $g >= 1.9 else 1)" || bad "default waits 2s before Enter (gap $g)"
[[ "$(grep -cE "$enter_re" "$MOCK_LOG")" == 1 ]] || bad "exactly one Enter"
ok "default: Enter follows the text after 2s ($g s), once"

adapter LETTERBOX_DOORBELL_ENTER_DELAY=0 >/dev/null
g="$(gap)"; python3 -c "import sys; sys.exit(0 if $g < 1.0 else 1)" || bad "0 is the fast path (gap $g)"
ok "LETTERBOX_DOORBELL_ENTER_DELAY=0: no pause ($g s)"

for v in x 6 -1 1.5 '2 '; do
  out="$(adapter LETTERBOX_DOORBELL_ENTER_DELAY="$v")"
  [[ "$out" == "doorbell-outcome v=1 outcome=no_live_surface reason=invalid_enter_delay target=-" ]] \
    || bad "invalid delay '$v' is refused ($out)"
  [[ ! -s "$MOCK_LOG" ]] || bad "invalid delay '$v' runs no $ED command"
done
ok "invalid delays are refused before any $ED command"

# The ring wrapper's whole-run budget includes the pause: a fake adapter that
# takes 6s fits 4x0 + 5 + 2 = 7s, but not the old 4x0 + 5 = 5s.
ID="2026-10-25T170000-chat-bridge-info-q-0a1b2c3d"
printf -- '---\nid: %s\nfrom: chat-bridge\nto: reviewer\ntype: info\n---\nq\n' "$ID" > "$work/box/reviewer/inbox/$ID.md"
printf '#!/usr/bin/env bash\nsleep 6\necho "doorbell-outcome v=1 outcome=submitted reason=- target=%%1"\n' > "$work/slow-adapter.sh"
chmod +x "$work/slow-adapter.sh"
out="$(env LETTERBOX_DIR="$work/box" LETTERBOX_DOORBELL="$work/slow-adapter.sh" LETTERBOX_DOORBELL_TIMEOUT=0 \
  "$EDITION/bin/letterbox" ring reviewer info "$ID")"
[[ "$out" == *"outcome=submitted"* ]] || bad "the ring budget covers the pause ($out)"
ok "ring budget grows by the Enter delay"

printf 'doorbell enter delay suite: PASS (%s)\n' "$pass"
