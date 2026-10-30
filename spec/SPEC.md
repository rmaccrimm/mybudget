# MyBudget server spec

This is the contract between the tester and the implementer. Only humans edit it. Number every requirement so tests can cite it (`/// SPEC 2.1`). When an agent raises a `QUESTION:` or `DISPUTE:`, settle it by changing this file.

## 1. Process

1.1 The server binary is `mybudget-server`.

1.2 It listens on the address in the `MYBUDGET_ADDR` environment variable, `ip:port`, defaulting to `127.0.0.1:8080`. Port `0` means any free port.

1.3 Once it is listening, its first line on stdout is exactly `listening on <ip>:<port>`, giving the actual port.

## 2. Health

2.1 `GET /health` returns `200` with the body `ok`.

2.2 A request to a path the API doesn't define returns `404`.

<!-- Next: accounts, transactions, categories, budgets. -->
