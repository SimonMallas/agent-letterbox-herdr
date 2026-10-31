#!/usr/bin/env bash
# LETTERBOX_DOORBELL_TIMEOUT bounds each mux call: whole seconds 1-999, default
# 1. The bounded runner used to start the mux command before it read the bound,
# so a value such as "x" crashed it with the command already running and no
# limit. A bad value is now refused before any mux command.
set -euo pipefail

EDITION="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ED=herdr
work="$(mktemp -d /tmp/lb-timeout.XXXXXX)"
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
for v in '' 1 3 999; do
  out="$(adapter LETTERBOX_DOORBELL_ENTER_DELAY=0 ${v:+LETTERBOX_DOORBELL_TIMEOUT="$v"})"
  [[ "$out" == *"outcome=submitted"* ]] || bad "timeout '${v:-default}' still rings ($out)"
done
ok "the default and whole seconds 1-999 ring as before"

for v in x 0 -1 1.5 1000 nan inf '1 '; do
  out="$(adapter LETTERBOX_DOORBELL_TIMEOUT="$v")"
  [[ "$out" == "doorbell-outcome v=1 outcome=no_live_surface reason=invalid_timeout target=-" ]] \
    || bad "invalid timeout '$v' is refused ($out)"
  [[ ! -s "$MOCK_LOG" ]] || bad "invalid timeout '$v' runs no $ED command"
done
ok "invalid timeouts are refused before any $ED command"

printf 'doorbell timeout suite: PASS (%s)\n' "$pass"
