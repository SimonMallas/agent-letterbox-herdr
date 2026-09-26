#!/usr/bin/env bash
# Popup: the focused agent's inbox, open requests it owes, and overdue requests.
# Read-only: it never sends, rings, files, or changes a letter.
set -uo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
. "$here/lib.sh"
set +e

finish() { printf '\nPress any key to close.'; read -r -n 1 _ 2>/dev/null || true; exit 0; }

if ! resolve_box; then
  printf 'Agent Letterbox\n\nNo Letterbox found. Run `letterbox herdr setup` first, or set LETTERBOX_DIR in\n%s/letterbox.env\n' "${HERDR_PLUGIN_CONFIG_DIR:-the plugin config dir}"
  finish
fi
pane="$(focused_pane)"
agent="$(agent_for_pane "$pane" "${HERDR_SOCKET_PATH:-}")"
hours="${LETTERBOX_PLUGIN_OVERDUE_HOURS:-24}"

if [[ -z "$agent" ]]; then
  printf 'Agent Letterbox\n\nThis pane (%s) is not registered as a Letterbox agent.\n' "${pane:-unknown}"
  printf 'Start the agent with: letterbox herdr run <agent> -- <agent command>\n'
  finish
fi

owed() { # extra filters...
  LETTERBOX_AGENT="$agent" "$LB" query --compat-v2 --participant "$agent" \
    to="$agent" state=open answered=no type=request "$@" 2>/dev/null | python3 "$here/brief.py"
}
until_ts="$(python3 -c 'import datetime,sys; t=datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=float(sys.argv[1])); print(t.strftime("%Y-%m-%dT%H:%M:%SZ"))' "$hours")"
printf 'Agent Letterbox: %s   (box %s)\n\n' "$agent" "$LETTERBOX_DIR"
printf 'Inbox\n'
LETTERBOX_AGENT="$agent" "$LB" check 2>&1 | sed 's/^/  /' | head -n 20
printf '\nWhat I owe (open requests, no answer yet)\n'
owed
printf '\nOverdue (open, unanswered, sent more than %s h ago)\n' "$hours"
owed until="$until_ts"
finish
