# Changelog

All notable changes to Agent Letterbox for Herdr are documented here.

## [0.3.1] — 2026-08-16

- Correct v0.3 release metadata and roadmap wording.
- Complete public v0.3 release-gate coverage, including worktree-clean vocabulary mutations and early-abort lifecycle checks.

## [0.3.0] — 2026-08-16

Public v0.3 adds operational reading verbs and additive doorbell tokens while keeping the v0.2 letter format and doorbell byte-prefix.

### Added

- `letterbox check` redesign: open work only, live first, stale last (>14 days of last-activity silence, marked `STALE <age>`), counts in the header. `check` never prints letter bodies; it labels display-ids (`timestamp · token`), `[UNACKED]` / `[ACCEPTED]` state, and progress notes with age. `--recent` hides stale items behind a hidden-count footer; `--thread <id>` gives a read-only fan-out (via `thread:`, then `re:` fallback) reporting lifecycle state, never attention.
- `letterbox read <id|display-id|token>` prints the exact durable letter from your own inbox.
- `letterbox progress <ref> <one-line>` records progress in the `.md.ack` sidecar of accepted work; `check` shows it with its age. No new letter, no state change.
- `letterbox nudge <id|display-id|token>` re-rings an open letter; it creates nothing and refuses a filed/terminal letter.
- `letterbox token <8hex>` resolves a doorbell token to `unhandled` / `already filed` / `unknown`, and lists matches (taking no action) on a collision.
- Doorbell lines may carry an additive opaque token suffix: `… — please check · <8hex>`. The token is derived from the letter id and is never a slug, body, or path.
- `letterbox file <path> --read` for inbound terminal replies given as a filesystem path (structural rule C: path-form filing of an unread inbound `result`/`nack` refuses; an explicit id, display-id, or unique token files directly).
- Low-ceremony close: a `requires_ack: false` letter may be closed in one step with `letterbox reply <id> result|nack <slug>` — no prior ACK. `ack` on a non-task letter is refused with the correct next action.
- The helper bounds doorbell adapter runs (`LETTERBOX_DOORBELL_TIMEOUT`, default 5s) so an unresponsive pane path cannot hang a sender; the letter is already durable. Adapter outcomes are reported as `submitted`, `pasted_not_submitted`, or `no_live_surface` — never that the letter was read.

### Changed

- `reply` reads the body from stdin before taking any lifecycle lock; a TTY or empty stdin fails fast with usage instead of hanging or pinning the letter.
- Confirmations and errors label letters by display-id (`timestamp · token`), never by filename, slug, or path.
- Lifecycle errors name the correct next action (wrong reply verb, terminal parent, unknown id, ACK-required).

### Compatibility

- Additive doorbell change: v0.2 tokenless lines and v0.3 token-bearing lines are both valid knocks. Match by prefix/pattern only; exact full-line equality is a cutover hazard.
- All v0.2 lifecycle rules are unchanged: ACK stays non-terminal, `file` refuses task letters, `done` refuses accepted work, ownership replies come from `letterbox reply`.
- All agents in a team should run the same helper version.

## [0.2.0] — 2026-08-11

Public v0.2 establishes a durable task lifecycle for local Herdr teams and documents the resulting state machine.

### Fixed

- `reply <id> ack` marks a task as accepted work in progress and leaves it in the inbox; only `nack` and `result` close it.
- The doorbell now rings after the letter's local state has settled, not before.
- `check` excludes `.ack` sidecars from the letter count and warns about an orphan sidecar.
- Message parsing tolerates CRLF line endings.
- A failed reply link is recovered deterministically rather than aborting.

### Added

- `.md.ack` sidecar marking a letter as accepted and in progress.
- `letterbox file <id>` to dispose of a letter that requires no acknowledgement.
- Lifecycle locking so concurrent replies to the same letter converge on one terminal state.
- Derived `thread` field on ownership replies.
- `docs/lifecycle.md` and expanded SPEC/README lifecycle wording.
- `letterbox herdr setup` / `run` / `register` / `unregister` / `status`, live pane+socket registry, static pane-id fallback, and beginner install path (folded from earlier unreleased history).

### Changed

- `SPEC.md` raised to v0.2 with an explicit letter state machine and task vs non-task rules.
- `done` refuses to close a letter that has been acknowledged; use `reply <id> result|nack`.
- `file` refuses letters that require acknowledgement.
- `send` rejects freeform `ack`, `nack`, and `result`; use `reply` for ownership responses so the helper derives their link and retry identity.
- `delegate` now requires `--ack`.
- Documentation examples use neutral role identities (`planner`, `reviewer`, `builder`, `researcher`).

### Compatibility

- Additive message-format change: ownership replies carry an optional `thread` field. Existing letters remain valid; older readers ignore unknown frontmatter keys.
- Existing scripts that send freeform `ack`, `nack`, or `result` must switch to `letterbox reply <id> <ack|nack|result> <slug>`.
- Existing delegate sends must include `--ack`.
- All agents in a team must run the same v0.2 helper version.

## [0.1.0] — 2026-07-18

### Added

- Durable Letterbox CLI with atomic publish, reply-first handling, locks, and completion checks.
- Local Herdr bootstrap (`setup` / `run` / `register` / `status`).
- Registry-first adapter using Herdr `pane send-text` + Enter when submit is enabled.
- Core tests and beginner documentation.
