# Formats one event from round.sh's events file (see round.sh) as one line.
# Used by watch-round.sh and round-status.sh. With --argjson all false, step_start events,
# which only say a step began, print nothing.
def money: if . == null then "$?"
  else (. * 100 | round) as $c | "$\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)" end;
def took: if . == null then "?" elif . < 60 then "\(.)s" else "\(. / 60 | floor)m\(. % 60)s" end;
def ago: (now - (.time | fromdateiso8601) | floor | took);

if .type == "round_start" then
  "round \(.round) started (START=\(.start), MAX_FIXES=\(.max_fixes), MAX_ATTACKS=\(.max_attacks)); events in \(.events)"
elif .type == "step_start" then
  if $all then "step \(.step): \(.role) (\(.kind)) started \(ago) ago" else empty end
elif .type == "agent_done" then
  "step \(.step): \(.role) (\(.kind)) finished: \(.outcome)"
  + (if .exit_status != 0 then " (exit \(.exit_status))" else "" end)
  + (if .commit != "" then " · committed \(.commit)" else " · no commit" end)
  + (if .tests_before != null then " · tests \(.tests_before) → \(.tests_after)" else "" end)
  + (if .changes != "" then " · \(.changes)" else "" end)
  + " · \(.usage.seconds | took) · \(.usage.cost_usd | money)"
  + (if (.usage.denials // 0) > 0 then " · \(.usage.denials) tool call(s) denied" else "" end)
  + (if .ruling != "" then " · \(.ruling | gsub("\n"; " | ") | .[0:400])" else "" end)
  + " · message: \(.message_file)"
elif .type == "judge_done" then
  "step \(.step): judge (run \(.run)) finished: \(.result)"
  + (if .passed != null then " · \(.passed) passed, \(.failed) failed" else "" end)
  + (if (.failing | length) > 0 then " · failing: \(.failing | join("; "))" else "" end)
  + (if .problem != "" then " · \(.problem)" else "" end)
  + " · \(.seconds | took) · summary: \(.summary_file)"
elif .type == "round_end" then
  "round \(.round) ended: exit \(.exit_status), \(.reason) · this run \(.run_cost_usd | money), round so far \(.round_cost_usd | money)"
else
  "unknown event: \(tojson)"
end
