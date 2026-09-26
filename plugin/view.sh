#!/usr/bin/env bash
# Popup: the focused agent's inbox, open requests it owes, and overdue requests.
# Read-only: it never sends, rings, files, or changes a letter.
set -uo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
. "$here/lib.sh"
set +e

finish() { printf '\nPress any key to close.'; read -r -n 1 _ 2>/dev/null || true; exit 0; }

if ! have_python; then
  printf 'Agent Letterbox\n\npython3 was not found. The popup needs Python 3.9 or newer (the query layer does too).\n'
  finish
fi
if ! resolve_box; then
  printf 'Agent Letterbox\n\nNo Letterbox found. Run `letterbox herdr setup` first, or set LETTERBOX_DIR in\n%s/letterbox.env\n' "${HERDR_PLUGIN_CONFIG_DIR:-the plugin config dir}"
  finish
fi
pane="$(focused_pane)"
agent="$(agent_for_pane "$pane" "${HERDR_SOCKET_PATH:-}")"
hours="${LETTERBOX_PLUGIN_OVERDUE_HOURS:-24}"
hours_note=''
if ! [[ "$hours" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "$hours" =~ ^0+([.]0+)?$ ]]; then
  hours_note="LETTERBOX_PLUGIN_OVERDUE_HOURS=$hours is not a positive number; using 24."
  hours=24
fi

if [[ -z "$agent" ]]; then
  printf 'Agent Letterbox\n\nThis pane (%s) is not registered as a Letterbox agent.\n' "${pane:-unknown}"
  printf 'Start the agent with: letterbox herdr run <agent> -- <agent command>\n'
  finish
fi

# One line per letter; control characters stripped as a second layer.
listing() { # filters...
  # Whole team scope: an answer lives in the SENDER's mailbox, so narrowing the scan to
  # this agent would hide it. to=<agent> only filters what is shown.
  LETTERBOX_AGENT="$agent" "$LB" query --compat-v2 to="$agent" "$@" 2>/dev/null \
    | python3 "$here/brief.py" | LC_ALL=C tr -d '\000-\011\013-\037\177' | LC_ALL=C sed $'s/\xc2[\x80-\x9f]//g'
}
until_ts="$(python3 -c 'import datetime,sys; t=datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=float(sys.argv[1])); print(t.strftime("%Y-%m-%dT%H:%M:%SZ"))' "$hours")"
printf 'Agent Letterbox: %s   (box %s)\n\n' "$agent" "$LETTERBOX_DIR"
[[ -n "$hours_note" ]] && printf '%s\n\n' "$hours_note"
printf 'Inbox (open letters to %s)\n' "$agent"
listing state=open
printf '\nWhat I owe (open requests, no answer yet)\n'
listing state=open answered=no type=request
printf '\nOverdue (open, unanswered, sent more than %s h ago)\n' "$hours"
listing state=open answered=no type=request until="$until_ts"
finish
