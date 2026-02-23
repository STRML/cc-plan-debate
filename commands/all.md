---
description: Run ALL available AI reviewers in parallel on the current plan, synthesize their feedback, debate contradictions, and produce a consensus verdict. Supports Codex, Gemini, and Claude Opus with graceful fallback if any are unavailable.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(which codex:*), Bash(which gemini:*), Bash(which claude:*), Bash(which jq:*), Bash(jq:*), Bash(codex exec -m:*), Bash(codex exec resume:*), Bash(gemini -p:*), Bash(gemini --list-sessions:*), Bash(gemini --resume:*), Bash(claude -p:*), Bash(claude --resume:*), Bash(timeout:*), Bash(gtimeout:*), Bash(diff:*), Bash(chmod +x /tmp/ai-review-:*), Bash(/tmp/ai-review-:*)
---

# AI Multi-Model Plan Review

Run all available AI reviewers in parallel, synthesize their feedback, debate contradictions, and produce a final consensus verdict. Max 3 total revision rounds.

Arguments:
- `skip-debate` — skip the targeted debate phase, go straight to final report

---

## Step 1: Prerequisite Check & Setup

### 1a. Check available reviewers

```bash
which codex
which gemini
which claude
which jq
```

Build `AVAILABLE_REVIEWERS` from the results. Display a prerequisite summary:

```text
## AI Review — Prerequisite Check

Reviewers found:
  ✅ codex    (OpenAI Codex)
  ✅ gemini   (Google Gemini)
  ✅ claude   (Anthropic Claude Opus)

Reviewers missing:
  ❌ [none]

Tools:
  ✅ jq       (JSON parser — required for Claude output)
```

If a reviewer binary is missing, show how to install it:

| Reviewer | Install Command |
|----------|----------------|
| codex | `npm install -g @openai/codex` + set `OPENAI_API_KEY` |
| gemini | `npm install -g @google/gemini-cli` + run `gemini auth` |
| claude | `npm install -g @anthropic-ai/claude-code` |

If `jq` is missing and `claude` is available, warn:
`jq is required for Claude output parsing — install: brew install jq (macOS) / apt install jq (Linux)`
And skip Claude reviewer until jq is installed.

If Gemini is available, verify it is authenticated:

```bash
gemini --list-sessions > /dev/null 2>&1
```

If this fails, warn: `Gemini is not authenticated — run: gemini auth`

**If NO reviewers are available**, stop and display the full install guide, then exit.

**If fewer than 2 reviewers are available**, note which is missing and proceed with the single available reviewer. Skip Step 5 (debate) entirely when only 1 reviewer runs — debate requires at least 2 reviewers.

### 1b. Resolve timeout command

Resolve once and build as an array — macOS ships `gtimeout` (coreutils), Linux ships `timeout`:

```bash
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 120)
else
  echo "Warning: neither 'timeout' nor 'gtimeout' found."
  echo "Install with: brew install coreutils"
  echo "Proceeding without timeout protection."
  TIMEOUT_CMD=()
fi
```

Invoke as `"${TIMEOUT_CMD[@]}" codex exec ...` — when `TIMEOUT_CMD` is empty this reduces to just `codex exec ...`.

### 1c. Generate session ID & temp dir

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/ai-review-${REVIEW_ID}
```

Temp file paths:
- Plan: `/tmp/ai-review-${REVIEW_ID}/plan.md`
- Codex output: `/tmp/ai-review-${REVIEW_ID}/codex-output.md`
- Codex stdout (for session ID): `/tmp/ai-review-${REVIEW_ID}/codex-stdout.txt`
- Codex exit code: `/tmp/ai-review-${REVIEW_ID}/codex-exit.txt`
- Gemini output: `/tmp/ai-review-${REVIEW_ID}/gemini-output.md`
- Gemini exit code: `/tmp/ai-review-${REVIEW_ID}/gemini-exit.txt`
- Opus JSON (raw): `/tmp/ai-review-${REVIEW_ID}/opus-raw.json`
- Opus output: `/tmp/ai-review-${REVIEW_ID}/opus-output.md`
- Opus exit code: `/tmp/ai-review-${REVIEW_ID}/opus-exit.txt`
- Sessions before: `/tmp/ai-review-${REVIEW_ID}/sessions-before.txt`
- Sessions after: `/tmp/ai-review-${REVIEW_ID}/sessions-after.txt`
- Runner script: `/tmp/ai-review-${REVIEW_ID}/run-parallel.sh`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/ai-review-${REVIEW_ID}` before stopping.

### 1d. Capture the plan

Write the current plan to `/tmp/ai-review-${REVIEW_ID}/plan.md`.

If there is no plan in the current context, ask the user to paste it or describe what they want reviewed.

### 1e. Announce

```text
Running parallel review with: codex, gemini, claude
Timeout per reviewer: 120s
```

Run `/debate:setup` to see the full permission allowlist and configure for unattended use.

---

## Step 2: Parallel Review (Round N)

**Snapshot Gemini sessions before launch:**
```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-before.txt
```

**Write the parallel runner script.** Note: `TIMEOUT_BIN` is passed as `$2` so the script can build its own array:

```bash
cat > /tmp/ai-review-${REVIEW_ID}/run-parallel.sh << 'SCRIPTEOF'
#!/bin/bash
REVIEW_ID="$1"
TIMEOUT_BIN="$2"

# Build timeout command array
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 120)
else
  TIMEOUT_CMD=()
fi

PIDS=()

if which codex > /dev/null 2>&1; then
  (
    "${TIMEOUT_CMD[@]}" codex exec \
      -m gpt-5.3-codex \
      -s read-only \
      -o /tmp/ai-review-${REVIEW_ID}/codex-output.md \
      "You are The Executor — a pragmatic runtime tracer. Review the implementation plan in /tmp/ai-review-${REVIEW_ID}/plan.md. Your job is to trace exactly what will happen at runtime. Assume nothing works until proven. Focus on:
1. Shell correctness — syntax errors, wrong flags, unquoted variables
2. Exit code handling — pipelines, \${PIPESTATUS}, timeout detection
3. Race conditions — PID capture, parallel job coordination, session ID timing
4. File I/O — are paths correct, do files exist before they are read, missing mkdir -p
5. Command availability — are all binaries assumed to be present without checking

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE" \
      2>&1 | tee /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt
    echo "${PIPESTATUS[0]}" > /tmp/ai-review-${REVIEW_ID}/codex-exit.txt
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
      < /tmp/ai-review-${REVIEW_ID}/plan.md \
      > /tmp/ai-review-${REVIEW_ID}/gemini-output.md 2>&1
    echo "$?" > /tmp/ai-review-${REVIEW_ID}/gemini-exit.txt
  ) &
  PIDS+=($!)
fi

if which claude > /dev/null 2>&1 && which jq > /dev/null 2>&1; then
  (
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
    "${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude -p \
      --model claude-opus-4-6 \
      --tools "" \
      --disable-slash-commands \
      --strict-mcp-config \
      --settings '{"disableAllHooks":true}' \
      --output-format json \
      "You are The Skeptic — a devil's advocate. Your job is to find what everyone else missed. Be specific, be harsh, be right. Review the implementation plan in /tmp/ai-review-${REVIEW_ID}/plan.md. Focus on:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one thing — if this plan has one fatal flaw, what is it?

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE" \
      > /tmp/ai-review-${REVIEW_ID}/opus-raw.json
    echo "$?" > /tmp/ai-review-${REVIEW_ID}/opus-exit.txt
    jq -r '.result // ""' /tmp/ai-review-${REVIEW_ID}/opus-raw.json \
      > /tmp/ai-review-${REVIEW_ID}/opus-output.md
  ) &
  PIDS+=($!)
fi

if [ ${#PIDS[@]} -gt 0 ]; then
  wait "${PIDS[@]}"
fi
echo "All reviewers complete"
SCRIPTEOF
chmod +x /tmp/ai-review-${REVIEW_ID}/run-parallel.sh
```

**Execute it:**
```bash
/tmp/ai-review-${REVIEW_ID}/run-parallel.sh "$REVIEW_ID" "$TIMEOUT_BIN"
```

### Check exit codes

Read each `*-exit.txt` file:
- `0` → success
- `124` → timed out (mark reviewer as timed-out, skip in synthesis)
- Other non-zero → error (mark as failed, note exit code)

**If all reviewers timed out or failed:**
```
## AI Review — UNDECIDED

All reviewers failed or timed out. No synthesis is possible.

Options:
- Increase timeout and re-run /debate:all
- Run /debate:codex-review or /debate:gemini-review individually
- Check reviewer installation and authentication
```
Then clean up and exit.

**Capture Codex session ID** from stdout:
```bash
grep 'session id:' /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt | head -1
```
Extract the UUID. Store as `CODEX_SESSION_ID`.

**Capture Gemini session UUID** by diffing the session list:
```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-after.txt
diff /tmp/ai-review-${REVIEW_ID}/sessions-before.txt \
     /tmp/ai-review-${REVIEW_ID}/sessions-after.txt
```
Find the new entry and parse its UUID from the `[uuid]` field. Store as `GEMINI_SESSION_UUID`.

If the diff shows multiple new sessions (concurrent usage), prefer the one whose title most closely matches the plan. If still ambiguous, set `GEMINI_SESSION_UUID=""` — resume will fall back to a fresh call if needed.

**Capture Opus session ID** from JSON output:
```bash
OPUS_SESSION_ID=$(jq -r '.session_id // ""' /tmp/ai-review-${REVIEW_ID}/opus-raw.json 2>/dev/null || echo "")
```
Store as `OPUS_SESSION_ID`. If the file doesn't exist or jq fails, set to `""`.

---

## Step 3: Present Reviewer Outputs

For each completed reviewer, display their output:

```
---
## Codex Review — Round N

[content of codex-output.md]

---
## Gemini Review — Round N

[content of gemini-output.md]

---
## Opus Review — Round N

[content of opus-output.md]
```

For timed-out or failed reviewers:
```
## [Reviewer] Review — Round N

⚠️ [Reviewer] timed out after 120s / failed (exit N). Skipping for synthesis.
```

---

## Step 4: Synthesize

Read all reviewer outputs and categorize:

```
## Synthesis — Round N

### Unanimous Agreements
- [Points all available reviewers agree on]

### Unique Insights
- [Reviewer]: [Point raised only by this reviewer]

### Contradictions
- Point A: Codex says X, Gemini says Y
- Point B: Codex says X, Opus says Y
- Point C: Gemini says X, Opus says Y
```

Extract each reviewer's verdict. Determine **overall verdict**:
- All available reviewers → APPROVED → skip debate, go to Step 6 (approved)
- Any reviewer → REVISE → continue to Step 5
- If only 1 reviewer succeeded → skip Step 5, treat that reviewer's verdict as final

---

## Step 5: Targeted Debate (unless `skip-debate` argument was passed, or fewer than 2 reviewers succeeded)

Max 2 debate rounds. Skip if there are no contradictions.

For each contradiction, send a targeted question to each reviewer in the disagreement via session resume.

**Build debate prompts from files** — never interpolate reviewer positions directly into shell strings:

```bash
# For Codex:
{
  echo "[Reviewer] raised a concern about [topic]: [their position]."
  echo "You said: [Codex's position]."
  echo "Can you address this specific disagreement? Do you stand by your position, or does their point change your assessment?"
} > /tmp/ai-review-${REVIEW_ID}/codex-debate-prompt.txt

DEBATE_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/codex-debate-prompt.txt)
"${TIMEOUT_CMD[@]}" codex exec resume ${CODEX_SESSION_ID} "$DEBATE_PROMPT" 2>&1 | tail -80
```

```bash
# For Gemini:
{
  echo "[Reviewer] raised a concern about [topic]: [their position]."
  echo "You said: [Gemini's position]."
  echo "Can you address this specific disagreement? Do you stand by your position, or does their point change your assessment?"
} > /tmp/ai-review-${REVIEW_ID}/gemini-debate-prompt.txt

DEBATE_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/gemini-debate-prompt.txt)
"${TIMEOUT_CMD[@]}" gemini --resume $GEMINI_SESSION_UUID -p "$DEBATE_PROMPT" -s -e "" 2>&1
```

```bash
# For Opus:
{
  echo "[Reviewer] raised a concern about [topic]: [their position]."
  echo "You said: [Opus's position]."
  echo "Can you address this specific disagreement? Do you stand by your position, or does their point change your assessment?"
} > /tmp/ai-review-${REVIEW_ID}/opus-debate-prompt.txt

DEBATE_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/opus-debate-prompt.txt)
if [ -n "$OPUS_SESSION_ID" ]; then
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
  "${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude --resume "$OPUS_SESSION_ID" \
    -p "$(cat /tmp/ai-review-${REVIEW_ID}/opus-debate-prompt.txt)" \
    --tools "" --disable-slash-commands --strict-mcp-config \
    --settings '{"disableAllHooks":true}' --output-format json \
    > /tmp/ai-review-${REVIEW_ID}/opus-debate-raw.json
  RESUME_EXIT=$?
  if [ "$RESUME_EXIT" -eq 0 ]; then
    jq -r '.result // ""' /tmp/ai-review-${REVIEW_ID}/opus-debate-raw.json
    NEW_SID=$(jq -r '.session_id // ""' /tmp/ai-review-${REVIEW_ID}/opus-debate-raw.json)
    [ -n "$NEW_SID" ] && OPUS_SESSION_ID="$NEW_SID"
  else
    echo "⚠️ Opus debate resume failed (exit $RESUME_EXIT) — skipping Opus debate response."
    OPUS_SESSION_ID=""
  fi
else
  # Fall back to fresh call; recapture OPUS_SESSION_ID from .session_id
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
  "${TIMEOUT_CMD[@]}" env CLAUDE_CODE_SIMPLE=1 claude -p \
    "$(cat /tmp/ai-review-${REVIEW_ID}/opus-debate-prompt.txt)" \
    --model claude-opus-4-6 \
    --tools "" --disable-slash-commands --strict-mcp-config \
    --settings '{"disableAllHooks":true}' --output-format json \
    > /tmp/ai-review-${REVIEW_ID}/opus-debate-raw.json
  jq -r '.result // ""' /tmp/ai-review-${REVIEW_ID}/opus-debate-raw.json
  OPUS_SESSION_ID=$(jq -r '.session_id // ""' /tmp/ai-review-${REVIEW_ID}/opus-debate-raw.json)
fi
```

If a session resume fails, skip that reviewer's debate response and note it.

Display each debate exchange:

```
### Debate Round N — [Topic]

**Codex:** [response]
**Gemini:** [response]
**Opus:** [response]

**Resolution:** [Claude's assessment: resolved/unresolved, why]
```

---

## Step 6: Final Report

```
---
## AI Review — Final Report (Round N of 3)

### Consensus Points
- [Things all reviewers agreed on, including post-debate convergence]

### Unresolved Disagreements
- [Contradictions that remained after debate, each reviewer's position]

### Claude's Recommendation
[Claude's synthesis: highest-priority concern, is the plan ready?]

### Overall VERDICT
VERDICT: APPROVED — All reviewers approved the plan.
   OR
VERDICT: REVISE — [Reviewer(s)] identified concerns that should be addressed.
   OR
VERDICT: SPLIT — Reviewers disagree. [Summary]. Claude recommends: [proceed/revise].
```

---

## Step 7: Revision Loop (if VERDICT: REVISE or SPLIT, max 3 total rounds)

1. **Claude revises the plan** — address highest-priority concerns from all reviewers
2. Write revision summary to a file (never inline in shell strings):
   ```bash
   cat > /tmp/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
   [Write revision bullets before closing the heredoc]
   EOF
   ```
3. Show revisions to the user:
   ```
   ### Revisions (Round N)
   - [What was changed and why]
   ```
4. Rewrite `/tmp/ai-review-${REVIEW_ID}/plan.md` with the revised plan
5. Snapshot Gemini sessions before re-launch
6. Return to **Step 2** with incremented round counter

If max rounds (3) reached without unanimous approval:

```
## AI Review — Max Rounds Reached

3 rounds completed. Remaining concerns:
[List unresolved issues]

You may:
- Address remaining concerns manually and re-run /debate:all
- Proceed at your own judgment given the reviewers' feedback
- Use /debate:codex-review or /debate:gemini-review for single-reviewer focused iteration
```

---

## Step 8: Cleanup

```bash
rm -rf /tmp/ai-review-${REVIEW_ID}
```

If any step failed before reaching this step, still run this cleanup.

---

## Rules

- **Security:** Never inline plan content or AI-generated text in shell strings — pass via file path, stdin redirect, or `$(cat file)` with a pre-written temp file
- **Parallelism:** Use the runner script approach so PIDs are captured correctly inside a single bash process with job control
- **Timeout array:** Always resolve `TIMEOUT_CMD` as an array at setup; use `"${TIMEOUT_CMD[@]}"` to invoke — empty array means no timeout, not a broken command
- **Exit codes:** Use `${PIPESTATUS[0]}` after Codex pipelines (pipeline starts with timeout); use `$?` directly after Gemini (stdin redirect, single command); use `$?` directly after Claude (single command)
- **Graceful degradation:** If only 1 reviewer is available, run the full flow and skip the debate phase
- **All-fail handling:** If all reviewers fail/timeout, return `UNDECIDED` with retry guidance
- **Session tracking:** Always recapture session IDs after fallback fresh calls — never reuse stale IDs
- **Gemini sessions:** Always use UUID from `--list-sessions` diff; if ambiguous, fall back to fresh call
- **Opus sessions:** Parse `OPUS_SESSION_ID` via `jq -r '.session_id'` from JSON output; always guard `--resume "$OPUS_SESSION_ID"` with `[ -n "$OPUS_SESSION_ID" ]`
- **Opus nested sessions:** Always `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT` inside the subshell before any `claude` invocation
- **Opus jq dependency:** Skip Claude reviewer if `jq` is not installed; show install guidance
- **Debate guard:** Explicitly skip Step 5 if fewer than 2 reviewers succeeded
- **Revision discipline:** Make real plan improvements, not cosmetic changes
- **User control:** If a revision would contradict the user's explicit requirements, skip it and note it
