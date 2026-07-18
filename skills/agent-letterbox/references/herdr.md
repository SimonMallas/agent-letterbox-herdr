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

Requires a running local Herdr server. Scope is local-only.
