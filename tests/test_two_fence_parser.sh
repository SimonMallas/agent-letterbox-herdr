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
echo "$out" | grep -qv 'from: attacker' || fail "attacker from leaked"
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
echo "$out" | grep -qv 'from: trusted' || fail "body from leaked"
echo "$out" | grep -qv 'MALFORMED' || fail "extra body fence treated as malformed"
pass "body may contain further ---; metadata stays the envelope"

echo "two-fence parser tests: PASS"
