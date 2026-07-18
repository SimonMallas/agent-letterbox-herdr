# Agent Letterbox for Herdr

## Ring the bell. Create the team.

![Agent Letterbox for Herdr](assets/hero/letterbox-hero-1600x900.png)

**Agent Letterbox for Herdr turns separate coding-agent terminals into a live team inside [Herdr](https://herdr.dev).**

## What it is

Agent Letterbox is not a model, a new terminal, or a second agent harness. It is the coordination layer that lets the agents you already run hand work to one another without making you the human message relay.

A task lands as a durable letter in a teammate's inbox. The doorbell rings, alerting the agent to check it:

```text
📬 letterbox doorbell: check your inbox
```

The agent wakes, picks up the real task from disk, replies, and keeps the work flowing. The terminal gets the knock; the inbox keeps the message.

> **Agent mail that waits safely—and a bell brings it alive.**

## Why it exists

Without coordination, a multi-agent workflow means juggling panes, copying task text, remembering who owns what, and hoping an agent eventually sees a message.

Directly injecting the full task into another terminal is fast, but the terminal becomes the only message record. Agent Letterbox keeps the fast part—the live doorbell—while putting the actual work in a durable, inspectable letter.

```text
full task → durable inbox letter
live wake-up → short generic doorbell
reply → sender inbox
archive → recipient processed history
```

Read the full comparison in [Why Letterbox?](docs/why-letterbox.md).

## What this opens up

- **Near-instant coordination** — a live Herdr agent can receive a doorbell and begin its next turn without human copy/paste.
- **Real handoffs** — implementation, review, research, QA, and fixes can move between agents as explicit owned work.
- **Local pane orchestration** — Herdr's pane API targets the right live terminal while Letterbox keeps the durable record.
- **Durable recovery** — if an agent is offline, restarting, busy, or misses the bell, the task remains in its inbox.
- **Clear responsibility** — delegates require ACK/NACK; replies are delivered before originals are archived.
- **Evidence over claims** — inbox, reply, and processed files show what happened even when an agent conversation is gone.
- **Less human relay work** — you direct the team instead of pasting the same request between terminals.

## What you need

- Bash, Git, and **Herdr 0.7+** (`herdr --version`)
- A running local Herdr session (`herdr` started; local socket only)
- Agents you already run in terminals (Claude Code, Pi, Grok, Hermes, …)

Agent Letterbox for Herdr is local-only and purpose-built for live Herdr agent teams.

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
