SPEC section 15 (persistence), which is new. It comes before section 14 now.

Earlier clauses changed with it: 3.2 and 3.4 add `500` for a change the server couldn't save (15.10), and 3.5 makes ids random version 4 UUIDs in lowercase, a different format from the server's current ids. Update any older tests that assume otherwise.

For the tester:
- Give every server that sets `MYBUDGET_DATA` a fresh directory under the test's `TMPDIR`. Tests that don't set it keep testing the in-memory server.
- The harness needs to restart a server on the same directory, kill it with `SIGKILL`, run `mybudget-server migrate`, and open plan files with `rusqlite` (with its `bundled` feature): to check file names, `user_version` and leftover journal files, and to plant files the server must skip.
- Persistence covers every kind of data the earlier sections define. Check that, for example by running the model-based test or the main scenarios against a server with `MYBUDGET_DATA` set, restarting it partway through and checking that nothing changed.
- Only schema version 1 exists so far, so 15.9 can only be tested with version 1 and with invalid versions.

For the implementer:
- Use `rusqlite` 0.41 with the `bundled` feature (`rusqlite_migration` 2.7 needs that version), `rusqlite_migration` for the schema versions, and `uuid` for ids.
- Keep the in-memory `Store` and its budget logic. Load every plan file at startup, and write each change through to its plan's file, in one SQLite transaction, before responding.
- A save can fail (15.10), which is the one exception to checking everything before changing anything: save before changing the `Store`, or put the `Store` back when the save fails.
- Keep each migration in `migrations/`, with both an up and a down. Once this round ends, version 1's migration never changes; later rounds add new ones.
- Use one table per kind of object, with explicit columns for list order, so a plan file is easy to read in any SQLite tool.
