#!/bin/bash
# Mock gemini binary for testing invoke-acpx.sh's direct CLI invocation path.
#
# Behavior is controlled by environment variables (MOCK_GEMINI_* preferred; MOCK_ACPX_* as fallback):
#   MOCK_GEMINI_EXIT     — exit code (default: 0)
#   MOCK_GEMINI_RESPONSE — stdout text (default: "Mock gemini review. VERDICT: APPROVED")
#   MOCK_GEMINI_DELAY    — seconds to sleep (default: 0)
#   MOCK_GEMINI_STDERR   — text to write to stderr (default: "")
#   MOCK_GEMINI_LOG      — file to append invocation args to (default: "")
#
# Invoked as: gemini -s -e "" < prompt_file
# Reads stdin (ignores it) and outputs the mock response.

EXIT_CODE="${MOCK_GEMINI_EXIT:-${MOCK_ACPX_EXIT:-0}}"
RESPONSE="${MOCK_GEMINI_RESPONSE-Mock gemini review. VERDICT: APPROVED}"
DELAY="${MOCK_GEMINI_DELAY:-${MOCK_ACPX_DELAY:-0}}"
STDERR="${MOCK_GEMINI_STDERR:-${MOCK_ACPX_STDERR:-}}"
GEMINI_LOG="${MOCK_GEMINI_LOG:-${MOCK_ACPX_LOG:-}}"
if [ -n "$GEMINI_LOG" ]; then
  echo "gemini $*" >> "$GEMINI_LOG"
fi

# Drain stdin so callers don't block
cat > /dev/null

# Simulate delay
if [ "$DELAY" -gt 0 ] 2>/dev/null; then
  sleep "$DELAY"
fi

if [ -n "$STDERR" ]; then
  echo "$STDERR" >&2
fi

if [ -n "$RESPONSE" ]; then
  echo "$RESPONSE"
fi
exit "$EXIT_CODE"
