# Contributing to Agent Letterbox for Herdr

## Scope (v0.1 local)

**Supported**

- Durable Markdown letters, reply-first handling, atomic publication, advisory locks
- Automatic opt-in Herdr doorbells to live registered panes
- Local Herdr sessions only

**Not in scope**

- cmux, tmux product trees, desktop agents, webhooks, remote/SSH transport packaging, marketplace plugins, servers beyond local Herdr

## Development

```bash
chmod +x bin/letterbox adapters/*.sh tests/*.sh
# Herdr server must be running for the live doorbell test
make test
```
