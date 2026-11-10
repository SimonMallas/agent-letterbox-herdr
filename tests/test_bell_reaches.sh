#!/usr/bin/env bash
# The doorbell must not be lost without anyone being told. Each case was
# reproduced on 0.7.0 before its fix.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
real_path="$PATH"

cat > "$tmp/bin/herdr" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
# A doorbell that records each ring and answers with a valid outcome line.
cat > "$tmp/bell.sh" <<BELL
#!/usr/bin/env bash
printf '%s\n' "\$1 \$2" >> "$tmp/rings.log"
echo 'doorbell-outcome v=1 outcome=submitted reason=- target=surface:1'
BELL
chmod +x "$tmp/bin/herdr" "$tmp/bell.sh"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config"
export LETTERBOX_DIR="$tmp/box" LETTERBOX_HERDR_REGISTRY="$tmp/box/herdr-agents.tsv"
unset LETTERBOX_DOORBELL LETTERBOX_AGENT LETTERBOX_CHECK_TIDY_AT LETTERBOX_NOTES_DIR LETTERBOX_SESSION

fails=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }
rings() { [[ -f "$tmp/rings.log" ]] && wc -l < "$tmp/rings.log" | tr -d ' ' || echo 0; }

"$letterbox" init alpha beta >/dev/null

# 1. Nothing configured: the agent is told its bell cannot ring.
out="$(LETTERBOX_AGENT=beta "$letterbox" check 2>&1)"
[[ "$out" == *"doorbell: not set up"* ]] && ok "check says when no doorbell is set up" || bad "check is silent about a missing doorbell: $out"

# 2. The box has settings but this shell never loaded them (an agent not
#    started by `herdr run`): send, reply and nudge still ring.
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s'\n" "$tmp/box" "$tmp/bell.sh" > "$tmp/box/env.sh"
out="$(LETTERBOX_AGENT=beta "$letterbox" check 2>&1)"
[[ "$out" != *"doorbell: not set up"* ]] && ok "no warning once the box has a doorbell" || bad "warning shown although the box has a doorbell"
sent="$(printf 'please\n' | LETTERBOX_AGENT=alpha "$letterbox" send beta request job --ack --now)"
[[ "$sent" == *"outcome=submitted"* && "$(rings)" == 1 ]] && ok "send --now rings from the box settings" || bad "send --now did not ring: $sent"
id="$(basename "$(printf '%s\n' "$sent" | grep -m1 '\.md$' | sed 's/^sent: //')" .md)"
out="$(LETTERBOX_AGENT=alpha "$letterbox" nudge "$id" 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == 2 ]] && ok "nudge rings from the box settings" || bad "nudge did not ring: $out"
out="$(printf 'on it\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" ack taking --now 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == 3 ]] && ok "reply --now rings from the box settings" || bad "reply --now did not ring: $out"

# 3. A --now reply that dies after the reply is written and before the bell:
#    the retry must ring. (mv fails once, which ends the helper before its ring.)
cat > "$tmp/bin/mv" <<SHIM
#!/usr/bin/env bash
if [[ ! -f "$tmp/mv-failed" ]]; then : > "$tmp/mv-failed"; exit 1; fi
exec /bin/mv "\$@"
SHIM
chmod +x "$tmp/bin/mv"
before="$(rings)"
printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now >/dev/null 2>&1
[[ -f "$tmp/mv-failed" && "$(rings)" == "$before" ]] || bad "crash set-up: the first attempt was meant to die before its ring"
ls "$tmp/box/alpha/inbox" | grep -q -- '--beta--result.md$' || bad "crash set-up: the reply should already be written"
out="$(printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now 2>&1)"
[[ "$(rings)" == $((before + 1)) ]] && ok "retry of a crashed --now reply rings" || bad "retry of a crashed --now reply stayed silent: $out"
# ... and once the task is filed and the reply still unread, a further retry rings too.
out="$(printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now 2>&1)"
[[ "$out" == *"already closed"* && "$(rings)" == $((before + 2)) ]] && ok "retry after filing rings while the reply is unread" || bad "retry after filing stayed silent: $out"
# ... but never after the sender has filed the reply.
r="$(ls "$tmp/box/alpha/inbox" | grep -- '--beta--result.md$')"
LETTERBOX_AGENT=alpha "$letterbox" file "${r%.md}" >/dev/null 2>&1
printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" result finished --now >/dev/null 2>&1
[[ "$(rings)" == $((before + 2)) ]] && ok "no ring for a reply the sender has filed" || bad "rang for a reply already filed"
rm -f "$tmp/bin/mv"

# Every letter rings: a send or reply without --now rings too.
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s'\n" "$tmp/box" "$tmp/bell.sh" > "$tmp/box/env.sh"
before="$(rings)"
sent="$(printf 'plain\n' | LETTERBOX_AGENT=alpha "$letterbox" send beta request plain --ack 2>&1)"
[[ "$sent" == *"outcome=submitted"* && "$(rings)" == $((before + 1)) ]] && ok "a send without --now rings" || bad "a send without --now did not ring: $sent"
pid="$(basename "$(printf '%s\n' "$sent" | sed -n 's/^sent: //p')" .md)"
out="$(printf 'taking it\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$pid" ack plain-ack 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == $((before + 2)) ]] && ok "a reply without --now rings" || bad "a reply without --now did not ring: $out"
out="$(printf 'done\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$pid" result plain-done 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == $((before + 3)) ]] && ok "a result without --now rings" || bad "a result without --now did not ring: $out"

# check says so loudly when typing has been switched off.
printf 'export LETTERBOX_HERDR_SUBMIT=0\n' >> "$tmp/box/env.sh"
out="$(LETTERBOX_AGENT=beta "$letterbox" check 2>&1)"
[[ "$out" == *"doorbell: typing is off"* ]] && ok "check warns when typing is off in env.sh" || bad "no warning for typing off in env.sh"
out="$(LETTERBOX_AGENT=beta LETTERBOX_DOORBELL="$tmp/bell.sh" LETTERBOX_HERDR_SUBMIT=0 "$letterbox" check 2>&1)"
[[ "$out" == *"doorbell: typing is off"* ]] && ok "check warns when typing is off in the environment" || bad "no warning for typing off in the environment"

# A caller's LETTERBOX_HERDR_SUBMIT=0 wins over the box's env.sh, as check reports it.
cat > "$tmp/env-bell.sh" <<ENVBELL
#!/usr/bin/env bash
printf '%s\n' "submit=\${LETTERBOX_HERDR_SUBMIT-unset}" >> "$tmp/env-bell.log"
echo 'doorbell-outcome v=1 outcome=no_live_surface reason=notify_only target=-'
ENVBELL
chmod +x "$tmp/env-bell.sh"
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s'\nexport LETTERBOX_HERDR_SUBMIT=1\n" "$tmp/box" "$tmp/env-bell.sh" > "$tmp/box/env.sh"
: > "$tmp/env-bell.log"
printf 'quiet\n' | env -u LETTERBOX_DOORBELL LETTERBOX_AGENT=alpha LETTERBOX_HERDR_SUBMIT=0 "$letterbox" send beta info quiet >/dev/null 2>&1
[[ "$(cat "$tmp/env-bell.log")" == "submit=0" ]] && ok "a caller's LETTERBOX_HERDR_SUBMIT=0 is not overwritten by env.sh" || bad "env.sh overwrote the caller's LETTERBOX_HERDR_SUBMIT=0: $(cat "$tmp/env-bell.log")"
: > "$tmp/env-bell.log"
printf 'loud\n' | env -u LETTERBOX_DOORBELL -u LETTERBOX_HERDR_SUBMIT LETTERBOX_AGENT=alpha "$letterbox" send beta info loud >/dev/null 2>&1
[[ "$(cat "$tmp/env-bell.log")" == "submit=1" ]] && ok "with nothing set by the caller, env.sh's LETTERBOX_HERDR_SUBMIT=1 applies" || bad "env.sh's LETTERBOX_HERDR_SUBMIT=1 did not apply: $(cat "$tmp/env-bell.log")"

# ring follows the same box rule as send: the caller's box stays the box,
# even when its env.sh names another directory.
mkdir -p "$tmp/elsewhere"
printf "export LETTERBOX_DIR='%s'\nexport LETTERBOX_DOORBELL='%s'\n" "$tmp/elsewhere" "$tmp/bell.sh" > "$tmp/box/env.sh"
rid="$(basename "$(printf 'ring me\n' | LETTERBOX_DOORBELL=/nonexistent LETTERBOX_AGENT=alpha "$letterbox" send beta info ring-me 2>/dev/null | sed -n 's/^sent: //p')" .md)"
before="$(rings)"
out="$(env -u LETTERBOX_DOORBELL "$letterbox" ring beta info "$rid" 2>&1)"
[[ "$out" == *"outcome=submitted"* && "$(rings)" == $((before + 1)) ]] && ok "ring keeps the caller's box when env.sh names another" || bad "ring switched to env.sh's box: $out"

[[ "$fails" -eq 0 ]] || exit 1
echo 'bell reaches: PASS'
