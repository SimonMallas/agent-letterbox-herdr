# Agent Letterbox for Herdr roadmap

## v0.2 scope (local)

Agent Letterbox for Herdr is a filesystem-first coordination system for live local Herdr terminal-agent teams.

Public v0.2 is a **correctness** release: task vs non-task lifecycle, non-terminal ACK with `.md.ack` sidecars, terminal NACK/RESULT, `file` for non-task disposal, publish-before-close ordering, and doorbell-after-local-state.

**Supported:**

- Durable Markdown letters in per-agent inboxes.
- Task vs non-task handling (`requires_ack`).
- Non-terminal `ack` (accepted WIP + sidecar); terminal `nack` / `result`.
- `letterbox file` for non-task letters.
- Reply-first publication and recipient-owned archival.
- Atomic message publication, advisory locks, lifecycle locks, and filesystem completion proof.
- `letterbox herdr setup` / `run` / `register` bootstrap with live pane **and** socket registry.
- Automatic opt-in Herdr pane input doorbells (`LETTERBOX_HERDR_SUBMIT=1`); notification toast when submit is off.
- Static pane-id pattern fallback after live registry.
- Local Herdr only (Herdr 0.7+).
- User-controlled Herdr layouts: workspaces, tabs, and panes.

**Not supported (deferred / non-goals):**

Carried forward:

- SSH/remote Herdr session packaging.
- Plugins marketplace distribution as a dependency.
- cmux/tmux/desktop/webhook adapters in this tree (sibling products).
- Autonomous desktop-agent turns.
- Persistent watchers, relay/proxy services, or required background daemons.
- Multi-machine file transport or networked doorbells.

New explicit deferrals for v0.2:

- Automatic backlog drain tools that bulk-file inboxes.
- `check --deep` reconciliation of letters that older helpers wrongly archived after ACK.
- A frontmatter protocol-version field (v0.2 keeps the on-disk format unchanged).
- Built-in chat bridges.
- Session `resume-log` as a public CLI surface.
- A permanent postmaster role or central dispatcher.

## Next milestones

1. Dogfood with multi-agent Herdr layouts.
2. Soak the published artifact (curl + git install paths, one real ack→result cycle) on a local Herdr server.
3. Keep lifecycle semantics aligned with cmux/tmux siblings without coupling releases.
