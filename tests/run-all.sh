#!/bin/bash
# Run all tests for the debate plugin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==============================="
echo "  debate plugin test suite"
echo "==============================="

TOTAL_PASS=0
TOTAL_FAIL=0

run_suite() {
  local name="$1"
  local script="$2"
  echo ""
  if bash "$script"; then
    echo "  Suite passed."
  else
    echo "  Suite FAILED."
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    return 1
  fi
  TOTAL_PASS=$((TOTAL_PASS + 1))
}

SUITE_FAIL=0

run_suite "invoke-acpx" "$SCRIPT_DIR/test-invoke-acpx.sh" || SUITE_FAIL=$((SUITE_FAIL + 1))
run_suite "run-parallel-acpx" "$SCRIPT_DIR/test-parallel-acpx.sh" || SUITE_FAIL=$((SUITE_FAIL + 1))
run_suite "reference integrity" "$SCRIPT_DIR/test-references.sh" || SUITE_FAIL=$((SUITE_FAIL + 1))

echo ""
echo "==============================="
if [ "$SUITE_FAIL" -eq 0 ]; then
  echo "  All suites passed."
else
  echo "  $SUITE_FAIL suite(s) FAILED."
fi
echo "==============================="

exit "$SUITE_FAIL"
