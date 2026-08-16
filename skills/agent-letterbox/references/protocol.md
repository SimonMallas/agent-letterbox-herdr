# Protocol reference

Letters are durable files. Doorbells are generic live-session attention signals.

For actionable work, reply before archive. Use `letterbox reply`; it delivers the reply before archiving the original letter.

Preserve urgency: add `--now` to a reply only when the original letter had `priority: now`. Acknowledgement alone does not require urgency escalation.

## v0.3 lifecycle additions

- A `requires_ack: false` letter may be closed in one step: `letterbox reply <id> result|nack <slug>` with no prior ACK. `ack` is refused on non-task letters.
- `letterbox file <path>` on an inbound terminal reply (`result` / `nack`) requires `--read` (caller assertion, not a receipt). An explicit id, display-id, or unique token files directly.
- `letterbox progress <ref> <one-line>` records progress in the `.md.ack` sidecar; it creates no letter and closes none.
- `reply` reads the body from stdin before taking any lifecycle lock; a TTY or empty stdin fails fast with usage.

## Doorbell knocks

A knock is matched by prefix/pattern only — both the tokenless v0.2 line and the v0.3 ` · <8hex>` token suffix are accepted. Exact full-line equality is a cutover BLOCK hazard. The token is opaque (never slug/body/path), and a ring outcome (`submitted` / `pasted_not_submitted` / `no_live_surface`) never proves the letter was read.
