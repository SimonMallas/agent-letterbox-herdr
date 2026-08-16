# Agent Letterbox for Herdr roadmap

## Shipped in v0.3.0

Agent Letterbox for Herdr is a filesystem-first coordination layer for live local Herdr coding teams.

- Durable letters with explicit ACK, RESULT, NACK, and filing lifecycle.
- One-shot RESULT/NACK for requests that explicitly opt out of ACK.
- Safe reference handling: full ID, display ID, or unique opaque doorbell token.
- Operational inbox view: live work first, stale work last, progress age, `--recent`, `read`, and read-only threads.
- Additive v0.2-compatible doorbell token and safe `nudge` for existing open letters.
- Herdr pane doorbells remain opt-in: a durable letter can arrive even when submit is disabled.
- Public privacy, vocabulary, mutation, and early-abort test gates.

## Next

- Observe real v0.3 use before adding more helper surface.
- Consider a full outbox/open-bets view only after an explicit trust-model review.
- Consider intentional group send only if real team usage justifies it.
- Improve operator diagnostics without turning Letterbox into a dispatcher or task board.

## Deferred / out of scope

- Customer messaging apps remain native and independent of Letterbox.
- Any external messaging or external-knock transport requires a separate, app-neutral charter.
- Auto-registration, machine read receipts, automatic reassignment, and guaranteed wake claims remain out of scope.
- Cross-host transport, message signing, and external agent-runtime adapters require separate evidence-led work.
