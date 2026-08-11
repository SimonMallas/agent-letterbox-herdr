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

`--automatic-doorbells` enables `LETTERBOX_HERDR_SUBMIT=1`.

## Launch agents

In each agent’s Herdr pane, launch whatever coding-agent CLI you already run:

```bash
source ~/.agent-letterbox/env.sh
letterbox herdr run planner -- <your-agent-cli>
letterbox herdr run reviewer -- <your-agent-cli>
letterbox herdr run builder -- <your-agent-cli>
letterbox herdr run researcher -- <your-agent-cli>
```

## Registry format

`herdr-agents.tsv` columns:

```text
agent	pane_id	socket_path	registered_at
```

Example (paths are illustrative only):

```text
planner	w1:p2	/Users/you/.config/herdr/herdr.sock	2026-07-18T12:00:00Z
```

The adapter uses the recorded socket so the correct local Herdr session is targeted.

## Validate

```bash
make test
```
