---
description: Send the current plan to Google Gemini CLI for iterative review. Claude and Gemini go back-and-forth until Gemini approves or max 5 rounds reached.
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-gemini.sh:*), Bash(rm -rf /tmp/claude/ai-review-:*), Bash(which gemini:*), Bash(gemini -s:*)
---

# Gemini Plan Review (Iterative)

Send the current implementation plan to Google Gemini for review. Claude revises the plan based on Gemini's feedback and re-submits until Gemini approves. Max 5 rounds.

Gemini plays the role of **The Architect** — a systems architect focused on approach validity, over-engineering, missing phases, and graceful degradation.

---

## Prerequisite Check

Before starting, verify Gemini CLI is available and authenticated:

```bash
which gemini
```

If `gemini` is not found, stop and display:

```text
Gemini CLI is not installed.

Install it with:
  npm install -g @google/gemini-cli

Then authenticate:
  gemini auth

After installing, re-run /debate:gemini-review.
```

If `gemini` is found, check authentication:

```bash
echo "reply with only the word PONG" | timeout 30 gemini -s -e "" 2>/dev/null
```

If the output does not contain "PONG" (case-insensitive), warn: `Gemini is not authenticated. Run: gemini auth`

## Step 1: Setup

**Model:** Check if a model argument was passed (e.g., `/debate:gemini-review gemini-2.0-flash`). If so, use it. Default: `gemini-3.1-pro-preview`. Store as `MODEL`.

If `~/.claude/debate-scripts` does not exist, stop and display:
```
~/.claude/debate-scripts not found.
Run /debate:setup first to create the stable scripts symlink.
```

Run the setup helper and note `REVIEW_ID`, `WORK_DIR`, and `SCRIPT_DIR` from the output:

```bash
bash ~/.claude/debate-scripts/debate-setup.sh
```

Use `SCRIPT_DIR` for all subsequent `bash` calls. Key files in `WORK_DIR`: `plan.md`, `gemini-output.md`, `gemini-session-id.txt`, `gemini-exit.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/claude/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

1. Write the full plan content to `/tmp/claude/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Run the Gemini reviewer script (handles all gemini flags, session UUID capture, and retry logic internally):

```bash
bash "<SCRIPT_DIR>/invoke-gemini.sh" \
  "<WORK_DIR>" "" "<MODEL>"
```

Check the exit code: 124 = timed out, non-zero = failed (cleanup and stop). On success, read `<WORK_DIR>/gemini-session-id.txt` and note the content as `GEMINI_SESSION_UUID`.

The script writes the review to `gemini-output.md` and the session UUID to `gemini-session-id.txt`.

## Step 4: Read Review & Check Verdict

1. Read `/tmp/claude/ai-review-${REVIEW_ID}/gemini-output.md`
2. Present Gemini's review:

```text
## Gemini Review — Round N (model: $MODEL)

[Gemini's feedback here]
```

3. Check the verdict:
   - If **VERDICT: APPROVED** → go to Step 7 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - If no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 7 with a note that max rounds hit

## Step 5: Revise the Plan

Based on Gemini's feedback:

1. **Revise the plan** — address each issue Gemini raised. Update the plan content in the conversation context and rewrite `/tmp/claude/ai-review-${REVIEW_ID}/plan.md` with the revised version.
2. **Write the revision summary to a file** (never compose this inline in a shell string):

```bash
cat > /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
[Write the revision bullets here before closing the heredoc]
EOF
```

3. Summarize changes for the user:

```text
### Revisions (Round N)
- [What was changed and why, one bullet per Gemini issue addressed]
```

4. Inform the user what's happening: "Sending revised plan back to Gemini for re-review..."

## Step 6: Re-submit to Gemini (Rounds 2–5)

Write the resume prompt, then call the script — it handles resume vs fresh-fallback internally:

```bash
{
  echo "I've revised the plan based on your feedback. The updated plan is provided via stdin."
  echo ""
  echo "Here's what I changed:"
  cat /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt
  echo ""
  echo "Please re-review the updated plan. If it is now solid and ready to implement, end with: VERDICT: APPROVED"
  echo "If more changes are needed, end with: VERDICT: REVISE"
} > /tmp/claude/ai-review-${REVIEW_ID}/gemini-prompt.txt

bash "<SCRIPT_DIR>/invoke-gemini.sh" \
  "<WORK_DIR>" "<GEMINI_SESSION_UUID>" "<MODEL>"
```

Check exit code (124 = timed out, non-zero = failed). On success, read `<WORK_DIR>/gemini-session-id.txt` and update `GEMINI_SESSION_UUID`.

Then go back to **Step 4** (Read Review & Check Verdict).

## Step 7: Present Final Result

Once approved (or max rounds reached):

```text
## Gemini Review — Final (model: $MODEL)

**Status:** ✅ Approved after N round(s)

[Final Gemini feedback / approval message]

---
**The plan has been reviewed and approved by Gemini. Ready for your approval to implement.**
```

If max rounds were reached without approval:

```text
## Gemini Review — Final (model: $MODEL)

**Status:** ⚠️ Max rounds (5) reached — not fully approved

**Remaining concerns:**
[List unresolved issues from last review]

---
**Gemini still has concerns. Review the remaining items and decide whether to proceed or continue refining.**
```

Then display the final plan so it persists in the conversation context after cleanup:

```
---
## Final Plan

[full content of /tmp/claude/ai-review-${REVIEW_ID}/plan.md]

---
Review complete. Clear context and implement this plan, or save it elsewhere first.
```

## Step 8: Cleanup

```bash
rm -rf /tmp/claude/ai-review-${REVIEW_ID}
```

## Loop Summary

```text
Round 1: Claude sends plan → Gemini reviews → REVISE?
Round 2: Claude revises → Gemini re-reviews (resume session) → REVISE?
Round 3: Claude revises → Gemini re-reviews (resume session) → APPROVED ✅
```

Max 5 rounds. Each round preserves Gemini's conversation context via session resume.

## Rules

- Claude **actively revises the plan** based on Gemini feedback between rounds — not just passing messages
- Default model is `gemini-3.1-pro-preview`. Accept model override (e.g., `/debate:gemini-review gemini-2.0-flash`)
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- Never interpolate AI-generated text directly into shell strings — always build via file operations
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
