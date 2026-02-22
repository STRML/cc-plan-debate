---
description: Send the current plan to OpenAI Codex CLI for iterative review. Claude and Codex go back-and-forth until Codex approves or max 5 rounds reached.
allowed-tools: Bash(uuidgen:*), Bash(command -v:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(codex exec -m:*), Bash(codex exec resume:*), Bash(which codex:*), Bash(timeout:*), Bash(gtimeout:*), Bash(cat /tmp/ai-review-:*)
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

**Timeout binary:** Resolve once — macOS ships `gtimeout` (coreutils), Linux ships `timeout`:

```bash
TIMEOUT_BIN=$(command -v timeout || command -v gtimeout)
```

If neither is found, warn the user (`Install GNU coreutils`) and proceed without a timeout wrapper.

**Session ID and temp dir:**

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/ai-review-${REVIEW_ID}
```

Temp file paths:
- Plan file: `/tmp/ai-review-${REVIEW_ID}/plan.md`
- Codex output: `/tmp/ai-review-${REVIEW_ID}/codex-output.md`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/ai-review-${REVIEW_ID}` before stopping. Also attempt cleanup at the end of Step 8.

## Step 2: Capture the Plan

Write the current plan to the temp file:

1. Write the full plan content to `/tmp/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Run Codex in non-interactive mode, wrapped in the timeout binary:

```bash
$TIMEOUT_BIN 120 codex exec \
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
```

If exit code is `124`, Codex timed out — inform the user and stop.

**Capture the Codex session ID** from the output line that says `session id: <uuid>`. Store as `CODEX_SESSION_ID`. You MUST use this exact ID to resume in subsequent rounds — do NOT use `--last`, which would grab the wrong session if multiple reviews are running concurrently.

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
2. **Briefly summarize** what you changed for the user:

```
### Revisions (Round N)
- [What was changed and why, one bullet per Codex issue addressed]
```

3. Inform the user what's happening: "Sending revised plan back to Codex for re-review..."

## Step 6: Re-submit to Codex (Rounds 2–5)

Resume the existing Codex session so it has full context of the prior review.

**Write the resume prompt to a file first** — never interpolate dynamic content (revision list, AI feedback) directly into a quoted shell string, as it may contain characters that break shell parsing:

```bash
cat > /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt << 'PROMPTEOF'
I've revised the plan based on your feedback. The updated plan is in /tmp/ai-review-${REVIEW_ID}/plan.md.

Here's what I changed:
[List the specific changes made — fill this in before writing the file]

Please re-review. If the plan is now solid and ready to implement, end with: VERDICT: APPROVED
If more changes are needed, end with: VERDICT: REVISE
PROMPTEOF
```

Fill in the revision list before writing the file, then resume:

```bash
RESUME_PROMPT=$(cat /tmp/ai-review-${REVIEW_ID}/resume-prompt.txt)
$TIMEOUT_BIN 120 codex exec resume ${CODEX_SESSION_ID} "$RESUME_PROMPT" 2>&1 | tail -80
```

**Note:** `codex exec resume` does NOT support `-o`. Capture output from stdout.

If resume fails (session expired), fall back to a fresh `codex exec` call with context about the prior rounds included in the prompt.

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

Remove the session-scoped temporary files:
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
- Never interpolate AI-generated text directly into shell strings — always write to a temp file first
- If Codex CLI is not installed or fails, inform the user and suggest `npm install -g @openai/codex`
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
