---
description: Run ALL available AI reviewers in parallel on the current plan, synthesize their feedback, debate contradictions, and produce a consensus verdict. Supports Codex and Gemini with graceful fallback if either is unavailable.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(which codex:*), Bash(which gemini:*), Bash(codex exec -m:*), Bash(codex exec resume:*), Bash(gemini -p:*), Bash(gemini --list-sessions:*), Bash(gemini --resume:*), Bash(cat /tmp/ai-review-:*), Bash(timeout:*), Bash(gtimeout:*), Bash(sh -c:*), Bash(chmod +x /tmp/ai-review-:*), Bash(wait:*)
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
```

Build `AVAILABLE_REVIEWERS` from the results. Display a prerequisite summary:

```
## AI Review — Prerequisite Check

Reviewers found:
  ✅ codex    (OpenAI Codex)
  ✅ gemini   (Google Gemini)

Reviewers missing:
  ❌ [none]
```

If a reviewer binary is missing, show how to install it:

| Reviewer | Install Command |
|----------|----------------|
| codex | `npm install -g @openai/codex` + set `OPENAI_API_KEY` |
| gemini | `npm install -g @google/gemini-cli` + run `gemini auth` |

**If NO reviewers are available**, stop and display the full install guide, then exit.

**If at least one reviewer is available**, proceed with those that are.

### 1b. Resolve timeout binary

Resolve once — macOS ships `gtimeout`, Linux ships `timeout`:

```bash
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout)
```

If neither is found, warn the user (`Install GNU coreutils: brew install coreutils`) and proceed without a timeout wrapper by setting `TIMEOUT_BIN=env`.

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
- Sessions snapshot (before): `/tmp/ai-review-${REVIEW_ID}/sessions-before.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/ai-review-${REVIEW_ID}` before stopping.

### 1d. Capture the plan

Write the current plan to `/tmp/ai-review-${REVIEW_ID}/plan.md`.

If there is no plan in the current context, ask the user to paste it or describe what they want reviewed.

### 1e. Announce

```
Running parallel review with: codex, gemini
Timeout per reviewer: 120s

Suggested permission allowlist (run once to avoid prompts):
  Bash(codex exec -m:*), Bash(codex exec resume:*),
  Bash(gemini -p:*), Bash(gemini --list-sessions:*), Bash(gemini --resume:*),
  Bash(uuidgen:*), Bash(timeout:*), Bash(gtimeout:*), Bash(which:*),
  Bash(cat /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*)
```

---

## Step 2: Parallel Review (Round N)

Write a parallel runner script and execute it. This avoids PID-capture issues with the Bash tool's non-interactive shell:

**Snapshot Gemini sessions before launch:**
```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-before.txt
```

**Write the runner script:**
```bash
cat > /tmp/ai-review-${REVIEW_ID}/run-parallel.sh << 'SCRIPTEOF'
#!/bin/bash
REVIEW_ID="$1"
TIMEOUT_BIN="$2"
PIDS=()

if which codex > /dev/null 2>&1; then
  (
    "$TIMEOUT_BIN" 120 codex exec \
      -m gpt-5.3-codex \
      -s read-only \
      -o /tmp/ai-review-${REVIEW_ID}/codex-output.md \
      "Review the implementation plan in /tmp/ai-review-${REVIEW_ID}/plan.md. Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE" \
      2>&1 | tee /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt
    echo "${PIPESTATUS[0]}" > /tmp/ai-review-${REVIEW_ID}/codex-exit.txt
  ) &
  PIDS+=($!)
fi

if which gemini > /dev/null 2>&1; then
  (
    cat /tmp/ai-review-${REVIEW_ID}/plan.md | "$TIMEOUT_BIN" 120 gemini \
      -p "Review this implementation plan (provided via stdin). Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE" \
      -m gemini-3.1-pro-preview \
      -s \
      -e "" \
      > /tmp/ai-review-${REVIEW_ID}/gemini-output.md 2>&1
    echo "${PIPESTATUS[0]}" > /tmp/ai-review-${REVIEW_ID}/gemini-exit.txt
  ) &
  PIDS+=($!)
fi

# Wait only for the PIDs we actually launched
if [ ${#PIDS[@]} -gt 0 ]; then
  wait "${PIDS[@]}"
fi
SCRIPTEOF
chmod +x /tmp/ai-review-${REVIEW_ID}/run-parallel.sh
```

**Execute it:**
```bash
/tmp/ai-review-${REVIEW_ID}/run-parallel.sh $REVIEW_ID $TIMEOUT_BIN
```

### Check exit codes

Read each `*-exit.txt` file:
- `0` → success
- `124` → timed out (mark reviewer as timed-out, skip in synthesis)
- Other non-zero → error (mark as failed, note exit code)

**Capture Codex session ID** from stdout:
```bash
grep 'session id:' /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt | head -1
```
Extract the UUID. Store as `CODEX_SESSION_ID`.

**Capture Gemini session UUID** by diffing the session list:
```bash
gemini --list-sessions 2>/dev/null > /tmp/ai-review-${REVIEW_ID}/sessions-after.txt
```
Find the new entry in `sessions-after.txt` that wasn't in `sessions-before.txt`. Parse the UUID in `[...]` format. Store as `GEMINI_SESSION_UUID`.

This is more reliable than positional indexes, which shift when sessions are deleted.

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
```

Extract each reviewer's verdict. Determine **overall verdict**:
- All available reviewers → APPROVED → skip debate, go to Step 6 (approved)
- Any reviewer → REVISE → continue to Step 5

---

## Step 5: Targeted Debate (unless `skip-debate` argument was passed)

Max 2 debate rounds. Skip if there are no contradictions.

For each contradiction, send a targeted question to each reviewer via session resume.

**Write prompts to temp files first** — never interpolate reviewer positions or debate content into quoted shell strings directly:

```bash
cat > /tmp/ai-review-${REVIEW_ID}/codex-debate-prompt.txt << 'PROMPTEOF'
Gemini raised a concern about [specific point]: [Gemini's position — fill in].
You said [Codex's position — fill in]. Can you address this specific disagreement?
Do you stand by your position, or does Gemini's point change your assessment?
PROMPTEOF

DEBATE_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/codex-debate-prompt.txt)
$TIMEOUT_BIN 60 codex exec resume ${CODEX_SESSION_ID} "$DEBATE_PROMPT" 2>&1 | tail -80
```

```bash
cat > /tmp/ai-review-${REVIEW_ID}/gemini-debate-prompt.txt << 'PROMPTEOF'
Codex raised a concern about [specific point]: [Codex's position — fill in].
You said [Gemini's position — fill in]. Can you address this specific disagreement?
Do you stand by your position, or does Codex's point change your assessment?
PROMPTEOF

DEBATE_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/gemini-debate-prompt.txt)
$TIMEOUT_BIN 60 gemini --resume $GEMINI_SESSION_UUID -p "$DEBATE_PROMPT" -s -e "" 2>&1
```

Display each response:

```
### Debate Round N — [Topic]

**Codex:** [response]
**Gemini:** [response]

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

## Step 7: Revision Loop (if VERDICT: REVISE, max 3 total rounds)

1. **Claude revises the plan** — address highest-priority concerns from all reviewers
2. Summarize what changed:
   ```
   ### Revisions (Round N)
   - [What was changed and why]
   ```
3. Rewrite `/tmp/ai-review-${REVIEW_ID}/plan.md` with the revised plan
4. Snapshot Gemini sessions before re-launch
5. Return to **Step 2** with incremented round counter

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

- **Security:** Never inline plan content or AI-generated text in shell command strings — pass via file path, stdin pipe, or temp file read into a variable
- **Parallelism:** Use the runner script approach so PIDs are captured correctly inside a single bash process
- **Exit codes:** Always use `${PIPESTATUS[0]}` (not `$?`) after pipelines to capture the real exit code through `tee`
- **Timeout:** Always resolve `TIMEOUT_BIN` first; use it for all reviewer calls
- **Graceful degradation:** If only one reviewer is available, run the full flow with that single reviewer
- **Timeout handling:** A timed-out reviewer is skipped in synthesis but noted in the report
- **Gemini sessions:** Always use UUID from `--list-sessions` diff — never positional indexes or `latest`
- **Debate scope:** Only query reviewers on points they specifically raised
- **Revision discipline:** Make real plan improvements, not cosmetic changes
- **User control:** If a revision would contradict the user's explicit requirements, skip it and note it
- **Custom reviewers:** Users can add reviewer definitions at `~/.claude/ai-review/reviewers/` — any `.md` file there overrides built-in reviewers by name
