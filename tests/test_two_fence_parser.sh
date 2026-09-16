#!/usr/bin/env bash
# Opening --- plus its closing ---; body may contain more ---.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="${LETTERBOX_BIN:-$root/bin/letterbox}"
box="$(mktemp -d "${TMPDIR:-/tmp}/lb-fence.XXXXXX")"
ringlog="$box/ring.log"
trap 'rm -rf "$box"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

lb() {
  local agent="$1"; shift
  LETTERBOX_DIR="$box" LETTERBOX_AGENT="$agent" LETTERBOX_DOORBELL="$box/doorbell.sh" \
    RINGLOG="$ringlog" "$letterbox" "$@"
}
cat > "$box/doorbell.sh" <<'EOF'
#!/usr/bin/env bash
echo "RING $*" >> "${RINGLOG}"
EOF
chmod +x "$box/doorbell.sh"
: > "$ringlog"

LETTERBOX_DIR="$box" "$letterbox" init alpha beta >/dev/null

printf 'Please review this.\n' | lb alpha send beta delegate review --ack >/dev/null
out="$(lb beta check)"
echo "$out" | grep -q 'from: alpha' || fail "valid from missing"
echo "$out" | grep -q 'type: delegate' || fail "valid type missing"
pass "valid two-fence still parses"

spoof="$box/beta/inbox/2026-09-02T193000-alpha-info-one-fence-a1b2c3d4.md"
cat > "$spoof" <<'EOF'
---
id: 2026-09-02T193000-alpha-info-one-fence-a1b2c3d4
from: attacker
to: beta
type: request
requires_ack: true
thread: BODY-INJECTED-THREAD-ROOT
type: delegate
EOF
: > "$ringlog"
out="$(lb beta check 2>"$box/check.err")" || fail "check died on mixed inbox"
echo "$out" | grep -q 'from: alpha' || fail "valid letter missing from check"
echo "$out" | grep -q 'MALFORMED' || fail "malformed not flagged: $out"
if grep -q 'from: attacker' <<<"$out"; then fail "attacker from leaked: $out"; fi
grep -q 'MALFORMED' "$box/check.err" || fail "no stderr MALFORMED"
[[ ! -s "$ringlog" ]] || fail "check rang doorbell"
[[ -f "$spoof" ]] || fail "check deleted malformed"
pass "check flags unterminated letter; no ring; file kept"

planted="$box/beta/inbox/2026-09-02T193000-alpha-info-planted-private-slug-deadbeef.md"
cat > "$planted" <<'EOF'
---
id: 2026-09-02T193000-alpha-info-planted-private-slug-deadbeef
from: attacker
to: beta
type: info
requires_ack: false
EOF
out="$(lb beta check 2>"$box/planted.err")" || fail "check died on planted slug"
echo "$out" | grep -q 'MALFORMED' || fail "planted not flagged"
echo "$out$box" >/dev/null
if grep -q 'planted-private-slug' <<<"$out"; then
  fail "stdout leaked planted slug: $out"
fi
if grep -q 'planted-private-slug' "$box/planted.err"; then
  fail "stderr leaked planted slug: $(cat "$box/planted.err")"
fi
if grep -Fq "$box/beta/inbox" <<<"$out"; then
  fail "stdout leaked inbox path: $out"
fi
if grep -Fq "$box/beta/inbox" "$box/planted.err"; then
  fail "stderr leaked inbox path: $(cat "$box/planted.err")"
fi
echo "$out" | grep -q '2026-09-02T193000 · deadbeef' || fail "missing compact label: $out"
grep -q '2026-09-02T193000 · deadbeef' "$box/planted.err" || fail "stderr missing compact label"
echo "$out" | grep -q 'from: alpha' || fail "valid letter lost beside planted"
pass "MALFORMED uses compact label; no planted slug or path"

if lb beta read 2026-09-02T193000-alpha-info-one-fence-a1b2c3d4 >/dev/null 2>&1; then
  fail "read accepted one-fence by id"
fi
if lb beta read a1b2c3d4 >/dev/null 2>&1; then
  fail "read accepted one-fence by token"
fi
pass "read refuses unterminated by id and token"

tok="$(lb beta token a1b2c3d4 2>/dev/null || true)"
[[ "$tok" == "unknown-token — no letter; ignore" ]] || fail "token on unterminated: $tok"
[[ ! -s "$ringlog" ]] || fail "token rang"
pass "token ignores unterminated (unknown, no ring)"

set +e
fout="$(lb beta file "$spoof" 2>&1)"
frc=$?
set -e
[[ $frc -ne 0 ]] || fail "file accepted unterminated path"
echo "$fout" | grep -q 'malformed' || fail "file missing malformed: $fout"
[[ -f "$spoof" ]] || fail "file moved unterminated"
[[ ! -s "$ringlog" ]] || fail "file rang"
pass "file path refuses unterminated; no state, no ring"

set +e
rout="$(printf 'ok\n' | lb beta reply "$spoof" ack nope 2>&1)"
rrc=$?
set -e
[[ $rrc -ne 0 ]] || fail "reply accepted unterminated path"
echo "$rout" | grep -q 'malformed' || fail "reply missing malformed: $rout"
[[ -f "$spoof" ]] || fail "reply closed unterminated"
if find "$box" -name '*.lifecycle.lock' -print -quit | grep -q .; then
  fail "reply left a lock"
fi
[[ ! -s "$ringlog" ]] || fail "reply rang"
pass "reply path refuses unterminated; no closure, no lock, no ring"

# CRLF two-fence
crlf="$box/beta/inbox/crlf.md"
python3 -c "
p='''---\r
id: crlf-ok\r
from: alpha\r
to: beta\r
type: info\r
requires_ack: false\r
---\r
body\r
'''
open('$crlf','wb').write(p.encode())
"
out="$(lb beta check 2>/dev/null)"
echo "$out" | grep -q 'from: alpha' || fail "CRLF valid letter lost"
pass "CRLF two-fence still parses"

# Body may contain further ---
rm -f "$box/beta/inbox"/*.md
cat > "$box/beta/inbox/body-keys.md" <<'EOF'
---
id: body-keys-ok
from: alpha
to: beta
type: info
re:
priority: next
requires_ack: false
deadline:
---
to: victim
from: trusted
type: delegate
---
still body
EOF
out="$(lb beta check)"
echo "$out" | grep -q 'from: alpha' || fail "real from lost"
echo "$out" | grep -q 'type: info' || fail "real type lost"
if grep -q 'from: trusted' <<<"$out"; then fail "body from leaked: $out"; fi
if grep -q 'MALFORMED' <<<"$out"; then fail "extra body fence treated as malformed: $out"; fi
pass "body may contain further ---; metadata stays the envelope"

# Identical ACK retry must keep body --- ; changed body still collides.
rm -f "$box/beta/inbox"/*.md "$box/alpha/inbox"/*.md
printf 'Please review this.\n' | lb alpha send beta delegate fence-retry --ack >/dev/null
shopt -s nullglob
freq=("$box/beta/inbox/"*fence-retry*.md)
shopt -u nullglob
[[ ${#freq[@]} -eq 1 ]] || fail "fence-retry setup count ${#freq[@]}"
freq_id="$(awk -F': ' '$1 == "id" { print $2; exit }' "${freq[0]}")"
fence_body=$'Accepted\n---\nDetails retained\n'
set +e
ack1="$(printf '%s' "$fence_body" | lb beta reply "$freq_id" ack same-reply 2>&1)"
ack1rc=$?
set -e
[[ $ack1rc -eq 0 ]] || fail "first fenced ACK refused: $ack1"
shopt -s nullglob
ackfiles=("$box/alpha/inbox/"*"--ack.md")
shopt -u nullglob
[[ ${#ackfiles[@]} -eq 1 ]] || fail "fenced ACK not published (${#ackfiles[@]})"
python3 -c "
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
body = text.split('---\n', 2)[-1]
assert body == 'Accepted\n---\nDetails retained\n', repr(body)
" "${ackfiles[0]}" || fail "stored ACK dropped body fence"
set +e
ack2="$(printf '%s' "$fence_body" | lb beta reply "$freq_id" ack same-reply 2>&1)"
ack2rc=$?
set -e
[[ $ack2rc -eq 0 ]] || fail "identical fenced ACK retry refused: $ack2"
set +e
ack3="$(printf 'other\n' | lb beta reply "$freq_id" ack same-reply 2>&1)"
ack3rc=$?
set -e
[[ $ack3rc -ne 0 ]] || fail "changed-body ACK retry accepted: $ack3"
echo "$ack3" | grep -q 'reply collision has different body' || fail "changed-body missing collision: $ack3"
pass "identical ACK retry preserves body ---; changed body refused"

# Unrelated unterminated letter must not abort check --thread.
rm -f "$box/beta/inbox"/*.md "$box/alpha/inbox"/*.md
printf 'Please review this.\n' | lb alpha send beta delegate thread-guard --ack >/dev/null
shopt -s nullglob
tg=("$box/beta/inbox/"*thread-guard*.md)
shopt -u nullglob
[[ ${#tg[@]} -eq 1 ]] || fail "thread-guard setup count ${#tg[@]}"
tg_id="$(awk -F': ' '$1 == "id" { print $2; exit }' "${tg[0]}")"
tg_tok="${tg_id##*-}"
cat > "$box/beta/inbox/000-unrelated-one-fence.md" <<'EOF'
---
id: 2026-09-02T193000-alpha-info-unrelated-one-fence-aabbccdd
from: attacker
to: beta
type: info
requires_ack: false
EOF
set +e
thout="$(lb beta check --thread "$tg_id" 2>"$box/thread.err")"
thrc=$?
set -e
[[ $thrc -eq 0 ]] || fail "check --thread died on unrelated malformed: rc=$thrc out=$thout err=$(cat "$box/thread.err")"
echo "$thout" | grep -q '── thread' || fail "missing thread header: $thout"
echo "$thout" | grep -q "$tg_tok" || fail "valid thread row missing: $thout"
echo "$thout" | grep -q 'beta' || fail "beta row missing: $thout"
if grep -q 'from: attacker' <<<"$thout"; then fail "attacker leaked in thread: $thout"; fi
if grep -q 'unrelated-one-fence' <<<"$thout"; then fail "malformed slug leaked: $thout"; fi
pass "check --thread stays 0 and lists valid rows despite unrelated malformed"

echo "two-fence parser tests: PASS"
