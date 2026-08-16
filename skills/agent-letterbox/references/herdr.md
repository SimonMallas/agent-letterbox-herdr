# Herdr doorbell

Automatic live doorbells use `adapters/herdr.sh`.

Lookup order:

1. Live registry (`LETTERBOX_HERDR_REGISTRY`) from `letterbox herdr run` / `register`
   Records `agent`, `HERDR_PANE_ID`, and `HERDR_SOCKET_PATH`.
2. Static patterns (`LETTERBOX_HERDR_PATTERNS`)

Delivery (when `LETTERBOX_HERDR_SUBMIT=1`):

```bash
herdr pane send-text <pane_id> '<generic doorbell>'
herdr pane send-keys <pane_id> enter
```

The line keeps the v0.2 shape; v0.3 appends an opaque token after `please check`:

```text
📬 letterbox doorbell: unacked <type> in <LETTERBOX_DIR>/<agent>/inbox/ — please check · <8hex>
```

Outcomes are `submitted`, `pasted_not_submitted`, or `no_live_surface` — a ring never proves the agent read the letter. The helper bounds the adapter run (`LETTERBOX_DOORBELL_TIMEOUT`, default 5s) so an unresponsive pane path cannot hang a sender; the letter is already durable.

Requires a running local Herdr server. Scope is local-only.
