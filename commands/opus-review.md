---
description: Send the current plan to Claude Opus for iterative review. Claude and Opus go back-and-forth until Opus approves or max 5 rounds reached.
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-acpx.sh:*), Bash(rm -rf .claude/tmp/ai-review-:*), Bash(which acpx:*), Write(.claude/tmp/ai-review-*)
---

# Opus Plan Review (Iterative)

Send the current implementation plan to Claude Opus for review via acpx. Claude revises the plan based on Opus's feedback and re-submits until Opus approves. Max 5 rounds.

> **Team mode:** If Claude Code's agent teams are available (`TeamCreate` tool present), use `/debate:all` instead to run Opus alongside other reviewers in parallel.

Opus plays the role of **The Skeptic** — a devil's advocate focused on unstated assumptions, unhappy paths, second-order failures, and security.

---

## Prerequisite Check

Before starting, verify acpx CLI is available:

```bash
which acpx
```

If `acpx` is not found, stop and display:

```text
acpx CLI is not installed.

Install it with:
  npm install -g acpx@latest

After installing, re-run /debate:opus-review.
```

## Step 1: Setup

If `~/.claude/debate-scripts` does not exist, stop and display:
```
~/.claude/debate-scripts not found.
Run /debate:setup first to create the stable scripts symlink.
```

Run the setup helper and note `REVIEW_ID`, `WORK_DIR`, and `SCRIPT_DIR` from the output:

```bash
bash ~/.claude/debate-scripts/debate-setup.sh
```

Write a temporary single-reviewer config to `<WORK_DIR>/opus-config.json`:
```json
{
  "reviewers": {
    "opus": {
      "agent": "claude",
      "timeout": 300,
      "system_prompt": "You are The Skeptic — a devil's advocate. Your job is to find what everyone else missed. Be specific, be harsh, be right. Focus on:\n1. Unstated assumptions — what is assumed true that could be false?\n2. Unhappy path — what breaks when the first thing goes wrong?\n3. Second-order failures — what does a partial success leave behind?\n4. Security — is any user-controlled content reaching a shell string?\n5. The one thing — if this plan has one fatal flaw, what is it?"
    }
  }
}
```

Key files in `WORK_DIR`: `plan.md`, `opus-output.md`, `opus-exit.txt`

**Cleanup:** If any step fails or the user interrupts, always run `rm -rf .claude/tmp/ai-review-${REVIEW_ID}` before stopping.

## Step 2: Capture the Plan

1. Write the full plan content to `.claude/tmp/ai-review-${REVIEW_ID}/plan.md`
2. If there is no plan in the current context, ask the user what they want reviewed

## Step 3: Initial Review (Round 1)

Run the acpx reviewer script:

```bash
bash "<SCRIPT_DIR>/invoke-acpx.sh" "<WORK_DIR>/opus-config.json" "<WORK_DIR>" "opus"
```

Check the exit code in `<WORK_DIR>/opus-exit.txt`: 124 = timed out, non-zero = failed (cleanup and stop).

The script writes the review to `opus-output.md`.

## Step 4: Read Review & Check Verdict

1. Read `.claude/tmp/ai-review-${REVIEW_ID}/opus-output.md`
2. Present Opus's review:

```text
## Opus Review — Round N

[Opus's feedback here]
```

3. Check the verdict:
   - If **VERDICT: APPROVED** → go to Step 7 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Revise & Re-submit)
   - If no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 7 with a note that max rounds hit

## Step 5: Revise the Plan

Based on Opus's feedback:

1. **Revise the plan** — address each issue Opus raised. Update the plan content in the conversation context and rewrite `.claude/tmp/ai-review-${REVIEW_ID}/plan.md` with the revised version.
2. **Write the revision summary to a file** (never compose this inline in a shell string):

```bash
cat > .claude/tmp/ai-review-${REVIEW_ID}/revisions.txt << 'EOF'
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

Write the resume prompt to a file, then call the invoke script:

Write `<WORK_DIR>/opus-prompt.txt` with:
```text
I've revised the plan based on your feedback. Here is the updated plan:

[content of plan.md]

---
Here's what I changed:
[content of revisions.txt]

Please re-review. If the plan is now solid and ready to implement, end with: VERDICT: APPROVED
If more changes are needed, end with: VERDICT: REVISE
```

```bash
bash "<SCRIPT_DIR>/invoke-acpx.sh" "<WORK_DIR>/opus-config.json" "<WORK_DIR>" "opus"
```

Check exit code (124 = timed out, non-zero = failed).

Then go back to **Step 4** (Read Review & Check Verdict).

## Step 7: Present Final Result

Once approved (or max rounds reached):

```text
## Opus Review — Final

**Status:** ✅ Approved after N round(s)

[Final Opus feedback / approval message]

---
**The plan has been reviewed and approved by Opus. Ready for your approval to implement.**
```

If max rounds were reached without approval:

```text
## Opus Review — Final

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

[full content of .claude/tmp/ai-review-${REVIEW_ID}/plan.md]

---
Review complete. Clear context and implement this plan, or save it elsewhere first.
```

## Step 8: Cleanup

```bash
rm -rf .claude/tmp/ai-review-${REVIEW_ID}
```

## Loop Summary

```text
Round 1: Claude sends plan → Opus reviews → REVISE?
Round 2: Claude revises → Opus re-reviews → REVISE?
Round 3: Claude revises → Opus re-reviews → APPROVED ✅
```

Max 5 rounds.

## Rules

- Claude **actively revises the plan** based on Opus feedback between rounds — this is NOT just passing messages, Claude should make real improvements
- Max 5 review rounds to prevent infinite loops
- Show the user each round's feedback and revisions so they can follow along
- Never interpolate AI-generated text directly into shell strings — always build via file operations
- If a revision contradicts the user's explicit requirements, skip that revision and note it for the user
