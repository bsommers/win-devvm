#!/usr/bin/env bash
# Run all repo test suites. Plain bash (3.2 compatible); no bats.
# Exit status: 0 if every suite passes, 1 otherwise.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0
for t in contract.sh syntax.sh; do
  echo "== $t"
  bash "$ROOT/tests/$t" || rc=1
  echo
done

if [ "$rc" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "SOME SUITES FAILED"
fi
exit $rc
