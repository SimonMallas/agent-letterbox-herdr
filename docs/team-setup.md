# Herdr team setup

This is the standard Agent Letterbox setup for a live **Herdr** agent team (local only).

**You control Herdr.** Create whatever workspaces, tabs, and panes fit the task. Letterbox never creates your product layout for you during normal use; it registers the pane you launch each agent in, then rings that pane when mail arrives.

## One-time setup

```bash
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"

letterbox herdr setup --agents pi,claude,grok,hermes --automatic-doorbells
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

`--automatic-doorbells` enables `LETTERBOX_HERDR_SUBMIT=1`.

## Launch agents

In each agent’s Herdr pane:

```bash
source ~/.agent-letterbox/env.sh
letterbox herdr run pi -- pi
```

## Registry format

`herdr-agents.tsv` columns:

```text
agent	pane_id	socket_path	registered_at
```

Example:

```text
pi	w1:p2	/Users/you/.config/herdr/herdr.sock	2026-07-18T12:00:00Z
```

The adapter uses the recorded socket so the correct local Herdr session is targeted.

## Validate

```bash
make test
```
