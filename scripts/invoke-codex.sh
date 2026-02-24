#!/bin/bash
# Single Codex reviewer invocation — initial call or session resume.
# Uses --json for structured JSONL output; extracts session ID, review text,
# and error messages from events rather than fragile text-pattern parsing.
#
# Usage: invoke-codex.sh <work_dir> [session_id] [model]
#   work_dir   — temp directory for this review (must contain plan.md)
#   session_id — optional; if set, attempts resume; falls back to fresh on failure
#   model      — optional; defaults to gpt-5.3-codex
#
# Env: TIMEOUT_BIN — optional path to timeout binary (timeout or gtimeout)
#
# Prompt selection:
#   If $work_dir/codex-prompt.txt exists, its contents are used as the prompt.
#   Otherwise (initial review), the standard Executor persona prompt is used.
#
# Plan content is always injected directly — never referenced by path, for
# consistency and to avoid any file-access issues across sandbox configurations.
#
# Output files (all written to $work_dir):
#   codex-output.md      review text (extracted from JSONL agent_message events)
#   codex-stdout.txt     raw JSONL stdout (for debugging)
#   codex-exit.txt       exit code
#   codex-session-id.txt session UUID (from thread.started event; empty on failure)

WORK_DIR="${1:-}"
SESSION_ID="${2:-}"
MODEL="${3:-gpt-5.3-codex}"

if [ -z "$WORK_DIR" ]; then
  echo "Usage: $0 <work_dir> [session_id] [model]" >&2
  exit 1
fi

if [ ! -d "$WORK_DIR" ]; then
  echo "invoke-codex.sh: work_dir does not exist: $WORK_DIR" >&2
  exit 1
fi

if [ ! -f "$WORK_DIR/plan.md" ]; then
  echo "invoke-codex.sh: plan.md not found in $WORK_DIR" >&2
  exit 1
fi

# Resolve timeout
if [ -z "${TIMEOUT_BIN:-}" ]; then
  TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
fi
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 120)
else
  TIMEOUT_CMD=()
fi

# Prompt selection
if [ -f "$WORK_DIR/codex-prompt.txt" ]; then
  PROMPT="$(cat "$WORK_DIR/codex-prompt.txt")"
else
  PLAN_CONTENT="$(cat "$WORK_DIR/plan.md")"
  PROMPT="You are The Executor — a pragmatic runtime tracer. Review this implementation plan:

$PLAN_CONTENT

Your job is to trace exactly what will happen at runtime. Assume nothing works until proven. Focus on:
1. Shell correctness — syntax errors, wrong flags, unquoted variables
2. Exit code handling — pipelines, \${PIPESTATUS}, timeout detection
3. Race conditions — PID capture, parallel job coordination, session ID timing
4. File I/O — are paths correct, do files exist before they are read, missing mkdir -p
5. Command availability — are all binaries assumed to be present without checking

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE"
fi

CODEX_EXIT=0

if [ -n "$SESSION_ID" ]; then
  # Resume: --json flag outputs JSONL; session ID extracted from thread.started event
  "${TIMEOUT_CMD[@]}" codex exec resume --json "$SESSION_ID" "$PROMPT" \
    2>&1 | tee "$WORK_DIR/codex-stdout.txt"
  CODEX_EXIT=${PIPESTATUS[0]}

  if [ "$CODEX_EXIT" -eq 124 ]; then
    echo "invoke-codex.sh: resume timed out (exit 124) — not falling back" >&2
    echo "124" > "$WORK_DIR/codex-exit.txt"
    : > "$WORK_DIR/codex-session-id.txt"
    exit 124
  elif [ "$CODEX_EXIT" -ne 0 ]; then
    echo "invoke-codex.sh: resume failed (exit $CODEX_EXIT) — falling back to fresh call" >&2
    SESSION_ID=""
  fi
fi

if [ -z "$SESSION_ID" ]; then
  # Fresh call: --json outputs JSONL to stdout; no -o needed (extracted below)
  "${TIMEOUT_CMD[@]}" codex exec \
    -m "$MODEL" \
    -s read-only \
    --json \
    "$PROMPT" \
    2>&1 | tee "$WORK_DIR/codex-stdout.txt"
  CODEX_EXIT=${PIPESTATUS[0]}
fi

echo "$CODEX_EXIT" > "$WORK_DIR/codex-exit.txt"

# Detect macOS sandbox panic — system-configuration crate crashes when
# SCDynamicStoreCreate returns NULL (blocked by Claude Code sandbox entitlements).
# This panic is emitted to stderr before any JSONL, so plain-text grep still works.
if [ "$CODEX_EXIT" -ne 0 ] && grep -q "Attempted to create a NULL object" "$WORK_DIR/codex-stdout.txt" 2>/dev/null; then
  {
    echo "## Codex — Sandbox Incompatible"
    echo ""
    echo "Codex CLI panicked (exit $CODEX_EXIT) due to a macOS sandbox restriction."
    echo ""
    echo "The Codex binary uses the \`system-configuration\` Rust crate which calls"
    echo "\`SCDynamicStoreCreate()\`. Inside the Claude Code sandbox this returns NULL,"
    echo "causing a Rust panic. This is a Codex binary issue, not a plan issue."
    echo ""
    echo "Fix: add \`codex:*\` to \`sandbox.excludedCommands\` in ~/.claude/settings.json"
    echo "     (run /debate:setup to see the exact snippet)"
  } > "$WORK_DIR/codex-output.md"
  echo "77" > "$WORK_DIR/codex-exit.txt"
  : > "$WORK_DIR/codex-session-id.txt"
  exit 77
fi

if [ "$CODEX_EXIT" -eq 0 ]; then
  # Extract session UUID from the thread.started JSONL event
  THREAD_ID=$(jq -r 'select(.type=="thread.started") | .thread_id' \
    "$WORK_DIR/codex-stdout.txt" 2>/dev/null | head -1)
  if [ -n "$THREAD_ID" ] && [ "$THREAD_ID" != "null" ]; then
    echo "$THREAD_ID" > "$WORK_DIR/codex-session-id.txt"
  else
    : > "$WORK_DIR/codex-session-id.txt"
  fi
  # Extract all agent_message texts in order as the review output
  jq -r 'select(.type=="item.completed") | select(.item.type=="agent_message") | .item.text' \
    "$WORK_DIR/codex-stdout.txt" 2>/dev/null > "$WORK_DIR/codex-output.md"
else
  : > "$WORK_DIR/codex-session-id.txt"
  # Surface error events from the JSONL stream for diagnostics;
  # fall back to raw stdout if no JSONL was emitted (e.g. pre-JSON panic).
  ERROR_TEXT=$(jq -r 'select(.type != null) | select(.type | ascii_downcase | contains("error")) | .message // .error // tostring' \
    "$WORK_DIR/codex-stdout.txt" 2>/dev/null | head -20)
  if [ -n "$ERROR_TEXT" ]; then
    printf 'Codex error (exit %s):\n%s\n' "$CODEX_EXIT" "$ERROR_TEXT" > "$WORK_DIR/codex-output.md"
  else
    printf 'Codex failed (exit %s). Raw output:\n\n' "$CODEX_EXIT" > "$WORK_DIR/codex-output.md"
    cat "$WORK_DIR/codex-stdout.txt" >> "$WORK_DIR/codex-output.md"
  fi
fi

exit "$CODEX_EXIT"
