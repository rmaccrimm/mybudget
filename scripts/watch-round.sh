#!/usr/bin/env bash
# Follow a round's events file (written by round.sh) and print one line per finished step,
# for Claude Code's Monitor tool: each printed line becomes one notification. Exits after
# round_end. step_start events print nothing.
#
# Usage: scripts/watch-round.sh <events file>
# The file may not exist yet. <events file>.cursor counts the events already printed, so
# a watcher restarted on the same file (a Monitor re-armed after its time limit) carries
# on where the last one stopped, never repeating or skipping an event.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
events="${1:?usage: $0 <events file>}"
cursor="$events.cursor"
done_=0
[[ -s "$cursor" ]] && done_="$(cat "$cursor")"

while true; do
  if [[ -f "$events" ]]; then
    # Only whole lines count; round.sh writes each event with a single append.
    total="$(wc -l <"$events" | tr -d ' ')"
    while (( done_ < total )); do
      line="$(sed -n "$(( done_ + 1 ))p" "$events")"
      jq -r --argjson all false -f "$ROOT/scripts/events.jq" <<<"$line" ||
        echo "watch-round.sh: unreadable event $(( done_ + 1 )): ${line:0:200}"
      done_=$(( done_ + 1 ))
      echo "$done_" >"$cursor"
      if [[ "$(jq -r '.type' <<<"$line" 2>/dev/null)" == round_end ]]; then exit 0; fi
    done
  fi
  sleep 2
done
