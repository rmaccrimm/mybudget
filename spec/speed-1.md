Make the slowest tests faster and steadier on a busy machine, without weakening what they check. The spec hasn't changed, and the server needs no changes for this.

The judge now runs four tests at once, each still in its own process, sandbox and scratch directory. Run one at a time, the suite takes 170s; its 42 slowest tests take 134s of that. The slowest, with their times alone and alongside other tests:

- tests/process_persistence.rs, the three tests that call `fill_with_plans` (MANY_PLANS = 2,000 plans, each with an account, created over HTTP): 12.3s, 7.7s and 7.5s alone, and 16 to 38s alongside other tests. Creating the plans is most of it. Under load `spec_1_4_exits_within_one_second_when_stdin_closes_while_plan_files_load` has failed in the judge because starting the server on those plans took longer than the harness's 10s STARTUP_TIMEOUT.
- tests/credit_edited_model.rs, `spec_15_5_edited_plans_survive_kills_and_go_on_matching_the_model`: 9.2s alone, up to 18s.
- tests/plan_files_startup.rs, `spec_15_6_nothing_is_left_beside_plan_files_after_a_kill_during_saves`: 6.8s alone.

Find ways to make these cheaper that keep each test meaningful. For example, decide how many plans a startup slow enough to close stdin during is really needed, make the plans faster, or build the data once where a test builds it twice. You can't write plan files from scratch with rusqlite: the spec doesn't define their schema, and copies of one plan count as duplicates (15.7). Waits where the spec gives no limit, such as STARTUP_TIMEOUT, should leave room for a machine running other tests; the spec's own limits, such as 1.4's one second, stay as they are. Don't remove tests or what they check, and keep the naming rule. The tests that wait on purpose in tests/process*.rs (STAYS_UP_FOR, LONG_IDLE) are fine as they are: they cost little CPU and run in parallel.

Every test passes today, so the whole suite should still pass. In your summary, list each slow test's time before and after.
