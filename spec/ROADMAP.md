# Roadmap: the remaining rounds

This is for the agent that resumes the work. The goal is a server that replicates YNAB's core budgeting, specified in `SPEC.md` and built one round at a time by the tester and implementer (see `README.md` for how rounds work). Sections 3 to 18 were drafted together from research into YNAB; this file holds the plan for the rounds still to run, the rules for running them, and the draft text of the sections not yet in `SPEC.md`.

## Where things stand (2026-10-31)

- Work is on the superproject branch `ynab-spec`, which the human hasn't merged into `main` yet. `lane.sh` commits inside the submodules on their own `main` branches. Don't push, or merge into `main`, without asking the human.
- **Round 1 (sections 3 and 4) is complete.** The judge passed 103 of 103 tests at superproject commit `9911cc4` (testsuite `254acec`, server `7dd56c5`).
- **Round 2 (sections 5 to 7) is green but not finished.** The judge passed 310 of 310 tests at superproject commit `32beace` (testsuite `069da03`, server `ff57440`). The tester's first attack was cut off by a usage limit and committed nothing. The next step is to rerun `round.sh` with run 2's task (the 3.6/5.2 ruling below), adding that the implementation already passes every test, so the tester goes straight to attacking.

## How to run a round

1. If the round's sections aren't in `SPEC.md` yet, re-read them against the checklist below, then paste them from the appendix in place of the `<!-- Next: ... -->` comment at the end of `SPEC.md`, and add a new comment naming the round after.
2. Commit. `lane.sh` refuses to start with uncommitted changes.
3. From the superproject root, start the round in the background with the Mac kept awake (round 1 lost a night to sleep):
   `caffeinate -i scripts/round.sh "<task>" > <log file> 2>&1`
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

Round 1 took four runs of `round.sh`, and each stopped on a tester question about an edge case: lone surrogates, oversized or deeply nested JSON, percent-encoded paths, `HEAD`, and malformed HTTP. Its last attack found nothing new, so a judge run after the last ruling finished it. Expect the same pattern: the tester reads the server code and probes every corner.

`scripts/test.sh` stops at the first test binary that fails; pass `--no-fail-fast` to see every result. The judge runs each test separately, so it isn't affected.

### Checklist before pasting a round's sections

Round 1's questions came from gaps like these. Fixing them before pasting saves a stopped round each.

- Every endpoint has an example, and every number in an example agrees with the clause's formulas.
- For each `PATCH`: which fields can change, whether a field it can't change is ignored (3.6) or rejected because the change is never allowed (3.4), and what a `PATCH` that sets a field to its current value does.
- For each request field: required or optional, nullable or not (3.10), and its format. 3.7 to 3.9 define amounts, dates and names.
- References to sections that aren't pasted yet: reword them, or keep the tester off them in the task.
- Behaviour that changes from an earlier round: say so in the task, so the tester updates its older tests. Known cases: section 13 defines `DELETE` on a category (405 until then); 16.6 extends 5.9 and 6.4; section 17 adds `target` to categories and `underfunded` to month entries; section 18 adds `age_of_money` to months.

## Rulings so far

| Commit | Clause | Ruling |
| --- | --- | --- |
| `bed976b` | 3.1 | A string with an escaped lone surrogate (`"a\ud800b"`) makes the body invalid JSON (400). |
| `7d7a025` | 3.13, 3.2 | The server may refuse a body over 1 MiB with a JSON `413`, before any other check, and with `400` nesting deeper than 64 or a number too large for a 64-bit float. Within those limits, ignored fields may hold any JSON. |
| `2ac308f` | 3.5 | Ids use only ASCII letters, digits, `-` and `_`. Clients never percent-encode paths, so what the server does with a percent-encoded path is unspecified. |
| `9911cc4` | 3.2, 3.4 | `HEAD` works wherever `GET` does, with no body. What the server does with malformed HTTP is unspecified. |
| This file's commit | 5 to 7 | Changes made before the round, not rulings: `starting_date` is unused when `starting_balance` is 0; a `PATCH` with a different account `type` returns 400; a `PATCH` naming a category's own group doesn't move it; examples added for 5.6, 6.3, 6.4, 7.4 and 7.6. |
| `6d0ec8f` | 3.6, 3.7, 5.2, 6.5 | A field the endpoint defines is checked whenever it's present, even when another field leaves it unused: `starting_date` (not nullable) when `starting_balance` is 0, and `payee_name` (a payee name or `null`) when `payee_id` is given. `-0` is an integer meaning 0. |

## The rounds

| Round | Sections | Task for `round.sh` | Notes |
| --- | --- | --- | --- |
| 2 | 5 to 7, already in `SPEC.md` | `SPEC sections 5 to 7 (accounts, payees, categories)` | 3.7 and 3.8 become testable through `starting_balance` and `starting_date`. Starting-balance transactions only show through balances and payees until round 3. |
| 3 | 8 to 10 | `SPEC sections 8 to 10 (transactions, transfers, splits)` | These refer to each other, so they go in together. It's the largest round; consider `MAX_FIXES=8`. |
| 4 | 11 | `SPEC section 11 (months and Ready to Assign), for plans without credit accounts; section 12 covers those next round` | 11 refers ahead to 12 for the credit fields, so the task keeps the tester to cash accounts. |
| 5 | 12 | `SPEC section 12 (credit cards)` | The hardest maths. Check 12.2 to 12.5 and the example in 12.7 before pasting. |
| 6 | 13 | `SPEC section 13 (deleting categories). DELETE on a category returned 405 until now.` | |
| 7 | 14 | `SPEC section 14 (reconciliation)` | |
| 8 | 15 | `SPEC section 15 (persistence)` | The tester will extend `Server` to pass env vars and restart on the same data directory. The judge's per-test scratch folder (`TMPDIR`) is writable. |
| 9 | 16 | `SPEC section 16 (scheduled transactions)` | Needs 15: a test moves "today" by restarting with a new `MYBUDGET_TODAY`. Tests should always set it. |
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

## Appendix: draft sections 8 to 18

Paste-ready text for the later rounds. Each round pastes its sections from here into `SPEC.md`, without the four-backtick fence around them. Sections 17 and 18 wait for the open questions above.

````markdown
## 8. Transactions

8.1 `POST /plans/{plan_id}/transactions` creates a transaction from:

- `account_id`, `date` and `amount`: required.
- `payee_id`, nullable, or `payee_name` (6.5): optional; without either, the transaction has no payee.
- `category_id`, nullable: see 8.2.
- `memo`, nullable: default `null`.
- `cleared`: `"uncleared"`, `"cleared"` or `"reconciled"`. The default is `"cleared"` in an account whose `type` is `"cash"` (money in a wallet clears at once) and `"uncleared"` in any other.
- `approved`: a boolean, default true.
- `flag_color`, nullable: `"red"`, `"orange"`, `"yellow"`, `"green"`, `"blue"` or `"purple"`; default `null`.
- `subtransactions`: see section 10.

```
POST /plans/PLAN_ID/transactions
{"account_id": "CHECKING_ID", "date": "2026-10-04", "amount": -120000,
 "payee_name": "Corner Shop", "category_id": "GROCERIES_ID", "memo": "weekly shop"}
→ 201
{"id": "SHOP_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-04", "amount": -120000,
 "payee_id": "CORNER_SHOP_ID", "category_id": "GROCERIES_ID", "memo": "weekly shop",
 "cleared": "uncleared", "approved": true, "flag_color": null,
 "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}
```

8.2 For a transaction that is neither a transfer (section 9) nor a split (section 10), `category_id` depends on the account:

- In an on-budget account it is required: a user category's id, or `ready_to_assign`. In a cash account, `ready_to_assign` marks income. In a credit account it marks a change in what's owed that doesn't touch the plan, such as a statement credit.
- In a tracking account it must be `null` or absent.

A payment category's id is never allowed. Anything else returns 400.

```
POST /plans/PLAN_ID/transactions
{"account_id": "CHECKING_ID", "date": "2026-10-15", "amount": 1800000, "payee_name": "Employer",
 "category_id": "ready_to_assign"}
→ 201
{"id": "PAY_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-15", "amount": 1800000,
 "payee_id": "EMPLOYER_ID", "category_id": "ready_to_assign", "memo": null,
 "cleared": "uncleared", "approved": true, "flag_color": null,
 "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}
```

8.3 A transaction whose payee is a transfer payee is a transfer, and section 9 applies to it.

8.4 `GET /plans/{plan_id}/transactions/{transaction_id}` returns a transaction.

8.5 `GET /plans/{plan_id}/transactions` lists the plan's transactions by date, and oldest first within a date. These query parameters filter it, and combine:

- `account_id`, `payee_id`: transactions with that account or payee.
- `category_id`: transactions with that category, or with a subtransaction that has it.
- `since_date`, `until_date`: transactions dated on or after, or on or before, that date.
- `approved`: `true` or `false`.

An id that matches nothing gives an empty list. A malformed date, or an `approved` other than `true` or `false`, returns 400.

```
GET /plans/PLAN_ID/transactions?account_id=CHECKING_ID&since_date=2026-10-02&until_date=2026-10-10
→ 200
[{"id": "SHOP_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-04", "amount": -120000,
  "payee_id": "CORNER_SHOP_ID", "category_id": "GROCERIES_ID", "memo": "weekly shop",
  "cleared": "uncleared", "approved": true, "flag_color": null,
  "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}]
```

8.6 `PATCH /plans/{plan_id}/transactions/{transaction_id}` can change any field in 8.1 except `account_id`; an `account_id` different from the transaction's returns 400. The changed transaction must meet every rule a new one must (8.2, sections 9 and 10); if it doesn't, the request returns 400.

```
PATCH /plans/PLAN_ID/transactions/SHOP_TXN_ID
{"cleared": "cleared", "flag_color": "green"}
→ 200
{"id": "SHOP_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-04", "amount": -120000,
 "payee_id": "CORNER_SHOP_ID", "category_id": "GROCERIES_ID", "memo": "weekly shop",
 "cleared": "cleared", "approved": true, "flag_color": "green",
 "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}
```

8.7 `DELETE /plans/{plan_id}/transactions/{transaction_id}` deletes a transaction.

```
DELETE /plans/PLAN_ID/transactions/SHOP_TXN_ID
→ 204
```

## 9. Transfers

9.1 A transaction in account A whose payee is account B's transfer payee is a transfer from A to B. Creating it also creates its other half in B, after it: same date, opposite amount, A's transfer payee, same memo, `cleared` defaulting as 8.1 says for B, `approved` true and no flag. Each half's `transfer_account_id` is the other half's account, and its `transfer_transaction_id` is the other half's id. Both are `null` on transactions that aren't transfers.

```
POST /plans/PLAN_ID/transactions
{"account_id": "CHECKING_ID", "date": "2026-10-05", "amount": -500000, "payee_id": "SAVINGS_PAYEE_ID"}
→ 201
{"id": "OUT_ID", "account_id": "CHECKING_ID", "date": "2026-10-05", "amount": -500000,
 "payee_id": "SAVINGS_PAYEE_ID", "category_id": null, "memo": null,
 "cleared": "uncleared", "approved": true, "flag_color": null,
 "transfer_account_id": "SAVINGS_ID", "transfer_transaction_id": "IN_ID", "subtransactions": []}

GET /plans/PLAN_ID/transactions/IN_ID
→ 200
{"id": "IN_ID", "account_id": "SAVINGS_ID", "date": "2026-10-05", "amount": 500000,
 "payee_id": "CHECKING_PAYEE_ID", "category_id": null, "memo": null,
 "cleared": "uncleared", "approved": true, "flag_color": null,
 "transfer_account_id": "CHECKING_ID", "transfer_transaction_id": "OUT_ID", "subtransactions": []}
```

9.2 A transfer from an account to itself returns 400, and so does a transfer with subtransactions.

9.3 Categories on transfers:

- Between two on-budget accounts, or two tracking accounts, neither half has a category, and a non-null `category_id` returns 400.
- Between an on-budget account and a tracking account, money enters or leaves the plan. The on-budget half follows 8.2 for its account, so it needs a category, and the tracking half has none. The request's `category_id` sets the on-budget half's category, whichever half the request is for.

9.4 Changing `date` or `amount` on either half changes the other to match: the same date and the opposite amount. `memo`, `cleared`, `approved` and `flag_color` belong to the half they're set on.

9.5 Changing a transfer's payee to one that isn't a transfer payee, or to `null`, deletes the other half. Changing it to another account's transfer payee deletes the other half and creates a new one in that account. Changing an ordinary transaction's payee to a transfer payee creates the other half. 8.6 applies to the result: for example, a cash account's half left without a transfer needs a category in the same request.

9.6 Deleting either half deletes both.

## 10. Split transactions

10.1 A transaction with a non-empty `subtransactions` array is a split. Each subtransaction has a required `amount` and a nullable `category_id` and `memo`, both defaulting to `null`. The subtransactions' amounts must add up to the transaction's amount, and the transaction's own `category_id` must be `null` or absent; otherwise 400.

```
POST /plans/PLAN_ID/transactions
{"account_id": "CHECKING_ID", "date": "2026-10-06", "amount": -90000, "payee_name": "Megastore",
 "subtransactions": [{"amount": -60000, "category_id": "GROCERIES_ID"},
                     {"amount": -30000, "category_id": "HOUSEHOLD_ID", "memo": "light bulbs"}]}
→ 201
{"id": "SPLIT_ID", "account_id": "CHECKING_ID", "date": "2026-10-06", "amount": -90000,
 "payee_id": "MEGASTORE_ID", "category_id": null, "memo": null,
 "cleared": "uncleared", "approved": true, "flag_color": null,
 "transfer_account_id": null, "transfer_transaction_id": null,
 "subtransactions": [{"amount": -60000, "category_id": "GROCERIES_ID", "memo": null},
                     {"amount": -30000, "category_id": "HOUSEHOLD_ID", "memo": "light bulbs"}]}
```

10.2 Each subtransaction's `category_id` follows 8.2 for the transaction's account. Splits aren't allowed in tracking accounts (400).

10.3 Responses list subtransactions in the order they were given, each with `amount`, `category_id` and `memo`. A transaction that isn't a split has `"subtransactions": []`.

10.4 A `PATCH` with `subtransactions` replaces all of them. An empty array makes the transaction an ordinary one again. 8.6 applies: for example, changing a split's `amount` without matching subtransactions returns 400.

## 11. Months and Ready to Assign

Every month, the plan's money is either assigned to categories or Ready to Assign. This section covers cash accounts; section 12 adds credit accounts.

11.1 A line is a transaction in an on-budget account that isn't a split, or one subtransaction of a split in an on-budget account. A line has its transaction's account and date. Only lines affect the plan; transactions in tracking accounts never do.

11.2 Each category has an assigned amount for every month, 0 until set. `PATCH /plans/{plan_id}/months/{month}/categories/{category_id}` with `assigned` sets it, for a user or a payment category. It may be negative. The response is the category's month entry (11.3). `ready_to_assign` isn't a category here: that path returns 404.

```
PATCH /plans/PLAN_ID/months/2026-10/categories/GROCERIES_ID
{"assigned": 400000}
→ 200
{"category_id": "GROCERIES_ID", "assigned": 400000, "activity": 0, "available": 400000,
 "cash_overspending": 0, "credit_overspending": 0}
```

11.3 `GET /plans/{plan_id}/months/{month}/categories/{category_id}` returns a category's month entry. `activity` is the sum of the amounts of the month's lines with that category (a payment category's activity is in 12.4); `available` is in 11.4, and the overspending fields in 11.5.

11.4 `available` = carryover + `assigned` + `activity`, where carryover is the previous month's `available` if that is positive, and 0 otherwise. Money left in a category rolls into the next month, and an overspent category starts the next month at 0. Before `1900-01` everything is 0.

11.5 A category is overspent when its `available` is negative. `credit_overspending` is the part spent on credit (12.3); it is 0 for a category with no spending in credit accounts that month. `cash_overspending` is the rest: max(0, -`available`) - `credit_overspending`.

11.6 `GET /plans/{plan_id}/months/{month}` returns the month:

- `income`: the sum of the amounts of the month's lines in cash accounts categorized to `ready_to_assign`.
- `cash_advances`: see 12.5; 0 without credit accounts.
- `assigned`: the sum of every category's `assigned` for the month.
- `activity`: the sum of every user category's `activity` for the month.
- `cash_overspending_last_month`: the sum of every category's `cash_overspending` in the previous month.
- `left_over_from_last_month`, `assigned_in_future` and `ready_to_assign`: see 11.7.
- `categories`: every category's month entry, in the order of 7.1.

11.7 For each month M, let net(M) be `income` + `cash_advances` - `assigned` for M. Then:

- `left_over_from_last_month` is the sum of net over every month before M, minus the sum of `cash_overspending_last_month` over every month before M.
- pool(M) is `left_over_from_last_month` + net(M) - `cash_overspending_last_month`.
- shortfall(M) is how far later assignments outrun later money at worst: the largest value of -(net(M+1) + ... + net(L)) over every month L after M, or 0 if none is positive.
- If pool(M) is negative, `assigned_in_future` is 0 and `ready_to_assign` is pool(M). Otherwise `assigned_in_future` is the smaller of pool(M) and shortfall(M), and `ready_to_assign` is pool(M) - `assigned_in_future`.

So `ready_to_assign` = `left_over_from_last_month` + `income` + `cash_advances` - `cash_overspending_last_month` - `assigned` - `assigned_in_future`. Cash overspending comes out of the following month. Money is only ready in a month if no later month needs it, and a month whose own pool is positive never shows a negative Ready to Assign because of later months; the later month does.

11.8 Example. Checking is created with a starting balance of 3000.00 on 2026-10-01. The group Everyday holds Groceries, Rent and Dining, created in that order. October assigns 400.00 to Groceries, 1200.00 to Rent and 50.00 to Dining, and November assigns 1200.00 to Rent. Checking spends 120.00 on Groceries on 2026-10-04 and 80.00 on Dining on 2026-10-11.

```
GET /plans/PLAN_ID/months/2026-10
→ 200
{"month": "2026-10", "income": 3000000, "cash_advances": 0, "assigned": 1650000,
 "activity": -200000, "cash_overspending_last_month": 0, "left_over_from_last_month": 0,
 "assigned_in_future": 1200000, "ready_to_assign": 150000,
 "categories": [
  {"category_id": "GROCERIES_ID", "assigned": 400000, "activity": -120000, "available": 280000,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "RENT_ID", "assigned": 1200000, "activity": 0, "available": 1200000,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "DINING_ID", "assigned": 50000, "activity": -80000, "available": -30000,
   "cash_overspending": 30000, "credit_overspending": 0}]}

GET /plans/PLAN_ID/months/2026-11
→ 200
{"month": "2026-11", "income": 0, "cash_advances": 0, "assigned": 1200000,
 "activity": 0, "cash_overspending_last_month": 30000, "left_over_from_last_month": 1350000,
 "assigned_in_future": 0, "ready_to_assign": 120000,
 "categories": [
  {"category_id": "GROCERIES_ID", "assigned": 0, "activity": 0, "available": 280000,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "RENT_ID", "assigned": 1200000, "activity": 0, "available": 2400000,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "DINING_ID", "assigned": 0, "activity": 0, "available": 0,
   "cash_overspending": 0, "credit_overspending": 0}]}
```

## 12. Credit cards

When you spend on a credit card from a category that has the money, that money moves to the card's payment category, ready to pay the bill. Spending beyond what the category has becomes debt instead.

12.1 A payment category's month entry follows 11.2 to 11.5, with its `activity` from 12.4 and a `credit_overspending` of 0.

12.2 For a user category C in a month, and each credit account K, let net(K) be the sum of the amounts of the month's lines in K with category C. K's spending is max(0, -net(K)) and its refund is max(0, net(K)). C's funds are its carryover (11.4) + its `assigned` + the amounts of the month's lines in cash accounts with category C + all the credit accounts' refunds. The funded amount is the smaller of the total spending and max(0, funds). It goes to the credit accounts in the order they were created, each taking the smaller of its spending and what is left.

12.3 C's `credit_overspending` is its total spending minus its funded amount. (Its `cash_overspending` then works out as max(0, -funds): cash spending uses a category's money first.)

12.4 A payment category's `activity` for a month is, for its account K: the amounts funded to K (12.2) from every user category, minus K's refunds in every user category, minus the payments into K (12.5).

12.5 In a transfer between a cash account and a credit account, the credit account's half decides what happens. A positive half is a payment: its amount comes off the payment category (12.4). A negative half is a cash advance: its size counts in the month's `cash_advances`, so it adds to Ready to Assign.

12.6 Lines in a credit account categorized to `ready_to_assign`, and transfers between two credit accounts or between two cash accounts, change no category and don't change Ready to Assign.

12.7 Example. Checking starts with 1000.00 and Visa (a credit card) with -200.00, both on 2026-10-01; Visa's starting balance changes nothing in the plan (12.6). October assigns 300.00 to Groceries and 200.00 to Visa's payment category. Visa spends 100.00 on Groceries on 2026-10-05 and 250.00 on 2026-10-09. Checking pays Visa 200.00 on 2026-10-20 (a transfer). On 2026-11-03, Visa gets a 30.00 refund categorized to Groceries.

```
GET /plans/PLAN_ID/months/2026-10
→ 200
{"month": "2026-10", "income": 1000000, "cash_advances": 0, "assigned": 500000,
 "activity": -350000, "cash_overspending_last_month": 0, "left_over_from_last_month": 0,
 "assigned_in_future": 0, "ready_to_assign": 500000,
 "categories": [
  {"category_id": "VISA_PAYMENT_ID", "assigned": 200000, "activity": 100000, "available": 300000,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "GROCERIES_ID", "assigned": 300000, "activity": -350000, "available": -50000,
   "cash_overspending": 0, "credit_overspending": 50000}]}

GET /plans/PLAN_ID/months/2026-11
→ 200
{"month": "2026-11", "income": 0, "cash_advances": 0, "assigned": 0,
 "activity": 30000, "cash_overspending_last_month": 0, "left_over_from_last_month": 500000,
 "assigned_in_future": 0, "ready_to_assign": 500000,
 "categories": [
  {"category_id": "VISA_PAYMENT_ID", "assigned": 0, "activity": -30000, "available": 270000,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "GROCERIES_ID", "assigned": 0, "activity": 30000, "available": 30000,
   "cash_overspending": 0, "credit_overspending": 0}]}
```

Visa now owes 320.00 and its payment category holds 270.00: the 50.00 of October's credit overspending is new debt, not a deduction from Ready to Assign.

## 13. Deleting categories

13.1 `DELETE /plans/{plan_id}/categories/{category_id}` deletes a user category. Deleting a payment category returns 400.

13.2 If any transaction or subtransaction has the category, the request needs the query parameter `reassign_to`; without it, it returns 409. `reassign_to` must be the id of another of the plan's user categories, or the request returns 400.

13.3 With `reassign_to`, every transaction and subtransaction that had the deleted category gets the `reassign_to` category, and for every month the deleted category's `assigned` is added to that category's. Without it, the deleted category's assigned amounts are dropped, which returns them to Ready to Assign.

```
DELETE /plans/PLAN_ID/categories/DINING_ID?reassign_to=GROCERIES_ID
→ 204

GET /plans/PLAN_ID/months/2026-10/categories/GROCERIES_ID
→ 200
{"category_id": "GROCERIES_ID", "assigned": 450000, "activity": -200000, "available": 250000,
 "cash_overspending": 0, "credit_overspending": 0}
```

(Applied to 11.8, November's `cash_overspending_last_month` becomes 0 and its `ready_to_assign` 150000.)

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

## 15. Persistence

15.1 When the environment variable `MYBUDGET_DATA` is set, it names a directory where the server keeps all its data, creating the directory if it doesn't exist. Without it, data lives only in memory and is lost when the server stops.

15.2 A server started with the same `MYBUDGET_DATA` as an earlier one serves the same data: the same ids, values and list orders. A change is saved before the response to the request that made it, so it survives the server being killed (`SIGKILL`) at any point afterwards.

```
(server started with MYBUDGET_DATA=<dir>)
POST /plans
{"name": "Household"}
→ 201
{"id": "PLAN_ID", "name": "Household", "currency_code": "USD"}

(server killed, then started again with the same MYBUDGET_DATA)
GET /plans
→ 200
[{"id": "PLAN_ID", "name": "Household", "currency_code": "USD"}]
```

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
