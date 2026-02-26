---
description: Send the current plan to Claude Opus for iterative review. Claude and Opus go back-and-forth until Opus approves or max 5 rounds reached.
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-opus.sh:*), Bash(rm -rf /tmp/claude/ai-review-:*), Bash(which claude:*), Bash(which jq:*)
---

# Opus Plan Review (Iterative)

Send the current implementation plan to Claude Opus for review. Claude revises the plan based on Opus's feedback and re-submits until Opus approves. Max 5 rounds.

> **Team mode:** If Claude Code's agent teams are available (`TeamCreate` tool present), use `/debate:all` instead to run Opus alongside Codex and Gemini reviewers in parallel — including teammate agents as substitutes for any missing CLIs.

Opus plays the role of **The Skeptic** — a devil's advocate focused on unstated assumptions, unhappy paths, second-order failures, and security.

---

## Prerequisite Check

Before starting, verify Claude CLI and jq are available:

```bash
which claude
which jq
```

If `claude` is not found, stop and display:

```text
Claude CLI is not installed.

Install it with:
  npm install -g @anthropic-ai/claude-code

After installing, re-run /debate:opus-review.
```

If `jq` is not found, stop and display:

```text
jq is not installed. It is required to parse Claude's JSON output.

Install it with:
  brew install jq   (macOS)
  apt install jq    (Linux)

After installing, re-run /debate:opus-review.
```

## Step 1: Setup

**Model:** Check if a model argument was passed (e.g., `/debate:opus-review claude-opus-4-5`). If so, use it. Default: `claude-opus-4-6`. Store as `MODEL`.

If `~/.claude/debate-scripts` does not exist, stop and display:
```
~/.claude/debate-scripts not found.
Run /debate:setup first to create the stable scripts symlink.
```

Run the setup helper and note `REVIEW_ID`, `WORK_DIR`, and `SCRIPT_DIR` from the output:

```bash
bash ~/.claude/debate-scripts/debate-setup.sh
```

Use `SCRIPT_DIR` for all subsequent `bash` calls. Key files in `WORK_DIR`: `plan.md`, `opus-output.md`, `opus-session-id.txt`, `opus-exit.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf /tmp/claude/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

1. Write the full plan content to `/tmp/claude/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Run the Opus reviewer script (handles all claude flags, session capture, and retry logic internally):

```bash
bash "<SCRIPT_DIR>/invoke-opus.sh" \
  "<WORK_DIR>" "" "<MODEL>"
```

Check the exit code: 124 = timed out, non-zero = failed (cleanup and stop). On success, read `<WORK_DIR>/opus-session-id.txt` and note the content as `OPUS_SESSION_ID`.

The script writes the review to `opus-output.md` and the session ID to `opus-session-id.txt`.

## Step 4: Read Review & Check Verdict

1. Read `/tmp/claude/ai-review-${REVIEW_ID}/opus-output.md`
2. Present Opus's review:

```text
## Opus Review — Round N (model: $MODEL)

[Opus's feedback here]
```

3. Check the verdict:
   - If **VERDICT: APPROVED** → go to Step 7 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - If no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 7 with a note that max rounds hit

## Step 5: Revise the Plan

Based on Opus's feedback:

1. **Revise the plan** — address each issue Opus raised. Update the plan content in the conversation context and rewrite `/tmp/claude/ai-review-${REVIEW_ID}/plan.md` with the revised version.
2. **Write the revision summary to a file** (never compose this inline in a shell string):

```bash
cat > /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
[Write the revision bullets here before closing the heredoc]
EOF
```

3. Summarize changes for the user:

```text
### Revisions (Round N)
- [What was changed and why, one bullet per Opus issue addressed]
```

4. Inform the user what's happening: "Sending revised plan back to Opus for re-review..."

## Step 6: Re-submit to Opus (Rounds 2–5)

Write the resume prompt, then call the script — it handles resume vs fresh-fallback internally:

```bash
{
  echo "I've revised the plan based on your feedback. Here is the updated plan:"
  echo ""
  cat /tmp/claude/ai-review-${REVIEW_ID}/plan.md
  echo ""
  echo "---"
  echo "Here's what I changed:"
  cat /tmp/claude/ai-review-${REVIEW_ID}/revisions.txt
  echo ""
  echo "Please re-review. If the plan is now solid and ready to implement, end with: VERDICT: APPROVED"
  echo "If more changes are needed, end with: VERDICT: REVISE"
} > /tmp/claude/ai-review-${REVIEW_ID}/opus-prompt.txt

bash "<SCRIPT_DIR>/invoke-opus.sh" \
  "<WORK_DIR>" "<OPUS_SESSION_ID>" "<MODEL>"
```

Check exit code (124 = timed out, non-zero = failed). On success, read `<WORK_DIR>/opus-session-id.txt` and update `OPUS_SESSION_ID`.

Then go back to **Step 4** (Read Review & Check Verdict).

## Step 7: Present Final Result

Once approved (or max rounds reached):

```text
## Opus Review — Final (model: $MODEL)

**Status:** ✅ Approved after N round(s)

[Final Opus feedback / approval message]

---
**The plan has been reviewed and approved by Opus. Ready for your approval to implement.**
```

If max rounds were reached without approval:

```text
## Opus Review — Final (model: $MODEL)

**Status:** ⚠️ Max rounds (5) reached — not fully approved

**Remaining concerns:**
[List unresolved issues from last review]

---
**Opus still has concerns. Review the remaining items and decide whether to proceed or continue refining.**
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
Round 1: Claude sends plan → Opus reviews → REVISE?
Round 2: Claude revises → Opus re-reviews (resume session) → REVISE?
Round 3: Claude revises → Opus re-reviews (resume session) → APPROVED ✅
```

Max 5 rounds. Each round preserves Opus's conversation context via session resume.

## Rules

- Claude **actively revises the plan** based on Opus feedback between rounds — this is NOT just passing messages, Claude should make real improvements
- Default model is `claude-opus-4-6`. Accept model override from the user's arguments (e.g., `/debate:opus-review claude-opus-4-5`)
- `jq` is required — stop and display install instructions if missing
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- Never interpolate AI-generated text directly into shell strings — always build via file operations
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
