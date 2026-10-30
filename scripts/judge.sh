#!/usr/bin/env bash
# Build and test the *committed* server and test suite. This is the result that counts.
#
# Each step runs in its own macOS sandbox that can write only to that step's scratch
# directory, so code from either lane (build scripts, the server process, tests) can't
# rewrite sources, other steps' binaries, or the results.
#
# Exit status: 0 all tests pass, 1 some fail, 2 build or harness error.
# Results: $MYBUDGET_CACHE/judge/results/{summary.txt,*.log}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MYBUDGET_CACHE:-$HOME/.cache/mybudget}"
J="$CACHE/judge"
RES="$J/results"
TIMEOUT="${JUDGE_TIMEOUT:-900}"   # seconds per step

git_() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }

# Where hidden tests (source or compiled) might be readable. Denied to the
# visible-test run so the server can't copy hidden tests into the visible log.
HIDDEN=("$J/src/testsuite/hidden" "$J/run/hidden-build" "$ROOT/testsuite/hidden"
        "$ROOT/target" "$ROOT/.git/modules/testsuite" "$CACHE/tester" "$HOME/.claude/projects")

rm -rf "$J"
mkdir -p "$J/src/server" "$J/src/testsuite" "$RES"
for sm in server testsuite; do
  git_ -C "$ROOT/$sm" archive HEAD | tar -x -C "$J/src/$sm"
done

# Vendor every dependency up front. No lane code runs here: vendoring doesn't run build
# scripts. The sandboxed steps then build offline from these read-only copies.
cd "$J/src"
mkdir .cargo
if ! cargo vendor --locked --manifest-path server/Cargo.toml \
     --sync testsuite/Cargo.toml --sync testsuite/hidden/Cargo.toml \
     vendor >"$RES/vendor.config" 2>"$RES/vendor.log"; then
  echo "harness error: cargo vendor failed (see $RES/vendor.log)" | tee "$RES/summary.txt"
  exit 2
fi
mv "$RES/vendor.config" .cargo/config.toml

# in_sandbox <step> <deny-hidden 0|1> <command...>
# Runs the command with writes limited to $J/run/<step>, cwd $J/src, a fresh CARGO_HOME
# and TMPDIR, and a timeout.
in_sandbox() {
  local step="$1" deny_hidden="$2"; shift 2
  local w="$J/run/$step" p
  mkdir -p "$w/tmp" "$w/cargo-home"
  local profile='(version 1)
(allow default)
(deny file-write*)
(allow file-write* (subpath "'"$w"'") (literal "/dev/null") (literal "/dev/zero")
  (literal "/dev/dtracehelper") (regex #"^/dev/tty") (regex #"^/dev/fd/"))'
  if (( deny_hidden )); then
    for p in "${HIDDEN[@]}"; do profile+=$'\n''(deny file-read* (subpath "'"$p"'"))'; done
  fi
  env TMPDIR="$w/tmp" CARGO_HOME="$w/cargo-home" CARGO_TARGET_DIR="$w/target" \
      MYBUDGET_SERVER_BIN="$J/run/server-build/target/debug/mybudget-server" \
      sandbox-exec -p "$profile" \
      perl -e 'alarm shift; exec @ARGV or die "exec $ARGV[0]: $!\n"' "$TIMEOUT" "$@"
}

# build_tests <suite> <manifest>: compile one suite's test binaries, listing them in <suite>.bins
build_tests() {
  in_sandbox "$1-build" 0 cargo test --locked --offline --no-run --message-format=json \
      --manifest-path "$2" >"$RES/$1-build.json" 2>"$RES/$1-build.log" || return 1
  jq -r 'select(.reason == "compiler-artifact" and .profile.test) | .executable' \
      "$RES/$1-build.json" >"$RES/$1.bins"
}

# run_tests <suite> <deny-hidden>: run each test binary; append "<passed> <failed>" to <suite>.counts
run_tests() {
  local suite="$1" deny_hidden="$2" bin out rc
  : >"$RES/$suite.log"
  : >"$RES/$suite.counts"
  while read -r bin; do
    rc=0
    out="$(cd "$J/src/testsuite" && in_sandbox "$suite-run" "$deny_hidden" "$bin" 2>&1)" || rc=$?
    printf '== %s\n%s\n' "$(basename "$bin")" "$out" >>"$RES/$suite.log"
    if grep -q '^test result: ' <<<"$out"; then
      sed -nE 's/^test result: [A-Za-z]+\. ([0-9]+) passed; ([0-9]+) failed.*/\1 \2/p' <<<"$out" >>"$RES/$suite.counts"
    elif (( rc != 0 )); then
      echo "0 1" >>"$RES/$suite.counts"   # crashed or timed out before reporting
    fi
  done <"$RES/$suite.bins"
}

counts() { awk '{p += $1; f += $2} END {printf "%d passed, %d failed", p, f}' "$RES/$1.counts"; }
failed() { awk '{f += $2} END {exit !(f > 0)}' "$RES/$1.counts"; }

if ! in_sandbox server-build 0 cargo build --locked --offline --manifest-path server/Cargo.toml \
     >"$RES/server-build.log" 2>&1; then
  echo "server build: FAILED (see $RES/server-build.log)" | tee "$RES/summary.txt"
  exit 2
fi
for suite in visible hidden; do
  manifest=testsuite/Cargo.toml
  [[ $suite == hidden ]] && manifest=testsuite/hidden/Cargo.toml
  if ! build_tests "$suite" "$manifest"; then
    echo "$suite test build: FAILED (see $RES/$suite-build.log)" | tee "$RES/summary.txt"
    exit 2
  fi
done

run_tests visible 1
run_tests hidden 0
{
  echo "server build: ok"
  echo "visible tests: $(counts visible)"
  echo "hidden tests: $(counts hidden)"
} | tee "$RES/summary.txt"

if failed visible || failed hidden; then exit 1; fi
