# Herdr team setup

This is the standard Agent Letterbox setup for a live **Herdr** agent team (local only).

**You control Herdr.** Create whatever workspaces, tabs, and panes fit the task. Letterbox never creates your product layout for you during normal use; it registers the pane you launch each agent in, then rings that pane when mail arrives.

## One-time setup

```bash
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"

letterbox herdr setup --agents planner,reviewer,builder,researcher --automatic-doorbells
source ~/.agent-letterbox/env.sh
```

Creates `~/.agent-letterbox/` by default:

```text
inboxes and processed folders for every named agent
herdr-agents.tsv         # live pane + socket self-registrations
herdr-patterns.tsv       # optional static pane-id fallback
env.sh                   # shared Letterbox/Herdr environment
AGENT-LETTERBOX.md       # startup/resume instruction snippet
```

Also links `~/.local/bin/letterbox` and `~/.agents/skills/agent-letterbox`.

`--automatic-doorbells` (alias `--submit`) enables `LETTERBOX_HERDR_SUBMIT=1` — inject the doorbell line + Enter into the live agent pane. Leave it out if you only want a Herdr notification toast.

Use another shared location when needed:

```bash
letterbox herdr setup --agents planner,reviewer --dir /shared/letterbox --automatic-doorbells
source /shared/letterbox/env.sh
```

## Launch agents

In each agent’s Herdr pane, launch whatever coding-agent CLI you already run:

```bash
source ~/.agent-letterbox/env.sh
letterbox herdr run planner -- <your-agent-cli>
letterbox herdr run reviewer -- <your-agent-cli>
letterbox herdr run builder -- <your-agent-cli>
letterbox herdr run researcher -- <your-agent-cli>
```

`herdr run`:

1. requires a Herdr-managed pane (`HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_SOCKET_PATH`)
2. registers **pane id + socket path** for that agent
3. starts the agent command in the foreground

Pane ids change after layout rebuilds — run `letterbox herdr run` (or `letterbox herdr register <id>`) again after relaunch. Do not reuse remembered pane ids.

### Manual registration

```bash
letterbox herdr register reviewer-secondary
letterbox herdr status
letterbox herdr unregister reviewer-secondary
```

### Registry format

`herdr-agents.tsv` columns:

```text
agent	pane_id	socket_path	registered_at
```

Illustrative example (paths are local-config placeholders only):

```text
planner	w1:p2	$HOME/.config/herdr/herdr.sock	2026-07-18T12:00:00Z
```

The adapter uses the recorded socket so the correct **local** Herdr session is targeted.

### Static fallback patterns

Optional `herdr-patterns.tsv`:

```text
# agent<TAB>herdr_pane_id
planner	w1:p2
reviewer	w1:p3
```

The adapter prefers the live registry, then falls back to this file. Static pane ids are a convenience only — never proof of identity after rebuilds.

## Send a live handoff (two-step lifecycle)

```bash
source ~/.agent-letterbox/env.sh
export LETTERBOX_AGENT=planner

printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  letterbox send reviewer delegate auth-review --ack --now
```

Prefer `printf` (or a quoted heredoc `<<'EOF'`) for the body so the shell does not expand `$` or backticks.

Accept work (non-terminal — letter stays in inbox):

```bash
printf '%s\n' 'ACK: I am reviewing it now.' |
  LETTERBOX_AGENT=reviewer letterbox reply <message-id> ack auth-review --now
```

Finish work (terminal — letter moves to `processed/`):

```bash
printf '%s\n' 'RESULT: findings in body.' |
  LETTERBOX_AGENT=reviewer letterbox reply <message-id> result auth-review --now
```

Non-task letters:

```bash
LETTERBOX_AGENT=reviewer letterbox file <message-id>
```

See [lifecycle.md](lifecycle.md) for the full state machine.

## Safety

Automatic terminal input is intentionally opt-in. `LETTERBOX_HERDR_SUBMIT=1` may submit text already waiting in a target pane buffer. Use dedicated agent panes only. The doorbell contains no task content.

## Validate

```bash
make test
```

Requires a running local Herdr server. Then send a harmless `--now` delegate between two live agents in separate panes. Verify the inbox letter, the target pane doorbell (or toast), the ACK (letter still present with sidecar), the RESULT, and the archived original.
