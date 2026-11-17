# MyBudget server spec

This is the contract between the tester and the implementer. When an agent raises a `QUESTION:` or `DISPUTE:`, settle it by changing this file.

The scripts depend on two format rules:

- A requirement is a line that starts with its number, such as `2.1 `. Tests are named after these numbers (`spec_2_1_...`), and the judge reports failures to the implementer by number.
- An example under a requirement is part of it: tests may check anything the example shows. The implementer never sees the tests, so examples are how it learns exact formats. Give every endpoint at least one.

## 1. Process

1.1 The server binary is `mybudget-server`.

1.2 It listens on the address in the `MYBUDGET_ADDR` environment variable, `ip:port`, defaulting to `127.0.0.1:8080`. Port `0` means any free port.

1.3 Once it is listening, its first line on stdout is exactly `listening on <ip>:<port>`, giving the actual port. The judge checks this before running any tests.

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

3.2 Every `400`, `404`, `405`, `409` and `413` response, including the `404` in 2.2, has a JSON body whose `error` field is a non-empty string. Its wording isn't specified: the messages in examples are only illustrations. A response to `HEAD` never has a body, as HTTP requires.

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

When more than one applies, the first of `405`, `404`, `400`, `409` wins. What the server does with a request that isn't valid HTTP, such as one with `Content-Length: abc`, isn't specified.

3.5 Ids are strings that the server generates, made only of ASCII letters, digits, `-` and `_`, so they go into paths as they are. Clients never percent-encode a path or a query parameter, and what the server does with one that is percent-encoded, or with a `+` in a query, isn't specified. When a query parameter appears more than once, each value is checked as if it were the only one, so any invalid value returns 400, and the last value counts. An id is unique across the server and is never reused, even after the thing it named is deleted. Examples show ids as capitalised placeholders such as `"PLAN_ID"`; within one example, the same placeholder is the same id.

3.6 A response object has every field its examples show. A field with no value is `null`, never left out. Responses may carry fields this spec doesn't mention. Request fields an endpoint doesn't define are ignored, and so are query parameters it doesn't define. A request field the endpoint does define is checked whenever it's present, even when another field leaves its value unused: an invalid value returns 400.

3.7 Amounts are integers in milliunits: 1000 milliunits is one unit of the plan's currency, so 12.34 is `12340` and -0.22 is `-220`. An amount in a request must be a JSON integer, written without a fraction or exponent, from -1000000000000 to 1000000000000; anything else returns 400. `-0` is such an integer, and means 0.

3.8 A date is a string `YYYY-MM-DD` naming a real calendar date from `1900-01-01` to `2999-12-31`. A month is a string `YYYY-MM` from `1900-01` to `2999-12`. Anything else where a date or month is expected, in a body, a path or a query parameter, returns 400. A transaction belongs to the month of its date. Any date in range is accepted, including dates after today.

3.9 A name is a string of 1 to 100 characters (Unicode scalar values), at least one of which isn't whitespace (Unicode `White_Space`). A payee name may have up to 200 characters. Names are stored exactly as given, and two things may share a name unless a section says otherwise. A note or memo is `null` or a string of at most 500 characters, stored exactly as given. Anything else returns 400.

3.10 `null` is accepted only for fields this spec calls nullable. A `PATCH` changes only the fields present in its body, and setting a nullable field to `null` clears it. A `PATCH` with no fields it recognises returns 200 and changes nothing.

3.11 A request that returns an error changes nothing. Concurrent requests behave as if they were handled one at a time.

3.12 A list endpoint returns a JSON array, in the order its clause gives.

3.13 The server may refuse a body it can't reasonably handle, even when the trouble is in a field it would ignore. A body over 1 MiB (1048576 bytes) may get `413`, whatever else is wrong with the request. A body that nests arrays and objects more than 64 deep, or holds a number too large for a 64-bit float, may get `400`. Within those limits, a field the endpoint ignores may hold any JSON value.

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
- Between an on-budget account and a tracking account, money enters or leaves the plan. The on-budget half follows 8.2 for its account, so it needs a category, and the tracking half has none. The `category_id` of a `POST` or `PATCH` sets the on-budget half's category, whichever half the request is for. A `PATCH` to the tracking half that leaves `category_id` out keeps the on-budget half's category, even when it moves that half to another on-budget account (9.5). When there was no on-budget half before the `PATCH`, there's no category to keep, so the request needs a `category_id`.

9.4 Changing `date` or `amount` on either half changes the other to match: the same date and the opposite amount. `memo`, `cleared`, `approved` and `flag_color` belong to the half they're set on.

9.5 Changing a transfer's payee to one that isn't a transfer payee, or to `null`, deletes the other half. Changing it to another account's transfer payee deletes the other half and creates a new one in that account, as 9.1 says. Changing an ordinary transaction's payee to a transfer payee creates the other half, as 9.1 says. 8.6 applies to the result: for example, an on-budget account's half left without a transfer needs a category in the same request.

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

10.2 Each subtransaction's `category_id` follows 8.2 for the transaction's account. Splits aren't allowed in tracking accounts (400).

10.3 Responses list subtransactions in the order they were given, each with `amount`, `category_id` and `memo`. A transaction that isn't a split has `"subtransactions": []`.

10.4 A `PATCH` with `subtransactions` replaces all of them. An empty array makes the transaction an ordinary one again, so in an on-budget account the same request needs a `category_id` (8.2). 8.6 applies: for example, changing a split's `amount` without matching subtransactions returns 400.

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
- `categories`: every category's month entry, group by group in the order of 7.1, payment categories included.

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

<!-- Next: section 14 (reconciliation). The plan and draft text for every later round are in spec/ROADMAP.md. -->
