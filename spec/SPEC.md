# MyBudget server spec

This is the contract between the tester and the implementer. When an agent raises a `QUESTION:` or `DISPUTE:`, settle it by changing this file.

The scripts depend on two format rules:

- A requirement is a line that starts with its number, such as `2.1 `. Tests are named after these numbers (`spec_2_1_...`), and the judge reports failures to the implementer by number.
- An example under a requirement is part of it: tests may check anything the example shows. The implementer never sees the tests, so examples are how it learns exact formats. Give every endpoint at least one.

## 1. Process

1.1 The server binary is `mybudget-server`.

1.2 It listens on the address in the `MYBUDGET_ADDR` environment variable, `ip:port`, defaulting to `127.0.0.1:8080`. Port `0` means any free port.

1.3 Once it is listening, its first line on stdout is exactly `listening on <ip>:<port>`, giving the actual port. The judge checks this before running any tests.

1.4 When the environment variable `MYBUDGET_EXIT_ON_STDIN_EOF` is `1`, the server exits with status 0 within one second of its standard input reaching end of file, as it does when the process that started it closes its end of a pipe or dies. Anything it reads from standard input before then is ignored. This holds from the moment the server starts, including while it is still starting up, for example reading its data (section 15): if end of file comes before it is listening, it exits without printing 1.3's line. Standard input with nothing left to read, like `/dev/null`, an empty file, or a pipe or socket whose other end closed with nothing in it, is at end of file from the start. When something is left to read (a file with content, or data a pipe or socket still holds), end of file comes when the server's reads reach it, so it may print 1.3's line first. Until then it keeps running: only end of file ends it, and a read that finds nothing waiting, as on a non-blocking pipe or socket, isn't end of file. What it does if reading standard input fails in some other way isn't specified. This lets the macOS app, which runs the server as a child process, make sure the server never outlives it. With the variable unset or set to anything else, the server never reads its standard input, so end of file there changes nothing.

```
(server started with MYBUDGET_EXIT_ON_STDIN_EOF=1, its stdin a pipe)
(the other end of the pipe is closed)
→ the server exits with status 0

(server started without MYBUDGET_EXIT_ON_STDIN_EOF, its stdin /dev/null)
GET /health
→ 200
ok
```

## 2. Health

2.1 `GET /health` returns `200` with the body `ok`.

```
GET /health
→ 200
ok
```

2.2 A request to a path the API doesn't define returns `404`.

```
GET /no-such-path
→ 404
```

## 3. Conventions

3.1 Request and response bodies are JSON (UTF-8), except the body of `GET /health`'s `200` response. A response with a JSON body has the header `Content-Type: application/json`. Every `POST` and `PATCH` takes a JSON object as its body, and clients send it with `Content-Type: application/json`; a missing or empty body isn't valid JSON (3.4). Every string in a body must be Unicode text, so one with an escaped lone surrogate, such as `"a\ud800b"`, makes the body invalid JSON too.

3.2 Every `400`, `404`, `405`, `409`, `413` and `500` response, including the `404` in 2.2, has a JSON body whose `error` field is a non-empty string. Its wording isn't specified: the messages in examples are only illustrations. A response to `HEAD` never has a body, as HTTP requires.

```
GET /no-such-path
→ 404
{"error": "not found"}
```

3.3 A successful request returns `201` with the new object for a `POST` that creates one, `204` with no body for a `DELETE`, and `200` with the result for anything else.

3.4 Errors:

- `400`: the request is wrong in itself. Its body isn't valid JSON or isn't a JSON object, a required field is missing, a field has the wrong JSON type or a value this spec doesn't allow, a body field refers to something that doesn't exist, or it asks for something this spec never allows (such as renaming a transfer payee).
- `404`: the path names something that doesn't exist.
- `405`: the path is one this spec defines, but not for that method. `HEAD` is defined wherever `GET` is, and gets the `GET` response without its body.
- `409`: the request is valid but conflicts with the current data, such as a name that's taken or deleting something still in use.
- `500`: the request is valid, but the server couldn't save the change (15.10).

When more than one applies, the first of `405`, `404`, `400`, `409` wins; `500` comes only after all of them are ruled out. What the server does with a request that isn't valid HTTP, such as one with `Content-Length: abc`, isn't specified.

3.5 Ids are random (version 4) UUIDs that the server generates, written in lowercase with hyphens, such as `3f9a2c1e-7b4d-4e8a-9c2f-1d6b5a8e0f37`, so they go into paths as they are. Clients never percent-encode a path or a query parameter, and what the server does with one that is percent-encoded, or with a `+` in a query, isn't specified. When a query parameter appears more than once, each value is checked as if it were the only one, so any invalid value returns 400, and the last value counts. An id is never reused, even after the thing it named is deleted, and ids made by different servers don't collide, so a plan's file can move between them (section 15). Examples show ids as capitalised placeholders such as `"PLAN_ID"`; within one example, the same placeholder is the same id.

3.6 A response object has every field its examples show. A field with no value is `null`, never left out. Responses may carry fields this spec doesn't mention. Request fields an endpoint doesn't define are ignored, and so are query parameters it doesn't define. A request field the endpoint does define is checked whenever it's present, even when another field leaves its value unused: an invalid value returns 400.

3.7 Amounts are integers in milliunits: 1000 milliunits is one unit of the plan's currency, so 12.34 is `12340` and -0.22 is `-220`. An amount in a request must be a JSON integer, written without a fraction or exponent, from -1000000000000 to 1000000000000; anything else returns 400. `-0` is such an integer, and means 0.

3.8 A date is a string `YYYY-MM-DD` naming a real calendar date from `1900-01-01` to `2999-12-31`. A month is a string `YYYY-MM` from `1900-01` to `2999-12`. Anything else where a date or month is expected, in a body, a path or a query parameter, returns 400. A transaction belongs to the month of its date. Any date in range is accepted, including dates after today.

3.9 A name is a string of 1 to 100 characters (Unicode scalar values), at least one of which isn't whitespace (Unicode `White_Space`). A payee name may have up to 200 characters. Names are stored exactly as given, and two things may share a name unless a section says otherwise. A note or memo is `null` or a string of at most 500 characters, stored exactly as given. Anything else returns 400.

3.10 `null` is accepted only for fields this spec calls nullable. A `PATCH` changes only the fields present in its body, and setting a nullable field to `null` clears it. A `PATCH` with no fields it recognises returns 200 and changes nothing.

3.11 A request that returns an error changes nothing. Concurrent requests behave as if they were handled one at a time.

3.12 A list endpoint returns a JSON array, in the order its clause gives.

3.13 The server may refuse a body it can't reasonably handle, even when the trouble is in a field it would ignore. A body over 1 MiB (1048576 bytes) may get `413`, whatever else is wrong with the request, except that the import endpoints (17.1) take bodies up to 16 MiB (16777216 bytes). A body that nests arrays and objects more than 64 deep, or holds a number too large for a 64-bit float, may get `400`. Within those limits, a field the endpoint ignores may hold any JSON value.

## 4. Plans

A plan is one budget: its accounts, payees, categories, transactions and monthly assignments. YNAB used to call plans budgets.

4.1 `POST /plans` creates a plan. `name` is required. `currency_code` is three uppercase ASCII letters and defaults to `"USD"`; the server only stores it.

```
POST /plans
{"name": "Household"}
→ 201
{"id": "PLAN_ID", "name": "Household", "currency_code": "USD"}
```

4.2 `GET /plans` lists every plan, oldest first. `GET /plans/{plan_id}` returns one.

```
GET /plans
→ 200
[{"id": "PLAN_ID", "name": "Household", "currency_code": "USD"}]
```

4.3 `PATCH /plans/{plan_id}` can change `name` and `currency_code`.

```
PATCH /plans/PLAN_ID
{"currency_code": "EUR"}
→ 200
{"id": "PLAN_ID", "name": "Household", "currency_code": "EUR"}
```

4.4 `DELETE /plans/{plan_id}` deletes the plan and everything in it.

```
DELETE /plans/PLAN_ID
→ 204
```

4.5 Everything in sections 5 onward belongs to one plan and lives under `/plans/{plan_id}/`. A path naming something that belongs to another plan returns 404, and a body field referring to it returns 400, exactly as if it didn't exist.

## 5. Accounts

5.1 An account's `type` is one of:

- cash accounts: `checking`, `savings`, `cash`
- credit accounts: `creditCard`, `lineOfCredit`
- tracking accounts: `otherAsset`, `otherLiability`

Cash and credit accounts are on budget (`"on_budget": true`): their transactions feed the plan's categories and Ready to Assign. Tracking accounts only keep a balance (`"on_budget": false`). An account's type never changes.

5.2 `POST /plans/{plan_id}/accounts` creates an account. `name` and `type` are required, and `note` is optional and nullable. `starting_balance` is an amount, default 0. `starting_date` is a date, and isn't nullable. It is required when `starting_balance` isn't 0. When `starting_balance` is 0 it may be left out and is unused, but if present it must still be a date (3.6), so `null` or `"2026-02-30"` returns 400.

```
POST /plans/PLAN_ID/accounts
{"name": "Checking", "type": "checking", "starting_balance": 2500000, "starting_date": "2026-10-01"}
→ 201
{"id": "CHECKING_ID", "name": "Checking", "type": "checking", "on_budget": true, "closed": false,
 "note": null, "balance": 2500000, "cleared_balance": 2500000, "uncleared_balance": 0,
 "transfer_payee_id": "CHECKING_PAYEE_ID", "payment_category_id": null}
```

5.3 A non-zero starting balance creates the account's first transaction. It is dated `starting_date`, has amount `starting_balance` and the payee named `Starting Balance` (found or created as in 6.5), memo `null`, `cleared` `"cleared"`, `approved` true and no flag. In an on-budget account its category is `ready_to_assign`; in a tracking account it has none. A zero starting balance creates no transaction.

5.4 `balance` is the sum of the amounts of the account's transactions. `cleared_balance` is the sum over those whose `cleared` is `"cleared"` or `"reconciled"`, and `uncleared_balance` the sum over those that are `"uncleared"`. A split transaction counts once, with its own amount.

5.5 Creating an account first creates its transfer payee (section 6), named `Transfer : ` followed by the account's name; `transfer_payee_id` is its id. Creating a credit account then creates its payment category (7.2); `payment_category_id` is its id, and `null` for other accounts. Only then is the starting balance transaction (5.3) created.

```
POST /plans/PLAN_ID/accounts
{"name": "Visa", "type": "creditCard", "starting_balance": -350000, "starting_date": "2026-10-01"}
→ 201
{"id": "VISA_ID", "name": "Visa", "type": "creditCard", "on_budget": true, "closed": false,
 "note": null, "balance": -350000, "cleared_balance": -350000, "uncleared_balance": 0,
 "transfer_payee_id": "VISA_PAYEE_ID", "payment_category_id": "VISA_PAYMENT_ID"}
```

5.6 `GET /plans/{plan_id}/accounts` lists the plan's accounts, oldest first. `GET /plans/{plan_id}/accounts/{account_id}` returns one. For a plan whose only account is 5.2's Checking:

```
GET /plans/PLAN_ID/accounts
→ 200
[{"id": "CHECKING_ID", "name": "Checking", "type": "checking", "on_budget": true, "closed": false,
  "note": null, "balance": 2500000, "cleared_balance": 2500000, "uncleared_balance": 0,
  "transfer_payee_id": "CHECKING_PAYEE_ID", "payment_category_id": null}]
```

5.7 `PATCH /plans/{plan_id}/accounts/{account_id}` can change `name`, `note` and `closed`; a `type` other than the account's returns 400 (5.1). Renaming an account renames its transfer payee and its payment category to match.

```
PATCH /plans/PLAN_ID/accounts/VISA_ID
{"name": "Visa Gold"}
→ 200
{"id": "VISA_ID", "name": "Visa Gold", "type": "creditCard", "on_budget": true, "closed": false,
 "note": null, "balance": -350000, "cleared_balance": -350000, "uncleared_balance": 0,
 "transfer_payee_id": "VISA_PAYEE_ID", "payment_category_id": "VISA_PAYMENT_ID"}
```

5.8 Setting `closed` to true on an open account returns 409 unless its `balance` is 0. A closed account still takes transactions, and can be reopened at any time.

5.9 `DELETE /plans/{plan_id}/accounts/{account_id}` returns 409 if the account has any transactions; its starting balance counts. Otherwise it deletes the account, its transfer payee, and its payment category along with that category's assigned amounts.

```
DELETE /plans/PLAN_ID/accounts/VISA_ID
→ 409
{"error": "the account has transactions"}
```

## 6. Payees

6.1 A payee has an `id`, a `name` and a `transfer_account_id`, which is an account's id for that account's transfer payee and `null` for any other payee. `GET /plans/{plan_id}/payees` lists all the plan's payees, transfer payees included, oldest first. `GET /plans/{plan_id}/payees/{payee_id}` returns one. For a plan whose only account is Checking, created with a starting balance:

```
GET /plans/PLAN_ID/payees
→ 200
[{"id": "CHECKING_PAYEE_ID", "name": "Transfer : Checking", "transfer_account_id": "CHECKING_ID"},
 {"id": "STARTING_BALANCE_ID", "name": "Starting Balance", "transfer_account_id": null}]
```

6.2 `POST /plans/{plan_id}/payees` creates a payee from `name`. Payees that aren't transfer payees have unique names, compared exactly (case matters): a name one of them already has returns 409.

```
POST /plans/PLAN_ID/payees
{"name": "Corner Shop"}
→ 201
{"id": "CORNER_SHOP_ID", "name": "Corner Shop", "transfer_account_id": null}
```

6.3 `PATCH /plans/{plan_id}/payees/{payee_id}` can change `name`, under the same rule; a payee keeping its own name isn't a conflict. A `PATCH` with `name` on a transfer payee returns 400, because its name follows its account (5.7).

```
PATCH /plans/PLAN_ID/payees/CORNER_SHOP_ID
{"name": "Corner Shop Ltd"}
→ 200
{"id": "CORNER_SHOP_ID", "name": "Corner Shop Ltd", "transfer_account_id": null}
```

6.4 `DELETE /plans/{plan_id}/payees/{payee_id}` returns 400 for a transfer payee and 409 for a payee that any transaction uses. Otherwise it deletes the payee.

```
DELETE /plans/PLAN_ID/payees/CHECKING_PAYEE_ID
→ 400
{"error": "a transfer payee can't be deleted"}

DELETE /plans/PLAN_ID/payees/CORNER_SHOP_ID
→ 204
```

6.5 Every request that takes `payee_id` also takes `payee_name`, which is a payee name (3.9) or `null`. When `payee_id` is absent or `null` and `payee_name` is a string, the payee is the one, not a transfer payee, whose name is exactly `payee_name`; it is created if there is none. When `payee_id` isn't `null`, `payee_name` is unused, though it must still be valid (3.6). Transfer payees are never found by name.

6.6 A transfer payee's name may be the same as any other payee's.

## 7. Categories

7.1 `GET /plans/{plan_id}/categories` lists the plan's category groups, each with its categories. The first group is always the internal group `Credit Card Payments`. The plan's own groups follow, oldest first. Within a group, categories are in the order they joined it. For a plan with one credit account, Visa, and one group, Bills, holding Rent:

```
GET /plans/PLAN_ID/categories
→ 200
[{"id": "CCP_GROUP_ID", "name": "Credit Card Payments", "hidden": false, "internal": true,
  "categories": [{"id": "VISA_PAYMENT_ID", "group_id": "CCP_GROUP_ID", "name": "Visa",
                  "hidden": false, "note": null, "payment_account_id": "VISA_ID"}]},
 {"id": "BILLS_ID", "name": "Bills", "hidden": false, "internal": false,
  "categories": [{"id": "RENT_ID", "group_id": "BILLS_ID", "name": "Rent",
                  "hidden": false, "note": null, "payment_account_id": null}]}]
```

7.2 Each credit account has one payment category, created with the account at the end of `Credit Card Payments`. Its name is always the account's name, and its `payment_account_id` is the account's id. Every other category is a user category, with `payment_account_id` `null`.

7.3 `POST /plans/{plan_id}/category_groups` creates a group from `name`.

```
POST /plans/PLAN_ID/category_groups
{"name": "Bills"}
→ 201
{"id": "BILLS_ID", "name": "Bills", "hidden": false, "internal": false, "categories": []}
```

7.4 `GET /plans/{plan_id}/category_groups/{group_id}` returns a group with its categories. `PATCH` on it can change `name` and `hidden`. `DELETE` on it deletes it, but returns 409 while it has categories. A `PATCH` with `name` or `hidden` on the internal group returns 400, and so does a `DELETE` of it.

```
PATCH /plans/PLAN_ID/category_groups/BILLS_ID
{"hidden": true}
→ 200
{"id": "BILLS_ID", "name": "Bills", "hidden": true, "internal": false,
 "categories": [{"id": "RENT_ID", "group_id": "BILLS_ID", "name": "Rent",
                 "hidden": false, "note": null, "payment_account_id": null}]}
```

7.5 `POST /plans/{plan_id}/categories` creates a user category at the end of a group. `group_id` and `name` are required, and `note` is optional and nullable. A `group_id` that isn't one of the plan's own groups returns 400.

```
POST /plans/PLAN_ID/categories
{"group_id": "BILLS_ID", "name": "Rent"}
→ 201
{"id": "RENT_ID", "group_id": "BILLS_ID", "name": "Rent", "hidden": false, "note": null,
 "payment_account_id": null}
```

7.6 `GET /plans/{plan_id}/categories/{category_id}` returns a category. `PATCH` on it can change `name`, `note`, `hidden` and `group_id`. A `group_id` other than the category's own moves it to the end of that group, which must be one of the plan's own groups (400 otherwise). A `PATCH` on a payment category that includes `name` or `group_id` returns 400.

```
PATCH /plans/PLAN_ID/categories/RENT_ID
{"group_id": "HOUSING_ID", "note": "due on the 1st"}
→ 200
{"id": "RENT_ID", "group_id": "HOUSING_ID", "name": "Rent", "hidden": false,
 "note": "due on the 1st", "payment_account_id": null}
```

7.7 Inflow: Ready to Assign isn't a category object. A transaction is categorized to it with the category id `ready_to_assign`, which no generated id ever equals. No group lists it, and `GET /plans/{plan_id}/categories/ready_to_assign` returns 404.

7.8 Hidden categories and groups behave exactly like visible ones; `hidden` is for clients.

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

- In an on-budget account it is a user category's id, `ready_to_assign`, or `null`, the default, which leaves the transaction uncategorized (section 16). In a cash account, `ready_to_assign` marks income. In a credit account it marks a change in what's owed that doesn't touch the plan, such as a statement credit.
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

For a plan holding 5.2's Checking and the transactions in 8.1 and 8.2:

```
GET /plans/PLAN_ID/transactions?account_id=CHECKING_ID&since_date=2026-10-02&until_date=2026-10-10
→ 200
[{"id": "SHOP_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-04", "amount": -120000,
  "payee_id": "CORNER_SHOP_ID", "category_id": "GROCERIES_ID", "memo": "weekly shop",
  "cleared": "uncleared", "approved": true, "flag_color": null,
  "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}]
```

8.6 `PATCH /plans/{plan_id}/transactions/{transaction_id}` can change any field in 8.1 except `account_id`; an `account_id` different from the transaction's returns 400. The changed transaction must meet every rule a new one must (8.2, sections 9 and 10); if it doesn't, the request returns 400.

- The payee changes when `payee_id` is present or `payee_name` is a string, and is then chosen as 6.5 says: `"payee_id": null` with no `payee_name` string removes it. `"payee_name": null` on its own changes nothing.
- A field the `PATCH` leaves out keeps its value, except `category_id`: it becomes `null` when the changed transaction can't have a category, because it's a split or a transfer whose halves have none (9.3). A `category_id` the request gives is checked as usual, so a non-null one there returns 400.

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

9.2 A transfer from an account to itself returns 400, and so does a transfer with a non-empty `subtransactions` array.

9.3 Categories on transfers:

- Between two on-budget accounts, or two tracking accounts, neither half has a category, and a non-null `category_id` returns 400.
- Between an on-budget account and a tracking account, money enters or leaves the plan. The on-budget half follows 8.2 for its account, so it has a category or is uncategorized (section 16), and the tracking half has none. The `category_id` of a `POST` or `PATCH` sets the on-budget half's category, whichever half the request is for. A `PATCH` to the tracking half that leaves `category_id` out keeps the on-budget half's category, even when it moves that half to another on-budget account (9.5). When there was no on-budget half before the `PATCH`, there's no category to keep, so without a `category_id` the on-budget half is uncategorized.

9.4 Changing `date` or `amount` on either half changes the other to match: the same date and the opposite amount. `memo`, `cleared`, `approved` and `flag_color` belong to the half they're set on.

9.5 Changing a transfer's payee to one that isn't a transfer payee, or to `null`, deletes the other half. Changing it to another account's transfer payee deletes the other half and creates a new one in that account, as 9.1 says. Changing an ordinary transaction's payee to a transfer payee creates the other half, as 9.1 says. 8.6 applies to the result: for example, an on-budget account's half left without a transfer keeps its `null` category, and so is uncategorized, unless the same request gives one.

9.6 Deleting either half deletes both.

## 10. Split transactions

10.1 A transaction with a non-empty `subtransactions` array is a split. `subtransactions` is an array of objects, each with a required `amount`, a required `category_id` (10.2), and a nullable `memo` defaulting to `null`. The subtransactions' amounts must add up to the transaction's amount, and the transaction's own `category_id` must be `null` (or, in a `POST`, absent; 8.6 covers a `PATCH`); otherwise 400.

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

10.2 Each subtransaction's `category_id` follows 8.2 for the transaction's account, except that it can't be `null`: a subtransaction is never uncategorized. Splits aren't allowed in tracking accounts (400).

10.3 Responses list subtransactions in the order they were given, each with `amount`, `category_id` and `memo`. A transaction that isn't a split has `"subtransactions": []`.

10.4 A `PATCH` with `subtransactions` replaces all of them. An empty array makes the transaction an ordinary one again; in an on-budget account it is uncategorized (section 16) unless the same request gives a `category_id`. 8.6 applies: for example, changing a split's `amount` without matching subtransactions returns 400.

## 11. Months and Ready to Assign

Every month, the plan's money is either assigned to categories or Ready to Assign. This section covers cash accounts; section 12 adds credit accounts.

11.1 A line is a transaction in an on-budget account that isn't a split, or one subtransaction of a split in an on-budget account. A line has its transaction's account and date. Only lines affect the plan; transactions in tracking accounts never do.

11.2 Each category has an assigned amount for every month, 0 until set. `PATCH /plans/{plan_id}/months/{month}/categories/{category_id}` with `assigned` sets it, for a user or a payment category. `assigned` is an amount (3.7), may be negative, and isn't nullable. The response is the category's month entry (11.3). `ready_to_assign` isn't a category here: that path returns 404.

```
PATCH /plans/PLAN_ID/months/2026-10/categories/GROCERIES_ID
{"assigned": 400000}
→ 200
{"category_id": "GROCERIES_ID", "assigned": 400000, "activity": 0, "available": 400000,
 "cash_overspending": 0, "credit_overspending": 0}
```

11.3 `GET /plans/{plan_id}/months/{month}/categories/{category_id}` returns a category's month entry. `activity` is the sum of the amounts of the month's lines with that category (a payment category's activity is in 12.4); `available` is in 11.4, and the overspending fields in 11.5. After 11.2's `PATCH`, in a plan with no transactions:

```
GET /plans/PLAN_ID/months/2026-10/categories/GROCERIES_ID
→ 200
{"category_id": "GROCERIES_ID", "assigned": 400000, "activity": 0, "available": 400000,
 "cash_overspending": 0, "credit_overspending": 0}
```

11.4 `available` = carryover + `assigned` + `activity`, where carryover is the previous month's `available` if that is positive, and 0 otherwise. Money left in a category rolls into the next month, and an overspent category starts the next month at 0. Before `1900-01` everything is 0.

11.5 A category is overspent when its `available` is negative. `credit_overspending` is the part spent on credit (12.3); it is 0 for a category with no spending in credit accounts that month. `cash_overspending` is the rest: max(0, -`available`) - `credit_overspending`.

11.6 `GET /plans/{plan_id}/months/{month}` returns the month:

- `income`: the sum of the amounts of the month's lines in cash accounts categorized to `ready_to_assign`.
- `cash_advances`: see 12.5; 0 without credit accounts.
- `assigned`: the sum of every category's `assigned` for the month.
- `activity`: the sum of every user category's `activity` for the month.
- `cash_overspending_last_month`: the sum of every category's `cash_overspending` in the previous month.
- `left_over_from_last_month`, `assigned_in_future` and `ready_to_assign`: see 11.7.
- `categories`: every category's month entry, group by group in the order of 7.1, payment categories included. Uncategorized money has its own field (16.3).

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

12.7 Example. Checking starts with 1000.00 and Visa (a credit card) with -200.00, both on 2026-10-01, and Groceries is the plan's only user category; Visa's starting balance changes nothing in the plan (12.6). October assigns 300.00 to Groceries and 200.00 to Visa's payment category. Visa spends 100.00 on Groceries on 2026-10-05 and 250.00 on 2026-10-09. Checking pays Visa 200.00 on 2026-10-20 (a transfer). On 2026-11-03, Visa gets a 30.00 refund categorized to Groceries.

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

13.1 `DELETE /plans/{plan_id}/categories/{category_id}` deletes a user category. Deleting a payment category returns 400: it goes only with its account (5.9). `ready_to_assign` isn't a category here: that path returns 404 (7.7).

13.2 If any transaction or subtransaction has the category, as Dining does in 11.8, the request needs the query parameter `reassign_to`; without it, it returns 409. Otherwise `reassign_to` is optional. Whenever it's present, it must be the id of one of the plan's user categories other than the one being deleted, or the request returns 400 (3.6). `ready_to_assign` and payment categories aren't allowed.

```
DELETE /plans/PLAN_ID/categories/DINING_ID
→ 409
{"error": "category is in use"}
```

13.3 With `reassign_to`, every transaction and subtransaction that had the deleted category gets the `reassign_to` category, and for every month the deleted category's `assigned` is added to that category's, whether or not the deleted category was in use. Nothing else about those transactions changes. Without `reassign_to`, the deleted category's assigned amounts are dropped, which returns them to Ready to Assign.

```
DELETE /plans/PLAN_ID/categories/DINING_ID?reassign_to=GROCERIES_ID
→ 204

GET /plans/PLAN_ID/months/2026-10/categories/GROCERIES_ID
→ 200
{"category_id": "GROCERIES_ID", "assigned": 450000, "activity": -200000, "available": 250000,
 "cash_overspending": 0, "credit_overspending": 0}
```

(Applied to 11.8, November's `cash_overspending_last_month` becomes 0 and its `ready_to_assign` 150000.)

13.4 Once deleted, the category no longer exists: its paths, its month entries included, return 404, and a body field or `reassign_to` naming it returns 400. It's left out of 7.1's lists, its group's `categories`, and every month's `categories`. The other categories keep their order.

## 14. Reconciliation

14.1 `POST /plans/{plan_id}/accounts/{account_id}/reconcile` reconciles the account to the cleared balance its bank reports. `balance`, an amount (3.7), and `date`, a date (3.8), are both required and not nullable. It works on any account, closed (5.8) or tracking included. It returns `200` with the account (5.4, after the changes below) and the adjustment it made, or `null` if it made none.

14.2 If `balance` differs from the account's `cleared_balance`, the server first adds an adjustment: amount `balance` - `cleared_balance`, dated `date`, payee `Reconciliation Balance Adjustment` (found or created as in 6.5), memo `null`, `cleared` `"reconciled"`, `approved` true, no flag. Its category is `ready_to_assign` in an on-budget account; in a tracking account it has none. If the adjustment's amount would be outside 3.7's range, the request returns 409 and changes nothing, so every transaction's amount stays in that range.

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

Without `MYBUDGET_DATA`, the server keeps its data only in memory, as the earlier sections assume. This section covers the server with it set.

15.1 `MYBUDGET_DATA`, when it is set and not empty, names a directory, relative to the server's working directory if it's a relative path. The server creates it, with any missing parents, if it doesn't exist. If it can't, or can't read and write files there, the server writes a message to stderr and exits with a non-zero status, without printing 1.3's line.

15.2 Each plan is kept in its own SQLite database file in that directory. The file's name is the plan's safe name (15.3) followed by `.sqlite`, such as `Household.sqlite`. If anything in the directory already has that name, such as another file or a folder, or the file system treats the name as the same as an existing one's (case-insensitive file systems ignore letter case), the server puts a space and the first 8 characters of the plan's id in parentheses before `.sqlite`: `Household (3f9a2c1e).sqlite`. If that name is taken too, it uses the whole id in the parentheses instead, and if even that is taken, the request returns `500` (15.10). The server never overwrites a file it didn't create for that plan.

15.3 A plan's safe name is its name with these steps applied in order:

- Each control character (U+0000 to U+001F, and U+007F) and each of `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>` and `|` becomes `_`.
- If the result is longer than 200 bytes in UTF-8, it's cut to the longest run of whole characters from its start that fits.
- Any mix of white space (Unicode `White_Space`) and `.` is removed from both ends.
- If nothing is left, the safe name is `Plan`.

```
"Household"         → Household.sqlite
"Bills/Rent: 2027"  → Bills_Rent_ 2027.sqlite
" .hidden. "        → hidden.sqlite
"..."               → Plan.sqlite
```

15.4 When a plan's name changes (4.3), its file is renamed as 15.2 names it, except that the plan's own file never counts as a clash: renaming `Household` to `household` gives `household.sqlite`. If the new safe name is exactly the old one, the file keeps its name, suffix included. Deleting a plan (4.4) deletes its file.

15.5 A server started on a directory serves the plans in every file there whose name ends in `.sqlite`, in lowercase, and ignores other files. A file whose name ends in `.SQLITE` or another mix of case is ignored, though its name can still clash with a plan file's (15.2). It serves the same data the earlier server did: the same ids, values and list orders. 4.2's "oldest first" uses a creation time kept in each plan's file. A change is saved before the response to the request that made it, so it survives the server being killed (`SIGKILL`) at any point afterwards.

```
(server started with MYBUDGET_DATA=<dir>)
POST /plans
{"name": "Household"}
→ 201
{"id": "PLAN_ID", "name": "Household", "currency_code": "USD"}

(<dir> now holds Household.sqlite; the server is killed, then started again with the same MYBUDGET_DATA)
GET /plans
→ 200
[{"id": "PLAN_ID", "name": "Household", "currency_code": "USD"}]
```

15.6 Between requests, each plan's file is a complete database on its own: no `-journal`, `-wal` or `-shm` file is left beside it.

15.7 At startup, a `.sqlite` file the server can't use is skipped: the server doesn't serve it or change it, writes one line to stderr naming the file and the reason, and starts as usual. How it writes a name holding a line break or other control character is up to the server, as long as the whole report stays on one line. That covers a file that isn't a plan file the server can read, one whose schema version (15.8) is newer than the server knows, and two or more files holding the same plan, as when a file has been copied: all of those are skipped. Only files the server could otherwise use count as holding a plan: a file counts only if the server would serve it were it the only file in the directory, so a file skipped for another reason never causes another file to be skipped. A skipped file's name still counts as taken (15.2).

15.8 A plan file records its schema version in SQLite's `user_version`; a database whose `user_version` is less than 1 isn't a plan file (15.7). Version 1 holds all the data that sections 1 to 14 and 16 define. A later section that adds data to keep says which version holds it and what migrating below that version drops; a section that adds no new kind of data adds no version. At startup the server upgrades every plan file with an older version to its latest before serving it. A file it can't upgrade is skipped (15.7) and left as it was.

15.9 `mybudget-server migrate <file> <version>` changes a plan file to that schema version, older or newer, and exits with status 0 without listening or reading `MYBUDGET_DATA`. Going down drops only what the older version can't hold, as the section that added it says, and going back up then restores everything else exactly. Migrating a file to its own version changes nothing. If the file isn't a plan file, if its version is newer than the server knows, or if `<version>` isn't an integer from 1 to the server's latest version, the command writes a message to stderr, exits with a non-zero status and leaves the file as it was. With no arguments the server serves as section 1 says; what it does with other arguments isn't specified.

```
$ mybudget-server migrate "<dir>/Household.sqlite" 1
(exit status 0)
```

15.10 If the server can't save a change, the request returns `500` and changes nothing, in memory or on disk (3.11).

15.11 The server reads the directory only when it starts. What happens if plan files are added, changed, renamed or removed while it runs, or if two servers use the same directory at once, isn't specified.

## 16. Uncategorized transactions

A bank doesn't know your categories, so a transaction can come in before it has one. It counts in the plan while it waits, as money in a category nothing was assigned to.

16.1 A transaction is uncategorized when it is in an on-budget account, its `category_id` is `null`, and it is neither a split nor a transfer between two on-budget accounts. The on-budget half of a transfer to or from a tracking account can be uncategorized; both halves then have `"category_id": null`. 8.2, 9.3, 9.5 and 10.4 say when a transaction is left without a category; a subtransaction never is (10.2).

16.2 In sections 11 and 12, uncategorized transactions are the lines (11.1) of one more user category, Uncategorized, whose `assigned` is always 0. So it has `activity`, `available` and overspending like any user category, it counts in its month's `activity` and in the next month's `cash_overspending_last_month`, and it funds credit card spending as 12.2 says. Uncategorized cash spending comes out of next month's Ready to Assign as cash overspending. Uncategorized credit card spending that Uncategorized can't fund becomes debt, and moves nothing into the card's payment category. An uncategorized inflow stays in Uncategorized, carrying into later months, until it is categorized; it isn't `income`.

16.3 Each month (11.6) has `uncategorized`: Uncategorized's month entry, with `"category_id": null`. It isn't in the month's `categories`, and it has no path of its own.

16.4 8.5's list takes the query parameter `uncategorized`: `true` lists only uncategorized transactions, and `false` only the others. Any other value returns 400.

```
GET /plans/PLAN_ID/transactions?uncategorized=true
→ 200
[{"id": "POWER_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-20", "amount": -64990,
  "payee_id": "POWER_PAYEE_ID", "category_id": null, "memo": null,
  "cleared": "cleared", "approved": false, "flag_color": null,
  "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": []}]
```

(This is the plan after 17.7's import, where the transaction also has `import`.)

16.5 Example. Checking starts with 1000.00 and Visa (a credit card) with 0, both on 2026-10-01, and Groceries is the plan's only user category. October assigns 300.00 to Groceries. With no category, Checking spends 50.00 on 2026-10-10, Visa spends 40.00 on 2026-10-12, and Checking receives 20.00 on 2026-10-15. Uncategorized's funds (12.2) are 0 + 0 - 50.00 + 20.00 = -30.00, so none of Visa's 40.00 is funded: it is credit overspending, and the other 30.00 is cash overspending.

```
GET /plans/PLAN_ID/months/2026-10
→ 200
{"month": "2026-10", "income": 1000000, "cash_advances": 0, "assigned": 300000,
 "activity": -70000, "cash_overspending_last_month": 0, "left_over_from_last_month": 0,
 "assigned_in_future": 0, "ready_to_assign": 700000,
 "uncategorized": {"category_id": null, "assigned": 0, "activity": -70000, "available": -70000,
                   "cash_overspending": 30000, "credit_overspending": 40000},
 "categories": [
  {"category_id": "VISA_PAYMENT_ID", "assigned": 0, "activity": 0, "available": 0,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "GROCERIES_ID", "assigned": 300000, "activity": 0, "available": 300000,
   "cash_overspending": 0, "credit_overspending": 0}]}

GET /plans/PLAN_ID/months/2026-11
→ 200
{"month": "2026-11", "income": 0, "cash_advances": 0, "assigned": 0,
 "activity": 0, "cash_overspending_last_month": 30000, "left_over_from_last_month": 700000,
 "assigned_in_future": 0, "ready_to_assign": 670000,
 "uncategorized": {"category_id": null, "assigned": 0, "activity": 0, "available": 0,
                   "cash_overspending": 0, "credit_overspending": 0},
 "categories": [
  {"category_id": "VISA_PAYMENT_ID", "assigned": 0, "activity": 0, "available": 0,
   "cash_overspending": 0, "credit_overspending": 0},
  {"category_id": "GROCERIES_ID", "assigned": 0, "activity": 0, "available": 300000,
   "cash_overspending": 0, "credit_overspending": 0}]}
```

Categorizing the 50.00 to Groceries afterwards (8.6) leaves Uncategorized's October funds at 20.00, which funds 20.00 of Visa's spending. October's Uncategorized entry then has `activity` -20000, `available` -20000, `credit_overspending` 20000 and `cash_overspending` 0; Visa's payment category has `activity` and `available` 20000; Groceries has `activity` -50000 and `available` 250000; and November's `cash_overspending_last_month` is 0 and its `ready_to_assign` 700000.

## 17. Importing OFX files

Banks export statements as OFX files; a QFX file is an OFX file with some extra elements for Quicken. An import adds a file's transactions to the plan's accounts. It skips any the account has imported before, and matches each of the rest to a transaction entered by hand where it can, so that nothing is entered twice.

17.1 `POST /plans/{plan_id}/imports/preview` reads a file and returns what's in it (17.6), changing nothing. `POST /plans/{plan_id}/imports` imports it (17.7). Both take `file`, required: the file's bytes in base64, using RFC 4648's standard alphabet with `=` padding and no white space. Anything else in `file`, or a file that isn't OFX as 17.2 to 17.5 describe, returns 400. Both endpoints take bodies up to 16 MiB (3.13).

17.2 A file is OFX 1.x or OFX 2.x. A UTF-8 byte order mark at its start is skipped, and so is any white space before the first header.

- OFX 1.x starts with header lines `KEY:VALUE`, the first being `OFXHEADER:100`, which run until the first `<`. Its text is UTF-8 when a header is `ENCODING:UTF-8`, and Windows-1252 otherwise, whatever `CHARSET` says.
- OFX 2.x starts with `<?xml` or `<?OFX`. Its text is in the XML declaration's `encoding`, or UTF-8 if there is no declaration or no `encoding`. The encoding may be UTF-8 or Windows-1252, named by any label the WHATWG Encoding Standard gives them, matched ignoring ASCII case, so `utf8`, `cp1252` and `iso-8859-1` are allowed. Any other encoding returns 400.

Both encodings are decoded as the WHATWG Encoding Standard says: in UTF-8, a byte or run of bytes that isn't valid reads as U+FFFD, and in Windows-1252 every byte reads as some character, the five Windows-1252 leaves undefined as the control characters with their codes.

17.3 After the headers, the file is a tree of elements, read the same way in 1.x and 2.x.

- A start tag is `<NAME>` and an end tag `</NAME>`. Element names match ignoring ASCII case. Comments (`<!-- ... -->`) and processing instructions (`<? ... ?>`) are skipped wherever they are. What the server does with other markup, such as attributes or CDATA sections, isn't specified.
- An element ends at its end tag, and holds everything between. An element with no end tag of its own before its parent's ends holds only the text up to the next `<`, which may be empty, as OFX 1.x writes `<TRNAMT>-64.99` with no `</TRNAMT>`. An end tag that closes no open element returns 400.
- A value is the text an element holds directly. In it, `&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`, `&nbsp;`, and numeric references such as `&#38;` and `&#x26;`, become the characters they name; any other `&` stays as it is, so `AT&T` reads as `AT&T`. Then white space (Unicode `White_Space`) is trimmed from both ends. A value left empty counts as absent.
- Elements that 17.4 doesn't name are ignored, with everything inside them. When an element 17.4 names appears more than once where it expects one, the first counts.

17.4 The file's statements are its `STMTRS` elements (bank statements) and `CCSTMTRS` elements (credit card statements), wherever they are, in the order they appear. A file with none returns 400. In each statement, these are read, and the rest ignored:

- `CURDEF`, the currency code: optional.
- The account: in a bank statement, `BANKACCTFROM`, holding `BANKID` (optional), `ACCTID` (required) and `ACCTTYPE` (optional); in a credit card statement, `CCACCTFROM`, holding `ACCTID` (required).
- `BANKTRANLIST`, optional, holding `DTSTART` and `DTEND` (both optional) and the statement's transactions, its `STMTTRN` elements, in order. Without it the statement has no transactions.
- `LEDGERBAL`, optional, holding `BALAMT` and `DTASOF` (both optional): the balance the bank reports.

Each `STMTTRN` holds `TRNTYPE` (optional), `DTPOSTED` (required), `TRNAMT` (required), `FITID` (optional), `NAME` (optional; when it is absent, the `NAME` inside a `PAYEE` element, if there is one) and `MEMO` (optional). A required element that's absent, or a date or amount that isn't as 17.5 says, returns 400.

17.5 A date value starts with eight digits, `YYYYMMDD`, naming a date in 3.8's range; anything after them, such as a time or `[-5:EST]`, is ignored, so the date is the one written, whatever its time zone. An amount value is an optional `+` or `-` followed by digits, with at most one `.` or `,` among them and at least one digit in all; `-64.99`, `+1800`, `12,5` and `.5` are amounts, and `1,234.56` isn't. It becomes milliunits (3.7), rounded half away from zero beyond three decimal places, so `-64.99` is `-64990`. An amount outside 3.7's range returns 400.

17.6 The preview returns `200` with `statements`, one object per statement in file order:

- `type`: `"bank"` or `"credit_card"`.
- `bank_id`, `account_number`, `account_type`: `BANKID`, `ACCTID` and `ACCTTYPE` as strings, or `null` when absent. `bank_id` and `account_type` are always `null` for a credit card statement.
- `currency_code`: `CURDEF`, or `null`.
- `start_date`, `end_date`: `DTSTART` and `DTEND` as dates, or `null`.
- `ledger_balance`, `ledger_balance_date`: `BALAMT` as an amount and `DTASOF` as a date, or `null`.
- `account_id`, `swap_payee_memo`, `invert_amounts`: what the last import of a statement with the same `type`, `bank_id` and `account_number` into this plan used (17.13), or `null`, `false` and `false` if there was none or its account has been deleted.
- `transactions`: one object per `STMTTRN`, in order, with `import_id` (17.8), `type` (`TRNTYPE`, or `null`), `date`, `amount`, `name` and `memo` (or `null`), as the file has them, before 17.7's options.

```
(the file, in Windows-1252; the lines before <BANKMSGSRSV1> are shortened)
OFXHEADER:100
DATA:OFXSGML
VERSION:102
ENCODING:USASCII
CHARSET:1252

<OFX>
<SIGNONMSGSRSV1><SONRS><STATUS><CODE>0<SEVERITY>INFO</STATUS></SONRS></SIGNONMSGSRSV1>
<BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS>
<CURDEF>USD
<BANKACCTFROM><BANKID>021000021<ACCTID>000123456789<ACCTTYPE>CHECKING</BANKACCTFROM>
<BANKTRANLIST><DTSTART>20261001<DTEND>20261031
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261005120000.000[-5:EST]<TRNAMT>-120.00
<FITID>202610050001<NAME>CORNER SHOP #42<MEMO>POS PURCHASE</STMTTRN>
<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20261015<TRNAMT>1800.00<FITID>202610150001
<NAME>ACME PAYROLL</STMTTRN>
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261020<TRNAMT>-64.99<FITID>202610200001
<NAME>CITY POWER & LIGHT</STMTTRN>
</BANKTRANLIST>
<LEDGERBAL><BALAMT>4115.01<DTASOF>20261031</LEDGERBAL>
</STMTRS></STMTTRNRS></BANKMSGSRSV1>
</OFX>

POST /plans/PLAN_ID/imports/preview
{"file": "T0ZYSEVBREVSOjEwMApEQVRBOk9GWFNHTUwK..."}
→ 200
{"statements": [
  {"type": "bank", "bank_id": "021000021", "account_number": "000123456789",
   "account_type": "CHECKING", "currency_code": "USD",
   "start_date": "2026-10-01", "end_date": "2026-10-31",
   "ledger_balance": 4115010, "ledger_balance_date": "2026-10-31",
   "account_id": null, "swap_payee_memo": false, "invert_amounts": false,
   "transactions": [
    {"import_id": "202610050001", "type": "DEBIT", "date": "2026-10-05", "amount": -120000,
     "name": "CORNER SHOP #42", "memo": "POS PURCHASE"},
    {"import_id": "202610150001", "type": "CREDIT", "date": "2026-10-15", "amount": 1800000,
     "name": "ACME PAYROLL", "memo": null},
    {"import_id": "202610200001", "type": "DEBIT", "date": "2026-10-20", "amount": -64990,
     "name": "CITY POWER & LIGHT", "memo": null}]}]}
```

17.7 The import takes `file` and `statements`, both required. `statements` is an array with one entry per statement in the file, in the same order; any other length returns 400. An entry is `null`, to skip that statement, or an object with:

- `account_id`, required: one of the plan's accounts. A closed account (5.8) or a tracking account is allowed.
- `swap_payee_memo`, a boolean, default `false`: take the payee from `MEMO` and the memo from `NAME`, for banks that put the merchant in `MEMO`.
- `invert_amounts`, a boolean, default `false`: change the sign of every amount, for banks that write spending as positive.
- `not_duplicates`, an array of import ids (strings), default `[]`: bank transactions with these ids skip 17.9's check for the same amount and a nearby date, for when that check is wrong, as with two equal purchases a day apart.

The statements are imported in order, and each statement's transactions in order. Each bank transaction is a duplicate (17.9), is matched to a transaction already in the account (17.10), or creates a new one (17.11). The response is `200` with `statements`, one entry per entry of the request's: `null` for a skipped statement, and otherwise an object with `account_id`, `imported` (the transactions created, in order), `matched` (the transactions matched, in the order they were matched) and `duplicates` (the bank transactions skipped as duplicates, 17.9). Every transaction in the response is as it is after the whole import.

In a plan where Checking has a starting balance of 2500.00 and holds only one other transaction, 8.1's uncleared Corner Shop transaction, importing 17.6's file into Checking matches the bank's Corner Shop transaction to it and creates the other two:

```
POST /plans/PLAN_ID/imports
{"file": "T0ZYSEVBREVSOjEwMApEQVRBOk9GWFNHTUwK...", "statements": [{"account_id": "CHECKING_ID"}]}
→ 200
{"statements": [
  {"account_id": "CHECKING_ID", "duplicates": [],
   "matched": [
    {"id": "SHOP_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-04", "amount": -120000,
     "payee_id": "CORNER_SHOP_ID", "category_id": "GROCERIES_ID", "memo": "weekly shop",
     "cleared": "cleared", "approved": true, "flag_color": null,
     "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": [],
     "import": {"id": "202610050001", "date": "2026-10-05", "amount": -120000,
                "payee_name": "CORNER SHOP #42", "memo": "POS PURCHASE", "matched": true}}],
   "imported": [
    {"id": "PAYROLL_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-15", "amount": 1800000,
     "payee_id": "ACME_PAYROLL_ID", "category_id": "ready_to_assign", "memo": null,
     "cleared": "cleared", "approved": false, "flag_color": null,
     "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": [],
     "import": {"id": "202610150001", "date": "2026-10-15", "amount": 1800000,
                "payee_name": "ACME PAYROLL", "memo": null, "matched": false}},
    {"id": "POWER_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-20", "amount": -64990,
     "payee_id": "POWER_PAYEE_ID", "category_id": null, "memo": null,
     "cleared": "cleared", "approved": false, "flag_color": null,
     "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": [],
     "import": {"id": "202610200001", "date": "2026-10-20", "amount": -64990,
                "payee_name": "CITY POWER & LIGHT", "memo": null, "matched": false}}]}]}
```

Checking's `balance` is now 4115010, the statement's `ledger_balance`. Importing the same file again skips all three: the statement's entry has `"matched": []`, `"imported": []`, and `duplicates` listing the three bank transactions, with `transaction_id` `SHOP_TXN_ID`, `PAYROLL_TXN_ID` and `POWER_TXN_ID`. Previewing it gives `"account_id": "CHECKING_ID"`.

17.8 A bank transaction's data is what 17.6 shows, after the statement's options:

- `import_id`: its `FITID`. Without one, it is the amount in milliunits as the file has it, the date and a count, joined by `:`, such as `-120000:2026-10-05:1`, where the count is 1 plus the number of transactions earlier in the statement that have no `FITID` and the same amount and date.
- `date`; and `amount`, with its sign changed when `invert_amounts` is true.
- `payee_name`: the value of `NAME`, or of `MEMO` when `swap_payee_memo` is true, cut to its first 200 characters (3.9) and trimmed again; `null` if absent or left empty.
- `memo`: the value of `MEMO`, or of `NAME` when `swap_payee_memo` is true, cut to its first 500 characters; `null` if absent.

17.9 Every transaction has `import`: `null` for one entered through the API, and otherwise an object with the bank transaction's `id` (its `import_id`), `date`, `amount`, `payee_name` and `memo`, and `matched`, which is true when it was matched to a transaction already in the account (17.10). Only imports and 17.14 change it; 8.6 ignores it. Each account keeps every import id it has had, from transactions imported or matched in it, even after they are deleted or unmatched. A bank transaction is a duplicate, and is skipped, when:

- its import id is one the account has had, including from earlier in the same import; or
- unless its import id is in the statement's `not_duplicates`, the account holds a transaction that was imported or matched before this import began (its `import` isn't `null`), with the same amount and a date no more than 2 days before or after the bank transaction's, which no other bank transaction in this import is a duplicate of. This catches a bank that changes a transaction's `FITID`, as some do when a pending transaction posts.

In each statement, the first check runs over all its transactions before the second, which then takes them in order; when several transactions are possible, the one whose date is closest wins, and then the one created first. Only the first check's ids count as had, so a bank transaction the second check skips is checked again by the next import. `duplicates` lists each duplicate as its bank data (17.8), with `id` for its import id, and `transaction_id`: the transaction it duplicates. For the first check, that is the account's transaction whose `import` has that id, or `null` if none is left; for the second, the one it was paired with.

```
{"id": "202610050001", "date": "2026-10-05", "amount": -120000,
 "payee_name": "CORNER SHOP #42", "memo": "POS PURCHASE", "transaction_id": "SHOP_TXN_ID"}
```

17.10 A bank transaction that isn't a duplicate matches a transaction in the same account whose `import` is `null`, whose payee isn't named `Starting Balance` or `Reconciliation Balance Adjustment` (5.3, 14.2), whose amount is the same as the bank transaction's, and whose date is no more than 10 days before or after the bank transaction's. Its `cleared` can be anything, and splits and transfer halves can match. If several can, the one whose date is closest wins, and then the one created first. The matched transaction's `import` becomes the bank transaction's data, with `matched` true, its `cleared` becomes `"cleared"` if it was `"uncleared"`, and its `approved` becomes true; nothing else about it changes, so it keeps its own date, payee, memo and category. A transfer's other half doesn't change.

17.11 A bank transaction that is neither a duplicate nor matched creates a transaction in the account with the bank transaction's `date`, `amount` and `memo`; the payee named `payee_name`, found or created as in 6.5 (so never a transfer payee), or no payee when that is `null`; `cleared` `"cleared"`; `approved` false; no flag; no subtransactions; and `import` with `matched` false. Its category is in 17.12. Transactions are created in the order they're in the file, so 8.5 lists those with the same date in that order.

17.12 In a tracking account, an imported transaction has no category. In an on-budget account, it takes the `category_id` of the most recently created transaction in the plan with the same payee whose `category_id` isn't `null`. If the transaction has no payee, or no such transaction exists, its category is `ready_to_assign` when its amount is positive and the account is a cash account, and otherwise `null`, so it is uncategorized (section 16).

17.13 For each statement it imports, an import remembers its `account_id`, `swap_payee_memo` and `invert_amounts` under the statement's `type`, `bank_id` and `account_number`, replacing what it remembered before for them. 17.6's preview returns them.

17.14 `POST /plans/{plan_id}/transactions/{transaction_id}/unmatch` undoes a match, as when two transactions with the same amount were matched the wrong way round. It takes an empty object. It returns 409 unless the transaction's `import` has `matched` true. Otherwise its `import` becomes `null`, and nothing else about it changes, `cleared` included; and the bank transaction is created as a new transaction, as 17.11 and 17.12 say, with the same import id; it isn't a duplicate. The response is `200` with `transaction`, the transaction as it is now, and `imported`, the new one.

```
POST /plans/PLAN_ID/transactions/SHOP_TXN_ID/unmatch
{}
→ 200
{"transaction": {"id": "SHOP_TXN_ID", "account_id": "CHECKING_ID", "date": "2026-10-04",
                 "amount": -120000, "payee_id": "CORNER_SHOP_ID", "category_id": "GROCERIES_ID",
                 "memo": "weekly shop", "cleared": "cleared", "approved": true, "flag_color": null,
                 "transfer_account_id": null, "transfer_transaction_id": null,
                 "subtransactions": [], "import": null},
 "imported": {"id": "SHOP_IMPORT_ID", "account_id": "CHECKING_ID", "date": "2026-10-05",
              "amount": -120000, "payee_id": "CORNER_SHOP_42_ID", "category_id": null,
              "memo": "POS PURCHASE", "cleared": "cleared", "approved": false, "flag_color": null,
              "transfer_account_id": null, "transfer_transaction_id": null, "subtransactions": [],
              "import": {"id": "202610050001", "date": "2026-10-05", "amount": -120000,
                         "payee_name": "CORNER SHOP #42", "memo": "POS PURCHASE", "matched": false}}}
```

17.15 Schema version 2 (15.8) holds every transaction's `import`, the import ids each account has had (17.9) and what 17.13 remembers. Migrating to version 1 drops all of them: transactions keep every other field and get `"import": null`, and a later import treats every bank transaction as new.

<!-- Next: section 18 (targets). The plan and draft text are in spec/ROADMAP.md. -->
