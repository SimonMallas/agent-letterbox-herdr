# Herdr adapter guide

Local-only automatic doorbells for Agent Letterbox using the Herdr CLI (0.7.x).

```text
letter written to inbox
→ adapters/herdr.sh finds a live registered pane (registry-first)
→ herdr pane send-text + pane send-keys enter  (when SUBMIT=1)
→ agent checks its durable inbox
```

The terminal gets a ring; the inbox keeps the message. Doorbell delivery is best-effort. The letter on disk is the record.

## Lookup order

1. **Live registry** — `$LETTERBOX_DIR/herdr-agents.tsv`  
   Columns: `agent`, `HERDR_PANE_ID`, `HERDR_SOCKET_PATH`, timestamp  
   Override path with `LETTERBOX_HERDR_REGISTRY`.  
   A pane is used only if it is still live on the recorded socket.

2. **Static patterns** — `$LETTERBOX_DIR/herdr-patterns.tsv`  
   Columns: `agent`, `pane_id` (default/current socket)  
   Override path with `LETTERBOX_HERDR_PATTERNS`.  
   Fallback only — not identity proof after rebuilds.

Registration refuses to silently assign the same live pane+socket pair to two agent identities.

## Enable automatic agent input

By default (submit off), the adapter prefers a Herdr notification toast and does **not** inject into the agent TUI.

To inject the standardized doorbell and Enter into the live pane:

```bash
export LETTERBOX_HERDR_SUBMIT=1
```

Setup flag `--automatic-doorbells` (alias `--submit`) turns this on in the generated environment.

Injection uses:

```bash
herdr pane send-text <pane-id> '<doorbell>'
herdr pane send-keys <pane-id> enter
```

(with `HERDR_SOCKET_PATH` set from the registry row when present)

## Safety

- Doorbell text is generic; no task body, paths, or secrets.
- `LETTERBOX_HERDR_SUBMIT=1` injects into a live agent TUI — dedicated panes only.
- Without SUBMIT, adapter attempts a Herdr notification toast only (not a terminal inject).
- Doorbell success means a wake-up was submitted to a verified live target — not that the agent read or handled the letter.
- If a safe live target cannot be verified, Letterbox prefers silent durable delivery over risky pane injection.

## Maintenance and recovery

### After pane rebuild, Herdr restart, or host reboot

1. Confirm local Herdr is running:

   ```bash
   herdr status
   herdr --version
   ```

2. **Re-register every live agent from inside its own pane.** Do not reuse remembered pane ids or sockets from a previous session without verifying liveness.

   ```bash
   letterbox herdr register <agent-id>
   letterbox herdr status
   ```

3. Each agent should scan its inbox (including any `[ACCEPTED]` WIP marked by `.md.ack` sidecars):

   ```bash
   letterbox check
   ```

4. Smoke check:

   - Send a `priority: now` `info` letter to a live agent in another pane.
   - Confirm the letter appears in that agent's inbox.
   - Confirm the doorbell/toast reaches the intended pane only.
   - Have the recipient `letterbox file` the info letter.
   - Optionally run one disposable `delegate --ack` → `reply ack` → `reply result` cycle.

### Accepted WIP after interruption

An `[ACCEPTED]` task letter is still open work. Finish with `reply … result` or decline with `reply … nack`. Do not `file` it, and do not hand-delete the `.md.ack` sidecar.

## Scope

Local Herdr only. No SSH/remote sockets packaging, plugins marketplace dependency, webhooks, desktop, cmux, or tmux adapters in this product tree.

## Validate

```bash
make test
```

Live Herdr bootstrap tests require a running local Herdr server.
