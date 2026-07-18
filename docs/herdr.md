# Herdr adapter guide

Local-only automatic doorbells for Agent Letterbox using the Herdr CLI (0.7.x).

```text
letter written to inbox
→ adapters/herdr.sh finds a live registered pane (registry-first)
→ herdr pane send-text + pane send-keys enter  (when SUBMIT=1)
→ agent checks its durable inbox
```

## Lookup order

1. **Live registry** — `$LETTERBOX_DIR/herdr-agents.tsv`
   `agent`, `HERDR_PANE_ID`, `HERDR_SOCKET_PATH`, timestamp
2. **Static patterns** — `$LETTERBOX_DIR/herdr-patterns.tsv`
   `agent`, `pane_id` (default socket)

## Safety

- Doorbell text is generic; no task body.
- `LETTERBOX_HERDR_SUBMIT=1` injects into a live agent TUI — dedicated panes only.
- Without SUBMIT, adapter attempts a Herdr notification toast only (not a terminal inject).

## Scope

Local Herdr only. No SSH/remote sockets packaging, plugins marketplace, webhooks, desktop, cmux, or tmux in this product.
