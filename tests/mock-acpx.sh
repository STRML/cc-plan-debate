#!/bin/bash
# Mock acpx binary for testing invoke-acpx.sh and run-parallel-acpx.sh.
#
# Behavior is controlled by environment variables:
#   MOCK_ACPX_EXIT     — exit code (default: 0)
#   MOCK_ACPX_RESPONSE — text to write to stdout (default: "Mock review. VERDICT: APPROVED")
#   MOCK_ACPX_DELAY    — seconds to sleep before responding (default: 0)
#   MOCK_ACPX_STDERR   — text to write to stderr (default: "")
#   MOCK_ACPX_LOG      — file to append invocation args to (default: "")
#
# This script mimics `acpx --format quiet --approve-reads <agent> --file <prompt>`.
# It reads the --file argument to verify it exists, then outputs the response.
#
# Session subcommands:
#   MOCK_ACPX_SESSION_LIST_EXIT — exit code for `<agent> sessions list` (default: 0)
#   MOCK_ACPX_SESSION_NEW_EXIT  — exit code for `<agent> sessions new`  (default: 0)
#
# When invoked as `acpx <agent> sessions list|new`, returns the configured exit code.

# Handle session subcommands: acpx <agent> sessions <list|new>
if [ $# -ge 3 ] && [ "$2" = "sessions" ]; then
  LOG="${MOCK_ACPX_LOG:-}"
  if [ -n "$LOG" ]; then
    echo "acpx $*" >> "$LOG"
  fi
  case "$3" in
    list)
      exit "${MOCK_ACPX_SESSION_LIST_EXIT:-0}"
      ;;
    new)
      exit "${MOCK_ACPX_SESSION_NEW_EXIT:-0}"
      ;;
  esac
fi

EXIT_CODE="${MOCK_ACPX_EXIT:-0}"
# Use ${VAR-default} (no colon) so MOCK_ACPX_RESPONSE="" is respected as empty
RESPONSE="${MOCK_ACPX_RESPONSE-Mock review. VERDICT: APPROVED}"
DELAY="${MOCK_ACPX_DELAY:-0}"
STDERR="${MOCK_ACPX_STDERR:-}"
LOG="${MOCK_ACPX_LOG:-}"

# Log the invocation
if [ -n "$LOG" ]; then
  echo "acpx $*" >> "$LOG"
fi

# Parse args to find --file
FILE_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE_ARG="$2"; shift 2 ;;
    --format|--approve-reads|--approve-all|--deny-all|--timeout) shift 2 ;;
    --*) shift ;;
    *) shift ;;
  esac
done

# Verify prompt file exists (mimics real acpx behavior)
if [ -n "$FILE_ARG" ] && [ ! -f "$FILE_ARG" ]; then
  echo "Error: file not found: $FILE_ARG" >&2
  exit 1
fi

# Simulate delay
if [ "$DELAY" -gt 0 ] 2>/dev/null; then
  sleep "$DELAY"
fi

# Output
if [ -n "$STDERR" ]; then
  echo "$STDERR" >&2
fi

# Only output response if non-empty (simulates truly empty output)
if [ -n "$RESPONSE" ]; then
  echo "$RESPONSE"
fi
exit "$EXIT_CODE"
