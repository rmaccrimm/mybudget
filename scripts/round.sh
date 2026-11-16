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
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MYBUDGET_CACHE:-$HOME/.cache/mybudget}"
RES="$CACHE/judge/results"
MAX_FIXES="${MAX_FIXES:-5}"
MAX_ATTACKS="${MAX_ATTACKS:-2}"
task="${1:?usage: $0 \"<task>\"}"
# Label every agent run's usage with the round, so reruns after a ruling add up together.
export MYBUDGET_ROUND="${MYBUDGET_ROUND:-$task}"
trap '"$ROOT/scripts/usage.sh" "$MYBUDGET_ROUND" || true' EXIT

lane() {
  "$ROOT/scripts/lane.sh" "$1" "$2"
  if grep -E '^(DISPUTE|QUESTION):' "$CACHE/$1/last-output.md" >&2; then
    echo "round.sh: the $1 needs a human ruling (above). Resolve it, then rerun." >&2
    exit 3
  fi
}

lane tester "Write tests for: $task"
for (( attack = 0; ; attack++ )); do
  fixes=0
  while true; do
    echo "== judge"
    if "$ROOT/scripts/judge.sh"; then break; else rc=$?; fi
    (( rc == 1 )) || { echo "round.sh: the test suite or harness is broken; see $RES" >&2; exit 2; }
    (( fixes < MAX_FIXES )) || { echo "round.sh: still failing after $MAX_FIXES implementer runs" >&2; exit 1; }
    fixes=$(( fixes + 1 ))
    # summary.txt is written to be safe for the implementer: failures by clause, no tests.
    lane implementer "Task: $task

Judge results for the committed code:
$(cat "$RES/summary.txt")"
  done
  if (( attack > 0 && fixes == 0 )); then
    echo "round.sh: the tester's last attack found nothing new. Round complete."
    exit 0
  fi
  if (( attack == MAX_ATTACKS )); then
    echo "round.sh: green after $MAX_ATTACKS attacks. Round complete."
    exit 0
  fi
  lane tester "The implementation of \"$task\" passes every test. Try to break it: write tests for behavior the spec requires that the server gets wrong or that no test covers yet.

Judge results for the committed code:
$(cat "$RES/summary.txt")"
done
