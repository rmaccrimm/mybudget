#!/usr/bin/env bash
# Summarise a round from its events file (written by round.sh): every step so far, the
# step running now and for how long, and the cost so far.
#
# Usage: scripts/round-status.sh [events file]
# Without one, it reads the newest file in $MYBUDGET_CACHE/events.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MYBUDGET_CACHE:-$HOME/.cache/mybudget}"
events="${1:-}"
if [[ -z "$events" ]]; then
  events="$(ls -t "$CACHE"/events/*.jsonl 2>/dev/null | head -n 1 || true)"
  [[ -n "$events" ]] || { echo "round-status.sh: no events files in $CACHE/events" >&2; exit 1; }
fi
[[ -s "$events" ]] || { echo "round-status.sh: $events is empty or missing" >&2; exit 1; }

echo "$events"
# Every finished step, then the one running now, if any: a step_start with no later event.
jq -r --argjson all false -f "$ROOT/scripts/events.jq" "$events"
last="$(tail -n 1 "$events")"
case "$(jq -r '.type' <<<"$last")" in
  step_start) echo "now: $(jq -r --argjson all true -f "$ROOT/scripts/events.jq" <<<"$last" | sed 's/^step [0-9]*: //')" ;;
  round_end) ;;
  *) echo "now: between steps" ;;
esac
round="$(jq -r '.round' <<<"$last")"
jq -rs --arg r "$round" '"agent cost so far for round \($r): $\(map(select(.round == $r) | .cost_usd // 0) | add // 0 | . * 100 | round / 100)"' \
  "$CACHE/usage.jsonl" 2>/dev/null || true
