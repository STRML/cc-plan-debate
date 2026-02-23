#!/bin/bash
# Static parallel runner for debate plugin — executed by /debate:all
# Usage: run-parallel.sh <REVIEW_ID> <TIMEOUT_BIN>
#   REVIEW_ID   — 8-char hex ID used for all temp file paths
#   TIMEOUT_BIN — path to timeout binary (optional; empty = no timeout)

REVIEW_ID="$1"
TIMEOUT_BIN="$2"

if [ -z "$REVIEW_ID" ]; then
  echo "Usage: $0 <REVIEW_ID> [TIMEOUT_BIN]" >&2
  exit 1
fi

WORK_DIR="/tmp/claude/ai-review-${REVIEW_ID}"

mkdir -p "$WORK_DIR" || { echo "Failed to create $WORK_DIR" >&2; exit 1; }

# Codex/Gemini: 120s. Opus gets 300s — claude CLI startup adds overhead.
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 120)
  OPUS_TIMEOUT_CMD=("$TIMEOUT_BIN" 300)
else
  TIMEOUT_CMD=()
  OPUS_TIMEOUT_CMD=()
fi

PIDS=()

if which codex > /dev/null 2>&1; then
  (
    "${TIMEOUT_CMD[@]}" codex exec \
      -m gpt-5.3-codex \
      -s read-only \
      -o "${WORK_DIR}/codex-output.md" \
      "You are The Executor — a pragmatic runtime tracer. Review the implementation plan in ${WORK_DIR}/plan.md. Your job is to trace exactly what will happen at runtime. Assume nothing works until proven. Focus on:
1. Shell correctness — syntax errors, wrong flags, unquoted variables
2. Exit code handling — pipelines, \${PIPESTATUS}, timeout detection
3. Race conditions — PID capture, parallel job coordination, session ID timing
4. File I/O — are paths correct, do files exist before they are read, missing mkdir -p
5. Command availability — are all binaries assumed to be present without checking

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE" \
      2>&1 | tee "${WORK_DIR}/codex-stdout.txt"
    echo "${PIPESTATUS[0]}" > "${WORK_DIR}/codex-exit.txt"
  ) &
  PIDS+=($!)
fi

if which gemini > /dev/null 2>&1; then
  (
    "${TIMEOUT_CMD[@]}" gemini \
      -p "You are The Architect — a systems architect reviewing for structural integrity. Review this implementation plan (provided via stdin). Think big picture before line-by-line. Focus on:
1. Approach validity — is this the right solution to the actual problem?
2. Over-engineering — what could be simplified or removed?
3. Missing phases — is anything structurally absent from the flow?
4. Graceful degradation — does the design hold when parts fail?
5. Alternatives — is there a meaningfully better approach?

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE" \
      -m gemini-3.1-pro-preview \
      -s \
      -e "" \
      < "${WORK_DIR}/plan.md" \
      > "${WORK_DIR}/gemini-output.md" 2>&1
    echo "$?" > "${WORK_DIR}/gemini-exit.txt"
  ) &
  PIDS+=($!)
fi

if which claude > /dev/null 2>&1 && which jq > /dev/null 2>&1; then
  (
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
    "${OPUS_TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude -p \
      --model claude-opus-4-6 \
      --effort medium \
      --tools "" \
      --disable-slash-commands \
      --strict-mcp-config \
      --settings '{"disableAllHooks":true}' \
      --output-format json \
      "You are The Skeptic — a devil's advocate. Your job is to find what everyone else missed. Be specific, be harsh, be right. Review the implementation plan in ${WORK_DIR}/plan.md. Focus on:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one thing — if this plan has one fatal flaw, what is it?

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE" \
      > "${WORK_DIR}/opus-raw.json"
    OPUS_EXIT=$?
    echo "$OPUS_EXIT" > "${WORK_DIR}/opus-exit.txt"
    if [ "$OPUS_EXIT" -eq 0 ]; then
      jq -r '.result // ""' "${WORK_DIR}/opus-raw.json" \
        > "${WORK_DIR}/opus-output.md"
    fi
  ) &
  PIDS+=($!)
fi

if [ ${#PIDS[@]} -gt 0 ]; then
  wait "${PIDS[@]}"
fi
echo "All reviewers complete"
