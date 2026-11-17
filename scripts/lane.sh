#!/usr/bin/env bash
# Run one headless Claude session confined to a lane, check it stayed in its lane,
# then commit its work.
#   tester       works in testsuite/ and can't write anywhere else
#   implementer  works in server/, can't write anywhere else, can't read the tests
# Enforcement comes from the role's settings (roles/<role>.json): the session starts in
# the lane's directory with Claude Code's OS-level sandbox on, so Bash and everything it
# runs can write only there.
#
# Usage: scripts/lane.sh <tester|implementer> "<prompt>"
# The session's final message is saved to $MYBUDGET_CACHE/<role>/last-output.md.
# Token usage is appended to $MYBUDGET_CACHE/usage.jsonl, labelled with $MYBUDGET_ROUND.
# Set MYBUDGET_MODEL to choose the model. A role's effort is roles/<role>.json's effortLevel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MYBUDGET_CACHE:-$HOME/.cache/mybudget}"
role="${1:-}"
prompt="${2:-}"
case "$role" in
  tester) lane=testsuite ;;
  implementer) lane=server ;;
  *) echo "usage: $0 <tester|implementer> \"<prompt>\"" >&2; exit 64 ;;
esac
[[ -n "$prompt" ]] || { echo "lane.sh: empty prompt" >&2; exit 64; }

SUBMODULES=(app server testsuite)
git_() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }
heads() { local sm; for sm in "${SUBMODULES[@]}"; do echo "$sm $(git_ -C "$ROOT/$sm" rev-parse HEAD)"; done; }

# Start clean, so every change after the run is the agent's.
if [[ -n "$(git_ -C "$ROOT" status --porcelain)" ]]; then
  echo "lane.sh: commit or stash your changes first:" >&2
  git_ -C "$ROOT" status --short >&2
  exit 1
fi

state="$CACHE/$role"
mkdir -p "$state/target" "$state/cargo-home"
# A /path rule in a --settings file anchors at that file's directory, so the role
# templates hold placeholders that become absolute paths here.
sed -e "s|@ROOT@|$ROOT|g" -e "s|@CACHE@|$CACHE|g" "$ROOT/roles/$role.json" >"$state/settings.json"

extra=()
if [[ -n "${MYBUDGET_MODEL:-}" ]]; then extra+=(--model "$MYBUDGET_MODEL"); fi
# A role's effortLevel goes on the command line too, so it beats any per-model effort
# in the human's own settings. Without one, the session uses the human's default.
effort="$(jq -r '.effortLevel // empty' "$state/settings.json")"
if [[ -n "$effort" ]]; then extra+=(--effort "$effort"); fi

before="$(heads)"
status=0
(
  cd "$ROOT/$lane"
  CARGO_TARGET_DIR="$state/target" CARGO_HOME="$state/cargo-home" \
    claude -p "$prompt" \
      --settings "$state/settings.json" \
      --permission-mode dontAsk \
      --append-system-prompt-file "$ROOT/roles/$role.md" \
      --no-session-persistence \
      --output-format json \
      "${extra[@]}"
) >"$state/last-run.json" || status=$?

# last-output.md stays the agent's final message, so round.sh's QUESTION:/DISPUTE: check still works.
jq -r '.result // empty' "$state/last-run.json" >"$state/last-output.md" 2>/dev/null || true
cat "$state/last-output.md"

# One line per run in $CACHE/usage.jsonl, written before the lane checks so failed runs count too.
# scripts/usage.sh sums it by round (MYBUDGET_ROUND, set by round.sh) and role.
jq -c --arg round "${MYBUDGET_ROUND:-}" --arg role "$role" --arg effort "${effort:-default}" --argjson status "$status" '{
    time: (now | todate), round: $round, role: $role, effort: $effort, status: $status,
    turns: .num_turns, denials: (.permission_denials | length), minutes: (.duration_ms / 60000 | round), cost_usd: .total_cost_usd,
    input:       ([.modelUsage[].inputTokens] | add),
    output:      ([.modelUsage[].outputTokens] | add),
    cache_read:  ([.modelUsage[].cacheReadInputTokens] | add),
    cache_write: ([.modelUsage[].cacheCreationInputTokens] | add),
    models: .modelUsage }' "$state/last-run.json" >>"$CACHE/usage.jsonl" 2>/dev/null ||
  echo "lane.sh: no usage recorded for this run (claude produced no JSON result)" >&2
# Denied tool calls mean the role's settings block work it needs, as when a Claude Code
# update stopped auto-allowing sandboxed Bash. Make them visible in the round's log.
jq -r '.permission_denials // [] | select(length > 0) |
  "lane.sh: \(length) tool call(s) were denied:", (.[] | "  - \(.tool_name): \(.tool_input.command // .tool_input.file_path // "" | tostring | gsub("\n"; " ") | .[0:120])")' \
  "$state/last-run.json" >&2 2>/dev/null || true

problems=()
[[ "$(heads)" == "$before" ]] || problems+=("a submodule's HEAD moved (agents must not commit)")
for sm in "${SUBMODULES[@]}"; do
  [[ $sm == "$lane" ]] && continue
  [[ -z "$(git_ -C "$ROOT/$sm" status --porcelain)" ]] || problems+=("$sm/ changed")
done
[[ -z "$(git_ -C "$ROOT" status --porcelain --ignore-submodules=all)" ]] ||
  problems+=("files outside the submodules changed")
[[ "$(git_ -C "$ROOT/$lane" rev-parse --absolute-git-dir)" == "$ROOT/.git/modules/$lane" ]] ||
  problems+=("$lane/.git no longer points at .git/modules/$lane")
if (( ${#problems[@]} )); then
  echo "lane.sh: the $role left its lane. Nothing was committed; inspect before cleaning up:" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 4
fi
if (( status )); then
  echo "lane.sh: claude exited with status $status; nothing was committed" >&2
  exit "$status"
fi

if [[ -z "$(git_ -C "$ROOT/$lane" status --porcelain)" ]]; then
  echo "lane.sh: the $role made no changes"
  exit 0
fi
subject="$role: $(head -n 1 <<<"$prompt" | cut -c 1-60)"
git_ -C "$ROOT/$lane" add -A
git_ -C "$ROOT/$lane" commit -q -m "$subject"
git_ -C "$ROOT" add "$lane"
git_ -C "$ROOT" commit -q -m "$subject"
echo "lane.sh: committed $lane@$(git_ -C "$ROOT/$lane" rev-parse --short HEAD)"
