#!/usr/bin/env bash
# Sum the agents' token usage by round and role, from $MYBUDGET_CACHE/usage.jsonl
# (written by lane.sh). Cost is Claude Code's list-price estimate.
# Usage: scripts/usage.sh [round]
set -euo pipefail
CACHE="${MYBUDGET_CACHE:-$HOME/.cache/mybudget}"
ledger="$CACHE/usage.jsonl"
[[ -s "$ledger" ]] || { echo "usage.sh: no usage recorded yet in $ledger" >&2; exit 0; }
{
  printf 'round\trole\truns\tturns\tinput\toutput\tcache_read\tcache_write\tcost_usd\n'
  jq -rs --arg r "${1:-}" '
    map(select($r == "" or .round == $r))
    | (group_by([.round, .role])[] | [.[0].round, .[0].role, .]),
      (if length > 0 then [(if $r == "" then "all" else $r end), "total", .] else empty end)
    | . as [$round, $role, $runs]
    | [$round, $role, ($runs | length), ($runs | map(.turns // 0) | add),
       ($runs | map(.input // 0) | add), ($runs | map(.output // 0) | add),
       ($runs | map(.cache_read // 0) | add), ($runs | map(.cache_write // 0) | add),
       ($runs | map(.cost_usd // 0) | add * 100 | round / 100)]
    | @tsv' "$ledger"
} | column -t -s $'\t'
