#!/usr/bin/env bash
# Herdr doorbell adapter — doorbell-outcome v=1 emitter.
# The letter is already durable; this rings a live pane and reports ONE
# machine-readable outcome line on stdout (the wrapper owns forwarding).
#
# Lookup order:
#   1) LETTERBOX_HERDR_REGISTRY (default: $LETTERBOX_DIR/herdr-agents.tsv)
#      agent<TAB>pane_id<TAB>socket_path<TAB>registered_at
#   2) LETTERBOX_HERDR_PATTERNS (static fallback)
#      agent<TAB>pane_id
#
# Submit is opt-in: LETTERBOX_HERDR_SUBMIT=1 sends text + enter into the pane.
# Uses Herdr 0.9.0 CLI (pane get / send-text / send-keys; live ring verified 2026-09-09)
#
# Arguments: recipient message-type slug [doorbell-token]
# The optional v0.3 token (8 lowercase hex, derived from the letter id by the
# helper) is appended to the doorbell line after the v0.2 tail — additive, so
# the v0.2 byte-prefix is preserved.
set -uo pipefail

to="${1:?recipient}"
type="${2:?type}"
slug="${3:?slug}"
token="${4:-}"

# doorbell-outcome v=1: exactly one line, validated before printing.
# outcome ∈ {submitted, pasted_not_submitted, no_live_surface}; reason/target
# cross-checked per the contract (no_live_surface always target=-; submitted
# and pasted always target=<pinned pane>, reason=- or enter_failed|-).
emit_outcome() { # $1=outcome $2=reason $3=target
    local outcome="$1" reason="$2" target="$3"
    case "$outcome" in
        submitted)
            [[ "$reason" == "-" && "$target" != "-" ]] || return 1
            [[ "$target" =~ ^[A-Za-z0-9._:+-]+$ || "$target" =~ ^%[0-9]+$ ]] || return 1
            ;;
        pasted_not_submitted)
            case "$reason" in enter_failed|-) ;; *) return 1;; esac
            [[ "$target" != "-" ]] || return 1
            [[ "$target" =~ ^[A-Za-z0-9._:+-]+$ || "$target" =~ ^%[0-9]+$ ]] || return 1
            ;;
        no_live_surface)
            [[ "$reason" != "-" && "$reason" =~ ^[A-Za-z0-9._:+-]+$ ]] || return 1
            [[ "$target" == "-" ]] || return 1
            ;;
        *) return 1;;
    esac
    printf 'doorbell-outcome v=1 outcome=%s reason=%s target=%s\n' \
        "$outcome" "$reason" "$target"
}

# Bounded call: 124 = actual timeout (runner-killed; the sentinel is
# runner-owned — a child exiting 124 itself is remapped to 123), 125 = runner
# (python3) unavailable, 127 = missing binary, else the child's exit code.
# Runner presence is verified up front, so a 124 at a classification point
# is always a genuine timeout — never ambiguous.
bounded_cmd() { # $1=seconds, rest=argv
    local secs="$1"; shift
    command -v python3 >/dev/null 2>&1 || return 125
    python3 -c '
import os, signal, subprocess, sys
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except FileNotFoundError:
    sys.exit(127)
try:
    rc = p.wait(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except Exception:
        p.kill()
    p.wait()
    sys.exit(124)
# The runner owns the 124 sentinel: a child that exits 124 on its own was
# NOT killed on timeout and must not be read as one — remap to 123.
sys.exit(123 if rc == 124 else rc)
' "$secs" "$@"
}

herdr_bin="${HERDR_BIN_PATH:-herdr}"
command -v "$herdr_bin" >/dev/null 2>&1 || { emit_outcome no_live_surface adapter_unavailable -; exit 0; }
# Runner presence is verified BEFORE any 124 is read as a timeout: a missing
# python3 is adapter_unavailable (non-retryable), never helper_timeout.
command -v python3 >/dev/null 2>&1 || { emit_outcome no_live_surface adapter_unavailable -; exit 0; }

# Ruling 5 middle insert: name the durable letter's sender, but only when the
# wrapper supplied a value that passes the safe-identifier regex (re-checked
# here — env is never trusted). Otherwise the line stays the old shape.
line_from="${LETTERBOX_DOORBELL_FROM:-}"
if [[ "$line_from" =~ ^[A-Za-z][A-Za-z0-9._-]{0,31}$ ]]; then
  line="📬 letterbox doorbell: unacked $type from $line_from in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
else
  line="📬 letterbox doorbell: unacked $type in ${LETTERBOX_DIR:?set LETTERBOX_DIR}/$to/inbox/ — please check"
fi
# Additive v0.3 token suffix; the token is opaque (never slug/body/path).
[[ "$token" =~ ^[0-9a-f]{8}$ ]] && line="$line · $token"

bound_s="${LETTERBOX_DOORBELL_TIMEOUT:-1}"

# 0 = live, 1 = dead, 124 = lookup timeout (retryable, pre-inject).
pane_live() {
  local p="$1" sock="${2:-}"
  if [[ -n "$sock" ]]; then
    bounded_cmd "$bound_s" env HERDR_SOCKET_PATH="$sock" "$herdr_bin" pane get "$p" >/dev/null 2>&1
  else
    bounded_cmd "$bound_s" "$herdr_bin" pane get "$p" >/dev/null 2>&1
  fi
}

# Bounded inject/notify on the registered socket (when one was pinned).
run_herdr() {
  if [[ -n "$socket" ]]; then
    bounded_cmd "$bound_s" env HERDR_SOCKET_PATH="$socket" "$herdr_bin" "$@"
  else
    bounded_cmd "$bound_s" "$herdr_bin" "$@"
  fi
}

pane_id=''
socket=''

# 1) Live registry
registry_file="${LETTERBOX_HERDR_REGISTRY:-}"
if [[ -z "$registry_file" && -n "${LETTERBOX_DIR:-}" ]]; then
  registry_file="$LETTERBOX_DIR/herdr-agents.tsv"
fi
if [[ -n "$registry_file" && -r "$registry_file" ]]; then
  while IFS=$'\t' read -r agent pane sock _ts || [[ -n "${agent:-}" ]]; do
    [[ "$agent" == "$to" && -n "${pane:-}" ]] || continue
    live_ec=0
    pane_live "$pane" "${sock:-}" || live_ec=$?
    if [[ "$live_ec" -eq 124 ]]; then
      emit_outcome no_live_surface helper_timeout -
      exit 0
    fi
    if [[ "$live_ec" -eq 0 ]]; then
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
      live_ec=0
      pane_live "$pane" "" || live_ec=$?
      if [[ "$live_ec" -eq 124 ]]; then
        emit_outcome no_live_surface helper_timeout -
        exit 0
      fi
      if [[ "$live_ec" -eq 0 ]]; then
        pane_id="$pane"
        socket=''
        break
      fi
    done < "$patterns_file"
  fi
fi

[[ -n "$pane_id" ]] || { emit_outcome no_live_surface surface_not_found -; exit 0; }

# Input injection is explicit opt-in: Enter can submit unrelated buffer text.
if [[ "${LETTERBOX_HERDR_SUBMIT:-0}" == 1 ]]; then
  send_ec=0
  run_herdr pane send-text "$pane_id" "$line" >/dev/null || send_ec=$?
  if [[ "$send_ec" -ne 0 ]]; then
    if [[ "$send_ec" -eq 124 ]]; then
      # Text step started; bytes may or may not have been injected.
      emit_outcome no_live_surface unconfirmed -
    else
      emit_outcome no_live_surface send_failed -
    fi
    exit 0
  fi
  enter_ec=0
  run_herdr pane send-keys "$pane_id" enter >/dev/null || enter_ec=$?
  if [[ "$enter_ec" -ne 0 ]]; then
    if [[ "$enter_ec" -eq 124 ]]; then
      # Enter may have landed after text was confirmed sent.
      emit_outcome no_live_surface unconfirmed -
    else
      emit_outcome pasted_not_submitted enter_failed "$pane_id"
    fi
    exit 0
  fi
  emit_outcome submitted - "$pane_id"
else
  # Best-effort toast; not a terminal inject.
  run_herdr notification show "letterbox doorbell" --body "unacked $type for $to" --sound request >/dev/null 2>&1 || true
  emit_outcome no_live_surface notify_only -
fi
