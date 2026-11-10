# Herdr adapter guide

Local-only automatic doorbells for Agent Letterbox using the Herdr CLI. The plugin, and the doorbell's check of what is in front of the pane, need Herdr 0.9.1 or newer. Native bootstrap and plugin suites have been verified on macOS ARM64 with Herdr 0.9.1 and 0.9.5; CI covers both versions with checksum-verified binaries on Linux and macOS.

The isolated test launchers set a 24×80 PTY grid: Herdr 0.9.5 refuses a zero-sized terminal. They retain a bounded 8 KiB output tail for startup failures. This is a test-harness requirement, not a change to the doorbell protocol. Remote-machine doorbells remain out of scope.

```text
letter written to inbox
→ adapters/herdr.sh finds a live registered pane (registry-first)
→ checks what is in front of the pane, refuses a shell at its prompt  (typing is the default; SUBMIT=0 turns it off)
→ herdr agent prompt, or pane send-text + pane send-keys enter
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

## Automatic agent input (the default)

Every letter rings. By default the adapter types the standardized doorbell and Enter into the live pane. With typing refused, it posts a Herdr notification toast and does **not** inject into the agent TUI:

```bash
# Typing is the default (setup writes this for you); refuse it with:
export LETTERBOX_HERDR_SUBMIT=0
```

Setup writes `LETTERBOX_HERDR_SUBMIT=1` into the generated environment. The old `--automatic-doorbells` flag (alias `--submit`) is still accepted and changes nothing.

Before typing anything, the adapter checks what is in front of the pane (Herdr 0.9.1 or newer):

- A coding agent Herdr recognises (`herdr agent get`) gets the doorbell through `herdr agent prompt <pane-id> '<doorbell>'`: text and Enter in one submission, only while that agent is the pane's foreground process. An agent waiting at an approval or question is refused as `agent_blocked`, so the doorbell does not answer it.
- Anything else is checked with `herdr pane process-info --pane <pane-id>`. A shell at its own prompt owns the pane's foreground process group and is refused as `shell_foreground`: the doorbell line would run as a command. Any other app gets `herdr pane send-text <pane-id> '<doorbell>'` and, after the pause, `herdr pane send-keys <pane-id> enter`, but only if it is still in front.
- With a Herdr older than 0.9.1, or when Herdr cannot say what is in front, the doorbell is typed as before, without the check, and `letterbox check` prints `shell-guard: unavailable`.

(with `HERDR_SOCKET_PATH` set from the registry row when present)

The doorbell line keeps the v0.2 byte-prefix; v0.3 may append an opaque token (`… — please check · <8hex>`). Ring outcomes are `submitted`, `pasted_not_submitted`, or `no_live_surface` — never that the agent read the letter. The helper bounds the adapter run (`LETTERBOX_DOORBELL_TIMEOUT`, default 5s); the letter is durable regardless.

## Safety

- Doorbell text is generic; no task body, paths, or secrets.
- Typing injects into a live agent TUI by default — dedicated panes only; `LETTERBOX_HERDR_SUBMIT=0` turns it off, and `check` warns `doorbell: typing is off`.
- On Herdr 0.9.1 or newer, a doorbell is refused when Herdr reports a shell at its prompt or an agent waiting at a question. It is a check, not a lock: what is in front can change between the check and the typing.
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
