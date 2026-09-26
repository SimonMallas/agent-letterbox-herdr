"""Print compatibility-query JSON as one short line per letter (read-only)."""
import json
import sys

LIMIT = 5
try:
    data = json.load(sys.stdin)
except ValueError:
    print("  (query output could not be read)")
    sys.exit(0)
cards = data.get("cards", [])
if not cards:
    print("  none in scope (an empty answer is not proof it never happened)")
uncertain = 0
for card in cards[:LIMIT]:
    f = card.get("fields", {})
    ident = f.get("id") or card.get("identity") or ""
    when = (f.get("sent") or card.get("publication_utc") or "time unknown")[:16].replace("T", " ")
    unknown = card.get("unknown_filters") or []
    doubtful = card.get("selection") == "indeterminate" or bool(unknown)
    mark = "?" if doubtful else " "
    note = f"  (uncertain: {', '.join(unknown) or 'selection'})" if doubtful else ""
    print(f" {mark}{when}  from {f.get('from') or '?':<12} {f.get('type') or '?':<9} {card.get('slug') or ''}  [{ident[-8:]}]{note}")
uncertain = sum(1 for c in cards if c.get("selection") == "indeterminate" or c.get("unknown_filters"))
if uncertain:
    print(f"  ? {uncertain} row(s) the query could not classify: they may not belong in this list")
if len(cards) > LIMIT:
    print(f"  +{len(cards) - LIMIT} more (letterbox query ... for the full list)")
if not data.get("complete", False):
    why = (data.get("issues") or data.get("diagnostics") or [])
    first = json.dumps(why[0])[:160] if why else "no reason given"
    print(f"  note: scan incomplete: {first}")
