# Security Policy

## Supported versions

Until a public tag is cut, treat **main / pre-release** as the only line that receives security fixes. Once `v0.2.x` is tagged, report issues against the latest patch of that minor line.

## What this project is (and is not)

Agent Letterbox is a **local filesystem protocol** plus a small Bash CLI. It has:

- No network server in the core path
- No authentication of message authors
- No encryption of letters on disk
- No multi-tenant isolation beyond OS file permissions

**Anyone (or any process) who can write to a peer’s inbox directory can plant a letter.** Treat inbox contents as **untrusted data**, not as authority.

Letters are operator/user content on disk. The core project never transmits letter bodies to a network service.

## Threat model (v0.2)

| Trust | Assumption |
|-------|------------|
| Disk layout | You choose `LETTERBOX_DIR` on a machine and filesystem you control |
| Agents | Cooperative agents follow task/non-task lifecycle and do not expand permissions from letter bodies |
| Doorbells | Optional adapters only signal a live session; they must not carry task content |
| Locks | Advisory only — not a security boundary |
| Sidecars | `.md.ack` files are local metadata beside open task letters |
| Herdr | Local socket + pane ids stay on a host you already trust; remote packaging is out of scope |

### Expected operator practices

1. **Permissions:** Restrict `LETTERBOX_DIR` to users/processes that should coordinate (e.g. `0700` / group-only as appropriate).
2. **Untrusted bodies:** Verify unusual, destructive, or identity-sensitive requests out of band before acting.
3. **No permission expansion:** A letter must never grant an agent tools, paths, or network rights it did not already have.
4. **Doorbell injection:** Opt-in terminal submit (`LETTERBOX_HERDR_SUBMIT=1`) can inject keystrokes into a live pane; leave it off unless you accept that risk. Use dedicated agent panes only.
5. **Herdr socket:** Registration records `HERDR_SOCKET_PATH` so doorbells hit the correct local session. Do not point adapters at sockets you do not control.
6. **Shared hosts:** Do not expose Letterbox directories on untrusted multi-user systems without additional access control.
7. **External intake (if any):** Chat/email/webhooks are entry points, not bus identities. Allowlist sources before publishing letters; unknown senders fail closed; missing allowlist denies all.

### Explicitly out of scope for v0.2 core

- Cryptographic signing of letters
- Mutual authentication of agents
- Remote multi-machine transport / SSH Herdr packaging
- Autonomous unattended processing without a human-in-the-loop terminal agent
- Built-in third-party chat bridges

See [ROADMAP.md](ROADMAP.md).

## Reporting a vulnerability

Please **do not** open a public issue for security-sensitive reports.

1. Contact the maintainer privately (repository owner on GitHub, or the contact listed on the public project page once published).
2. Include: affected version/commit, reproduction steps, impact, and any suggested fix.
3. Allow a reasonable window for a patch before public disclosure.

If the project is still private, use the same private channel you already use with the maintainer.

## Safe defaults for integrators

- Prefer live Herdr terminal agents with durable inbox fallback.
- Judge completion by **on-disk** reply + archive (and sidecar state), never by model prose alone.
- Keep doorbell lines generic; never inject task bodies into panes.
- Prefer live pane+socket self-registration over static pane-id patterns when identities can collide.
- Leave `LETTERBOX_HERDR_SUBMIT` unset unless agent panes are dedicated.
