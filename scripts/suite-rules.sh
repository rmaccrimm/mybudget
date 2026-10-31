# The naming rule for tests in testsuite/tests. Sourced by test.sh and judge.sh.
#
# A test's name starts with the spec clause it checks: spec_3_2_rejects_duplicate_name
# checks SPEC 3.2. The part after the clause starts with a letter. The implementer never
# sees the tests, and the judge reports failures to it by clause, so the name is how a
# failure gets back to the spec.

# clause_of <test name>: prints the clause, such as "3.2", or nothing if the name has none.
clause_of() {
  sed -nE 's/^(.*::)?spec_([0-9]+(_[0-9]+)*)_[A-Za-z].*/\2/p' <<<"$1" | tr _ .
}

# naming_problems <spec file>: reads test names on stdin and prints a line for each test
# that doesn't name a clause, or names one the spec doesn't have.
naming_problems() {
  local spec="$1" name clause
  while IFS= read -r name; do
    clause="$(clause_of "$name")"
    if [[ -z $clause ]]; then
      echo "$name: name doesn't start with spec_<clause>_"
    elif ! grep -qE "^${clause//./\\.} " "$spec"; then
      echo "$name: SPEC $clause isn't in the spec"
    fi
  done
}
