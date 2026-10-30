# MyBudget

| Path | Repo | What |
| --- | --- | --- |
| `server/` | `mybudget-server` | Rust HTTP API (axum) |
| `app/` | `mybudget-app` | macOS SwiftUI client (not created yet; see `app/README.md`) |
| `testsuite/` | `mybudget-testsuite` | Rust tests that run the server as a subprocess |
| `spec/SPEC.md` | this repo | The contract both agents work from |
| `roles/` | this repo | Agent prompts and per-role Claude Code settings |
| `scripts/` | this repo | Test runner, lane runner, judge, round loop |

## How the agents are kept apart

`scripts/lane.sh <role> "<prompt>"` runs `claude -p` with the role's prompt and settings:

1. **Lane = working directory.** The session starts in `testsuite/` (tester) or `server/` (implementer). Claude Code's sandbox only lets Bash, and everything Bash starts, write inside the working directory, plus the role's own cargo cache in `~/.cache/mybudget/<role>/`. `allowUnsandboxedCommands: false` removes the escape hatch, and `dontAsk` mode denies anything not explicitly allowed.
2. **Hidden tests.** The implementer can't read `testsuite/hidden/`, the testsuite's git objects, the tester's cache or Claude transcripts. It only learns how many hidden tests fail.
3. **Commits are checked.** Agents can't commit; their git directories are outside their lane. After each run `lane.sh` checks that nothing outside the lane changed, then commits the lane itself.
4. **The judge.** `scripts/judge.sh` exports the committed code, vendors dependencies, then builds and runs each step under `sandbox-exec`. Each step can write only to its own scratch folder, so build scripts, the server process and tests can't change sources, other steps' binaries or the results. The tests run the server as a separate process, so server code never runs inside the test process.

## Running a round

```sh
scripts/round.sh "SPEC section 2 (health)"
```

The tester writes tests, the implementer runs until the judge is green, then the tester tries to break the implementation. This repeats until an attack finds nothing new or `MAX_ATTACKS` (default 2) is reached. If an agent ends its final message with a `DISPUTE:` or `QUESTION:` line, the round stops so you can decide, usually by editing `spec/SPEC.md`.

The working tree must be clean before each agent run. Results: `~/.cache/mybudget/judge/results/`. Each agent's last message: `~/.cache/mybudget/<role>/last-output.md`.

## Remotes

The submodule URLs are relative (`../mybudget-server.git` and so on), so they resolve next to wherever this repo is pushed. Create the four repos on your host, then add the remotes and push each submodule before the superproject.

## Known limits

- The lanes rely on Claude Code's sandbox (macOS Seatbelt) and the judge relies on `sandbox-exec`. Both are macOS-only as configured here.
- Hiding the hidden tests is best effort. The read-deny lists cover the places copies are known to end up. If you copy hidden tests anywhere else, add that path to `roles/implementer.json` and to `HIDDEN` in `scripts/judge.sh`.
- Nothing here stops an implementation that detects test conditions at runtime. Hidden tests are the main defense, and reading the implementer's diffs is the backstop.
