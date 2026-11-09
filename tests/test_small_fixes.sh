#!/usr/bin/env bash
# Regressions for small defects, each reproduced on 0.7.0 before its fix.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
letterbox="$root/bin/letterbox"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" LETTERBOX_DIR="$tmp/box"
unset LETTERBOX_DOORBELL LETTERBOX_AGENT LETTERBOX_CHECK_STALE_DAYS LETTERBOX_CHECK_TIDY_AT LETTERBOX_NOTES_DIR LETTERBOX_SESSION

fails=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

"$letterbox" init alpha beta >/dev/null
sent="$(printf 'please\n' | LETTERBOX_AGENT=alpha "$letterbox" send beta request job --ack | grep -m1 '\.md$')"
id="$(basename "${sent##* }" .md)"
tok="${id##*-}"
[[ -n "$id" && -n "$tok" ]] || { echo "FAIL: setup (id=$id tok=$tok)" >&2; exit 1; }

# 1. A stale-days value that is not a plain number falls back, it does not abort check.
for days in 08 1.5 abc ''; do
  out="$(LETTERBOX_AGENT=beta LETTERBOX_CHECK_STALE_DAYS="$days" "$letterbox" check 2>&1)" && [[ "$out" == *"$tok"* ]] \
    && ok "check with LETTERBOX_CHECK_STALE_DAYS='$days'" || bad "check with LETTERBOX_CHECK_STALE_DAYS='$days': $out"
done
# ... and the documented name is the one that is read.
out="$(LETTERBOX_AGENT=beta LETTERBOX_CHECK_STALE_DAYS=3 "$letterbox" check 2>&1)"
[[ "$out" == *"(>3d)"* ]] && ok "LETTERBOX_CHECK_STALE_DAYS is honoured" || bad "LETTERBOX_CHECK_STALE_DAYS=3 ignored: $out"

# 2. A progress note is another agent's text: no control bytes reach the terminal.
printf 'ok\n' | LETTERBOX_AGENT=beta "$letterbox" reply "$id" ack taking >/dev/null
LETTERBOX_AGENT=beta "$letterbox" progress "$id" "$(printf 'half\033[2Jdone\302\233x')" >/dev/null
out="$(LETTERBOX_AGENT=beta "$letterbox" check)"
[[ "$out" == *"progress: half[2Jdonex"* && "$out" != *$'\033'* && "$out" != *$'\302\233'* ]] \
  && ok "progress note printed without control bytes" || bad "progress note carries control bytes"

# 3. A dangling symlink is skipped; the letters after it are still shown.
ln -s "$tmp/nowhere.md" "$tmp/box/beta/inbox/0000-dangling.md"
out="$(LETTERBOX_AGENT=beta "$letterbox" check)"
[[ "$out" == *"$tok"* ]] && ok "check reads past a dangling symlink" || bad "check stopped at a dangling symlink"

[[ "$fails" -eq 0 ]] || exit 1
echo 'small fixes: PASS'
