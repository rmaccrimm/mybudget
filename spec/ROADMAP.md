# Roadmap: the remaining rounds

This is for the agent that resumes the work. The goal is a server that replicates YNAB's core budgeting, specified in `SPEC.md` and built one round at a time by the tester and implementer (see `README.md` for how rounds work). The sections were drafted together from research into YNAB; this file holds the plan for the rounds still to run, the rules for running them, and the draft text of the sections not yet in `SPEC.md`.

## Where things stand (2026-11-19)

- Work is on the superproject branch `ynab-spec`, which the human hasn't merged into `main` yet. `lane.sh` commits inside the submodules on their own `main` branches. Don't push, or merge into `main`, without asking the human.
- **Round 1 (sections 3 and 4) is complete.** The judge passed 103 of 103 tests at superproject commit `9911cc4` (testsuite `254acec`, server `7dd56c5`).
- **Round 2 (sections 5 to 7) is complete.** The judge passed 333 of 333 tests at superproject commit `a565335` (testsuite `c105a26`, server `ff57440`). It took three runs: one tester question (the 3.6/5.2 ruling below), one implementer run that passed every test at once, and one rerun after a usage limit cut the first attack off. The implementer replaced serde_json with its own parser (`server/src/json.rs`) to tell `-0` from `-0.0`.
- **Round 3 (sections 8 to 10) is complete.** The judge passed 563 of 563 tests at superproject commit `7c2b566` (testsuite `efa5c08`, server `4d88767`). It took two runs. The first stopped on an implementer question (ruled in 9.3), and in it neither agent could use Bash, because Claude Code 2.1.325 stopped auto-allowing sandboxed Bash in `dontAsk` mode; `roles/*.json` now set `autoAllowBashIfSandboxed`, and `lane.sh` lists any denied tool calls. The implementer's one run, written without compiling, passed every test. The tester's attack added 19 tests where features meet (splits becoming transfers, moving a transfer's other half) and found nothing new.
- **Round 4 (section 11) is complete.** The judge passed 640 of 640 tests at superproject commit `e3575ff` (testsuite `b70fea3`, server `928d991`), in one run of `round.sh`: one implementer run made the tester's 67 failing tests pass, and the attack (lines from unapproved transactions, the ends of the date range, edited transfer halves) found nothing new. Section 11 was pasted with credit accounts left unspecified until section 12.
- **Round 5 (section 12) is complete.** The judge passed 714 of 714 tests at superproject commit `6755ed4` (testsuite `937c53a`, server `775ddec`), in one run of `round.sh` with the tester at xhigh effort. One 2-minute implementer run made the tester's 54 failing tests pass. The attack found nothing new; it added worked scenarios for edits and a model-based test in `testsuite/` (four seeds of 360 random edits, checked against the tester's own model of sections 11 and 12), which guard this code before section 13 changes it.
- **Refactor round 1 is complete.** A code review found the server hand-rolling what axum, serde and `indexmap` provide, and repeating rules in several places. `roles/implementer.md` gained a "How the code should look" section, and `round.sh` gained `START=implementer` for rounds with no new tests first. With the brief in `spec/refactor-1.md`, the implementer moved the server to axum's `Router`, serde views, `IndexMap` storage and a `Month` type in one run (a first run hit a usage limit). The judge passed 714 of 714; the tester's attack found nothing new and asked about query decoding, ruled in 3.5. A final judge run passed 717 of 717 at superproject commit `b7694c5` (testsuite `de71230`, server `ece59d4`).
- **Round 6 (section 13) is complete.** The judge passed 766 of 766 tests at superproject commit `032b3c7` (testsuite `f272024`, server `df0a08f`), in one run of `round.sh`. Section 13 was tightened before pasting (see the rulings). One implementer run made the tester's 36 failing tests pass, and the attack (concurrent deletes, credit funding after a merge, transfers and splits whose category moved) found nothing new. The tester reads a bare `?reassign_to` as present with an empty value (400), as its 8.5 tests do for `since_date=`.
- **Clause 1.4 was added for the macOS app** (`app/`), so the server it bundles exits when the app dies. It's opt-in, through `MYBUDGET_EXIT_ON_STDIN_EOF=1`, because the judge's startup check runs the server with stdin `/dev/null`.
- **Round app-1 (clause 1.4) is complete.** The judge passed 809 of 809 tests at superproject commit `67a7709` (testsuite `a1ba732`, server `b624e62`), in two runs of `round.sh`. The first run's attack found that the server took an empty read on non-blocking stdin for end of file, and asked whether that was allowed; the ruling says it isn't. The rerun's implementer run fixed it, and the last attack (stdin that never ends, long quiet stretches, a full pipe closed, a parent that exits) found nothing new. `lane.sh` no longer requires a clean `app/` or watches it, because the app session works there during rounds, and it commits only its lane in the superproject.
- **Persistence was pulled forward (2026-11-18).** The human asked for section 15 before 14, rewritten: one SQLite file per plan, named after the plan, with schema migrations that each have a down and a `migrate` command to run them (see "Decisions the draft makes"). Section 15 is in `SPEC.md`, with changes to 3.2 and 3.4 (a `500` for a failed save) and 3.5 (ids become version 4 UUIDs). Section 14 keeps its number.
- **Round 7 (section 15) is complete.** The judge passed 916 of 916 tests at the superproject commit that records this (testsuite `9e1e35c`, server `0f09776`), after nine runs of `round.sh`: four stopped on questions, two on a dispute and three on usage limits (resumed with `START=judge`). The rulings settled what clashes with a plan file's name and the fallback to the whole id (15.2), lowercase `.sqlite` only (15.5), which files count as duplicates (15.7, a dispute upheld), and that 1.4's one second runs from startup. The round ended at the two-attack limit, not on a clean attack: the last two attacks still found bugs (a startup check that deleted user folders with the server's scratch prefix, `migrate` failing in a read-only folder, half-made plan files after a kill), all fixed. Expect section 15 to have more corners; a later round's attacks may find them. Version 1's migration is now fixed: `spec/migrations.sha256` holds its checksums and the judge fails any change to it. The round cost $59.62, the most so far.
- **Round 8 (section 14) is complete.** The judge passed 980 of 980 tests at the superproject commit that records this (testsuite `7e87efb`, server `3caec01`), in two runs of `round.sh`. Section 14 was pasted with 14.1 tightened (required fields, closed and tracking accounts, `200`). The first run stopped on a tester question about adjustments outside 3.7's range (ruled in 14.2: 409). One implementer run passed every test, and the attack (adjustments edited, deleted and listed like other transactions, races with new cleared transactions) found nothing new.
- **The judge got faster (2026-11-19).** `scripts/judge.sh` now runs tests four at a time (`JUDGE_JOBS`, default one per performance core), each still in its own sandbox; limits every sandboxed step to loopback networking; and caches dependency builds in `~/.cache/mybudget/judge/deps`, built from the lanes' manifests with stub sources so no lane code writes the cache. With macOS's first-launch scan turned off for the terminal (System Settings, Privacy & Security, Developer Tools), a full judge run went from about 4.5 minutes to about 1m10s. Running tests side by side exposed races that one-at-a-time runs hid, so expect a new server race to show up as an intermittent failure.
- **Round race-1 (clause 1.4) is complete.** The judge passed 998 of 998 tests at superproject commit `f67f987` (testsuite `b212427`, server `3d5139d`), after three runs of `round.sh` (brief: `spec/race-1.md`, started with `START=implementer`). The parallel judge exposed a race: the server could print `listening on` although stdin was at end of file from the start. The server now checks stdin itself, without blocking, just before printing. The tester's attacks found named pipes the first fix missed, then asked two questions, ruled in 1.4: a file with content reaches end of file when reads reach it, and so does any stdin with data left in it (a closed writer behind megabytes looks like a live one until it's read). The tester's CPU-load tests take turns across processes with `flock` on the test binary.
- **Round speed-1 (tests only) is complete.** The judge passed 998 of 998 tests at superproject commit `f67f987` (testsuite `3897c9f`), in one tester run (brief: `spec/speed-1.md`, `MAX_ATTACKS=0`). The five slowest tests went from 6.8–12.3s to 2.2–4.6s each: 1,200 empty plans instead of 2,000 with accounts for the 1.4 startup tests, a 30s startup wait in the harness instead of 10s, 15.5's two seeds side by side, and 15.6 killing after acknowledged saves instead of fixed sleeps. Plan files can't be written from scratch in tests: the spec doesn't define their schema, and copies count as duplicates (15.7).
- **Imports were pulled forward (2026-11-19).** The human asked for OFX/QFX file import next, YNAB-style: imported transactions arrive uncategorized and unapproved, to be categorized later, and an import matches transactions entered by hand. Uncategorized transactions reverse the decision that every on-budget transaction has a category, so they come first as section 16, in their own round; the import itself is section 17. Both are in `SPEC.md`, with changes to 3.13, 8.2, 9.3, 9.5, 10.2, 10.4, 11.6 and 15.8. Targets moved from section 16 to 18, and from schema version 2 to 3, since imports take version 2. Version 1 already holds uncategorized transactions (its `category_id` column is nullable), so section 16 adds no schema version.
- **Round 9 (section 16) is complete.** The judge passed 1037 of 1037 tests at superproject commit `fb3f0f2` (testsuite `b109694`, server `f69c579`), in two runs of `round.sh`. In the first, one implementer run left 5 failures and the implementer disputed 3.11, 9.3, 12.4 and 12.5. The disputes were upheld: three older tests still rejected a `null` category, and the edited-plan model skipped lines with no category (an uncategorized card refund showed it). In the rerun, the tester fixed them and the judge passed with no implementer run; the attack (card halves of tracking transfers, card payments and cash advances losing their transfer) found nothing new.
- **Round 10 (section 17, imports) is next**, then round 11 (section 18, targets), with the tasks in the rounds table below. Scheduled transactions are out of scope (the human, 2026-11-19).

## How to run a round

1. If the round's sections aren't in `SPEC.md` yet, re-read them against the checklist below, then paste them from the appendix in place of the `<!-- Next: ... -->` comment at the end of `SPEC.md`, and add a new comment naming the round after.
2. Commit. `lane.sh` refuses to start with uncommitted changes.
3. From the superproject root, start the round in the background with the Mac kept awake (round 1 lost a night to sleep):
   `MYBUDGET_ROUND=<n> caffeinate -i scripts/round.sh "<task>" > <log file> 2>&1`
   `MYBUDGET_ROUND` labels the token usage of every agent run in the round; use the same number for reruns.
   Name the events file yourself, so you can watch it before it exists: add `MYBUDGET_EVENTS=$HOME/.cache/mybudget/events/round-<n>[letter].jsonl`, with a new name for each run. `round.sh` adds one line to it as each step finishes (tester, judge, implementer) and a `round_end` line when it exits, and copies each step's final message or judge summary into the folder beside it.
   - Follow it with a Monitor running `scripts/watch-round.sh <events file>`, at its 30-minute limit, and re-arm it on each expiry: a cursor file beside the events file makes the new watcher carry on without repeating or skipping an event. It exits after `round_end`.
   - The human wants a short chat update after every step: what finished, its outcome, tests or commit, time and cost, and what runs next. On judge failures, say whether they look like a server bug or a stale test.
   - Send a desktop notification only when the round ends, or when it stops for the human (exit 1, exit 2, any other stop such as an agent leaving its lane, a usage limit, or a question or dispute that needs the human's ruling under step 5). Questions you settle yourself get a chat update only.
   - `scripts/round-status.sh [events file]` summarises a round on demand: the steps so far, the step running now and for how long, and the cost so far.
4. Read the exit status:
   - 0: the round is complete.
   - 1: the implementer was still failing after `MAX_FIXES` runs, or the working tree wasn't clean; the log says which. For failures, read `~/.cache/mybudget/judge/results/` and decide whether the spec is at fault.
   - 2: the suite or harness is broken; same folder.
   - 3: an agent ended with a `QUESTION:` or `DISPUTE:` line. It's in the log and in `~/.cache/mybudget/<role>/last-output.md`.
   - Anything else: `lane.sh` stopped, for example because an agent left its lane. Read the log.
5. To settle a question or dispute, change `SPEC.md` and commit, quoting the question in the message. Then rerun `round.sh` with the same task followed by `Tests for them already exist. Since the last run, <what changed>.` A rerun starts again with the tester revising its tests, then runs the judge, the implementer and the attacks.
   - Rule yourself on HTTP, JSON and validation edge cases. Prefer a general rule in section 3 to a one-off, and keep the server's current behaviour when it's reasonable.
   - Ask the human before any ruling that changes budget behaviour (sections 11 to 14, 16 and 18) or goes against a decision listed below.
   - For a dispute, read the clause's tests (`grep -rn spec_5_2_ testsuite/tests`) and their output in `~/.cache/mybudget/judge/results/tests.log`. If the tests ask too much, name them in the rerun's task so the tester fixes them. Only the tester edits `testsuite/`.
6. An attack that finds nothing new ends the round, even if it also raises a question. Settle the question, run `scripts/judge.sh` (under `caffeinate -i`) to confirm everything passes, and move on. Round 1 ended this way.
7. When the round is complete, run `scripts/usage.sh <n>` and add its totals to the token usage table below, in the same commit as the "round N is complete" note. If the round added a migration, also record its checksums in the same commit: `cd server && shasum -a 256 migrations/*/*.sql > ../spec/migrations.sha256`. The judge fails any later change to a migration listed there.
8. If an agent run is cut off (a usage limit, a crash), its lane may have uncommitted files; move them out of the submodule so `lane.sh` can start, then resume with `START=judge`, which judges the committed code and carries on with fixes and attacks.

For a refactor, where the spec doesn't change, start with `START=implementer` so the implementer runs first; the judge and the tester's attacks then follow as usual. Write the brief in a file under `spec/` and pass its text as the task: `START=implementer MYBUDGET_ROUND=refactor-1 caffeinate -i scripts/round.sh "$(cat spec/refactor-1.md)"`.

Round 1 took four runs of `round.sh`, and each stopped on a tester question about an edge case: lone surrogates, oversized or deeply nested JSON, percent-encoded paths, `HEAD`, and malformed HTTP. Its last attack found nothing new, so a judge run after the last ruling finished it. Expect the same pattern: the tester reads the server code and probes every corner.

`scripts/test.sh` stops at the first test binary that fails; pass `--no-fail-fast` to see every result. The judge runs each test separately, so it isn't affected.

### Checklist before pasting a round's sections

Round 1's questions came from gaps like these. Fixing them before pasting saves a stopped round each.

- Every endpoint has an example, and every number in an example agrees with the clause's formulas.
- For each `PATCH`: which fields can change, whether a field it can't change is ignored (3.6) or rejected because the change is never allowed (3.4), and what a `PATCH` that sets a field to its current value does.
- For each request field: required or optional, nullable or not (3.10), and its format. 3.7 to 3.9 define amounts, dates and names.
- References to sections that aren't pasted yet: reword them, or keep the tester off them in the task.
- Behaviour that changes from an earlier round: say so in the task, so the tester updates its older tests. Known cases: section 13 defines `DELETE` on a category (405 until then); section 16 lets an on-budget transaction have no category (8.2, 9.3, 9.5, 10.4), where earlier tests expect 400, and adds `uncategorized` to months; section 17 adds `import` to transactions; section 18 adds `target` to categories, `target`, `due` and `underfunded` to month entries, and `underfunded` to months, and changes what 11.2's `PATCH` and 13.3 do to assigned amounts.
- Data to keep: since section 15, a section that adds a new kind of data says which schema version (15.8) holds it and what migrating below that version drops. Its round's task says the new data must persist and migrate both ways. Sections 14 and 16 add no new kind of data; section 17's import data is the first, as version 2, and section 18's assignments and targets are version 3.

## Rulings so far

| Commit | Clause | Ruling |
| --- | --- | --- |
| `bed976b` | 3.1 | A string with an escaped lone surrogate (`"a\ud800b"`) makes the body invalid JSON (400). |
| `7d7a025` | 3.13, 3.2 | The server may refuse a body over 1 MiB with a JSON `413`, before any other check, and with `400` nesting deeper than 64 or a number too large for a 64-bit float. Within those limits, ignored fields may hold any JSON. |
| `2ac308f` | 3.5 | Ids use only ASCII letters, digits, `-` and `_`. Clients never percent-encode paths, so what the server does with a percent-encoded path is unspecified. |
| `9911cc4` | 3.2, 3.4 | `HEAD` works wherever `GET` does, with no body. What the server does with malformed HTTP is unspecified. |
| This file's commit | 5 to 7 | Changes made before the round, not rulings: `starting_date` is unused when `starting_balance` is 0; a `PATCH` with a different account `type` returns 400; a `PATCH` naming a category's own group doesn't move it; examples added for 5.6, 6.3, 6.4, 7.4 and 7.6. |
| `6d0ec8f` | 3.6, 3.7, 5.2, 6.5 | A field the endpoint defines is checked whenever it's present, even when another field leaves it unused: `starting_date` (not nullable) when `starting_balance` is 0, and `payee_name` (a payee name or `null`) when `payee_id` is given. `-0` is an integer meaning 0. |
| This file's commit | 8 to 10 | Changes made before round 3, not rulings: context for 8.5's example; in a `PATCH` the payee changes only when `payee_id` is present or `payee_name` is a string, and a left-out `category_id` becomes `null` when the result can't have one (8.6); a subtransaction's `category_id` is required (10.1); a split made ordinary again needs a category in the same request (10.4); wording in 9.2, 9.3 and 9.5. |
| This file's commit | 8.6, 9.3 | A `PATCH` to the tracking half of an on-budget/tracking transfer that leaves `category_id` out keeps the on-budget half's category, even when the other half moves to another on-budget account; with no on-budget half before, it needs a `category_id`. (Implementer question, round 3.) |
| This file's commit | 11 | Changes made before round 4, not rulings: until section 12, what a plan with a credit account shows in its months isn't specified, and 11's references to 12.3 to 12.5 point at section 12; `assigned` is an amount and not nullable (11.2); an example for `GET` on a category's month (11.3); the month's `categories` go group by group (11.6). |
| This file's commit | 11, 12 | Changes made before round 5, not rulings: section 11's references point back at 12.3 to 12.5 and its intro no longer leaves credit months unspecified; 12.7's example says Groceries is the plan's only user category. |
| This file's commit | 3.5, 8.5 | Clients never percent-encode query parameters either, so decoding them (and `+`) is unspecified. A repeated query parameter has each value checked, so any invalid one returns 400, and the last counts. (Tester question, refactor round 1.) |
| This file's commit | 13 | Changes made before round 6, not rulings: `DELETE` returns 204 (3.3); `reassign_to` is checked whenever present and can't be the deleted category, `ready_to_assign` or a payment category; assigned amounts move to `reassign_to` even when the category wasn't in use; an example of the 409; 13.4 says what a deleted category looks like afterwards. |
| This file's commit | 1.4 | Added for the macOS app, not a ruling: with `MYBUDGET_EXIT_ON_STDIN_EOF=1` the server exits when stdin reaches end of file, ignoring anything it reads first. |
| This file's commit | 1.4 | The server exits only at end of file on stdin: a read that finds nothing waiting (non-blocking stdin) isn't end of file. Other read errors are unspecified. (Tester question, round app-1.) |
| This file's commit | 3.2, 3.4, 3.5, 15 | Changes made with the human before round 7, not rulings: section 15 rewritten for one SQLite file per plan, migrations and `migrate`; `500` for a failed save; ids become version 4 UUIDs. |
| This file's commit | 15.2, 15.8 | Anything in the directory with a plan file's name, a folder included, makes it clash; a database with `user_version` below 1 isn't a plan file. (Readings the tester flagged in round 7.) |
| This file's commit | 15.2 | When the name with 8 characters of the id is taken too, the file gets the whole id; if that's taken, the request returns 500. (Implementer question, round 7.) |
| This file's commit | 15.5 | Only names ending in lowercase `.sqlite` are plan files; `.SQLITE` and other mixes of case are ignored, though they can still clash (15.2). (Tester question, round 7.) |
| This file's commit | 15.7 | A file skipped for another reason (unreadable, a newer version) never hides another file holding the same plan; only usable files count as duplicates. (Implementer question, round 7.) |
| This file's commit | 15.7 | Dispute rejected: a file counts as holding a plan only if the server would serve it alone, so a read-only WAL copy it can't use doesn't hide the original; each skipped file's report stays on one line, however its name is escaped. (Implementer dispute, round 7.) |
| This file's commit | 1.4 | The one second runs from the moment the server starts, including while it loads its data; end of file before it's listening means it exits without the `listening on` line. (Implementer question, round 7.) |
| `afdb0dd` | 14.2 | An adjustment whose amount would fall outside 3.7's range returns 409 and changes nothing, so every transaction's amount stays in range. (Tester question, round 8.) |
| This file's commit | 1.4 | Stdin that is an empty file is at end of file from the start, like `/dev/null`; for a file with content, end of file comes when the server's reads reach it, so it may print 1.3's line first. (Tester question, round race-1.) |
| This file's commit | 1.4 | Widened: stdin with nothing left to read (`/dev/null`, an empty file, a pipe or socket closed empty) is at end of file from the start; with anything left to read, end of file comes when the server's reads reach it, so the line may come first. A closed writer behind megabytes of data looks like a live one until it's read, so no server can tell in time. (Implementer dispute, round race-1.) |
| This file's commit | 3.13, 8.2, 9.3, 9.5, 10.2, 10.4, 11.6, 15.8, 16, 17 | Changes made with the human before round 9, not rulings: on-budget transactions may be uncategorized (section 16); OFX import with matching (section 17), and 16 MiB bodies for its endpoints; targets renumbered to section 18 and schema version 3. |
| This file's commit | 3.11, 9.3, 12.4, 12.5 | Dispute upheld, no spec change: five tests weren't updated for section 16. Three still expect a `null` category on an on-budget transaction to return 400, and the edited-plan model (`tests/credit_edited_model.rs`) skips lines with no category, where 16.2 makes them lines of Uncategorized, refunds on cards included. (Implementer dispute, round 9.) |
| This file's commit | 17.3, 17.5, 17.9 | A comment or processing instruction inside a value is skipped and the value carries on (`<NAME>AB<!-- x -->CD` is `ABCD`); of a repeated element, the first that isn't absent counts; `5.` is an amount; `duplicates` is in file order, whichever check found each. (Tester questions, round 10.) |
| This file's commit | 17.9 | A bank transaction whose import id an earlier one in the same import has is a duplicate by the first check, even if that earlier one was itself skipped by the second check; its `transaction_id` is the account's transaction with that id once the import is done, or `null`. (Implementer question, round 10.) |
| This file's commit | 17.9 | Only earlier bank transactions going into the same account count: `FITID`s are unique per account, so a statement for another account in the same import never makes one a duplicate. (Implementer question, round 10.) |
| This file's commit | 17.4 | Each element 17.4 lists is read only directly inside the element that holds it; one nested elsewhere (`<NAME>SHOP<MEMO>X</MEMO></NAME>`) is ignored. Statements are still found anywhere. (Tester question, round 10.) |

## Token usage

`lane.sh` appends each agent run's usage to `~/.cache/mybudget/usage.jsonl`, and `round.sh` prints the round's totals when it exits. `scripts/usage.sh [round]` sums them by round and role. Tokens are summed over every model the session used; cache reads are the bulk of the input. Cost is Claude Code's list-price estimate. A run killed before it finishes (a usage limit, a crash) records nothing. Rounds 1 and 2 ran before tracking and left no transcripts. Rounds 1 to 4 ran both agents on Opus 5.5 at high effort, from the human's own settings. From round 5 the tester runs at xhigh (`effortLevel` in `roles/tester.json`, which `lane.sh` passes as `--effort`), and each line in `usage.jsonl` records its effort. During round 7 the human set the tester back to high.

| Round | Agent runs (tester / implementer) | Input | Output | Cache read | Cache write | Est. cost (USD) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | not tracked | | | | | |
| 2 | not tracked | | | | | |
| 3 | 3 / 1 | 178 | 215,018 | 8,346,360 | 541,687 | 10.30 |
| 4 | 2 / 1 | 104 | 107,650 | 3,864,488 | 322,560 | 5.51 |
| 5 | 2 / 1 | 148 | 195,078 | 10,011,759 | 503,208 | 9.93 |
| refactor-1 | 1 / 2 | 184 | 174,767 | 12,087,108 | 483,818 | 9.78 |
| 6 | 2 / 1 | 128 | 120,653 | 5,747,449 | 389,243 | 6.68 |
| app-1 | 4 / 2 | 210 | 175,618 | 7,101,894 | 430,880 | 8.38 |
| 7 | 12 / 10 | 1,350 | 1,056,864 | 77,068,862 | 2,883,407 | 59.62 |
| 8 | 3 / 1 | 178 | 95,347 | 6,891,130 | 393,244 | 6.43 |
| race-1 | 4 / 5 | 400 | 214,874 | 11,222,616 | 582,591 | 11.20 |
| speed-1 | 1 / 0 | 82 | 36,288 | 3,805,753 | 118,451 | 2.43 |
| 9 | 3 / 2 | 348 | 171,906 | 16,456,837 | 658,360 | 12.00 |

## The rounds

| Round | Sections | Task for `round.sh` | Notes |
| --- | --- | --- | --- |
| 2 | 5 to 7, already in `SPEC.md` | `SPEC sections 5 to 7 (accounts, payees, categories)` | 3.7 and 3.8 become testable through `starting_balance` and `starting_date`. Starting-balance transactions only show through balances and payees until round 3. |
| 3 | 8 to 10 | `SPEC sections 8 to 10 (transactions, transfers, splits)` | These refer to each other, so they go in together. It's the largest round; consider `MAX_FIXES=8`. |
| 4 | 11 | `SPEC section 11 (months and Ready to Assign), for plans without credit accounts; section 12 covers those next round` | 11 refers ahead to 12 for the credit fields, so the task keeps the tester to cash accounts. |
| 5 | 12 | `SPEC section 12 (credit cards)` | The hardest maths. Check 12.2 to 12.5 and the example in 12.7 before pasting. Section 11 was pasted with credit accounts left unspecified: point 11.3, 11.5 and 11.6 back at 12.4, 12.3 and 12.5, and drop the intro's sentence saying credit months aren't specified. |
| 6 | 13 | `SPEC section 13 (deleting categories). DELETE on a category returned 405 until now.` | |
| app-1 | 1.4, already in `SPEC.md` | `SPEC clause 1.4 (exiting when stdin reaches end of file), which is new` | Testing 1.4 needs `Server` to pass env vars and pipe stdin. |
| 7 | 15, already in `SPEC.md` | `spec/round-7.md` (pass its text) | Pulled ahead of 14. The tester extends the harness to restart on the same data directory and to open plan files with `rusqlite`. The judge's per-test scratch folder (`TMPDIR`) is writable. A bundled SQLite builds offline in a sandbox like the judge's (checked 2026-11-18). |
| 8 | 14 | `SPEC section 14 (reconciliation). Its data persists like the rest (section 15).` | Adds no schema version. Paste it before section 15 in `SPEC.md`, to keep the sections in order. |
| 9 | 16 | `SPEC section 16 (uncategorized transactions). It changes earlier behaviour: an on-budget transaction may now have no category (8.2, 9.3, 9.5, 10.2, 10.4), so tests expecting 400 for a missing category must change, and months gain uncategorized. Section 17 is in SPEC.md too but is next round's; don't test it yet. Uncategorized transactions persist like the rest, in schema version 1.` | Changes budget behaviour, so ask the human before ruling on 16.2. The tester should extend its model-based test (round 5) with uncategorized lines. Check 16.5's numbers against the model. |
| 10 | 17 | `SPEC section 17 (importing OFX files). Transactions gain import, and the import data is schema version 2, which must persist and migrate both ways (17.15). Implementer: decode the file with the base64 and encoding_rs crates, and hand-roll the OFX reader (17.3 to 17.5) in its own module, explaining at its top why, as src/json.rs does: the OFX crates (ofx-rs, ofx-kit) apply their own validation, which 17.4 and 17.5 contradict (FITID and TRNTYPE required, known TRNTYPEs only, a raw & breaks their XML step), and sgmlish, unmaintained since 2021, rejects AT&T as an unknown entity.` | Parser decision (2026-11-19): hand-rolled, with `base64` and `encoding_rs`; see "Decisions the draft makes". The tester writes its own OFX and QFX fixtures, 1.x and 2.x, in the encodings 17.2 names. 17.3's leniency (unclosed leaves, stray `&`) is where attacks will go; rule on parsing corners yourself, and ask the human about 17.10 to 17.12. The round adds a migration, so record its checksums when it's complete. |
| 11 | 18 | `SPEC section 18 (targets and assignment history). It changes earlier behaviour: 11.2's PATCH now records assignments, 13.3 moves them, and categories, month entries and months gain fields.` | Today comes from 18.1: tests should always set `MYBUDGET_TODAY`, and move it by restarting with a new one and the same `MYBUDGET_DATA`. Assignments and targets are schema version 3 (18.8). The round adds a migration, so record its checksums when it's complete. |

## Decisions the draft makes

YNAB doesn't decide these, or doesn't fit an HTTP contract. Keep rulings consistent with them, and ask the human before reversing one.

- **Several plans per server**, under `/plans/{plan_id}`, like YNAB's API (which renamed budgets to plans). There's no `{"data": ...}` wrapper and no delta sync.
- **Field names follow YNAB's app**, not its API: `assigned`, `activity`, `available` and `ready_to_assign` are the API's `budgeted`, `activity`, `balance` and `to_be_budgeted`. The month fields `left_over_from_last_month`, `cash_overspending_last_month` and `assigned_in_future` come from the app's Ready to Assign breakdown.
- **Errors** are `{"error": "..."}`, with 405 before 404 before 400 before 409.
- **Uncategorized transactions (section 16)** were allowed on 2026-11-19, for imports; until then every on-budget transaction needed a category. YNAB doesn't publish how uncategorized money behaves, so 16.2 treats it as one more user category that's never assigned anything: uncategorized cash spending is cash overspending, uncategorized card spending is unfunded debt (YNAB warns that uncategorized transactions affect the payment category), and an uncategorized inflow waits in Uncategorized rather than counting as income. Subtransactions still need a category. In a credit account, `ready_to_assign` means only the debt changes, which is how YNAB treats statement credits and balance adjustments. Starting balances and reconciliation adjustments in on-budget accounts use `ready_to_assign`.
- **Credit card funding is worked out per month and category** (12.2), so it doesn't depend on the order transactions were entered or edited. When several cards share an underfunded category, the cards are funded in the order they were created. YNAB funds the earliest purchases first.
- **The Ready to Assign formula (11.7)** isn't published by YNAB. It was derived from YNAB's help articles on assigning ahead, overspending and later income, and reproduces every case they describe.
- **There's no clock until section 18.** Transactions dated in the future count as soon as they're entered, even after section 18, which reads today from `MYBUDGET_TODAY` for targets and assignment dates.
- **`approved` defaults to true** for transactions created through the API.
- **Closing an account needs a zero balance**, and deleting one needs it to have no transactions. Deleting a category that's in use needs `reassign_to`.
- **Persistence (section 15)**, decided with the human on 2026-11-18:
  - One SQLite file per plan, so single plans can be copied between devices. It's named after the plan, with 8 characters of the plan's id added only when the name clashes. This breaks parity with YNAB, which the human accepted.
  - Files are copied by hand while the app is closed. The server reads the directory only at startup, and live changes to the files are unspecified.
  - A plan file the server can't use is skipped with a warning; only an unusable directory stops the server. Two files holding the same plan are both skipped.
  - Every migration has a down, and `mybudget-server migrate` runs them either way. Some data may be lost between versions.
  - SQLite is bundled (`rusqlite`), so every device writes files with the same SQLite version.
- **Imports (section 17)**, decided with the human on 2026-11-19:
  - OFX and QFX only; no CSV, so no column mapping. The server parses the file, so a web client can reuse it. The file travels as base64 in JSON, so the server can read its declared encoding, with a 16 MiB body limit for the import endpoints.
  - Two steps: a preview that reads the file and suggests each statement's account from the last import, then an import naming an account for each statement. The server remembers each statement's account and options by its bank id and account number.
  - Duplicates are found by `FITID`, kept per account even after a transaction is deleted, as YNAB does, and also by the same amount within 2 days of an earlier imported or matched transaction, paired one to one (the human, 2026-11-19; YNAB uses the exact date). That check can skip a real transaction, so the response lists every duplicate and the import takes `not_duplicates` to override it.
  - Imported transactions are cleared and unapproved. Their category comes from the payee's most recent category; with no history, inflows to cash accounts go to Ready to Assign (YNAB says checking accounts) and everything else is uncategorized. YNAB's rule that the default changes when 2 of the last 3 differ is left out.
  - Matching follows YNAB: same account, exact amount, dates within 10 days, the hand-entered transaction keeps its own date, payee, memo and category, and becomes approved. Transactions already cleared or reconciled can match too, since they may be entered from the bank's website (the human, 2026-11-19); starting balances and reconciliation adjustments can't, found by their payees' names. Unmatching leaves `cleared` alone. Matching is automatic; there's no manual match of different amounts.
  - The options are YNAB's "Swap Payee and Memo" and "Swap Inflow and Outflow". Memos are always imported.
  - The OFX reader is hand-rolled (decided 2026-11-19, after looking at the crates). `ofx-rs` 0.2 and its fork `ofx-kit` 0.3 are young and little used, and parse into typed structs with their own validation (FITID and TRNTYPE required, known TRNTYPEs only, length limits, raw `&` passed to `quick-xml`), which would fight 17.4 and 17.5. `sgmlish` 0.2 closes unclosed elements as 17.3 does, but it hasn't had a release since 2021, fails on unknown entities such as `AT&T`, and still leaves headers, encodings and the walk over elements to us. 17.3's reading is a small tokenizer and a stack. Decoding uses `encoding_rs`, so 17.2 follows the WHATWG Encoding Standard, which also reads files labelled ISO-8859-1 as Windows-1252, as browsers do. `ofxy` is GPL-3.0 and built on `sgmlish`.
- **Targets (section 18)**, decided with the human on 2026-11-19:
  - Two types, `set_aside` and `refill`. Both are monthly and repeat until removed. There are no one-off goals, weekly or yearly targets, or snoozing.
  - `by_date` is the day of the month a target is due, returned as each month's `due` date. It doesn't change `underfunded`.
  - Spending never counts against a target. A `refill` target counts the money carried in from last month.
  - A category keeps every target it has had, each applying to a range of months, and no two ranges overlap. So past months keep the target they had. Clients set and remove targets on the category, and the server manages the ranges. A change applies from today's month or a later `start_month`, never an earlier one.
  - Assignments are kept as a log of changes, each with the date it was made, and a month's `assigned` is their sum. `PATCH` still sets the total (11.2). The log can be read now, and is there for later features.

## Left out on purpose

- Credit cards with a positive balance. YNAB treats that money as cash ("Inflow from Debt Account" in Ready to Assign); the draft doesn't.
- Loan accounts and YNAB's built-in Credit Card Interest category.
- Payees on individual subtransactions, and transfers inside a split.
- CSV import, Direct Import (bank connections), payee rename rules, pending transactions and manual matching of transactions with different amounts. Payee locations, money-movement history, undo, delta sync, ordering of categories and groups, month notes, and most of YNAB's target types (one-off goals, weekly and yearly targets, snoozing).
- Age of Money. The human dropped it on 2026-11-19; the app doesn't need it.
- Scheduled transactions. The human ruled them out of scope on 2026-11-19.

Possible sections after 18: moving money between categories in one request, ordering categories and groups, month notes, payee rename rules for imports, delta sync for the app, and the items above.

## How YNAB keeps its books

These are the rules the draft copies.

- Money in cash accounts (checking, savings, cash) arrives in Ready to Assign. You assign it to categories, month by month. Tracking accounts (investments, other assets and debts) don't take part.
- Each category has Assigned, Activity and Available every month. A positive Available carries into next month; a negative one doesn't, and the category starts next month at 0.
- Spending more cash than a category had is cash overspending. It comes out of next month's Ready to Assign. Spending more on a credit card than the category had is credit overspending, which becomes card debt instead. A category overspent both ways spends its own money on the cash spending first.
- Each credit card has a payment category. Card spending a category covers moves that money into the payment category. Payments take money out of it, and refunds move money back to the spending category. A cash advance (card to checking) adds to Ready to Assign without touching the payment category. A card's starting debt, statement credits and balance adjustments only change what's owed. To pay off old debt, you assign money to the payment category.
- Money assigned in a future month comes out of this month's Ready to Assign, as Assigned in Future. A later month's income covers that month's assignments first. If you assign more than you have, the month that runs out shows a negative Ready to Assign, not the months before it.
- A transfer between two on-budget accounts, or two tracking accounts, has no category. A transfer between an on-budget account and a tracking account moves money into or out of the plan, so its on-budget side needs a category.
- Splits spread one payment over categories. Cleared and reconciled statuses track agreement with the bank, and reconciling adds an adjustment for any difference. Amounts are milliunits (1000 is one unit of currency).

Sources:
- https://pypi.org/project/ynab/: the Python client, version 4.4.1, built from API spec 1.86.0.
- https://api.ynab.com/ and its OpenAPI spec, version 1.88.0, at https://api.ynab.com/papi/open_api_spec.yaml
- YNAB support articles at `https://support.ynab.com/en_us/<slug>`. Mainly:
  - Ready to Assign and months: `the-plan-header-BkmiuJ_C9`, `assigning-future-income-an-overview-BJsTo0jCq`, `when-ready-to-assign-is-negative-an-overview-HylZA0zCc`, `overspending-and-the-monthly-rollover-S1ySgcLSMx`.
  - Credit cards: `credit-cards-funded-spending-By7XIs8HMg`, `credit-card-overspending-an-overview-HkMGpSbJs`, `credit-card-refunds-and-returns-H1J7qDWkj`, `credit-card-cash-advances-an-overview-Hy6PmlOC9`, `credit-card-rewards-and-statement-credits-a-guide-ryoRzYY0q`, `credit-cards-with-a-positive-balance-an-overview-By_H6uzJo`.
  - Transactions, accounts and categories: `transfer-transactions-a-guide-HJOsZz4Jj`, `split-transactions-a-guide-SJLEKwY0q`, `reconciling-accounts-a-guide-BJFE3fHys`, `balance-adjustments-a-guide-rko4OwILs`, `how-to-close-or-delete-an-account-in-ynab-ry_409Gko`, `adding-removing-and-customizing-categories-a-guide-HJFO5j909`.
  - Targets: `how-to-use-targets-rk5kkI9ks`, `underfunded-a-guide-BJwPhQO09`.

## How the examples were checked

The numbers in the examples in 11.8, 12.7 and 13.3 were checked against a small Python model of sections 11 and 12. The model also reproduced YNAB's documented cases:

- assigning ahead with nothing left to assign (the later month goes negative, not the current one)
- new income covering an over-assignment
- overspending this month leaving this month's Ready to Assign alone
- a cash advance
- two cards sharing an underfunded category
- cash and credit overspending in one category
- overpaying a card
- a statement credit
- money coming in from a tracking account

The model isn't in the repo, because the agents can read `spec/`. With a reference implementation, the implementer could skip the spec, and ambiguities the tester should surface would stay hidden. If you change sections 11 or 12, recheck those examples by hand or with a fresh model kept outside the repo. The examples in sections 16 to 18 were worked out by hand.

## Appendix: draft section 18

Paste-ready text for the later rounds. Each round pastes its sections from here into `SPEC.md`, without the four-backtick fence around them.

````markdown
## 18. Targets

18.1 Today is the date in the environment variable `MYBUDGET_TODAY` (`YYYY-MM-DD`) if it is set, and otherwise the current date in the server's local time zone. If it is set to anything that isn't a date (3.8), the server writes a message to stderr and exits with a non-zero status, without printing 1.3's line. Transactions still count as soon as they're entered, whatever their date.

18.2 Each change to a category's `assigned` for a month is kept as an assignment: the amount it adds, positive or negative, and the date it was made, which is today (18.1). A month's `assigned` (11.2) is the sum of its assignments, so it is 0 until one is made. 11.2's `PATCH` makes one assignment, of the new `assigned` minus the old; a `PATCH` that leaves `assigned` as it was makes none. `GET /plans/{plan_id}/months/{month}/categories/{category_id}/assignments` lists a category's assignments for that month, in the order they were made, as objects with `date` and `amount`. It works for user and payment categories, and an empty month gives `[]`. `ready_to_assign` isn't a category here: that path returns 404, as in 11.2.

```
(11.8's plan, made on a server started with MYBUDGET_TODAY=2026-10-01, which is then restarted
 with MYBUDGET_TODAY=2026-11-20 and the same MYBUDGET_DATA)
PATCH /plans/PLAN_ID/months/2026-10/categories/GROCERIES_ID
{"assigned": 350000}
→ 200
{"category_id": "GROCERIES_ID", "assigned": 350000, "activity": -120000, "available": 230000,
 "cash_overspending": 0, "credit_overspending": 0, "target": null, "due": null, "underfunded": null}

GET /plans/PLAN_ID/months/2026-10/categories/GROCERIES_ID/assignments
→ 200
[{"date": "2026-10-01", "amount": 400000}, {"date": "2026-11-20", "amount": -50000}]
```

The examples in 18.3 to 18.6 each start again from 11.8's plan, on a server started with `MYBUDGET_TODAY=2026-11-05`.

18.3 Every category object (7.1 to 7.6) has a `target`: the category's current target (18.4), or `null`. `PATCH /plans/{plan_id}/categories/{category_id}` with `target` sets a new target, and with `null` removes it (18.4). A `PATCH` on a payment category that includes `target`, even `null`, returns 400, so a payment category's `target` is always `null`. A target in a request is an object with these fields:

- `type`, required: `"set_aside"`, to assign `amount` every month, or `"refill"`, to fill the category up to `amount` every month (18.5).
- `amount`, required: an amount (3.7) greater than 0.
- `by_date`, optional and nullable: the day of the month the target is due, a JSON integer from 1 to 31 written without a fraction or exponent. `null`, the default, means the month's last day.
- `start_month`, optional and not nullable: the first month the target applies to (3.8). It defaults to today's month, and a month before today's returns 400.

Anything else where a target is expected returns 400. A target is returned with all four fields.

```
PATCH /plans/PLAN_ID/categories/GROCERIES_ID
{"target": {"type": "refill", "amount": 400000, "by_date": 15}}
→ 200
{"id": "GROCERIES_ID", "group_id": "EVERYDAY_ID", "name": "Groceries", "hidden": false, "note": null,
 "payment_account_id": null,
 "target": {"type": "refill", "amount": 400000, "by_date": 15, "start_month": "2026-11"}}
```

18.4 A category may have many targets over time, but no two apply to the same month. Each target applies from its `start_month` until the month before the next one's `start_month`, or without end if no other target follows it; the category's current target is the one without end, if there is one. Setting a target that starts in month S removes every target of the category whose `start_month` is S or later, ends the one that applied in S at the month before S, and adds the new target without end. Removing the target with `null` does the same for S equal to today's month, without adding one, so today's month and every later month have no target. If the current target already has the new target's `type`, `amount` and `by_date`, and its `start_month` is S or earlier, setting it changes nothing: sending 18.3's `PATCH` again leaves its `start_month` at `2026-11`.

After 18.3's `PATCH`, this keeps the refill target for November and applies a new one from December:

```
PATCH /plans/PLAN_ID/categories/GROCERIES_ID
{"target": {"type": "set_aside", "amount": 300000, "start_month": "2026-12"}}
→ 200
{"id": "GROCERIES_ID", "group_id": "EVERYDAY_ID", "name": "Groceries", "hidden": false, "note": null,
 "payment_account_id": null,
 "target": {"type": "set_aside", "amount": 300000, "by_date": null, "start_month": "2026-12"}}

PATCH /plans/PLAN_ID/categories/GROCERIES_ID
{"target": {"type": "set_aside", "amount": 300000, "start_month": "2026-10"}}
→ 400
{"error": "start_month is before this month"}
```

Sending `{"target": null}` after that removes both targets, since both start in November or later.

18.5 Each month entry (11.3) gets three fields, all `null` for a month that no target applies to. Otherwise:

- `target`: the target that applies that month, as 18.3 returns it.
- `due`: the date in that month on the target's `by_date`, or the month's last day when `by_date` is `null` or past the end of the month.
- `underfunded`: how much more to assign that month. With carryover as in 11.4, a `set_aside` target's is max(0, `amount` - `assigned`), so money carried in or spent never counts. A `refill` target's is max(0, `amount` - carryover - `assigned`), so money carried in counts but money spent that month doesn't.

The month's `uncategorized` entry (16.3) has all three `null`.

After 18.3's `PATCH`, November's entry asks for 120000: 400000, less 280000 carried in and 0 assigned. October's entry has `null` for all three, because the target starts in November.

```
GET /plans/PLAN_ID/months/2026-11/categories/GROCERIES_ID
→ 200
{"category_id": "GROCERIES_ID", "assigned": 0, "activity": 0, "available": 280000,
 "cash_overspending": 0, "credit_overspending": 0,
 "target": {"type": "refill", "amount": 400000, "by_date": 15, "start_month": "2026-11"},
 "due": "2026-11-15", "underfunded": 120000}
```

After 18.4's first `PATCH` as well, December's entry has the set-aside target, `"due": "2026-12-31"` and `"underfunded": 300000`: the 280000 carried in doesn't count. A `by_date` of 31 gives `"due": "2027-02-28"` in February 2027.

18.6 Each month (11.6) gets `underfunded`: the sum of its categories' `underfunded`, counting `null` as 0. After 18.3's `PATCH` and a set-aside target of 1200000 on Rent with a `by_date` of 1, November's `underfunded` is 120000: 120000 for Groceries, 0 for Rent (November assigns it 1200000, and its `due` is `2026-11-01`) and `null` for Dining.

18.7 Deleting a category (13.1) deletes its targets. With `reassign_to`, its assignments move to that category with their dates and amounts unchanged, which is how 13.3 adds its `assigned` to that category's, and every list of assignments stays in the order they were made. Without `reassign_to`, its assignments are dropped. The other category's targets don't change.

18.8 Schema version 3 (15.8) holds assignments and targets. Upgrading a file from version 2 or older turns each month's `assigned` for a category, when that isn't 0, into one assignment for the whole amount, dated the first day of the month. Migrating to version 2 or below drops every target and keeps only each month's total `assigned`, so going back up to version 3 gives one assignment per month, as upgrading does.

````
