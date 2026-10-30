#!/usr/bin/env bash
# Build the server, then run the test suite against it.
# Usage: scripts/test.sh [--hidden] [cargo test args...]
#   --hidden  also run testsuite/hidden (the implementer can't read it, so this fails for them)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"

hidden=0
if [[ "${1:-}" == --hidden ]]; then hidden=1; shift; fi

cargo build --locked --manifest-path "$ROOT/server/Cargo.toml"
export MYBUDGET_SERVER_BIN="$CARGO_TARGET_DIR/debug/mybudget-server"

cargo test --locked --manifest-path "$ROOT/testsuite/Cargo.toml" "$@"
if (( hidden )); then
  cargo test --locked --manifest-path "$ROOT/testsuite/hidden/Cargo.toml" "$@"
fi
