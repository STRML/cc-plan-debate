---
description: Run ALL available AI reviewers in parallel on the current plan, synthesize their feedback, debate contradictions, and produce a consensus verdict. Supports Codex, Gemini, and Claude Opus with graceful fallback if any are unavailable.
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/run-parallel.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-codex.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-gemini.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-opus.sh:*), Bash(rm -rf /tmp/claude/ai-review-:*), Bash(which codex:*), Bash(which gemini:*), Bash(which claude:*), Bash(which jq:*), Bash(gemini -s:*), Write(/tmp/claude/ai-review-*)
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
echo "reply with only the word PONG" | timeout 30 gemini -s -e "" 2>/dev/null
```

If output does not contain "PONG" (case-insensitive), warn: `Gemini is not authenticated — run: gemini auth`

**If NO reviewers are available**, stop and display the full install guide, then exit.

**If fewer than 2 reviewers are available**, note which is missing and proceed with the single available reviewer. Skip Step 5 (debate) entirely when only 1 reviewer runs — debate requires at least 2 reviewers.

### 1b. Generate session ID & temp dir

If `~/.claude/debate-scripts` does not exist, stop and display:
```
~/.claude/debate-scripts not found.
Run /debate:setup first to create the stable scripts symlink.
```

Run the setup helper and note `REVIEW_ID`, `WORK_DIR`, and `SCRIPT_DIR` from the output:

```bash
bash ~/.claude/debate-scripts/debate-setup.sh
```

Then write `config.env` to `<WORK_DIR>/config.env` with the model values (use user-provided overrides or defaults):

```
CODEX_MODEL=<CODEX_MODEL|gpt-5.3-codex>
GEMINI_MODEL=<GEMINI_MODEL|gemini-3.1-pro-preview>
OPUS_MODEL=<OPUS_MODEL|claude-opus-4-6>
```

Use `SCRIPT_DIR` for all subsequent `bash` calls — never re-glob.

Temp file paths:
- Plan: `/tmp/claude/ai-review-${REVIEW_ID}/plan.md`
- Codex output: `/tmp/claude/ai-review-${REVIEW_ID}/codex-output.md`
- Codex exit code: `/tmp/claude/ai-review-${REVIEW_ID}/codex-exit.txt`
- Codex session ID: `/tmp/claude/ai-review-${REVIEW_ID}/codex-session-id.txt`
- Gemini output: `/tmp/claude/ai-review-${REVIEW_ID}/gemini-output.md`
- Gemini exit code: `/tmp/claude/ai-review-${REVIEW_ID}/gemini-exit.txt`
- Gemini session UUID: `/tmp/claude/ai-review-${REVIEW_ID}/gemini-session-id.txt`
- Opus JSON (raw): `/tmp/claude/ai-review-${REVIEW_ID}/opus-raw.json`
- Opus output: `/tmp/claude/ai-review-${REVIEW_ID}/opus-output.md`
- Opus exit code: `/tmp/claude/ai-review-${REVIEW_ID}/opus-exit.txt`
- Opus session ID: `/tmp/claude/ai-review-${REVIEW_ID}/opus-session-id.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/claude/ai-review-${REVIEW_ID}` before stopping.

### 1c. Capture the plan

Write the current plan to `/tmp/claude/ai-review-${REVIEW_ID}/plan.md`.

If there is no plan in the current context, ask the user to paste it or describe what they want reviewed.

### 1d. Announce

```text
Running parallel review with: codex, gemini, claude
Timeout: codex 120s, gemini 240s, opus 300s
```

Run `/debate:setup` to see the full permission allowlist and configure for unattended use.

---

## Step 2: Parallel Review (Round N)

**Execute the parallel runner script** from the plugin:

```bash
bash "<SCRIPT_DIR>/run-parallel.sh" "<REVIEW_ID>"
```

The script is pre-built in the plugin — Codex runs with 120s, Gemini with 240s, Opus with 300s (the `claude` CLI has more startup overhead). Session capture is handled inside each invoke-*.sh script.

**Important:** this Bash call blocks until all reviewers complete (up to 300s for Opus). Use `timeout: 360000` on the Bash tool call to avoid the default 2-minute kill.

### Check exit codes

Read each `*-exit.txt` file:
- `0` → success
- `77` → sandbox incompatible (Codex only — show message from `codex-output.md`, mark as unavailable, skip in synthesis)
- `124` → timed out (mark reviewer as timed-out, skip in synthesis)
- Other non-zero → error (mark as failed, note exit code)

**If all reviewers timed out or failed:**
```text
## AI Review — UNDECIDED

All reviewers failed or timed out. No synthesis is possible.

Options:
- Increase timeout and re-run /debate:all
- Run /debate:codex-review or /debate:gemini-review individually
- Check reviewer installation and authentication
```
Then clean up and exit.

**Capture session IDs** by reading these files (use the Read tool or note content directly):
- `<WORK_DIR>/codex-session-id.txt` → `CODEX_SESSION_ID`
- `<WORK_DIR>/gemini-session-id.txt` → `GEMINI_SESSION_UUID`
- `<WORK_DIR>/opus-session-id.txt` → `OPUS_SESSION_ID`

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
} > /tmp/claude/ai-review-${REVIEW_ID}/codex-prompt.txt

bash "<SCRIPT_DIR>/invoke-codex.sh" "<WORK_DIR>" "<CODEX_SESSION_ID>" "<CODEX_MODEL>"
```

```bash
# For Gemini:
{
  echo "[Reviewer] raised a concern about [topic]: [their position]."
  echo "You said: [Gemini's position]."
  echo "Can you address this specific disagreement? Do you stand by your position, or does their point change your assessment?"
} > /tmp/claude/ai-review-${REVIEW_ID}/gemini-prompt.txt

bash "<SCRIPT_DIR>/invoke-gemini.sh" "<WORK_DIR>" "<GEMINI_SESSION_UUID>" "<GEMINI_MODEL>"
```

```bash
# For Opus:
{
  echo "[Reviewer] raised a concern about [topic]: [their position]."
  echo "You said: [Opus's position]."
  echo "Can you address this specific disagreement? Do you stand by your position, or does their point change your assessment?"
} > /tmp/claude/ai-review-${REVIEW_ID}/opus-prompt.txt

bash "<SCRIPT_DIR>/invoke-opus.sh" "<WORK_DIR>" "<OPUS_SESSION_ID>" "<OPUS_MODEL>"
```

After each invoke call: check the exit code; on success read the reviewer's `*-output.md` and updated `*-session-id.txt`. If a session resume fails, skip that reviewer's debate response and note it.

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
   cat > /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
   [Write revision bullets before closing the heredoc]
   EOF
   ```
3. Show revisions to the user:
   ```
   ### Revisions (Round N)
   - [What was changed and why]
   ```
4. Rewrite `/tmp/claude/ai-review-${REVIEW_ID}/plan.md` with the revised plan
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

## Step 8: Present Final Plan

Before cleanup, always display the final plan so it persists in the conversation context. The user will need it after clearing context to implement.

Read `/tmp/claude/ai-review-${REVIEW_ID}/plan.md` and output it under a clear header:

```
---
## Final Plan

[full content of plan.md]

---
Review complete. Clear context and implement this plan, or save it elsewhere first.
```

## Step 9: Cleanup

```bash
rm -rf /tmp/claude/ai-review-${REVIEW_ID}
```

If any step failed before reaching this step, still run this cleanup.

---

## Rules

- **Security:** Never inline plan content or AI-generated text in shell strings — pass via file path, stdin redirect, or `$(cat file)` with a pre-written temp file
- **Parallelism:** Execute the static runner script from the plugin (`scripts/run-parallel.sh`) — it manages job control and PID capture correctly. Never write a runner script dynamically.
- **Timeout binary:** Resolve `TIMEOUT_BIN` at setup. Each invoke-*.sh script self-detects it via `command -v timeout`. Do NOT prefix bash calls with `TIMEOUT_BIN=...` — the env var prefix changes the command string and prevents sandbox exclusion pattern matching. Model vars go in `config.env`, not env var prefixes.
- **Exit codes:** Check `$?` after each `bash "$SCRIPT_DIR/invoke-*.sh"` call — the script propagates the reviewer's exit code
- **Graceful degradation:** If only 1 reviewer is available, run the full flow and skip the debate phase
- **All-fail handling:** If all reviewers fail/timeout, return `UNDECIDED` with retry guidance
- **Session tracking:** Always recapture session IDs from `*-session-id.txt` after each invoke script call — stale IDs cause silent failures on next resume; each script handles fallback internally
- **Opus session ID:** Read `OPUS_SESSION_ID` from `opus-session-id.txt` (written by invoke-opus.sh); script guards `--resume` with `[ -n "$OPUS_SESSION_ID" ]` internally
- **Opus nested sessions:** `invoke-opus.sh` handles `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT` and `CLAUDE_CODE_SIMPLE=1` internally
- **Opus jq dependency:** Skip Claude reviewer if `jq` is not installed; show install guidance
- **Debate guard:** Explicitly skip Step 5 if fewer than 2 reviewers succeeded
- **Revision discipline:** Make real plan improvements, not cosmetic changes
- **User control:** If a revision would contradict the user's explicit requirements, skip it and note it
