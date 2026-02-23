# Opus Reviewer — Implementation Plan

## Overview

Add Claude Opus as a third reviewer to the debate plugin, using the `claude` CLI (shell process, matching the codex/gemini architecture). Each reviewer gets a distinct persona that plays to its model's genuine strengths. Update `/debate:all` to run all three in parallel and `/debate:setup` to cover the new prereq.

---

## Files to Create/Modify

```text
reviewers/
  codex.md       — update prompt for Executor persona
  gemini.md      — update prompt for Architect persona
  opus.md        — new: Skeptic persona, claude CLI mechanics

commands/
  opus-review.md — new: standalone iterative loop (mirrors codex-review.md)
  all.md         — update: add Opus to parallel runner, three-way synthesis
  setup.md       — update: add claude prereq check + allowlist entries
```

---

## Reviewer Personas

### Codex — The Executor

Prompt angle: "You are a pragmatic executor. Your job is to trace exactly what will happen at runtime. Assume nothing works until proven."

Focus:
1. Shell correctness — syntax errors, wrong flags, unquoted variables
2. Exit code handling — pipelines, `${PIPESTATUS}`, timeout detection
3. Race conditions — PID capture, parallel job coordination, session ID timing
4. File I/O — paths correct, files exist before read, missing `mkdir -p`
5. Command availability — all binaries assumed present?

### Gemini — The Architect

Prompt angle: "You are a systems architect reviewing for structural integrity. Think big picture before line-by-line."

Focus:
1. Approach validity — is this the right solution to the actual problem?
2. Over-engineering — what could be simplified or removed?
3. Missing phases — is anything structurally absent from the flow?
4. Graceful degradation — does the design hold when parts fail?
5. Alternatives — is there a meaningfully better approach?

### Opus — The Skeptic

Prompt angle: "You are a devil's advocate. Your job is to find what everyone else missed. Be specific, be harsh, be right."

Focus:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one thing — if this plan has one fatal flaw, what is it?

---

## `reviewers/opus.md` — Mechanics

### Availability check

```bash
which claude
```

If not found: `npm install -g @anthropic-ai/claude-code`

### Critical: unset nested session guard

**Before any `claude` invocation**, unset the env vars that block nested calls:

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
```

This must be done inside the runner script subshell and in the standalone `opus-review.md` before each call. Without this, `claude -p` exits immediately with: `Claude Code cannot be launched inside another Claude Code session`.

### Initial review

Use `--output-format json` — this puts the full JSON result on stdout, which contains both the review text (`.result`) and the session ID (`.session_id`). No stderr needed.

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
"${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude -p \
  --model claude-opus-4-6 \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --output-format json \
  "You are The Skeptic. Review the implementation plan in {plan_file}. ..." \
  > {json_file}
OPUS_EXIT=$?
if [ "$OPUS_EXIT" -eq 124 ]; then
  echo "Opus timed out."; exit 1
elif [ "$OPUS_EXIT" -ne 0 ]; then
  echo "Opus failed (exit $OPUS_EXIT)."; exit 1
else
  jq -r '.result // ""' {json_file} > {output_file}
  OPUS_SESSION_ID=$(jq -r '.session_id // ""' {json_file})
fi
```

Flags:
- `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT` — **required** to allow nested invocation
- `CLAUDE_CODE_SIMPLE=1` — simple mode, no plugin/skill loading
- `--tools ""` — no tool access
- `--disable-slash-commands` — no skills
- `--strict-mcp-config` — no MCP servers
- `--settings '{"disableAllHooks":true}'` — no hooks
- `--output-format json` — structured output; `.result` is review text, `.session_id` is the resume key
- **No `--no-session-persistence`** — sessions kept for resume

**Verified**: `--output-format json` confirmed to emit `session_id` in stdout JSON. No stderr output in this mode.

### Session ID capture

Deterministic — parse from the JSON output file:

```bash
OPUS_SESSION_ID=$(jq -r '.session_id // ""' {json_file})
```

**Always guard resume on a non-empty session ID:**

```bash
if [ -n "$OPUS_SESSION_ID" ]; then
  # resume
else
  # fall back to fresh call, recapture session ID
fi
```

### Session resume

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
"${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude --resume "$OPUS_SESSION_ID" \
  -p "$(cat {prompt_file})" \
  --tools "" \
  --disable-slash-commands \
  --strict-mcp-config \
  --settings '{"disableAllHooks":true}' \
  --output-format json \
  > {json_file}
RESUME_EXIT=$?
if [ "$RESUME_EXIT" -eq 0 ]; then
  jq -r '.result // ""' {json_file} > {output_file}
  NEW_SID=$(jq -r '.session_id // ""' {json_file})
  [ -n "$NEW_SID" ] && OPUS_SESSION_ID="$NEW_SID"
fi
# On non-zero exit: fall back to fresh call, recapture OPUS_SESSION_ID
```

---

## `commands/opus-review.md` — Standalone Loop

Direct mirror of `codex-review.md` with:
- Model: `claude-opus-4-6` (override via argument, e.g. `/debate:opus-review claude-opus-4-5`)
- Persona: The Skeptic (full prompt in the review call)
- Temp files: `opus-raw.json`, `opus-output.md`, `opus-exit.txt`
- Session ID: captured from `--output-format json` stdout (`.session_id` field via jq), used for resume rounds 2–5
- Fallback: fresh call if resume fails, recapture session ID
- Max 5 rounds
- `allowed-tools` frontmatter: add `Bash(claude -p:*)`, `Bash(claude --resume:*)`

---

## `commands/all.md` — Parallel Runner Updates

### 1a. Prereq check

Add `which claude` to the availability check. Display three-way status:

```text
Reviewers found:
  ✅ codex    (OpenAI Codex)
  ✅ gemini   (Google Gemini)
  ✅ claude   (Anthropic Claude Opus)
```

Fewer-than-2 guard still applies. Debate phase requires ≥2 reviewers.

### 1c. Temp files

Add:
- Opus raw JSON: `/tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json`
- Opus output: `/tmp/claude/ai-review-${REVIEW_ID}/opus-output.md`
- Opus exit code: `/tmp/claude/ai-review-${REVIEW_ID}/opus-exit.txt`

### Runner script — Opus block

Add after the Gemini block:

```bash
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
      "You are The Skeptic. Review the implementation plan in /tmp/claude/ai-review-${REVIEW_ID}/plan.md. ..." \
      > /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json
    OPUS_EXIT=$?
    echo "$OPUS_EXIT" > /tmp/claude/ai-review-${REVIEW_ID}/opus-exit.txt
    if [ "$OPUS_EXIT" -eq 0 ]; then
      jq -r '.result // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json \
        > /tmp/claude/ai-review-${REVIEW_ID}/opus-output.md
    fi
  ) &
  PIDS+=($!)
fi
```

### Session ID capture

After runner completes, parse from the JSON output (no stderr in JSON mode):
```bash
OPUS_SESSION_ID=$(jq -r '.session_id // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json)
```
Store as `OPUS_SESSION_ID`. Guard all resume calls: `[ -n "$OPUS_SESSION_ID" ]`.

### Synthesis (Step 4)

Three-way synthesis: unanimous agreements, per-reviewer unique insights, and pairwise contradictions:
- Codex ↔ Gemini
- Codex ↔ Opus
- Gemini ↔ Opus

Overall verdict logic unchanged (any REVISE → REVISE, all APPROVED → APPROVED).

### Debate (Step 5)

Up to three pairwise debates. Each targeted question goes to both parties in the disagreement via session resume. Opus resume:

```bash
if [ -n "$OPUS_SESSION_ID" ]; then
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
  "${OPUS_TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude --resume "$OPUS_SESSION_ID" \
    -p "$(cat /tmp/claude/ai-review-${REVIEW_ID}/opus-debate-prompt.txt)" \
    --effort medium \
    --tools "" --disable-slash-commands --strict-mcp-config \
    --settings '{"disableAllHooks":true}' --output-format json \
    > /tmp/claude/ai-review-${REVIEW_ID}/opus-debate-raw.json
  RESUME_EXIT=$?
  if [ "$RESUME_EXIT" -eq 0 ]; then
    jq -r '.result // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-debate-raw.json
    NEW_SID=$(jq -r '.session_id // ""' /tmp/claude/ai-review-${REVIEW_ID}/opus-debate-raw.json)
    [ -n "$NEW_SID" ] && OPUS_SESSION_ID="$NEW_SID"
  fi
else
  # fresh call — recapture OPUS_SESSION_ID from .session_id
fi
```

### `allowed-tools` frontmatter

Add: `Bash(claude -p:*)`, `Bash(claude --resume:*)`

---

## `commands/setup.md` — Updates

### Step 1: Binary check

Add `which claude` to the check. Report found/missing with install command.

### Step 2: Codex auth

Unchanged.

### Step 3: Gemini auth

Unchanged.

### Step 3b: Claude + jq check (new) — also update `setup.md` frontmatter `allowed-tools`

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
claude --version
which jq
```

If `claude --version` succeeds, Claude Code CLI is installed. Note: `--version` only confirms binary presence, not authentication. Authentication uses Claude Code's own stored credentials — no separate API key needed. A failed review call will surface auth issues at runtime.

If `jq` is not found: `❌ jq: not found — install: brew install jq` (jq is required to parse JSON output from `claude -p --output-format json`).

### Step 5: Permission allowlist

Add to the printed snippet AND the frontmatter `allowed-tools`:
```json
"Bash(which claude:*)",
"Bash(claude --version:*)",
"Bash(claude -p:*)",
"Bash(claude --resume:*)"
```

### Step 6: Summary

Add Claude Opus to the final status block:
```text
  Codex:   ✅ ready (v0.x.x, API key set)
  Gemini:  ✅ ready (authenticated)
  Claude:  ✅ ready (v1.x.x)
  Timeout: ✅ /opt/homebrew/bin/timeout
```

---

## Verified Behavior

- **`--output-format json`** emits a single JSON object to stdout with `.result` (review text) and `.session_id` (UUID for resume). No stderr output. Confirmed empirically.
- **`unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT`** is required before nested `claude -p` calls. Without it: `Claude Code cannot be launched inside another Claude Code session`.
- **`jq`** is required as a new dependency to parse JSON output.

## Resolved Questions

1. **`--output-format json` with `--resume`**: ✅ Resolved — `.session_id` is present in resume responses. Implementation captures it via `NEW_SID=$(jq -r '.session_id // ""' ...)` and updates `OPUS_SESSION_ID` on every resume call.
2. **`CLAUDE_CODE_SIMPLE=1` with `--resume`**: ✅ Resolved — `env CLAUDE_CODE_SIMPLE=1` is passed on all resume calls in the implementation and works correctly.

---

## Implementation Order

1. Update `reviewers/codex.md` — add Executor persona prompt
2. Update `reviewers/gemini.md` — add Architect persona prompt
3. Create `reviewers/opus.md` — Skeptic persona + CLI mechanics
4. Create `commands/opus-review.md` — standalone loop
5. Update `commands/all.md` — three-way parallel runner
6. Update `commands/setup.md` — Claude prereq + allowlist
