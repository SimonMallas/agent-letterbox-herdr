#!/usr/bin/env bash
# Herdr doorbell adapter (local automatic live-agent ring).
#
# Lookup order:
#   1) LETTERBOX_HERDR_REGISTRY (default: $LETTERBOX_DIR/herdr-agents.tsv)
#      agent<TAB>pane_id<TAB>socket_path<TAB>registered_at
#   2) LETTERBOX_HERDR_PATTERNS (static fallback)
#      agent<TAB>pane_id
#
# Submit is opt-in: LETTERBOX_HERDR_SUBMIT=1 sends text + enter into the pane.
# Uses Herdr 0.7.x CLI: pane send-text / pane send-keys
#
# Arguments: recipient message-type slug [doorbell-token]
# The optional v0.3 token (8 lowercase hex, derived from the letter id by the
# helper) is appended to the doorbell line after the v0.2 tail — additive, so
# the v0.2 byte-prefix is preserved. Outcomes are reported as submitted,
# pasted_not_submitted, or no_live_surface — never that the letter was read.
set -euo pipefail

to="${1:?recipient}"
type="${2:?type}"
slug="${3:?slug}"
token="${4:-}"

herdr_bin="${HERDR_BIN_PATH:-herdr}"
command -v "$herdr_bin" >/dev/null 2>&1 || {
  echo 'herdr doorbell deferred: herdr is unavailable' >&2
  exit 0
}

line="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
# Additive v0.3 token suffix; the token is opaque (never slug/body/path).
[[ "$token" =~ ^[0-9a-f]{8}$ ]] && line="$line · $token"
pane_id=''
socket=''

pane_live() {
  local p="$1" sock="${2:-}"
  if [[ -n "$sock" ]]; then
    HERDR_SOCKET_PATH="$sock" "$herdr_bin" pane get "$p" >/dev/null 2>&1
  else
    "$herdr_bin" pane get "$p" >/dev/null 2>&1
  fi
}

# 1) Live registry
registry_file="${LETTERBOX_HERDR_REGISTRY:-}"
if [[ -z "$registry_file" && -n "${LETTERBOX_DIR:-}" ]]; then
  registry_file="$LETTERBOX_DIR/herdr-agents.tsv"
fi
if [[ -n "$registry_file" && -r "$registry_file" ]]; then
  while IFS=$'\t' read -r agent pane sock _ts || [[ -n "${agent:-}" ]]; do
    [[ "$agent" == "$to" && -n "${pane:-}" ]] || continue
    if pane_live "$pane" "${sock:-}"; then
      pane_id="$pane"
      socket="${sock:-}"
      break
    fi
  done < "$registry_file"
fi

# 2) Static patterns fallback (pane ids only; uses default socket)
if [[ -z "$pane_id" ]]; then
  patterns_file="${LETTERBOX_HERDR_PATTERNS:-}"
  if [[ -z "$patterns_file" && -n "${LETTERBOX_DIR:-}" ]]; then
    patterns_file="$LETTERBOX_DIR/herdr-patterns.tsv"
  fi
  if [[ -n "$patterns_file" && -r "$patterns_file" ]]; then
    while IFS=$'\t' read -r agent pane || [[ -n "${agent:-}" ]]; do
      [[ "$agent" == \#* || -z "${agent:-}" ]] && continue
      [[ "$agent" == "$to" && -n "${pane:-}" ]] || continue
      if pane_live "$pane" ""; then
        pane_id="$pane"
        socket=''
        break
      fi
    done < "$patterns_file"
  fi
fi

if [[ -z "$pane_id" ]]; then
  echo "herdr doorbell deferred: no live herdr pane for $to" >&2
  exit 0
fi

run_herdr() {
  if [[ -n "$socket" ]]; then
    HERDR_SOCKET_PATH="$socket" "$herdr_bin" "$@"
  else
    "$herdr_bin" "$@"
  fi
}

if [[ "${LETTERBOX_HERDR_SUBMIT:-0}" == 1 ]]; then
  if ! run_herdr pane send-text "$pane_id" "$line" >/dev/null; then
    printf 'herdr doorbell no_live_surface send_failed for %s\n' "$to"
    exit 0
  fi
  if ! run_herdr pane send-keys "$pane_id" enter >/dev/null; then
    printf 'herdr doorbell pasted_not_submitted to %s on %s\n' "$to" "$pane_id"
    exit 0
  fi
  printf 'herdr doorbell submitted to %s on %s\n' "$to" "$pane_id"
else
  # Best-effort toast; not a terminal inject
  run_herdr notification show "letterbox doorbell" --body "unacked $type for $to" --sound request >/dev/null 2>&1 || true
  printf 'herdr notification attempted for %s; set LETTERBOX_HERDR_SUBMIT=1 to inject the doorbell\n' "$to"
fi
