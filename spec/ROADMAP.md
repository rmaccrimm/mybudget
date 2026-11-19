# Roadmap: the remaining rounds

This is for the agent that resumes the work. The goal is a server that replicates YNAB's core budgeting, specified in `SPEC.md` and built one round at a time by the tester and implementer (see `README.md` for how rounds work). Sections 3 to 18 were drafted together from research into YNAB; this file holds the plan for the rounds still to run, the rules for running them, and the draft text of the sections not yet in `SPEC.md`.

## Where things stand (2026-11-18)

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
- **Round 8 (section 14) is next**, with the task in the rounds table below. Paste section 14 before section 15 in `SPEC.md`.

## How to run a round

1. If the round's sections aren't in `SPEC.md` yet, re-read them against the checklist below, then paste them from the appendix in place of the `<!-- Next: ... -->` comment at the end of `SPEC.md`, and add a new comment naming the round after.
2. Commit. `lane.sh` refuses to start with uncommitted changes.
3. From the superproject root, start the round in the background with the Mac kept awake (round 1 lost a night to sleep):
   `MYBUDGET_ROUND=<n> caffeinate -i scripts/round.sh "<task>" > <log file> 2>&1`
   `MYBUDGET_ROUND` labels the token usage of every agent run in the round; use the same number for reruns.
4. Read the exit status:
   - 0: the round is complete.
   - 1: the implementer was still failing after `MAX_FIXES` runs, or the working tree wasn't clean; the log says which. For failures, read `~/.cache/mybudget/judge/results/` and decide whether the spec is at fault.
   - 2: the suite or harness is broken; same folder.
   - 3: an agent ended with a `QUESTION:` or `DISPUTE:` line. It's in the log and in `~/.cache/mybudget/<role>/last-output.md`.
   - Anything else: `lane.sh` stopped, for example because an agent left its lane. Read the log.
5. To settle a question or dispute, change `SPEC.md` and commit, quoting the question in the message. Then rerun `round.sh` with the same task followed by `Tests for them already exist. Since the last run, <what changed>.` A rerun starts again with the tester revising its tests, then runs the judge, the implementer and the attacks.
   - Rule yourself on HTTP, JSON and validation edge cases. Prefer a general rule in section 3 to a one-off, and keep the server's current behaviour when it's reasonable.
   - Ask the human before any ruling that changes budget behaviour (sections 11 to 18) or goes against a decision listed below.
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
- Behaviour that changes from an earlier round: say so in the task, so the tester updates its older tests. Known cases: section 13 defines `DELETE` on a category (405 until then); 16.6 extends 5.9 and 6.4; section 17 adds `target` to categories and `underfunded` to month entries; section 18 adds `age_of_money` to months.
- Data to keep: since section 15, a section that adds a new kind of data says which schema version (15.8) holds it and what migrating below that version drops. Its round's task says the new data must persist and migrate both ways. Section 14 adds no new kind of data; section 16's scheduled transactions are the first, as version 2.

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
| 9 | 16 | `SPEC section 16 (scheduled transactions)` | Needs 15: a test moves "today" by restarting with a new `MYBUDGET_TODAY`. Tests should always set it. Scheduled transactions are schema version 2, the first with a real down migration: add to 16 what migrating to version 1 drops. |
| 10 | 17 | `SPEC section 17 (targets)` | Only after the human answers open questions 1 to 3. |
| 11 | 18 | `SPEC section 18 (age of money)` | Only after the human answers open question 4. |

## Decisions the draft makes

YNAB doesn't decide these, or doesn't fit an HTTP contract. Keep rulings consistent with them, and ask the human before reversing one.

- **Several plans per server**, under `/plans/{plan_id}`, like YNAB's API (which renamed budgets to plans). There's no `{"data": ...}` wrapper and no delta sync.
- **Field names follow YNAB's app**, not its API: `assigned`, `activity`, `available` and `ready_to_assign` are the API's `budgeted`, `activity`, `balance` and `to_be_budgeted`. The month fields `left_over_from_last_month`, `cash_overspending_last_month` and `assigned_in_future` come from the app's Ready to Assign breakdown.
- **Errors** are `{"error": "..."}`, with 405 before 404 before 400 before 409.
- **Every on-budget transaction has a category**, unless it's a transfer between on-budget accounts or a split. YNAB allows uncategorized transactions. In a credit account, `ready_to_assign` means only the debt changes, which is how YNAB treats statement credits and balance adjustments. Starting balances and reconciliation adjustments in on-budget accounts use `ready_to_assign`.
- **Credit card funding is worked out per month and category** (12.2), so it doesn't depend on the order transactions were entered or edited. When several cards share an underfunded category, the cards are funded in the order they were created. YNAB funds the earliest purchases first.
- **The Ready to Assign formula (11.7)** isn't published by YNAB. It was derived from YNAB's help articles on assigning ahead, overspending and later income, and reproduces every case they describe.
- **There's no clock until section 16.** Transactions dated in the future count as soon as they're entered. Section 16 reads today from `MYBUDGET_TODAY`.
- **`approved` defaults to true** for transactions created through the API. Scheduled transactions are entered with `approved` false, as in YNAB.
- **Closing an account needs a zero balance**, and deleting one needs it to have no transactions. Deleting a category that's in use needs `reassign_to`.
- **Persistence (section 15)**, decided with the human on 2026-11-18:
  - One SQLite file per plan, so single plans can be copied between devices. It's named after the plan, with 8 characters of the plan's id added only when the name clashes. This breaks parity with YNAB, which the human accepted.
  - Files are copied by hand while the app is closed. The server reads the directory only at startup, and live changes to the files are unspecified.
  - A plan file the server can't use is skipped with a warning; only an unusable directory stops the server. Two files holding the same plan are both skipped.
  - Every migration has a down, and `mybudget-server migrate` runs them either way. Some data may be lost between versions.
  - SQLite is bundled (`rusqlite`), so every device writes files with the same SQLite version.

## Left out on purpose

- Credit cards with a positive balance. YNAB treats that money as cash ("Inflow from Debt Account" in Ready to Assign); the draft doesn't.
- Loan accounts and YNAB's built-in Credit Card Interest category.
- Payees on individual subtransactions, and transfers inside a split.
- Importing and matching bank transactions, payee locations, money-movement history, undo, delta sync, ordering of categories and groups, month notes, and most of YNAB's target types.

Possible sections after 18: moving money between categories in one request, ordering categories and groups, month notes, bulk import with an `import_id` so a transaction imported twice is entered once, delta sync for the app, and the items above.

## Open questions for the human

Settle these before pasting sections 17 and 18. Nothing earlier depends on them.

1. **When does a target start?** The draft applies a target to every month, including months before it was set. YNAB targets start in a given month and can be snoozed. An option is a `start_month` field, defaulting to the month the target was set ("this month" from `MYBUDGET_TODAY`).
2. **What does a `by_date` target do after its month?** The draft says it needs nothing more. YNAB can repeat it, for example yearly.
3. **Do targets count spending?** The draft's `set_aside` ignores spending and `refill` looks only at the carried-over balance. That matches YNAB's "Set aside another" and "Refill up to". YNAB's "Have a balance of" also counts this month's spending; the draft has no such target.
4. **Age of Money details.** YNAB describes it as the average age of the last ten cash outflows, card payments included, transfers and starting balances excluded, but doesn't publish the algorithm. The draft's first-in, first-out queue is the usual reading. Rounding, split lines counted separately, and outflows made before any income are guesses.

## How YNAB keeps its books

These are the rules the draft copies.

- Money in cash accounts (checking, savings, cash) arrives in Ready to Assign. You assign it to categories, month by month. Tracking accounts (investments, other assets and debts) don't take part.
- Each category has Assigned, Activity and Available every month. A positive Available carries into next month; a negative one doesn't, and the category starts next month at 0.
- Spending more cash than a category had is cash overspending. It comes out of next month's Ready to Assign. Spending more on a credit card than the category had is credit overspending, which becomes card debt instead. A category overspent both ways spends its own money on the cash spending first.
- Each credit card has a payment category. Card spending a category covers moves that money into the payment category. Payments take money out of it, and refunds move money back to the spending category. A cash advance (card to checking) adds to Ready to Assign without touching the payment category. A card's starting debt, statement credits and balance adjustments only change what's owed. To pay off old debt, you assign money to the payment category.
- Money assigned in a future month comes out of this month's Ready to Assign, as Assigned in Future. A later month's income covers that month's assignments first. If you assign more than you have, the month that runs out shows a negative Ready to Assign, not the months before it.
- A transfer between two on-budget accounts, or two tracking accounts, has no category. A transfer between an on-budget account and a tracking account moves money into or out of the plan, so its on-budget side needs a category.
- Splits spread one payment over categories. Cleared and reconciled statuses track agreement with the bank, and reconciling adds an adjustment for any difference. Scheduled transactions are entered when they fall due, unapproved. Amounts are milliunits (1000 is one unit of currency).

Sources:
- https://pypi.org/project/ynab/: the Python client, version 4.4.1, built from API spec 1.86.0.
- https://api.ynab.com/ and its OpenAPI spec, version 1.88.0, at https://api.ynab.com/papi/open_api_spec.yaml
- YNAB support articles at `https://support.ynab.com/en_us/<slug>`. Mainly:
  - Ready to Assign and months: `the-plan-header-BkmiuJ_C9`, `assigning-future-income-an-overview-BJsTo0jCq`, `when-ready-to-assign-is-negative-an-overview-HylZA0zCc`, `overspending-and-the-monthly-rollover-S1ySgcLSMx`.
  - Credit cards: `credit-cards-funded-spending-By7XIs8HMg`, `credit-card-overspending-an-overview-HkMGpSbJs`, `credit-card-refunds-and-returns-H1J7qDWkj`, `credit-card-cash-advances-an-overview-Hy6PmlOC9`, `credit-card-rewards-and-statement-credits-a-guide-ryoRzYY0q`, `credit-cards-with-a-positive-balance-an-overview-By_H6uzJo`.
  - Transactions, accounts and categories: `transfer-transactions-a-guide-HJOsZz4Jj`, `split-transactions-a-guide-SJLEKwY0q`, `reconciling-accounts-a-guide-BJFE3fHys`, `balance-adjustments-a-guide-rko4OwILs`, `how-to-close-or-delete-an-account-in-ynab-ry_409Gko`, `adding-removing-and-customizing-categories-a-guide-HJFO5j909`, `scheduled-transactions-a-guide-BygrAIFA9`.
  - Targets and Age of Money: `how-to-use-targets-rk5kkI9ks`, `underfunded-a-guide-BJwPhQO09`, `age-of-money-H1ZS84W1s`.

## How the examples were checked

The numbers in the examples in 11.8, 12.7, 13.3, 17.2 and 18.3 were checked against a small Python model of sections 11 and 12. The model also reproduced YNAB's documented cases:

- assigning ahead with nothing left to assign (the later month goes negative, not the current one)
- new income covering an over-assignment
- overspending this month leaving this month's Ready to Assign alone
- a cash advance
- two cards sharing an underfunded category
- cash and credit overspending in one category
- overpaying a card
- a statement credit
- money coming in from a tracking account

The model isn't in the repo, because the agents can read `spec/`. With a reference implementation, the implementer could skip the spec, and ambiguities the tester should surface would stay hidden. If you change sections 11 or 12, recheck those examples by hand or with a fresh model kept outside the repo. The recurrence dates in 16.4 and 16.5 were generated the same way.

## Appendix: draft sections 14 and 16 to 18

Paste-ready text for the later rounds. Each round pastes its sections from here into `SPEC.md`, without the four-backtick fence around them. Sections 17 and 18 wait for the open questions above.

````markdown
## 14. Reconciliation

14.1 `POST /plans/{plan_id}/accounts/{account_id}/reconcile` with `balance`, an amount, and `date` reconciles the account to the cleared balance its bank reports. It returns the account and the adjustment it made, or `null` if it made none.

14.2 If `balance` differs from the account's `cleared_balance`, the server first adds an adjustment: amount `balance` - `cleared_balance`, dated `date`, payee `Reconciliation Balance Adjustment` (found or created as in 6.5), memo `null`, `cleared` `"reconciled"`, `approved` true, no flag. Its category is `ready_to_assign` in an on-budget account; in a tracking account it has none.

14.3 Then every transaction in the account whose `cleared` is `"cleared"` becomes `"reconciled"`.

```
POST /plans/PLAN_ID/accounts/CHECKING_ID/reconcile
{"balance": 2375500, "date": "2026-10-31"}
→ 200
{"account": {"id": "CHECKING_ID", "name": "Checking", "type": "checking", "on_budget": true,
             "closed": false, "note": null, "balance": 2340500, "cleared_balance": 2375500,
             "uncleared_balance": -35000, "transfer_payee_id": "CHECKING_PAYEE_ID",
             "payment_category_id": null},
 "adjustment": {"id": "ADJUSTMENT_ID", "account_id": "CHECKING_ID", "date": "2026-10-31",
                "amount": -4500, "payee_id": "ADJUSTMENT_PAYEE_ID", "category_id": "ready_to_assign",
                "memo": null, "cleared": "reconciled", "approved": true, "flag_color": null,
                "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}}
```

(Before this, Checking had its 2500.00 starting balance, a cleared -120.00 and an uncleared -35.00.)

## 16. Scheduled transactions

16.1 Today is the date in the environment variable `MYBUDGET_TODAY` (`YYYY-MM-DD`) if it is set, and otherwise the current date in the server's local time zone.

16.2 `POST /plans/{plan_id}/scheduled_transactions` creates a scheduled transaction from `account_id`, `date`, `amount` (all required), `frequency` (default `"never"`), `payee_id` or `payee_name` (6.5), `category_id`, `memo` and `flag_color`, which follow 8.1, 8.2 and 9.3. It has no subtransactions. `date` must be after today and no more than five years after it: on or before the same month and day five years later, or 28 February when that day doesn't exist. Otherwise the request returns 400.

```
(server started with MYBUDGET_TODAY=2026-10-30)
POST /plans/PLAN_ID/scheduled_transactions
{"account_id": "CHECKING_ID", "date": "2026-10-31", "frequency": "monthly", "amount": -1200000,
 "payee_name": "Landlord", "category_id": "RENT_ID"}
→ 201
{"id": "RENT_SCHEDULE_ID", "account_id": "CHECKING_ID", "date_first": "2026-10-31",
 "date_next": "2026-10-31", "frequency": "monthly", "amount": -1200000,
 "payee_id": "LANDLORD_ID", "category_id": "RENT_ID", "memo": null, "flag_color": null,
 "transfer_account_id": null}
```

16.3 `GET /plans/{plan_id}/scheduled_transactions` lists them by `date_next`, then oldest first; `GET .../scheduled_transactions/{id}` returns one. `PATCH` on one can change every field 16.2 takes except `account_id` (400 if different). A `PATCH` with `date` or `frequency` restarts the schedule: `date_first` and `date_next` both become the new `date`, or the current `date_next` if there's no new `date`. `DELETE` deletes one.

```
(server started with MYBUDGET_TODAY=2026-10-30; GYM_SCHEDULE_ID is a monthly schedule)
PATCH /plans/PLAN_ID/scheduled_transactions/GYM_SCHEDULE_ID
{"date": "2026-11-05"}
→ 200
{"id": "GYM_SCHEDULE_ID", "account_id": "CHECKING_ID", "date_first": "2026-11-05",
 "date_next": "2026-11-05", "frequency": "monthly", "amount": -45000,
 "payee_id": "GYM_ID", "category_id": "FITNESS_ID", "memo": null, "flag_color": null,
 "transfer_account_id": null}

DELETE /plans/PLAN_ID/scheduled_transactions/GYM_SCHEDULE_ID
→ 204
```

16.4 `frequency` is one of the values below. A schedule's occurrences start at `date_first`:

- `never`: only `date_first`.
- `daily`, `weekly`, `everyOtherWeek`, `every4Weeks`: every 1, 7, 14 or 28 days.
- `monthly`, `everyOtherMonth`, `every3Months`, `every4Months`, `twiceAYear`, `yearly`, `everyOtherYear`: every 1, 2, 3, 4, 6, 12 or 24 months, on `date_first`'s day of the month, or the month's last day when it is shorter.
- `twiceAMonth`: in every month from `date_first`'s on, on `date_first`'s day of the month (or the month's last day when it is shorter), and again 15 days after that day.

There are no occurrences after `2999-12-31`.

```
monthly      from 2027-01-31: 2027-01-31, 2027-02-28, 2027-03-31, 2027-04-30
twiceAMonth  from 2026-11-20: 2026-11-20, 2026-12-05, 2026-12-20, 2027-01-04
twiceAMonth  from 2027-01-31: 2027-01-31, 2027-02-15, 2027-02-28, 2027-03-15
every4Weeks  from 2026-11-02: 2026-11-02, 2026-11-30, 2026-12-28, 2027-01-25
yearly       from 2028-02-29: 2028-02-29, 2029-02-28, 2030-02-28, 2031-02-28
```

16.5 Before handling each request, the server enters every scheduled transaction whose `date_next` is on or before today, oldest schedule first. If the schedule's account is open, entering creates a transaction as `POST /plans/{plan_id}/transactions` would from the schedule's fields, dated `date_next`, with `approved` false and the default `cleared` (a transfer gets its other half as in 9.1). Then `date_next` moves to the next occurrence; a schedule with none left is deleted. This repeats until `date_next` is after today. While the account is closed, occurrences pass without creating transactions.

```
(the server from 16.2 restarted with MYBUDGET_TODAY=2026-12-01 and the same MYBUDGET_DATA)
GET /plans/PLAN_ID/transactions?payee_id=LANDLORD_ID
→ 200
[{"id": "OCT_RENT_ID", "account_id": "CHECKING_ID", "date": "2026-10-31", "amount": -1200000,
  "payee_id": "LANDLORD_ID", "category_id": "RENT_ID", "memo": null,
  "cleared": "uncleared", "approved": false, "flag_color": null,
  "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []},
 {"id": "NOV_RENT_ID", "account_id": "CHECKING_ID", "date": "2026-11-30", "amount": -1200000,
  "payee_id": "LANDLORD_ID", "category_id": "RENT_ID", "memo": null,
  "cleared": "uncleared", "approved": false, "flag_color": null,
  "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}]

GET /plans/PLAN_ID/scheduled_transactions/RENT_SCHEDULE_ID
→ 200
{"id": "RENT_SCHEDULE_ID", "account_id": "CHECKING_ID", "date_first": "2026-10-31",
 "date_next": "2026-12-31", "frequency": "monthly", "amount": -1200000,
 "payee_id": "LANDLORD_ID", "category_id": "RENT_ID", "memo": null, "flag_color": null,
 "transfer_account_id": null}
```

16.6 Deleting an account (5.9) also deletes the scheduled transactions in it and those that transfer to it. A payee that a scheduled transaction uses counts as in use (6.4), and a category that one uses counts as used (13.2) and is reassigned along with transactions (13.3).

<!-- DRAFT: settle the open questions in spec/ROADMAP.md before pasting sections 17 and 18, and don't paste this comment. -->

## 17. Targets

17.1 Every category has a `target`, `null` until set. `PATCH /plans/{plan_id}/categories/{category_id}` with `target` sets it, and `null` removes it. Setting one on a payment category returns 400. A target is one of:

- `{"type": "monthly", "amount": <amount>, "behavior": "set_aside"}`: assign this much every month.
- `{"type": "monthly", "amount": <amount>, "behavior": "refill"}`: top the category up to this much every month.
- `{"type": "by_date", "amount": <amount>, "month": "<month>"}`: have this much available by the end of that month.

The amount must be positive. A target is returned with exactly its type's fields.

```
PATCH /plans/PLAN_ID/categories/GROCERIES_ID
{"target": {"type": "monthly", "amount": 400000, "behavior": "refill"}}
→ 200
{"id": "GROCERIES_ID", "group_id": "EVERYDAY_ID", "name": "Groceries", "hidden": false, "note": null,
 "payment_account_id": null, "target": {"type": "monthly", "amount": 400000, "behavior": "refill"}}
```

17.2 Each month entry (11.3) gets `underfunded`: `null` without a target, otherwise how much more to assign that month. With carryover as in 11.4:

- `set_aside`: max(0, amount - `assigned`).
- `refill`: max(0, amount - carryover - `assigned`).
- `by_date`, up to and including its month: with n the number of months from this month to the target month inclusive, max(0, ceil(max(0, amount - carryover) / n) - `assigned`), rounding up to a whole milliunit. After its month: 0.

With 17.1's target on Groceries in 11.8's plan, October's entry has `"underfunded": 0`, and November's has 120000: 400000, less 280000 carried over and 0 assigned.

```
GET /plans/PLAN_ID/months/2026-11/categories/GROCERIES_ID
→ 200
{"category_id": "GROCERIES_ID", "assigned": 0, "activity": 0, "available": 280000,
 "cash_overspending": 0, "credit_overspending": 0, "underfunded": 120000}
```

A `by_date` target of 600000 for `2027-03` asks 100000 of October (600000 over 6 months). If October assigns that and nothing is spent, November's `underfunded` is 500000 over 5 months, 100000.

17.3 Each month (11.6) gets `underfunded`: the sum of its categories' `underfunded`, counting `null` as 0.

## 18. Age of Money

18.1 Money in is every line in a cash account with a positive amount, except the half of a transfer from another cash account. Money out is every line in a cash account with a negative amount, except the half of a transfer to another cash account and a starting balance (5.3).

18.2 Money in and money out are taken in date order, money in first within a date, then oldest first. Each money in joins the back of a queue. Each money out takes its size from the front of the queue, partly using up a money in if it needs to. Its age is the average, weighted by amount, of the days from each money in it took from to its own date, rounded down. Any part it can't take because the queue is empty is ignored, and a money out that took nothing has no age.

18.3 Each month (11.6) gets `age_of_money`: the average of the ages of the last 10 money outs with an age dated on or before the month's last day, rounded down; `null` if there are fewer than 10.

Example: Checking starts with 1000.00 on 2026-09-01, gets 1000.00 of income on 2026-10-01, and spends 100.00 on each day from 2026-10-01 to 2026-10-10. All ten come out of September's 1000.00, aged 30 to 39 days, so October's `age_of_money` is `34` (34.5 rounded down) and September's is `null`.
````
