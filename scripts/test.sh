#!/usr/bin/env bash
# Build the server, then run the test suite against it. For the tester and for humans:
# the implementer can't read testsuite/, so this fails for it.
# Usage: scripts/test.sh [cargo test args...]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUITE="$ROOT/testsuite/Cargo.toml"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
source "$ROOT/scripts/suite-rules.sh"

cargo build --locked --manifest-path "$ROOT/server/Cargo.toml"
export MYBUDGET_SERVER_BIN="$CARGO_TARGET_DIR/debug/mybudget-server"

# The judge rejects the whole suite if any test breaks the naming rule, so check first.
if [[ -n "$(find "$ROOT/testsuite/tests" -name '*.rs' 2>/dev/null)" ]]; then
  problems="$(cargo test -q --locked --manifest-path "$SUITE" --test '*' -- --list --format terse |
    sed -n 's/: test$//p' | naming_problems "$ROOT/spec/SPEC.md")"
  if [[ -n $problems ]]; then
    printf 'These tests break the naming rule (see scripts/suite-rules.sh):\n%s\n' "$problems" >&2
    exit 1
  fi
fi

cargo test --locked --manifest-path "$SUITE" "$@"
