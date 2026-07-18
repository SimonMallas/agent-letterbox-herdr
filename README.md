# Agent Letterbox for Herdr

## Ring the agent. Keep the message. Work as a team.

**Agent Letterbox for Herdr turns separate coding-agent terminals into a live team inside [Herdr](https://herdr.dev).**

A message is saved safely on disk. When the recipient is live, Herdr receives one short instruction in its pane:

```text
📬 letterbox doorbell: unacked delegate in <letterbox>/<agent>/inbox/ — please check
```

The agent checks the durable message, replies, and hands work onward.

> **The doorbell makes it a team.**

## What you need

- Bash, Git, and **Herdr 0.7+** (`herdr --version`)
- A running local Herdr session (`herdr` started; local socket only)
- Agents you already run in terminals (Claude Code, Pi, Grok, Hermes, …)

No servers beyond Herdr’s local multiplexer. No SSH/remote transport, plugins marketplace, desktop apps, webhooks, cmux, or tmux.

## Install (copy / paste)

### Option A — Recommended: copy/paste installer

```bash
curl -fsSL https://raw.githubusercontent.com/SimonMallas/agent-letterbox-herdr/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
letterbox herdr setup --agents pi,claude,grok,hermes --automatic-doorbells
source "$HOME/.agent-letterbox/env.sh"
```

To update later, run the same installer again:

```bash
curl -fsSL https://raw.githubusercontent.com/SimonMallas/agent-letterbox-herdr/main/install.sh | sh
```

### Option B — Manual Git install

```bash
git clone https://github.com/SimonMallas/agent-letterbox-herdr.git \
  ~/Developer/agent-letterbox-herdr
cd ~/Developer/agent-letterbox-herdr
chmod +x bin/letterbox adapters/*.sh tests/*.sh
export PATH="$PWD/bin:$PATH"
letterbox herdr setup --agents pi,claude,grok,hermes --automatic-doorbells
source "$HOME/.agent-letterbox/env.sh"
```

Check:

```bash
letterbox --version
herdr --version
echo "$LETTERBOX_DIR"
```

## Launch agents (you choose the panes)

Open Herdr and arrange agents however the task requires. In **each agent pane**:

```bash
source "$HOME/.agent-letterbox/env.sh"

letterbox herdr run pi -- pi
# other panes:
letterbox herdr run claude -- claude
letterbox herdr run grok -- grok
letterbox herdr run hermes -- hermes
```

`herdr run` registers the current Herdr pane id **and** `HERDR_SOCKET_PATH` for live doorbells, then starts the command.

If a pane was rebuilt:

```bash
letterbox herdr register pi
letterbox herdr status
```

## Send a live handoff

```bash
source "$HOME/.agent-letterbox/env.sh"
export LETTERBOX_AGENT=pi

printf '%s\n' 'Review src/auth.ts and report correctness findings.' |
  letterbox send claude delegate auth-review --ack --now
```

1. Letter lands in Claude’s inbox
2. Doorbell is injected into Claude’s registered Herdr pane (`pane send-text` + `enter`)
3. Claude ACKs / works / replies with `letterbox reply`
4. Original letter is archived

> `LETTERBOX_HERDR_SUBMIT=1` (set by `--automatic-doorbells`) injects into a live pane. Use dedicated agent panes only.

## Test

```bash
make test
```

Requires a running local Herdr server (`herdr status` shows running).

## Learn more

- [docs/why-letterbox.md](docs/why-letterbox.md) — why durable letters plus generic doorbells beat direct task injection
- [docs/team-setup.md](docs/team-setup.md) — full Herdr team bootstrap
- [docs/herdr.md](docs/herdr.md) — adapter details and safety
- [SPEC.md](SPEC.md) — message format and reply-first semantics
- [SECURITY.md](SECURITY.md) — threat model

## License

[MIT](LICENSE)
