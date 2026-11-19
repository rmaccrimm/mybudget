#!/usr/bin/env bash
# Build and test the *committed* server and test suite. This is the result that counts.
#
# Each step runs in its own macOS sandbox that can write only to that step's scratch
# directory, so code from either lane (build scripts, the server, the tests) can't
# rewrite sources, other steps' binaries or the results. Steps that run only server code
# can't read the tests either, so what they print is safe to show the implementer.
#
# Exit status:
#   0  every test passes
#   1  the server fails (build, startup or tests); summary.txt is the implementer's feedback
#   2  the test suite or the harness is broken, and a human needs to look
# Results in $MYBUDGET_CACHE/judge/results: summary.txt (failures by clause, safe for
# the implementer) and tests.log (every test's result, with output for failures).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${MYBUDGET_CACHE:-$HOME/.cache/mybudget}"
J="$CACHE/judge"
RES="$J/results"
STEP_TIMEOUT="${JUDGE_STEP_TIMEOUT:-900}"  # seconds per build step
TEST_TIMEOUT="${JUDGE_TEST_TIMEOUT:-60}"   # seconds per test
SERVER_BIN="$J/run/server-build/target/debug/mybudget-server"
source "$ROOT/scripts/suite-rules.sh"

git_() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }

# Everywhere the tests, or anything built from them, can be read.
TESTS=("$J/src/testsuite" "$J/run/tests" "$RES" "$ROOT/testsuite" "$ROOT/target"
       "$ROOT/.git/modules/testsuite" "$CACHE/tester" "$HOME/.claude/projects")

# sandbox_cmd <step> <hide-tests 0|1> <timeout>: sets CMD to a command prefix that runs
# with writes limited to $J/run/<step>, a fresh CARGO_HOME and TMPDIR, and a timeout.
# With hide-tests=1 the command also can't read anything in TESTS.
sandbox_cmd() {
  local w="$J/run/$1" hide_tests="$2" limit="$3" p profile
  mkdir -p "$w/tmp" "$w/cargo-home"
  profile='(version 1)
(allow default)
(deny file-write*)
(allow file-write* (subpath "'"$w"'") (literal "/dev/null") (literal "/dev/zero")
  (literal "/dev/dtracehelper") (regex #"^/dev/tty") (regex #"^/dev/fd/"))'
  if (( hide_tests )); then
    for p in "${TESTS[@]}"; do profile+=$'\n''(deny file-read* (subpath "'"$p"'"))'; done
  fi
  CMD=(env TMPDIR="$w/tmp" CARGO_HOME="$w/cargo-home" CARGO_TARGET_DIR="$w/target"
       MYBUDGET_SERVER_BIN="$SERVER_BIN" sandbox-exec -p "$profile"
       perl -e 'alarm shift; exec @ARGV or die "exec $ARGV[0]: $!\n"' "$limit")
}

# in_sandbox <step> <hide-tests 0|1> <timeout> <command...>
in_sandbox() {
  sandbox_cmd "$1" "$2" "$3"
  shift 3
  "${CMD[@]}" "$@"
}

# finish <exit status> <summary line...>: writes summary.txt, prints it, and exits.
finish() {
  local status="$1"
  shift
  printf '%s\n' "$@" >"$RES/summary.txt"
  cat "$RES/summary.txt"
  echo "(details in $RES)"
  exit "$status"
}

# startup_problem: checks SPEC 1.3 directly, so a startup mistake is reported as one
# instead of as every test failing. Prints the problem, or nothing if startup works.
startup_problem() {
  local fifo="$J/run/startup.fifo" line="" pid fd
  sandbox_cmd startup 1 30
  mkfifo "$fifo"
  "${CMD[@]}" env MYBUDGET_ADDR=127.0.0.1:0 "$SERVER_BIN" \
    >"$fifo" 2>"$RES/startup.log" </dev/null &
  pid=$!
  exec {fd}<"$fifo"
  IFS= read -r -t 10 -u "$fd" line || true
  if [[ -z $line ]]; then
    echo "SPEC 1.3: the server printed nothing on stdout within 10s"
  elif ! [[ $line =~ ^listening\ on\ 127\.0\.0\.1:([1-9][0-9]*)$ ]]; then
    echo "SPEC 1.3: its first line was \"${line:0:200}\", not \"listening on 127.0.0.1:<port>\""
  elif ! (exec 3<>"/dev/tcp/127.0.0.1/${BASH_REMATCH[1]}") 2>/dev/null; then
    echo "SPEC 1.3: nothing accepts connections on port ${BASH_REMATCH[1]}"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  exec {fd}<&-
}

rm -rf "$J"
mkdir -p "$J/src/server" "$J/src/testsuite" "$J/run/tests" "$RES"
for sm in server testsuite; do
  git_ -C "$ROOT/$sm" archive HEAD | tar -x -C "$J/src/$sm"
done
git_ -C "$ROOT" show HEAD:spec/SPEC.md >"$J/spec.md"

# A migration a finished round shipped never changes (roles/implementer.md):
# spec/migrations.sha256 lists each one's checksum, recorded when its round completed.
if git_ -C "$ROOT" cat-file -e HEAD:spec/migrations.sha256 2>/dev/null; then
  git_ -C "$ROOT" show HEAD:spec/migrations.sha256 >"$J/migrations.sha256"
  if ! changed="$(cd "$J/src/server" && shasum -a 256 -c --quiet "$J/migrations.sha256" 2>&1)"; then
    finish 1 "migrations: a migration from an earlier round changed or is missing" "" "$changed"
  fi
fi

# Vendor every dependency up front. No lane code runs here (vendoring doesn't run build
# scripts); the sandboxed steps then build offline from these read-only copies.
cd "$J/src"
mkdir .cargo
cargo vendor --locked --manifest-path server/Cargo.toml --sync testsuite/Cargo.toml \
    vendor >"$RES/vendor.config" 2>"$RES/vendor.log" ||
  finish 2 "harness: cargo vendor failed (see vendor.log)"
mv "$RES/vendor.config" .cargo/config.toml

in_sandbox server-build 1 "$STEP_TIMEOUT" cargo build --locked --offline \
    --manifest-path server/Cargo.toml >"$RES/server-build.log" 2>&1 ||
  finish 1 "server build: FAILED" "" "$(grep -v '^ *Compiling ' "$RES/server-build.log" | tail -n 40)"

problem="$(startup_problem)"
if [[ -n $problem ]]; then
  summary=("server build: ok" "startup: FAILED" "$problem")
  if [[ -s $RES/startup.log ]]; then
    summary+=("" "server stderr (last 20 lines):" "$(tail -n 20 "$RES/startup.log")")
  fi
  finish 1 "${summary[@]}"
fi

in_sandbox tests/build 0 "$STEP_TIMEOUT" cargo test --locked --offline --no-run --tests \
    --message-format=json --manifest-path testsuite/Cargo.toml \
    >"$J/run/tests/build.json" 2>"$RES/tests-build.log" ||
  finish 2 "server build: ok" "startup: ok" "test suite build: FAILED (see tests-build.log)"
# Integration tests (tests/*.rs) only; the harness's own unit tests don't count.
jq -r 'select(.reason == "compiler-artifact" and .profile.test and .target.kind == ["test"])
       | .executable' "$J/run/tests/build.json" >"$J/run/tests/bins"

cd "$J/src/testsuite"
: >"$J/run/tests/names"   # "<binary>\t<test name>" per test
while IFS= read -r bin; do
  in_sandbox tests/list 0 "$TEST_TIMEOUT" "$bin" --list --format terse </dev/null \
      >"$J/run/tests/list.out" 2>>"$RES/tests-list.log" ||
    finish 2 "server build: ok" "startup: ok" \
      "test suite: listing $(basename "$bin") failed (see tests-list.log)"
  awk -v bin="$bin" 'sub(/: test$/, "") { print bin "\t" $0 }' "$J/run/tests/list.out" \
    >>"$J/run/tests/names"
done <"$J/run/tests/bins"

problems="$(cut -f2 "$J/run/tests/names" | naming_problems "$J/spec.md")"
[[ -z $problems ]] ||
  finish 2 "server build: ok" "startup: ok" "test suite: these tests break the naming rule:" \
    "$problems"

# Each test runs alone, with its own scratch directory so servers can't pass state from
# one test to the next. Its exit status, not its output, decides pass or fail.
: >"$RES/tests.log"
: >"$J/run/tests/results"   # "<clause>\t<pass|fail>" per test
i=0
while IFS=$'\t' read -r bin name; do
  i=$(( i + 1 ))
  rc=0
  out="$(in_sandbox "tests/run/$i" 0 "$TEST_TIMEOUT" "$bin" --exact "$name" \
           --include-ignored --test-threads 1 </dev/null 2>&1)" || rc=$?
  result=pass
  (( rc == 0 )) || result=fail
  printf '%s\t%s\n' "$(clause_of "$name")" "$result" >>"$J/run/tests/results"
  printf '== %s %s\n' "$result" "$name" >>"$RES/tests.log"
  [[ $result == pass ]] || printf '%s\n\n' "$out" >>"$RES/tests.log"
done <"$J/run/tests/names"

read -r passed failed < <(awk -F'\t' '{ if ($2 == "pass") p++; else f++ }
  END { print p + 0, f + 0 }' "$J/run/tests/results")
summary=("server build: ok" "startup: ok" "tests: $passed passed, $failed failed")
if (( failed )); then
  summary+=("failing clauses:")
  mapfile -t -O "${#summary[@]}" summary < <(awk -F'\t' '
      { n[$1]++; if ($2 == "fail") f[$1]++ }
      END { for (c in f) printf "%s\t  SPEC %s: %d of %d tests fail\n", c, c, f[c], n[c] }' \
    "$J/run/tests/results" | sort -V | cut -f2-)
  finish 1 "${summary[@]}"
fi
finish 0 "${summary[@]}"
