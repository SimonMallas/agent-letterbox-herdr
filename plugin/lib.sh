#!/usr/bin/env bash
# Shared helpers for the Agent Letterbox Herdr plugin.
# Herdr runs plugin commands with the plugin directory as the working directory.
set -euo pipefail

PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LB="$PLUGIN_ROOT/bin/letterbox"

# Optional user settings (KEY=VALUE lines): LETTERBOX_DIR, LETTERBOX_HERDR_REGISTRY,
# LETTERBOX_PLUGIN_OVERDUE_HOURS.
if [[ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" && -f "$HERDR_PLUGIN_CONFIG_DIR/letterbox.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$HERDR_PLUGIN_CONFIG_DIR/letterbox.env"
  set +a
fi

# Resolve the Letterbox explicitly: the plugin's letterbox.env, else the box that
# `letterbox herdr setup` recorded. Never fall back to a .letterbox in the plugin tree.
resolve_box() {
  local recorded="${XDG_CONFIG_HOME:-$HOME/.config}/agent-letterbox/default-dir"
  if [[ -z "${LETTERBOX_DIR:-}" && -f "$recorded" ]]; then
    LETTERBOX_DIR="$(<"$recorded")"
  fi
  if [[ -z "${LETTERBOX_DIR:-}" || ! -d "$LETTERBOX_DIR" ]]; then
    return 1
  fi
  # Use the real path, as letterbox does for its own box: query refuses a root
  # reached through a symlinked component (for example macOS /tmp).
  LETTERBOX_DIR="$(cd "$LETTERBOX_DIR" && pwd -P)"
  export LETTERBOX_DIR
}

# Print the Letterbox agent registered for a Herdr pane on this server, or nothing.
agent_for_pane() { # $1 = pane id, $2 = socket path
  local pane="$1" socket="$2"
  [[ -n "$pane" && -n "$socket" ]] || return 0
  "$LB" herdr status 2>/dev/null \
    | awk -F '\t' -v pane="$pane" -v sock="$socket" 'NR > 1 && $2 == pane && $3 == sock { print $1; exit }'
}

# Focused pane from the invocation context (popups get no HERDR_PANE_ID).
focused_pane() {
  if [[ -n "${HERDR_PANE_ID:-}" ]]; then
    printf '%s' "$HERDR_PANE_ID"
    return
  fi
  python3 -c 'import json,os; print(json.loads(os.environ.get("HERDR_PLUGIN_CONTEXT_JSON") or "{}").get("focused_pane_id",""), end="")'
}
