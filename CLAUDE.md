# MyBudget

A macOS SwiftUI app (`app/`) backed by a Rust HTTP server (`server/`), so a web client can reuse the server later. `testsuite/` is a separate Rust crate that starts the server as a subprocess and tests it over HTTP. All three are git submodules.

## Adversarial development

Server work goes through two agents, each run by `scripts/lane.sh` in its own sandbox:

- **tester**: writes tests in `testsuite/` from `spec/SPEC.md`. Can't write anywhere else.
- **implementer**: writes `server/`. Can't write anywhere else or read `testsuite/hidden/`.

`spec/SPEC.md` is the contract. `spec/`, `roles/`, `scripts/` and the app are edited by humans only. `scripts/judge.sh` builds and tests the committed code in a macOS sandbox, and its result is the one that counts.

## Commands

- `scripts/test.sh`: build the server and run the visible tests. Add `--hidden` for the hidden ones too.
- `scripts/judge.sh`: the authoritative run.
- `scripts/round.sh "<task>"`: tester → implementer → tester attack, repeated until green.
