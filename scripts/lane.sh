#!/usr/bin/env bash
# Run one headless Claude session confined to a lane, check it stayed in its lane,
# then commit its work.
#   tester       works in testsuite/ and can't write anywhere else
#   implementer  works in server/, can't write anywhere else, can't read the hidden tests
# Enforcement comes from the role's settings (roles/<role>.json): the session starts in
# the lane's directory with Claude Code's OS-level sandbox on, so Bash and everything it
# runs can write only there.
#
# Usage: scripts/lane.sh <tester|implementer> "<prompt>"
# The session's final message is saved to $MYBUDGET_CACHE/<role>/last-output.md.
# Set MYBUDGET_MODEL to choose the model.
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
      "${extra[@]}"
) | tee "$state/last-output.md" || status=$?

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
