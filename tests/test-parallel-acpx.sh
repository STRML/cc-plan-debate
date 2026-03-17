#!/bin/bash
# Tests for scripts/run-parallel-acpx.sh
# Uses mock-acpx.sh as a fake acpx binary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PARALLEL="$PROJECT_DIR/scripts/run-parallel-acpx.sh"
MOCK="$SCRIPT_DIR/mock-acpx.sh"

PASS=0
FAIL=0

# --- Helpers ---

setup_env() {
  local work_dir
  work_dir=$(mktemp -d)

  # Create config with 2 reviewers
  cat > "$work_dir/config.json" << 'EOF'
{
  "reviewers": {
    "alpha": { "agent": "codex", "timeout": 10 },
    "beta": { "agent": "gemini", "timeout": 10 }
  }
}
EOF

  echo "$work_dir"
}

run_test() {
  local name="$1"
  shift
  echo -n "  $name... "
  if "$@"; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

# --- Tests ---

test_parallel_happy_path() {
  local tmp_dir review_id work_dir
  tmp_dir=$(setup_env)
  review_id="test-$(date +%s)"
  work_dir=".tmp/ai-review-${review_id}"

  mkdir -p "$work_dir"
  echo "Test plan" > "$work_dir/plan.md"

  # Ensure mock acpx is on PATH
  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="Mock review. VERDICT: APPROVED" \
    bash "$PARALLEL" "$tmp_dir/config.json" "$review_id" 2>/dev/null

  local exit_code=$?

  # Both reviewers should have output
  [ -f "$work_dir/alpha-exit.txt" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }
  [ -f "$work_dir/beta-exit.txt" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }
  [ -f "$work_dir/alpha-output.md" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }
  [ -f "$work_dir/beta-output.md" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }

  # Both should succeed
  [ "$(cat "$work_dir/alpha-exit.txt")" = "0" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }
  [ "$(cat "$work_dir/beta-exit.txt")" = "0" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }

  rm -rf "$work_dir" "$tmp_dir"
}

test_subset_reviewers() {
  local tmp_dir review_id work_dir
  tmp_dir=$(setup_env)
  review_id="test-$(date +%s)-sub"
  work_dir=".tmp/ai-review-${review_id}"

  mkdir -p "$work_dir"
  echo "Test plan" > "$work_dir/plan.md"

  # Only run alpha
  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="Mock review. VERDICT: APPROVED" \
    bash "$PARALLEL" "$tmp_dir/config.json" "$review_id" "alpha" 2>/dev/null

  # Alpha should exist, beta should NOT
  [ -f "$work_dir/alpha-exit.txt" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }
  [ ! -f "$work_dir/beta-exit.txt" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }

  rm -rf "$work_dir" "$tmp_dir"
}

test_missing_plan_fails() {
  local tmp_dir review_id work_dir
  tmp_dir=$(setup_env)
  review_id="test-$(date +%s)-noplan"
  work_dir=".tmp/ai-review-${review_id}"

  mkdir -p "$work_dir"
  # No plan.md

  set +e
  bash "$PARALLEL" "$tmp_dir/config.json" "$review_id" 2>/dev/null
  local exit_code=$?
  set -e

  [ "$exit_code" -ne 0 ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }

  rm -rf "$work_dir" "$tmp_dir"
}

test_missing_config_fails() {
  local review_id work_dir
  review_id="test-$(date +%s)-nocfg"
  work_dir=".tmp/ai-review-${review_id}"

  mkdir -p "$work_dir"
  echo "Test plan" > "$work_dir/plan.md"

  set +e
  bash "$PARALLEL" "/nonexistent/config.json" "$review_id" 2>/dev/null
  local exit_code=$?
  set -e

  [ "$exit_code" -ne 0 ] || { rm -rf "$work_dir"; return 1; }

  rm -rf "$work_dir"
}

test_prompt_files_cleaned_up() {
  local tmp_dir review_id work_dir
  tmp_dir=$(setup_env)
  review_id="test-$(date +%s)-clean"
  work_dir=".tmp/ai-review-${review_id}"

  mkdir -p "$work_dir"
  echo "Test plan" > "$work_dir/plan.md"
  # Simulate leftover prompt files from a prior debate
  echo "old prompt" > "$work_dir/alpha-prompt.txt"

  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="Mock review. VERDICT: APPROVED" \
    bash "$PARALLEL" "$tmp_dir/config.json" "$review_id" 2>/dev/null

  # Prompt files should be cleaned up
  [ ! -f "$work_dir/alpha-prompt.txt" ] || { rm -rf "$work_dir" "$tmp_dir"; return 1; }

  rm -rf "$work_dir" "$tmp_dir"
}

test_invalid_review_id_rejected() {
  set +e
  bash "$PARALLEL" "/dev/null" "../escape" 2>/dev/null
  local exit_code=$?
  set -e

  [ "$exit_code" -ne 0 ] || return 1
}

# --- Run ---

echo ""
echo "=== run-parallel-acpx.sh tests ==="
echo ""

# Rename mock to 'acpx' so PATH lookup finds it
ln -sf "$MOCK" "$SCRIPT_DIR/acpx"
chmod +x "$SCRIPT_DIR/acpx"
trap 'rm -f "$SCRIPT_DIR/acpx"' EXIT

run_test "parallel happy path" test_parallel_happy_path
run_test "subset reviewers" test_subset_reviewers
run_test "missing plan fails" test_missing_plan_fails
run_test "missing config fails" test_missing_config_fails
run_test "prompt files cleaned up" test_prompt_files_cleaned_up
run_test "invalid review ID rejected" test_invalid_review_id_rejected

echo ""
echo "=== Results: $PASS passed, $FAIL failed ($(( PASS + FAIL )) total) ==="

[ "$FAIL" -eq 0 ]
