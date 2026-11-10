# Herdr doorbell

Automatic live doorbells use `adapters/herdr.sh`.

Lookup order:

1. Live registry (`LETTERBOX_HERDR_REGISTRY`) from `letterbox herdr run` / `register`
   Records `agent`, `HERDR_PANE_ID`, and `HERDR_SOCKET_PATH`.
2. Static patterns (`LETTERBOX_HERDR_PATTERNS`)

Delivery (typing is the default; `LETTERBOX_HERDR_SUBMIT=0` turns it off). On Herdr 0.9.1 or newer the adapter first checks what is in front of the pane and refuses a shell at its prompt:

```bash
herdr agent prompt <pane_id> '<generic doorbell>'     # a coding agent Herdr recognises
herdr pane send-text <pane_id> '<generic doorbell>'   # any other app, then after the pause:
herdr pane send-keys <pane_id> enter                  # only if that app is still in front
```

`no_live_surface` reasons from this check: `shell_foreground` (a shell at its prompt), `agent_blocked` (the agent is waiting at an approval or question), and `agent_not_ready`. With Herdr older than 0.9.1, or when it cannot say, the doorbell is typed as before, and `letterbox check` prints `shell-guard: unavailable`.

The line keeps the v0.2 shape; v0.3 appends an opaque token after `please check`:

```text
📬 letterbox doorbell: unacked <type> in <LETTERBOX_DIR>/<agent>/inbox/ — please check · <8hex>
```

Outcomes are `submitted`, `pasted_not_submitted`, or `no_live_surface` — a ring never proves the agent read the letter. Each adapter step is bounded by `LETTERBOX_DOORBELL_TIMEOUT` (default 1s); the helper also applies an outer backstop. An unresponsive pane path cannot hang a sender; the letter is already durable.

Requires a running local Herdr server. Scope is local-only.
