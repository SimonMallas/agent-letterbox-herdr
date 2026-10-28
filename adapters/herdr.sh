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
# Submit is opt-in: LETTERBOX_HERDR_SUBMIT=1 sends text + enter into the pane,
# after the shell-foreground guard below on Herdr 0.9.1+.
# Uses Herdr 0.9.1 CLI (pane get / process-info / send-text / send-keys,
# agent get / prompt, status server; guard verified live 2026-10-28)
#
# Arguments: recipient message-type slug [doorbell-token]
#        or: --shell-guard recipient (for letterbox check; prints one line)
# The optional v0.3 token (8 lowercase hex, derived from the letter id by the
# helper) is appended to the doorbell line after the v0.2 tail — additive, so
# the v0.2 byte-prefix is preserved.
set -uo pipefail

probe=false
if [[ "${1:-}" == --shell-guard ]]; then
  probe=true
  set -- "${2:?recipient}" probe probe
fi

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
# Read the bound before starting the child, so a bad bound fails with
# nothing running.
secs = float(sys.argv[1])
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except FileNotFoundError:
    sys.exit(127)
try:
    rc = p.wait(timeout=secs)
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

# Enter waits after the text: an agent TUI that detects pastes takes an Enter
# arriving with the text as part of the paste and never submits it (Muse Code,
# 25 Oct). Whole seconds 0..5; 0 is an explicit fast path. Checked before any
# command runs, so a bad value touches no terminal.
enter_delay="${LETTERBOX_DOORBELL_ENTER_DELAY:-2}"
[[ "$enter_delay" =~ ^[0-5]$ ]] || { emit_outcome no_live_surface invalid_enter_delay -; exit 0; }
# Each mux call is bounded at LETTERBOX_DOORBELL_TIMEOUT: whole seconds 1..999,
# default 1. Checked before any command runs, like the delay: any other value
# used to leave a mux command running with no limit.
bound_s="${LETTERBOX_DOORBELL_TIMEOUT:-1}"
[[ "$bound_s" =~ ^[1-9][0-9]{0,2}$ ]] || { emit_outcome no_live_surface invalid_timeout -; exit 0; }

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

# Shell-foreground guard: a doorbell typed into a shell at its prompt runs as
# a command. Herdr 0.9.1+ knows which agent occupies a pane (agent get) and
# submits text with Enter only while that agent is the pane's foreground
# process, refusing one blocked at an approval or question (agent prompt).
# For anything else, pane process-info tells a shell at its prompt (it owns
# the foreground process group) from an app. Below 0.9.1, or when Herdr
# cannot say, the doorbell is typed as before, without the check, the way
# every edition types it; letterbox check says the check is off.
herdr_says() { # $1=question; reads one Herdr reply on stdin, prints the answer or nothing
  python3 -c '
import json, re, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
result, error = d.get("result") or {}, d.get("error") or {}
question = sys.argv[1]
if question == "floor":
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)([-+].*)?", str(d.get("version", "")))
    print("yes" if m and tuple(map(int, m.groups()[:3])) >= (0, 9, 1) else "no")
elif question == "occupant":
    if result.get("type") == "agent_info":
        print("agent")
    elif error.get("code") == "agent_not_found":
        print("none")
elif question == "front":
    info = result.get("process_info") or {}
    shell, group = info.get("shell_pid"), info.get("foreground_process_group_id")
    if type(shell) is int and type(group) is int:
        print("shell" if group == shell else "app")
elif question == "error":
    print(error.get("code", ""))
' "$1"
}

# 0 = Herdr 0.9.1+, 1 = older or cannot say, 124 = timed out.
guard_floor_met() {
  local out ec=0
  out="$(run_herdr status server --json 2>/dev/null)" || ec=$?
  [[ "$ec" -eq 124 ]] && return 124
  [[ "$(printf '%s' "$out" | herdr_says floor)" == yes ]]
}

# Prints shell or app, or nothing when Herdr cannot say; 124 = timed out.
pane_front() {
  local out ec=0
  out="$(run_herdr pane process-info --pane "$pane_id" 2>/dev/null)" || ec=$?
  [[ "$ec" -eq 124 ]] && return 124
  [[ "$ec" -eq 0 ]] && printf '%s' "$out" | herdr_says front
  return 0
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

if [[ "$probe" == true ]]; then
  # For letterbox check: only a typing doorbell needs the guard.
  [[ "${LETTERBOX_HERDR_SUBMIT:-0}" == 1 ]] || exit 0
  if guard_floor_met; then
    printf 'shell-guard: available\n'
  else
    printf 'shell-guard: unavailable (Herdr 0.9.1 or newer checks what is in front before typing; doorbells are typed without that check)\n'
  fi
  exit 0
fi

# Input injection is explicit opt-in: Enter can submit unrelated buffer text.
if [[ "${LETTERBOX_HERDR_SUBMIT:-0}" == 1 ]]; then
  floor_ec=0
  guard_floor_met || floor_ec=$?
  [[ "$floor_ec" -eq 124 ]] && { emit_outcome no_live_surface helper_timeout -; exit 0; }
  guarded=false
  [[ "$floor_ec" -eq 0 ]] && guarded=true

  occupant=''
  if [[ "$guarded" == true ]]; then
    get_ec=0
    got="$(run_herdr agent get "$pane_id" 2>&1)" || get_ec=$?
    [[ "$get_ec" -eq 124 ]] && { emit_outcome no_live_surface helper_timeout -; exit 0; }
    occupant="$(printf '%s' "$got" | herdr_says occupant)"
  fi
  if [[ "$occupant" == agent ]]; then
    # Text and Enter in one submission: no pause, so no gap to race.
    prompt_ec=0
    said="$(run_herdr agent prompt "$pane_id" "$line" 2>&1)" || prompt_ec=$?
    if [[ "$prompt_ec" -eq 0 ]]; then
      emit_outcome submitted - "$pane_id"
    elif [[ "$prompt_ec" -eq 124 ]]; then
      # The submission started; it may or may not have landed.
      emit_outcome no_live_surface unconfirmed -
    else
      code="$(printf '%s' "$said" | herdr_says error)"
      case "$code" in
        agent_blocked|agent_not_ready|agent_not_found) emit_outcome no_live_surface "$code" -;;
        *) emit_outcome no_live_surface send_failed -;;
      esac
    fi
    exit 0
  fi

  if [[ "$guarded" == true ]]; then
    front_ec=0
    front="$(pane_front)" || front_ec=$?
    [[ "$front_ec" -eq 124 ]] && { emit_outcome no_live_surface helper_timeout -; exit 0; }
    [[ "$front" == shell ]] && { emit_outcome no_live_surface shell_foreground -; exit 0; }
  fi

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
  sleep "$enter_delay"
  # The app may have exited during the pause: no Enter for a shell that would
  # run the line.
  if [[ "$guarded" == true ]]; then
    front="$(pane_front)" || front=''
    [[ "$front" == shell ]] && { emit_outcome pasted_not_submitted - "$pane_id"; exit 0; }
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
