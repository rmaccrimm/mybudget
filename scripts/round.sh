#!/usr/bin/env bash
# One adversarial round on a piece of the spec:
#   1. the tester writes tests for the task
#   2. the implementer works until the judge is green (up to MAX_FIXES runs)
#   3. the tester tries to break it; if it finds new failures, back to 2
# The round ends when an attack finds nothing new or after MAX_ATTACKS attacks.
# It stops for a human when either agent ends with a DISPUTE: or QUESTION: line.
#
# Usage: scripts/round.sh "<task, e.g. 'SPEC section 3 (accounts)'>"
# Set MYBUDGET_ROUND (e.g. 3) to label the round's token usage; it defaults to the task.
# Set START=implementer for a task that needs no new tests first, such as a refactor:
# the implementer works on the task, then the judge and the attacks follow as usual.
# Set START=judge to resume a round whose last agent run was cut off (a usage limit):
# the judge runs on the committed code, then the fixes and attacks follow as usual.
#
# Progress: each step appends one JSON line to an events file, $MYBUDGET_EVENTS, or by
# default $MYBUDGET_CACHE/events/round-<round>-<time>.jsonl, written only here, outside
# the agents' sandboxes. Types: round_start, step_start, agent_done, judge_done and
# round_end (always last, with the exit status). Each step's final message or judge
# summary is copied beside it, into <events file without .jsonl>.d/.
# scripts/watch-round.sh follows the file; scripts/round-status.sh summarises it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MYBUDGET_CACHE:-$HOME/.cache/mybudget}"
RES="$CACHE/judge/results"
MAX_FIXES="${MAX_FIXES:-2}"
MAX_ATTACKS="${MAX_ATTACKS:-1}"
task="${1:?usage: $0 \"<task>\"}"
# Label every agent run's usage with the round, so reruns after a ruling add up together.
export MYBUDGET_ROUND="${MYBUDGET_ROUND:-$task}"

label="$(printf '%s' "${MYBUDGET_ROUND:0:40}" | tr -c 'A-Za-z0-9._-' _)"
EVENTS="${MYBUDGET_EVENTS:-$CACHE/events/round-$label-$(date +%Y%m%d-%H%M%S).jsonl}"
STEPS="${EVENTS%.jsonl}.d"
mkdir -p "$STEPS"
echo "round.sh: events in $EVENTS"

# emit --arg type <type> [--arg|--argjson name value]...: appends one event. A failure to
# write one never stops the round.
emit() {
  jq -nc --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg round "$MYBUDGET_ROUND" "$@" '$ARGS.named' \
    >>"$EVENTS" 2>/dev/null || echo "round.sh: couldn't write an event to $EVENTS" >&2
}

step=0 judge_runs=0 run_cost=0 reason=""
on_exit() {
  local status=$? round_cost
  [[ -n "$reason" ]] || reason="round.sh stopped with status $status (see its log)"
  round_cost="$(jq -s --arg r "$MYBUDGET_ROUND" \
    'map(select(.round == $r) | .cost_usd // 0) | add // 0' "$CACHE/usage.jsonl" 2>/dev/null || echo null)"
  emit --arg type round_end --argjson exit_status "$status" --arg reason "$reason" \
    --argjson steps "$step" --argjson run_cost_usd "$run_cost" --argjson round_cost_usd "${round_cost:-null}"
  "$ROOT/scripts/usage.sh" "$MYBUDGET_ROUND" || true
}
trap on_exit EXIT
trap 'reason="round.sh was interrupted"; exit 130' INT TERM

emit --arg type round_start --arg task "$task" --arg start "${START:-tester}" --arg events "$EVENTS" \
  --argjson max_fixes "$MAX_FIXES" --argjson max_attacks "$MAX_ATTACKS"

count_tests() { grep -rhE '^[[:space:]]*(async[[:space:]]+)?fn[[:space:]]+spec_' "$ROOT/testsuite/tests" | wc -l | tr -d ' '; }

# lane <role> <kind> <prompt>: runs one agent through lane.sh and reports it as an event.
# kind says which step it is: write, task, fix <n> or attack <n>.
lane() {
  local role="$1" kind="$2" prompt="$3" dir rc=0 before after outcome ruling copy
  local tests_before=null tests_after=null usage=null changes="" commit=""
  step=$(( step + 1 ))
  [[ $role == tester ]] && dir=testsuite || dir=server
  copy="$STEPS/$(printf %02d "$step")-$role-${kind// /-}.md"
  emit --arg type step_start --argjson step "$step" --arg role "$role" --arg kind "$kind"
  before="$(git -C "$ROOT/$dir" rev-parse HEAD)"
  [[ $role == tester ]] && tests_before="$(count_tests)"

  "$ROOT/scripts/lane.sh" "$role" "$prompt" || rc=$?

  after="$(git -C "$ROOT/$dir" rev-parse HEAD)"
  [[ $role == tester ]] && tests_after="$(count_tests)"
  if [[ $after != "$before" ]]; then
    commit="$dir@$(git -C "$ROOT/$dir" rev-parse --short HEAD)"
    changes="$(git -C "$ROOT/$dir" diff --shortstat "$before" "$after" | sed 's/^ *//')"
  fi
  cp "$CACHE/$role/last-output.md" "$copy" 2>/dev/null || : >"$copy"
  ruling="$(grep -E '^(DISPUTE|QUESTION):' "$copy" || true)"
  usage="$(jq -c '{seconds: (.duration_ms / 1000 | round), cost_usd: .total_cost_usd, turns: .num_turns,
      denials: (.permission_denials | length)}' "$CACHE/$role/last-run.json" 2>/dev/null || echo null)"
  run_cost="$(jq -n --argjson a "$run_cost" --argjson u "${usage:-null}" '$a + ($u.cost_usd // 0)')"
  if (( rc == 4 )); then outcome=left_lane
  elif (( rc != 0 )); then outcome=claude_failed
  elif grep -q '^QUESTION:' <<<"$ruling"; then outcome=question
  elif [[ -n "$ruling" ]]; then outcome=dispute
  elif [[ -z "$commit" ]]; then outcome=no_changes
  else outcome=ok
  fi
  emit --arg type agent_done --argjson step "$step" --arg role "$role" --arg kind "$kind" \
    --arg outcome "$outcome" --argjson exit_status "$rc" --arg commit "$commit" --arg changes "$changes" \
    --argjson tests_before "$tests_before" --argjson tests_after "$tests_after" \
    --argjson usage "${usage:-null}" --arg ruling "$ruling" --arg message_file "$copy"

  if (( rc != 0 )); then
    reason="lane.sh stopped the $role with status $rc ($outcome)"
    exit "$rc"
  fi
  if [[ -n "$ruling" ]]; then
    echo "$ruling" >&2
    echo "round.sh: the $role needs a human ruling (above). Resolve it, then rerun." >&2
    reason="the $role ended with a $outcome; it needs a ruling"
    exit 3
  fi
}

# judge: runs judge.sh, reports it as an event, and returns its status.
judge() {
  local rc=0 start=$SECONDS copy marker passed=null failed=null failing problem="" result
  step=$(( step + 1 )) judge_runs=$(( judge_runs + 1 ))
  copy="$STEPS/$(printf %02d "$step")-judge-$judge_runs.txt"
  marker="$STEPS/.judge-start"
  : >"$marker"
  emit --arg type step_start --argjson step "$step" --arg role judge --arg kind "run $judge_runs"
  echo "== judge"
  "$ROOT/scripts/judge.sh" || rc=$?
  # summary.txt is written on every exit of judge.sh; an older one belongs to an earlier run.
  if [[ "$RES/summary.txt" -nt "$marker" ]]; then cp "$RES/summary.txt" "$copy"; else : >"$copy"; fi
  passed="$(sed -nE 's/^tests: ([0-9]+) passed.*/\1/p' "$copy")"
  failed="$(sed -nE 's/^tests: [0-9]+ passed, ([0-9]+) failed.*/\1/p' "$copy")"
  failing="$(sed -nE 's/^  (SPEC .*)$/\1/p' "$copy" | jq -Rsc 'split("\n") | map(select(. != ""))')"
  problem="$(grep -E 'FAILED|harness:|migrations:|naming rule' "$copy" | head -n 3 | paste -sd ';' - || true)"
  case $rc in 0) result=pass ;; 1) result=fail ;; 2) result=broken ;; *) result="exit $rc" ;; esac
  emit --arg type judge_done --argjson step "$step" --argjson run "$judge_runs" --arg result "$result" \
    --argjson exit_status "$rc" --argjson passed "${passed:-null}" --argjson failed "${failed:-null}" \
    --argjson failing "${failing:-[]}" --arg problem "$problem" \
    --argjson seconds "$(( SECONDS - start ))" --arg summary_file "$copy"
  return "$rc"
}

case "${START:-tester}" in
  implementer) lane implementer task "Task: $task" ;;
  judge) ;;  # resume after an interrupted run: judge the committed code, then fix and attack
  *) lane tester write "Write tests for: $task" ;;
esac
for (( attack = 0; ; attack++ )); do
  fixes=0
  while true; do
    if judge; then break; else rc=$?; fi
    if (( rc != 1 )); then
      reason="the test suite or harness is broken; see $RES"
      echo "round.sh: $reason" >&2
      exit 2
    fi
    if (( fixes >= MAX_FIXES )); then
      reason="still failing after $MAX_FIXES implementer runs"
      echo "round.sh: $reason" >&2
      exit 1
    fi
    fixes=$(( fixes + 1 ))
    # summary.txt is written to be safe for the implementer: failures by clause and the
    # failing tests' names, never their code or output. The last run is told to dispute
    # what it can't pass rather than guess again.
    last=""
    (( fixes < MAX_FIXES )) || last=$'\n\nThis is your last run before the round stops for a human. For any failing test you can\'t make pass, end with a DISPUTE: line for it (see your rules) instead of guessing again.'
    lane implementer "fix $fixes" "Task: $task

Judge results for the committed code:
$(cat "$RES/summary.txt")$last"
  done
  if (( attack > 0 && fixes == 0 )); then
    reason="the tester's last attack found nothing new. Round complete."
    echo "round.sh: $reason"
    exit 0
  fi
  if (( attack == MAX_ATTACKS )); then
    reason="green after $MAX_ATTACKS attacks. Round complete."
    echo "round.sh: $reason"
    exit 0
  fi
  lane tester "attack $(( attack + 1 ))" "The implementation of \"$task\" passes every test. Try to break it: write tests for behavior the spec requires that the server gets wrong or that no test covers yet.

Judge results for the committed code:
$(cat "$RES/summary.txt")"
done
