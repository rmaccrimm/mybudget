# MyBudget

A macOS SwiftUI app (`app/`) backed by a Rust HTTP server (`server/`), so a web client can reuse the server later. `testsuite/` is a separate Rust crate that starts the server as a subprocess and tests it over HTTP. All three are git submodules.

## Adversarial development

Server work goes through two agents, each run by `scripts/lane.sh` in its own sandbox:

- **tester**: writes tests in `testsuite/` from `spec/SPEC.md`. Can't write anywhere else.
- **implementer**: writes `server/`. Can't write anywhere else, and can't read `testsuite/` at all. It only learns which spec clauses fail.

`spec/SPEC.md` is the contract. `spec/` is edited by humans or by the session running the rounds, never by the tester or implementer. `roles/`, `scripts/` and the app are edited by humans only. `scripts/judge.sh` builds and tests the committed code in a macOS sandbox, and its result is the one that counts.

Each test in `testsuite/tests/` is named after the clause it checks: `spec_3_2_...` checks SPEC 3.2.

## Commands

- `scripts/test.sh`: build the server and run the test suite (not available to the implementer).
- `scripts/judge.sh`: the authoritative run.
- `scripts/round.sh "<task>"`: tester → implementer → tester attack, repeated until green.

## Resuming the work

`spec/ROADMAP.md` has where the YNAB-style spec stands, how to run and settle rounds, the plan for the remaining rounds, and the draft text of the sections not yet in `SPEC.md`. Start there.
