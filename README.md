# MyBudget

| Path | Repo | What |
| --- | --- | --- |
| `server/` | `mybudget-server` | Rust HTTP API (axum) |
| `app/` | `mybudget-app` | Native macOS client (Swift 6, SwiftUI), which bundles and runs the server; see `app/README.md` |
| `testsuite/` | `mybudget-testsuite` | Rust tests that run the server as a subprocess |
| `spec/SPEC.md` | this repo | The contract both agents work from |
| `roles/` | this repo | Agent prompts and per-role Claude Code settings |
| `scripts/` | this repo | Test runner, lane runner, judge, round loop |

## The app

`app/` is a native macOS app (Swift 6, SwiftUI, no dependencies). Its build compiles `server/` with cargo into the app bundle. At launch the app starts that server on a free port (SPEC 1.2, 1.3) and talks to it over the same HTTP API a web client would use. The app is outside the adversarial loop: neither agent can read or write it. It relies only on what `SPEC.md` promises, so a server change the spec allows can't break it. When the app needs something new from the server, add a clause for a round to build, as with 1.4. `app/README.md` covers the stack, building and testing.

## How the agents are kept apart

`scripts/lane.sh <role> "<prompt>"` runs `claude -p` with the role's prompt and settings:

1. **Lane = working directory.** The session starts in `testsuite/` (tester) or `server/` (implementer). Claude Code's sandbox only lets Bash, and everything Bash starts, write inside the working directory, plus the role's own cargo cache in `~/.cache/mybudget/<role>/`. `allowUnsandboxedCommands: false` removes the escape hatch, and `dontAsk` mode denies anything not explicitly allowed.
2. **The implementer can't see any tests.** It can't read `testsuite/`, the test suite's git objects, the tester's cache or Claude transcripts. After each of its runs, the judge tells it whether the server builds, whether it starts up (SPEC 1), and how many tests fail for each spec clause. It never sees test names, inputs or failure output.
3. **Commits are checked.** Agents can't commit; their git directories are outside their lane. After each run `lane.sh` checks that nothing outside the lane changed, then commits the lane itself.
4. **The judge.** `scripts/judge.sh` exports the committed code, vendors dependencies, then builds and runs each step under `sandbox-exec`. Each step can write only to its own scratch folder, so build scripts, the server and the tests can't change sources, other steps' binaries or the results. The steps that run only server code can't read the tests either, so their output is safe to pass to the implementer. Each test runs on its own, in a fresh scratch folder, and its exit status decides pass or fail.

## Writing the spec

The scripts depend on two rules, also stated at the top of `spec/SPEC.md`:

- A requirement is a line starting with its number, such as `2.1 `. Each test's name starts with the clause it checks (`spec_2_1_...`). `scripts/test.sh` and the judge reject any test that doesn't follow this, or that cites a clause the spec doesn't have.
- An example under a requirement is part of it. The implementer never sees a test, so examples are how it learns exact formats: field names, status codes, numbers versus strings. Give every endpoint at least one.

## Running a round

```sh
scripts/round.sh "SPEC section 2 (health)"
```

The tester writes tests, then the implementer runs until the judge is green (up to `MAX_FIXES` runs, default 5). Then the tester tries to break the implementation. This repeats until an attack finds nothing new or `MAX_ATTACKS` (default 2) is reached.

The round stops for you when an agent ends its final message with a `DISPUTE:` or `QUESTION:` line. A dispute names a clause. To review it, find that clause's tests (`grep -rn spec_3_2_ testsuite/tests`) and their output in `~/.cache/mybudget/judge/results/tests.log`. Then fix the tests or clarify the spec, commit, and rerun the round with a task that says what changed.

The working tree must be clean before each agent run. Each agent's last message is saved in `~/.cache/mybudget/<role>/last-output.md`.

## Remotes

The submodule URLs are relative (`../mybudget-server.git` and so on), so they resolve next to wherever this repo is pushed. Create the four repos on your host, then add the remotes and push each submodule before the superproject.

## Known limits

- The lanes rely on Claude Code's sandbox (macOS Seatbelt) and the judge relies on `sandbox-exec`. Both are macOS-only as configured here.
- Hiding the tests is best effort. The read-deny lists cover the places copies are known to end up. If you copy tests anywhere else, add that path to `roles/implementer.json` and to `TESTS` in `scripts/judge.sh`.
- Nothing here stops an implementation that detects test conditions at runtime. Hidden tests make that hard, and reading the implementer's diffs is the backstop.
