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

3.5 Ids are strings that the server generates, made only of ASCII letters, digits, `-` and `_`, so they go into paths as they are. Clients never percent-encode a path, and what the server does with one that is percent-encoded isn't specified. An id is unique across the server and is never reused, even after the thing it named is deleted. Examples show ids as capitalised placeholders such as `"PLAN_ID"`; within one example, the same placeholder is the same id.

3.6 A response object has every field its examples show. A field with no value is `null`, never left out. Responses may carry fields this spec doesn't mention. Request fields an endpoint doesn't define are ignored, and so are query parameters it doesn't define.

3.7 Amounts are integers in milliunits: 1000 milliunits is one unit of the plan's currency, so 12.34 is `12340` and -0.22 is `-220`. An amount in a request must be a JSON integer, written without a fraction or exponent, from -1000000000000 to 1000000000000; anything else returns 400.

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

5.2 `POST /plans/{plan_id}/accounts` creates an account. `name` and `type` are required, and `note` is optional and nullable. `starting_balance` is an amount, default 0. `starting_date` is a date, required when `starting_balance` isn't 0 and unused when it is.

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

6.5 Every request that takes `payee_id` also takes `payee_name`. When `payee_id` is absent or `null` and `payee_name` is a string, the payee is the one, not a transfer payee, whose name is exactly `payee_name`; it is created if there is none. When `payee_id` isn't `null`, `payee_name` is ignored. Transfer payees are never found by name.

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

<!-- Next: sections 8 to 10 (transactions, transfers, splits). The plan and draft text for every later round are in spec/ROADMAP.md. -->
