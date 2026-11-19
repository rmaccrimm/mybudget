#!/usr/bin/env bash
# Build and test the *committed* server and test suite. This is the result that counts.
#
# Each step runs in its own macOS sandbox that can write only to that step's scratch
# directory, so code from either lane (build scripts, the server, the tests) can't
# rewrite sources, other steps' binaries or the results. Steps that run only server code
# can't read the tests either, so what they print is safe to show the implementer.
# Sandboxed code can't connect to anything but loopback (builds are offline; only the
# unsandboxed vendoring step uses the network). Seatbelt can't stop a socket bound to
# 0.0.0.0 from accepting connections from the LAN, so inbound isn't fully closed.
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
# Tests (and test listings) run at once. One per performance core: with one per core
# (8 here), the plan-file startup tests ran past the suite's 10s startup timeout.
JOBS="${JUDGE_JOBS:-$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu)}"
SERVER_BIN="$J/run/server-build/target/debug/mybudget-server"
source "$ROOT/scripts/suite-rules.sh"

git_() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }

# Everywhere the tests, or anything built from them, can be read.
TESTS=("$J/src/testsuite" "$J/run/tests" "$RES" "$J/deps/tests" "$ROOT/testsuite"
       "$ROOT/target" "$ROOT/.git/modules/testsuite" "$CACHE/tester" "$HOME/.claude/projects")

# sandbox_cmd <step> <hide-tests 0|1> <timeout>: sets CMD to a command prefix that runs
# with writes limited to $J/run/<step>, network limited to loopback, a fresh CARGO_HOME
# and TMPDIR, and a timeout. With hide-tests=1 the command also can't read anything in
# TESTS. (An "allow network* (local ip ...)" rule would let outbound connections to any
# host through, so outbound is allowed only by remote address.)
sandbox_cmd() {
  local w="$J/run/$1" hide_tests="$2" limit="$3" p profile
  mkdir -p "$w/tmp" "$w/cargo-home"
  profile='(version 1)
(allow default)
(deny file-write*)
(allow file-write* (subpath "'"$w"'") (literal "/dev/null") (literal "/dev/zero")
  (literal "/dev/dtracehelper") (regex #"^/dev/tty") (regex #"^/dev/fd/"))
(deny network*)
(allow network-bind network-inbound (local ip "localhost:*"))
(allow network-outbound (remote ip "localhost:*"))'
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

# with_deps <name> <work dir> <step> <hide-tests 0|1> <src dir> <cargo command...>
# Most of a build is the dependencies, which change only with Cargo.toml, Cargo.lock or
# the toolchain. So the build in <step> starts from a copy of a target directory in which
# only the dependencies were built: from <src dir>'s manifest and lockfile, with every
# source file replaced by an empty stub, so no lane code ran there. $J/deps/<name> holds
# that directory and is written only from such builds; lane code writes only its clone.
# Prints how the dependencies were prepared. Any problem means an ordinary clean build.
DEPS_VERSION=1
with_deps() {
  local name="$1" work="$2" step="$3" hide="$4" src="$5"; shift 5
  local target="$J/run/$step/target" cache="$J/deps/$name" root pkg key kind path rel
  mkdir -p "$work/src"
  # Which source files the package has. Path dependencies would be lane code, so a
  # package with any (it has none) isn't cached.
  in_sandbox "$step" "$hide" "$STEP_TIMEOUT" cargo metadata --locked --offline \
      --format-version 1 --manifest-path "$src/Cargo.toml" \
      >"$work/metadata.json" 2>"$work/metadata.log" || { echo "not cached (cargo metadata failed)"; return 0; }
  root="$(jq -r '.resolve.root' "$work/metadata.json")"
  [[ "$(jq '[.packages[] | select(.source == null)] | length' "$work/metadata.json")" == 1 ]] ||
    { echo "not cached (path dependencies)"; return 0; }
  cp "$src/Cargo.toml" "$src/Cargo.lock" "$work/src/"
  jq -r --arg root "$root" '.packages[] | select(.id == $root) | .targets[]
      | [(.kind | join(",")), .src_path] | @tsv' "$work/metadata.json" >"$work/targets"
  while IFS=$'\t' read -r kind path; do
    rel="${path#"$src"/}"
    [[ $rel != /* && $rel != *..* ]] || { echo "not cached (a target outside the package)"; return 0; }
    mkdir -p "$work/src/$(dirname "$rel")"
    case ",$kind," in
      *,bin,* | *,test,* | *,bench,* | *,example,* | *,custom-build,*) echo 'fn main() {}' ;;
      *) : ;;
    esac >"$work/src/$rel"
  done <"$work/targets"

  key="$( { echo "$DEPS_VERSION"; printf '%s\n' "$@"; rustc -vV; cargo -V
            cd "$work/src" && find . -type f | LC_ALL=C sort | xargs shasum -a 256
          } | shasum -a 256 | cut -d' ' -f1)"
  rm -rf "$target"
  if [[ -f $cache/key && "$(cat "$cache/key")" == "$key" ]]; then
    cp -cR "$cache/target" "$target" ||
      { rm -rf "$target"; echo "not cached (copying the cache failed)"; return 0; }
    echo "cached"
    return 0
  fi
  # Cargo identifies a path package relative to its workspace, so the stub package and
  # the real one share artifacts, and the stubs are newer than the real sources. Its own
  # artifacts are cleaned out, or the real build would take the stubs' as up to date.
  pkg="$(jq -r --arg root "$root" '.packages[] | select(.id == $root) | .name' \
    "$work/metadata.json")"
  if in_sandbox "$step" "$hide" "$STEP_TIMEOUT" "$@" --manifest-path "$work/src/Cargo.toml" \
      >"$work/build.log" 2>&1 &&
    in_sandbox "$step" "$hide" "$STEP_TIMEOUT" cargo clean --locked --offline -p "$pkg" \
      --manifest-path "$work/src/Cargo.toml" >>"$work/build.log" 2>&1 &&
    [[ -z "$(find "$target" -path "*/.fingerprint/$pkg-*" -print -quit)" ]]; then
    rm -rf "$cache"
    mkdir -p "$cache"
    if cp -cR "$target" "$cache/target"; then
      echo "$key" >"$cache/key"   # written last: a cache without it is never used
      echo "built and cached"
    else
      rm -rf "$cache"
      echo "built, but saving the cache failed"
    fi
  else
    rm -rf "$target"
    echo "not cached (building or cleaning the stubs failed; see $work/build.log)"
  fi
}

# Start from nothing but the dependency caches.
mkdir -p "$J"
find "$J" -mindepth 1 -maxdepth 1 ! -name deps -exec rm -rf {} +
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
# Vendoring rewrites every file. A fixed old mtime keeps dependency build scripts that
# watch their sources (rerun-if-changed) from rerunning on every judge.
find vendor -exec touch -h -t 200001010000 {} +

echo "server dependencies: $(with_deps server "$J/run/deps-server" server-build 1 \
    "$J/src/server" cargo build --locked --offline)" >>"$RES/deps.log"
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

echo "test suite dependencies: $(with_deps tests "$J/run/tests/deps" tests/build 0 \
    "$J/src/testsuite" cargo test --locked --offline --no-run --tests)" >>"$RES/deps.log"
in_sandbox tests/build 0 "$STEP_TIMEOUT" cargo test --locked --offline --no-run --tests \
    --message-format=json --manifest-path testsuite/Cargo.toml \
    >"$J/run/tests/build.json" 2>"$RES/tests-build.log" ||
  finish 2 "server build: ok" "startup: ok" "test suite build: FAILED (see tests-build.log)"
# Integration tests (tests/*.rs) only; the harness's own unit tests don't count.
jq -r 'select(.reason == "compiler-artifact" and .profile.test and .target.kind == ["test"])
       | .executable' "$J/run/tests/build.json" >"$J/run/tests/bins"

# throttle: waits until fewer than JOBS background jobs are running.
throttle() {
  while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n || true; done
}

# Jobs write their output to $OUT, which no sandbox can write to. The shell, not the
# sandboxed command, opens those files and records each exit status.
OUT="$J/run/tests/out"
mkdir -p "$OUT/list" "$OUT/run"

cd "$J/src/testsuite"
k=0
while IFS= read -r bin; do
  k=$(( k + 1 ))
  throttle
  ( rc=0
    in_sandbox "tests/list/$k" 0 "$TEST_TIMEOUT" "$bin" --list --format terse </dev/null \
        >"$OUT/list/$k.out" 2>"$OUT/list/$k.err" || rc=$?
    echo "$rc" >"$OUT/list/$k.rc" ) &
done <"$J/run/tests/bins"
wait

: >"$J/run/tests/names"   # "<binary>\t<test name>" per test
k=0
while IFS= read -r bin; do
  k=$(( k + 1 ))
  cat "$OUT/list/$k.err" >>"$RES/tests-list.log" 2>/dev/null || true
  [[ "$(cat "$OUT/list/$k.rc" 2>/dev/null)" == 0 ]] ||
    finish 2 "server build: ok" "startup: ok" \
      "test suite: listing $(basename "$bin") failed (see tests-list.log)"
  awk -v bin="$bin" 'sub(/: test$/, "") { print bin "\t" $0 }' "$OUT/list/$k.out" \
    >>"$J/run/tests/names"
done <"$J/run/tests/bins"

problems="$(cut -f2 "$J/run/tests/names" | naming_problems "$J/spec.md")"
[[ -z $problems ]] ||
  finish 2 "server build: ok" "startup: ok" "test suite: these tests break the naming rule:" \
    "$problems"

# Each test runs in its own process and sandbox, with its own scratch directory so
# servers can't pass state from one test to another; up to JOBS run at once. Its exit
# status, not its output, decides pass or fail.
i=0
while IFS=$'\t' read -r bin name; do
  i=$(( i + 1 ))
  throttle
  ( rc=0
    in_sandbox "tests/run/$i" 0 "$TEST_TIMEOUT" "$bin" --exact "$name" \
        --include-ignored --test-threads 1 </dev/null >"$OUT/run/$i.out" 2>&1 || rc=$?
    echo "$rc" >"$OUT/run/$i.rc" ) &
done <"$J/run/tests/names"
wait

# Collect the results in the listed order, so tests.log reads the same on every run.
: >"$RES/tests.log"
: >"$J/run/tests/results"   # "<clause>\t<pass|fail>" per test
i=0
while IFS=$'\t' read -r bin name; do
  i=$(( i + 1 ))
  result=pass
  [[ "$(cat "$OUT/run/$i.rc" 2>/dev/null)" == 0 ]] || result=fail
  printf '%s\t%s\n' "$(clause_of "$name")" "$result" >>"$J/run/tests/results"
  printf '== %s %s\n' "$result" "$name" >>"$RES/tests.log"
  [[ $result == pass ]] || { cat "$OUT/run/$i.out"; echo; } >>"$RES/tests.log"
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
