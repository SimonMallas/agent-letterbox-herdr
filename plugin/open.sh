#!/usr/bin/env bash
# Action: open the Letterbox popup for the focused pane.
set -euo pipefail
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin "${HERDR_PLUGIN_ID:-agent-letterbox}" --entrypoint letterbox
