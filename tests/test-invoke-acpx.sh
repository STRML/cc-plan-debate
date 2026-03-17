#!/bin/bash
# Tests for scripts/invoke-acpx.sh
# Uses mock-acpx.sh as a fake acpx binary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INVOKE="$PROJECT_DIR/scripts/invoke-acpx.sh"
MOCK="$SCRIPT_DIR/mock-acpx.sh"

PASS=0
FAIL=0
TESTS=()

# --- Helpers ---

setup_work_dir() {
  local dir
  dir=$(mktemp -d)
  echo "Test plan content" > "$dir/plan.md"
  echo "$dir"
}

setup_config() {
  local dir="$1"
  cat > "$dir/config.json" << 'EOF'
{
  "reviewers": {
    "test-reviewer": {
      "agent": "codex",
      "timeout": 30,
      "system_prompt": "You are a test reviewer."
    },
    "no-prompt": {
      "agent": "gemini",
      "timeout": 60
    }
  }
}
EOF
  echo "$dir/config.json"
}

run_test() {
  local name="$1"
  shift
  TESTS+=("$name")
  echo -n "  $name... "
  if "$@"; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

cleanup() {
  rm -rf "$WORK_DIR" 2>/dev/null || true
}

# --- Tests ---

test_happy_path() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")

  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="Great plan! VERDICT: APPROVED" \
    bash "$INVOKE" "$config" "$work_dir" "test-reviewer" 2>/dev/null

  # Check output file
  [ -f "$work_dir/test-reviewer-output.md" ] || return 1
  grep -q "VERDICT: APPROVED" "$work_dir/test-reviewer-output.md" || return 1

  # Check exit file
  [ -f "$work_dir/test-reviewer-exit.txt" ] || return 1
  [ "$(cat "$work_dir/test-reviewer-exit.txt")" = "0" ] || return 1

  rm -rf "$work_dir"
}

test_prompt_file_used_for_debate() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")

  # Write a debate prompt
  echo "Debate: do you still think X?" > "$work_dir/test-reviewer-prompt.txt"

  local log_file="$work_dir/acpx-log.txt"

  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="I stand by my position. VERDICT: REVISE" \
  MOCK_ACPX_LOG="$log_file" \
    bash "$INVOKE" "$config" "$work_dir" "test-reviewer" 2>/dev/null

  # The prompt file passed to acpx should be the debate prompt, not the generated one
  grep -q "test-reviewer-prompt.txt" "$log_file" || return 1

  # Should NOT have generated an acpx-prompt file
  [ ! -f "$work_dir/test-reviewer-acpx-prompt.txt" ] || return 1

  rm -rf "$work_dir"
}

test_initial_prompt_includes_plan() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")

  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="Looks good. VERDICT: APPROVED" \
    bash "$INVOKE" "$config" "$work_dir" "test-reviewer" 2>/dev/null

  # Generated prompt should include system prompt and plan
  [ -f "$work_dir/test-reviewer-acpx-prompt.txt" ] || return 1
  grep -q "You are a test reviewer" "$work_dir/test-reviewer-acpx-prompt.txt" || return 1
  grep -q "Test plan content" "$work_dir/test-reviewer-acpx-prompt.txt" || return 1

  rm -rf "$work_dir"
}

test_fallback_system_prompt() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")

  # "no-prompt" reviewer has no system_prompt in config
  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="VERDICT: APPROVED" \
    bash "$INVOKE" "$config" "$work_dir" "no-prompt" 2>/dev/null

  # Should use the built-in fallback
  grep -q "senior engineer" "$work_dir/no-prompt-acpx-prompt.txt" || return 1

  rm -rf "$work_dir"
}

test_acpx_failure_populates_output() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")

  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_EXIT=1 \
  MOCK_ACPX_RESPONSE="" \
  MOCK_ACPX_STDERR="connection refused" \
    bash "$INVOKE" "$config" "$work_dir" "test-reviewer" 2>/dev/null || true

  # Exit file should be non-zero
  [ "$(cat "$work_dir/test-reviewer-exit.txt")" != "0" ] || return 1

  # Output should contain error info
  grep -q "acpx error" "$work_dir/test-reviewer-output.md" || return 1

  rm -rf "$work_dir"
}

test_empty_response_detected() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")

  set +e
  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_EXIT=0 \
  MOCK_ACPX_RESPONSE="" \
    bash "$INVOKE" "$config" "$work_dir" "test-reviewer" 2>/dev/null
  local exit_code=$?
  set -e

  # Should fail with exit 1
  [ "$exit_code" -eq 1 ] || return 1

  # Exit file should be 1
  [ "$(cat "$work_dir/test-reviewer-exit.txt")" = "1" ] || return 1

  # Output should mention empty response
  grep -q "Empty response" "$work_dir/test-reviewer-output.md" || return 1

  rm -rf "$work_dir"
}

test_missing_config_fails() {
  local work_dir
  work_dir=$(setup_work_dir)

  set +e
  bash "$INVOKE" "/nonexistent/config.json" "$work_dir" "test" 2>/dev/null
  local exit_code=$?
  set -e

  [ "$exit_code" -ne 0 ] || return 1

  rm -rf "$work_dir"
}

test_missing_plan_fails() {
  local work_dir config
  work_dir=$(mktemp -d)
  config=$(setup_config "$work_dir")

  # No plan.md in work_dir
  set +e
  bash "$INVOKE" "$config" "$work_dir" "test-reviewer" 2>/dev/null
  local exit_code=$?
  set -e

  [ "$exit_code" -ne 0 ] || return 1

  rm -rf "$work_dir"
}

test_unknown_reviewer_fails() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")

  set +e
  bash "$INVOKE" "$config" "$work_dir" "nonexistent-reviewer" 2>/dev/null
  local exit_code=$?
  set -e

  [ "$exit_code" -ne 0 ] || return 1

  rm -rf "$work_dir"
}

test_timeout_override() {
  local work_dir config
  work_dir=$(setup_work_dir)
  config=$(setup_config "$work_dir")
  local log_file="$work_dir/acpx-log.txt"

  # Pass timeout as 4th arg — the invoke script wraps with system timeout binary
  PATH="$SCRIPT_DIR:$PATH" \
  MOCK_ACPX_RESPONSE="VERDICT: APPROVED" \
  MOCK_ACPX_LOG="$log_file" \
    bash "$INVOKE" "$config" "$work_dir" "test-reviewer" "45" 2>/dev/null

  # Can't easily verify the timeout value was used (it's an arg to the timeout binary),
  # but we can verify the script succeeded
  [ "$(cat "$work_dir/test-reviewer-exit.txt")" = "0" ] || return 1

  rm -rf "$work_dir"
}

# --- Run ---

echo ""
echo "=== invoke-acpx.sh tests ==="
echo ""

# Rename mock to 'acpx' so PATH lookup finds it
ln -sf "$MOCK" "$SCRIPT_DIR/acpx"
chmod +x "$SCRIPT_DIR/acpx"
trap 'rm -f "$SCRIPT_DIR/acpx"' EXIT

run_test "happy path" test_happy_path
run_test "debate prompt file" test_prompt_file_used_for_debate
run_test "initial prompt includes plan" test_initial_prompt_includes_plan
run_test "fallback system prompt" test_fallback_system_prompt
run_test "acpx failure populates output" test_acpx_failure_populates_output
run_test "empty response detected" test_empty_response_detected
run_test "missing config fails" test_missing_config_fails
run_test "missing plan fails" test_missing_plan_fails
run_test "unknown reviewer fails" test_unknown_reviewer_fails
run_test "timeout override" test_timeout_override

echo ""
echo "=== Results: $PASS passed, $FAIL failed ($(( PASS + FAIL )) total) ==="

[ "$FAIL" -eq 0 ]
