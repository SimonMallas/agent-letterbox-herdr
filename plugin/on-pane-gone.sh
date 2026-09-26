#!/usr/bin/env bash
# Event hook (pane.closed / pane.exited): remove the registration for a pane that
# no longer hosts its agent, so doorbells stop targeting a dead pane.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

resolve_box || { printf 'agent-letterbox: no Letterbox found; nothing to clean up\n'; exit 0; }
# The event payload names the pane that closed; fall back to HERDR_PANE_ID only if absent.
pane="$(python3 -c 'import json,os; d=json.loads(os.environ.get("HERDR_PLUGIN_EVENT_JSON") or "{}").get("data",{}); print(d.get("pane_id") or (d.get("pane") or {}).get("pane_id",""), end="")')"
pane="${pane:-${HERDR_PANE_ID:-}}"
agent="$(agent_for_pane "$pane" "${HERDR_SOCKET_PATH:-}")"
if [[ -n "$agent" ]]; then
  "$LB" herdr unregister "$agent"
  printf 'agent-letterbox: %s pane %s gone; unregistered %s\n' "${HERDR_PLUGIN_EVENT:-event}" "$pane" "$agent"
else
  printf 'agent-letterbox: %s pane %s had no registration\n' "${HERDR_PLUGIN_EVENT:-event}" "$pane"
fi
