#!/usr/bin/env bash
# Popup: the focused agent's inbox, open requests it owes, and overdue requests.
# Read-only: it never sends, rings, files, or changes a letter.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e

pane="$(focused_pane)"
agent="$(agent_for_pane "$pane" "${HERDR_SOCKET_PATH:-}")"
hours="${LETTERBOX_PLUGIN_OVERDUE_HOURS:-24}"

if [[ -z "$agent" ]]; then
  printf 'Agent Letterbox\n\nThis pane (%s) is not registered as a Letterbox agent.\n' "${pane:-unknown}"
  printf 'Start the agent with: letterbox herdr run <agent> -- <agent command>\n'
else
  until_ts="$(python3 -c 'import datetime,sys; t=datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=float(sys.argv[1])); print(t.strftime("%Y-%m-%dT%H:%M:%SZ"))' "$hours")"
  printf 'Agent Letterbox: %s\n\n' "$agent"
  printf '== Inbox ==\n'
  LETTERBOX_AGENT="$agent" "$LB" check
  printf '\n== What I owe (open requests, no answer yet) ==\n'
  LETTERBOX_AGENT="$agent" "$LB" query state=open answered=no type=request to="$agent"
  rc=$?
  printf '\n== Overdue (sent more than %s h ago) ==\n' "$hours"
  LETTERBOX_AGENT="$agent" "$LB" query state=open answered=no type=request to="$agent" until="$until_ts"
  rc2=$?
  if [[ $rc -eq 2 || $rc2 -eq 2 ]]; then
    printf '\nStrict query refused an older letter in this box. Try: letterbox query --compat-v2 ...\n'
  fi
fi
printf '\nPress any key to close.'
read -r -n 1 _ 2>/dev/null || true
