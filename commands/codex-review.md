---
description: Send the current plan to OpenAI Codex CLI for iterative review. Claude and Codex go back-and-forth until Codex approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(codex exec -m:*), Bash(codex exec resume:*), Bash(which codex:*), Bash(timeout:*), Bash(gtimeout:*)
---

# Codex Plan Review (Iterative)

Send the current implementation plan to OpenAI Codex for review. Claude revises the plan based on Codex's feedback and re-submits until Codex approves. Max 5 rounds.

---

## Prerequisite Check

Before starting, verify Codex CLI is available:

```bash
which codex
```

If `codex` is not found, stop and display this message:

```
Codex CLI is not installed.

Install it with:
  npm install -g @openai/codex

Then ensure you have configured your OpenAI API key:
  export OPENAI_API_KEY=<your-key>

After installing, re-run /debate:codex-review.
```

## Step 1: Setup

**Model:** Check if a model argument was passed (e.g., `/debate:codex-review o4-mini`). If so, use it. Default: `gpt-5.3-codex`. Store as `MODEL`.

**Timeout command:** Resolve once and build as an array — macOS ships `gtimeout` (coreutils), Linux ships `timeout`:

```bash
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)
if [ -n "$TIMEOUT_BIN" ]; then
  TIMEOUT_CMD=("$TIMEOUT_BIN" 120)
else
  echo "Warning: neither 'timeout' nor 'gtimeout' found. Install: brew install coreutils"
  echo "Proceeding without timeout protection."
  TIMEOUT_CMD=()
fi
```

Invoke as `"${TIMEOUT_CMD[@]}" codex exec ...` — when `TIMEOUT_CMD` is empty this reduces to just `codex exec ...` with no timeout.

**Session ID and temp dir:**

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/ai-review-${REVIEW_ID}
```

Temp file paths:
- Plan file: `/tmp/ai-review-${REVIEW_ID}/plan.md`
- Codex output: `/tmp/ai-review-${REVIEW_ID}/codex-output.md`
- Codex stdout (for session ID): `/tmp/ai-review-${REVIEW_ID}/codex-stdout.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

Write the current plan to the temp file:

1. Write the full plan content to `/tmp/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Run Codex in non-interactive mode. Capture stdout (for session ID) alongside the `-o` output:

```bash
"${TIMEOUT_CMD[@]}" codex exec \
  -m $MODEL \
  -s read-only \
  -o /tmp/ai-review-${REVIEW_ID}/codex-output.md \
  "Review the implementation plan in /tmp/ai-review-${REVIEW_ID}/plan.md. Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED

If changes are needed, end with exactly: VERDICT: REVISE" \
  2>&1 | tee /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt
CODEX_EXIT=${PIPESTATUS[0]}
```

If `CODEX_EXIT` is `124`, Codex timed out — inform the user and stop.

**Capture the Codex session ID:**
```bash
grep 'session id:' /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt | head -1
```
Extract the UUID. Store as `CODEX_SESSION_ID`. You MUST use this exact ID to resume in subsequent rounds — do NOT use `--last`, which would grab the wrong session if multiple reviews are running concurrently.

**Notes:**
- Use `-m $MODEL` (resolved from args above; defaults to `gpt-5.3-codex`)
- Use `-s read-only` so Codex can read the codebase for context but cannot modify anything
- Use `-o` to capture the review output to a file for reliable reading

## Step 4: Read Review & Check Verdict

1. Read `/tmp/ai-review-${REVIEW_ID}/codex-output.md`
2. Present Codex's review:

```
## Codex Review — Round N (model: $MODEL)

[Codex's feedback here]
```

3. Check the verdict:
   - If **VERDICT: APPROVED** → go to Step 7 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - If no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 7 with a note that max rounds hit

## Step 5: Revise the Plan

Based on Codex's feedback:

1. **Revise the plan** — address each issue Codex raised. Update the plan content in the conversation context and rewrite `/tmp/ai-review-${REVIEW_ID}/plan.md` with the revised version.
2. **Write the revision summary to a file** (never compose this inline in a shell string):

```bash
cat > /tmp/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
[Write the revision bullets here before closing the heredoc]
EOF
```

3. Summarize changes for the user:

```
### Revisions (Round N)
- [What was changed and why, one bullet per Codex issue addressed]
```

4. Inform the user what's happening: "Sending revised plan back to Codex for re-review..."

## Step 6: Re-submit to Codex (Rounds 2–5)

Resume the existing Codex session so it has full context of the prior review.

Build the resume prompt from files — never interpolate dynamic content directly into a shell string:

```bash
# Write the resume prompt to a file
{
  echo "I've revised the plan based on your feedback. The updated plan is in /tmp/ai-review-${REVIEW_ID}/plan.md."
  echo ""
  echo "Here's what I changed:"
  cat /tmp/ai-review-${REVIEW_ID}/revisions.txt
  echo ""
  echo "Please re-review. If the plan is now solid and ready to implement, end with: VERDICT: APPROVED"
  echo "If more changes are needed, end with: VERDICT: REVISE"
} > /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt

RESUME_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt)
"${TIMEOUT_CMD[@]}" codex exec resume ${CODEX_SESSION_ID} "$RESUME_PROMPT" \
  2>&1 | tee /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt
CODEX_EXIT=${PIPESTATUS[0]}
```

**Note:** `codex exec resume` does NOT support `-o`. Capture output from stdout.

If `CODEX_EXIT` is non-zero or resume returns an error (session expired):
- Fall back to a fresh `codex exec` call with a summary of prior rounds in the prompt (assembled via file, not inline)
- After the fresh call, recapture `CODEX_SESSION_ID` from the new stdout — do NOT continue using the old session ID

Then go back to **Step 4** (Read Review & Check Verdict).

## Step 7: Present Final Result

Once approved (or max rounds reached):

```
## Codex Review — Final (model: $MODEL)

**Status:** ✅ Approved after N round(s)

[Final Codex feedback / approval message]

---
**The plan has been reviewed and approved by Codex. Ready for your approval to implement.**
```

If max rounds were reached without approval:

```
## Codex Review — Final (model: $MODEL)

**Status:** ⚠️ Max rounds (5) reached — not fully approved

**Remaining concerns:**
[List unresolved issues from last review]

---
**Codex still has concerns. Review the remaining items and decide whether to proceed or continue refining.**
```

## Step 8: Cleanup

```bash
rm -rf /tmp/ai-review-${REVIEW_ID}
```

If any step failed before reaching this step, still run this cleanup.

## Loop Summary

```
Round 1: Claude sends plan → Codex reviews → REVISE?
Round 2: Claude revises → Codex re-reviews (resume session) → REVISE?
Round 3: Claude revises → Codex re-reviews (resume session) → APPROVED ✅
```

Max 5 rounds. Each round preserves Codex's conversation context via session resume.

## Rules

- Claude **actively revises the plan** based on Codex feedback between rounds — this is NOT just passing messages, Claude should make real improvements
- Default model is `gpt-5.3-codex`. Accept model override from the user's arguments (e.g., `/debate:codex-review o4-mini`)
- Always use read-only sandbox mode — Codex should never write files
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- Never interpolate AI-generated text directly into shell strings — always build via file operations
- If Codex CLI is not installed or fails, inform the user and suggest `npm install -g @openai/codex`
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
