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

3.2 Every `400`, `404`, `405` and `409` response, including the `404` in 2.2, has a JSON body whose `error` field is a non-empty string. Its wording isn't specified: the messages in examples are only illustrations.

```
GET /no-such-path
→ 404
{"error": "not found"}
```

3.3 A successful request returns `201` with the new object for a `POST` that creates one, `204` with no body for a `DELETE`, and `200` with the result for anything else.

3.4 Errors:

- `400`: the request is wrong in itself. Its body isn't valid JSON or isn't a JSON object, a required field is missing, a field has the wrong JSON type or a value this spec doesn't allow, a body field refers to something that doesn't exist, or it asks for something this spec never allows (such as renaming a transfer payee).
- `404`: the path names something that doesn't exist.
- `405`: the path is one this spec defines, but not for that method.
- `409`: the request is valid but conflicts with the current data, such as a name that's taken or deleting something still in use.

When more than one applies, the first of `405`, `404`, `400`, `409` wins.

3.5 Ids are strings that the server generates. An id is unique across the server and is never reused, even after the thing it named is deleted. Examples show ids as capitalised placeholders such as `"PLAN_ID"`; within one example, the same placeholder is the same id.

3.6 A response object has every field its examples show. A field with no value is `null`, never left out. Responses may carry fields this spec doesn't mention. Request fields an endpoint doesn't define are ignored, and so are query parameters it doesn't define.

3.7 Amounts are integers in milliunits: 1000 milliunits is one unit of the plan's currency, so 12.34 is `12340` and -0.22 is `-220`. An amount in a request must be a JSON integer, written without a fraction or exponent, from -1000000000000 to 1000000000000; anything else returns 400.

3.8 A date is a string `YYYY-MM-DD` naming a real calendar date from `1900-01-01` to `2999-12-31`. A month is a string `YYYY-MM` from `1900-01` to `2999-12`. Anything else where a date or month is expected, in a body, a path or a query parameter, returns 400. A transaction belongs to the month of its date. Any date in range is accepted, including dates after today.

3.9 A name is a string of 1 to 100 characters (Unicode scalar values), at least one of which isn't whitespace (Unicode `White_Space`). A payee name may have up to 200 characters. Names are stored exactly as given, and two things may share a name unless a section says otherwise. A note or memo is `null` or a string of at most 500 characters, stored exactly as given. Anything else returns 400.

3.10 `null` is accepted only for fields this spec calls nullable. A `PATCH` changes only the fields present in its body, and setting a nullable field to `null` clears it. A `PATCH` with no fields it recognises returns 200 and changes nothing.

3.11 A request that returns an error changes nothing. Concurrent requests behave as if they were handled one at a time.

3.12 A list endpoint returns a JSON array, in the order its clause gives.

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

<!-- Next: accounts, payees and categories (sections 5 to 7). -->
