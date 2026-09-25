# Changelog

All notable changes to Agent Letterbox for Herdr are documented here.

## v0.5.0 — unreleased (Herdr edition)

- Add read-only `letterbox query`: strict-v1 envelope cards by default and
  explicit `--compat-v2` JSON with diagnostics and scoped completeness.
- Query requires Python 3.9+ (standard library only), with an explicit refusal
  when unavailable. Existing send/reply/registration and bounded doorbell
  behavior is unchanged.
- Writer contract: new send/reply letters carry UTC `sent` from a single clock
  snapshot; `letterbox send --supersedes <id>` adds the optional annotation
  with bounded reference validation (repeated flags refused; replies do not
  inherit). Existing letters are unchanged.
- Identifier/reference grammar is 1–243 ASCII bytes (255-byte filename budget
  minus the 12-byte temporary wrapper) across writer and both query modes.
  New sends bound their normalized slug to leave room for the recipient's
  longest reply suffix, reporting the actual per-send maximum on refusal.
  Session and deadline are validated before any lock or publication; inherited
  reply linkage is validated before publication. Invalid session labels are
  refused before a reply can create a lifecycle lock.
- Add synthetic query/writer test suites to `make ci`, with Python 3.9 and 3.13
  on the Ubuntu and macOS workflow matrix. Matrix configuration is not a claim
  of a passed run.
- No archive traversal, archive verb, or send-side validation expansion.
  See [query contracts and limitations](docs/query.md).

## [0.4.0] — 2026-09-17

### Changed

Release 2 doorbell contract. The ring now reports exactly one
`doorbell-outcome v=1` line per attempt — `submitted`,
`pasted_not_submitted`, or `no_live_surface` with a named reason — owned by
the helper wrapper, never by adapter prose. The typed doorbell line may
name the durable letter's sender.

- The wrapper is the sole outcome owner: the adapter's stdout is a private
  pipe; exactly one valid contract line on exit 0 forwards, anything else
  reports `unconfirmed` (`unparseable` is the consumer's verdict, never an
  emitter token).
- Two-step bounded inject (text, then Enter), each step bounded and
  classified: `send_failed`, `pasted_not_submitted enter_failed`,
  post-inject `unconfirmed`; only a proven pre-injection timeout is
  `helper_timeout` (the one retryable class).
- Runner-owned timeout sentinel: a child exiting 124 on its own is
  remapped and can never be misread as a timeout. Verified-runner check:
  missing python3 or herdr is `adapter_unavailable` (non-retryable), and
  without the bounder the wrapper fails closed — the adapter is never run
  unbounded.
- Ruled exit-status precedence: `submitted`/`pasted` claims after a
  nonzero exit downgrade to `unconfirmed`; a valid `no_live_surface` line
  keeps its named reason.
- Ruling-5 sender clause resolved from the durable letter (never
  `LETTERBOX_AGENT`), omitted when invalid — never `from -`.
- Bounds budget documented in SPEC: 1s step budget, 4×step+5s wrapper
  backstop (9s at default), strictly inside the caller's 10s deadline.
- `nudge` now passes a real slug to the doorbell adapter (previously an
  empty argument silently prevented the ring).

## [0.3.3] — 2026-09-16

Maintenance cut of public main since 0.3.2. Outbox inbound exclusion is
already on this tree and is not reimplemented. Timestamp helpers already
had a GNU date fallback and are unchanged.

### Fixed

- `file_mtime` accepts a probe only when the complete captured stdout is a
  canonical decimal epoch (optional minus; no leading zeros). Nonzero exit
  discards stdout. GNU `-c` then BSD `-f`.
- `send` and `reply` refuse an empty or whitespace-only body. Non-blank
  bodies keep their surrounding whitespace.
- Frontmatter is trusted only with an opening `---` and its closing `---`.
  Further `---` lines belong to the body. Unterminated letters are skipped
  in check/token/read/file/reply with compact ids (no raw path or slug).
- `message_body` keeps `---` lines after the envelope close, so an identical
  ACK retry with a fenced body matches the stored letter. A different body
  still collides.
- `check --thread` skips unterminated letters instead of exiting 1.
- `message_body` emits raw lines so CRLF bodies survive identical ACK retry.

### Added

- README links the shared guide.

## [0.3.2] — 2026-08-16

### Fixed

- **The documented doorbell example did not match what the adapter emits.** README, SPEC and
  the Herdr docs showed:

  a short form ending in `check your inbox`, with no type, path or token. The adapter has
  never emitted that shape. It emits:

  ```text
  📬 letterbox doorbell: unacked <type> in <letterbox>/<agent>/inbox/ — please check
  📬 letterbox doorbell: unacked <type> in <letterbox>/<agent>/inbox/ — please check · <8-lowercase-hex>
  ```

  **Impact:** an agent that built its permitted-line rule from the documented example would
  have matched nothing and silently ignored every live doorbell — with no error to diagnose.
  If you configured doorbell acceptance from the docs before 0.3.2, re-check it against the
  two shapes above and match by prefix, never by exact equality.

### Added

- **A docs/code drift gate** (`tests/test_doorbell_docs_drift.sh`, run by `make test`). It
  executes the adapter against a mocked platform CLI, captures the line actually emitted, and
  asserts every documented doorbell line in every tracked file conforms to it. Failures name
  the file and line. A companion mutation harness proves the gate catches planted drift in
  README, SPEC, SKILL and `docs/`, and that it still passes on a clean tree.

  This is the durable fix. The wrong example was a symptom; nothing previously bound the
  documentation to the code.

- **An agent entry point in the README**, naming `skills/agent-letterbox/SKILL.md` as the
  operating manual. The acceptance rule lived only in the skill, and nothing pointed to it.

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

- Additive doorbell change: v0.2 tokenless lines and v0.3 token-bearing lines are both valid doorbells. Match by prefix/pattern only; exact full-line equality is a cutover hazard.
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
