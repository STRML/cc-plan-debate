---
description: Run ALL configured AI reviewers in parallel via acpx, synthesize feedback, debate contradictions, and produce a consensus verdict. Configure reviewers in ~/.claude/debate-acpx.json.
allowed-tools: Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*), Bash(bash ~/.claude/debate-scripts/invoke-acpx.sh:*), Bash(rm -rf .claude/tmp/ai-review-:*), Write(.claude/tmp/ai-review-*), TeamCreate, TeamDelete, SendMessage, Agent
---

# AI Multi-Model Plan Review (acpx)

Run all configured AI reviewers in parallel via acpx, synthesize their feedback, debate contradictions, and produce a final consensus verdict. Max 3 total revision rounds.

Arguments:
- First arg: optional comma-separated reviewer names (e.g. `codex,gemini`). Defaults to all from config.
- `skip-debate` — skip the targeted debate phase, go straight to final report.

---

## Step 1: Prerequisites & Setup

### 1a. Validate config

Read `~/.claude/debate-acpx.json`. If missing, stop:
```text
Config not found: ~/.claude/debate-acpx.json
Run /debate:acpx-setup to create it.
```

Parse reviewer list. If a comma-separated reviewer list was passed as argument, filter to only those reviewers. Validate each reviewer has an `agent` field.

### 1b. Generate session ID & temp dir

Verify `~/.claude/debate-scripts` exists. If not:
```text
~/.claude/debate-scripts not found.
Run /debate:setup first to create the stable scripts symlink.
```

Run setup:
```bash
bash ~/.claude/debate-scripts/debate-setup.sh
```

Note `REVIEW_ID`, `WORK_DIR`, and `SCRIPT_DIR` from output.

### 1c. Announce

List the reviewers that will run:

```text
## acpx Review — Starting

Reviewers:
  codex   → agent: codex    (120s)
  gemini  → agent: gemini   (240s)
  kimi    → agent: kimi     (120s)
```

### 1d. Capture the plan

Write the current plan to `<WORK_DIR>/plan.md`.

If there is no plan in context, ask the user to paste it or describe what to review.

### 1e. Execution Mode

**First, fetch the TeamCreate tool schema** — it's a deferred tool that must be loaded before use:
```
ToolSearch: query="select:TeamCreate,TeamDelete,SendMessage", max_results=3
```

If ToolSearch returns TeamCreate, it is available. If it returns nothing or errors, it is not available.

**If `TeamCreate` is available:**

Attempt to create the review team:
```
TeamCreate: name="acpx-<REVIEW_ID>", description="Parallel acpx plan review"
```

- On success → Set `EXEC_MODE=team`. Announce: `Execution mode: team (persistent agents across rounds)`
- On failure → Set `EXEC_MODE=agent`. Announce: `TeamCreate failed — falling back to agent mode`

**The team lives for the entire review session. Do NOT call `TeamCreate` again on subsequent rounds. `TeamDelete` is called only at Step 9.**

**If `TeamCreate` is not available:** Set `EXEC_MODE=agent`. Announce: `Execution mode: agent (subagents per round)`

---

## Step 2: Parallel Review (Round N)

### Option A — Team Mode (`EXEC_MODE=team`)

The review team was created in Step 1e and persists for the full session. Do NOT call `TeamCreate` here.

**Round 1 — Spawn reviewer agents in parallel:**

For each reviewer in the config, use the Agent tool with `team_name: "acpx-<REVIEW_ID>"`. Spawn all in parallel.

Agent `name`: `<reviewer-name>-reviewer`
```
Your job is to call an external AI reviewer via acpx. Do NOT write the review yourself.

Run this command (use timeout: 360000 on the Bash call):
  bash <SCRIPT_DIR>/invoke-acpx.sh "~/.claude/debate-acpx.json" "<WORK_DIR>" "<name>"

Then read <WORK_DIR>/<name>-exit.txt for the exit code.
  - If "0": Read <WORK_DIR>/<name>-output.md — this is the review.
    Message me: "<name> complete. Exit: 0"
  - If non-zero: Message me: "<name> failed. Exit: <code>"

Wait for further instructions — you may be asked to debate or re-review.
```

Wait for `SendMessage` from all reviewer agents. When all have reported (or 360s elapses), proceed.

**Do NOT call `TeamDelete` here.** The team remains active for debates and revision rounds.

**Round 2+ — Message existing teammates (do NOT spawn new agents):**

For each reviewer, first write revision-aware prompt to `<WORK_DIR>/<name>-prompt.txt`, then send:

```
SendMessage:
  Recipient: "<name>-reviewer"
  Content:
    "The plan has been revised. A new prompt has been written to <WORK_DIR>/<name>-prompt.txt.
     Re-run the invoke script:
     bash <SCRIPT_DIR>/invoke-acpx.sh "~/.claude/debate-acpx.json" "<WORK_DIR>" "<name>"
     Read <WORK_DIR>/<name>-exit.txt and report back.
     After completion, delete <WORK_DIR>/<name>-prompt.txt."
```

### Option B — Agent Mode (`EXEC_MODE=agent`)

**Every round:** Spawn reviewer agents using the Agent tool with `run_in_background: true`. Spawn all in parallel.

**Round 1 prompt** — same as team mode Round 1, but without team_name and without "Wait for further instructions".

**Round 2+ prompt:** Write revision-aware prompt to `<WORK_DIR>/<name>-prompt.txt`, then spawn a fresh agent:
"Run `bash <SCRIPT_DIR>/invoke-acpx.sh "~/.claude/debate-acpx.json" "<WORK_DIR>" "<name>"` (use timeout: 360000). Read `<WORK_DIR>/<name>-exit.txt` for the exit code. After completion, delete `<WORK_DIR>/<name>-prompt.txt`."

### Check results (both modes)

For each reviewer, read:
- `<WORK_DIR>/<name>-exit.txt` — exit code
- `<WORK_DIR>/<name>-output.md` — review text

Exit code meanings:
- `0` — success
- `124` — timed out
- Other — error (check output for details)

**If all reviewers failed:**
```text
## acpx Review — UNDECIDED

All reviewers failed or timed out. No synthesis is possible.

Options:
- Check agent availability with /debate:acpx-setup
- Re-run /debate:all
```
Then clean up and exit.

---

## Step 3: Present Reviewer Outputs

For each completed reviewer:

```text
---
## <Name> Review — Round N (<Agent>)

[content of <name>-output.md]
```

For failed/timed-out reviewers:
```text
## <Name> Review — Round N

⚠️ <Name> timed out after <timeout>s / failed (exit <code>). Skipping.
```

---

## Step 4: Synthesize

Read all successful reviewer outputs and categorize:

```text
## Synthesis — Round N

### Unanimous Agreements
- [Points all reviewers agree on]

### Unique Insights
- [Reviewer]: [Point only this reviewer raised]

### Contradictions
- Point A: <Reviewer1> says X, <Reviewer2> says Y
```

Extract each verdict. Determine overall:
- All APPROVED → skip debate, go to Step 6
- Any REVISE → continue to Step 5
- Only 1 reviewer succeeded → skip debate, use that verdict as final

---

## Step 5: Targeted Debate (unless `skip-debate` was passed or fewer than 2 reviewers succeeded)

Max 2 debate rounds. Skip if no contradictions.

For each contradiction, write debate prompts to files:

```bash
cat > <WORK_DIR>/<name>-prompt.txt << 'DEBATE_EOF'
There is a disagreement on [topic].

The other reviewer's position:
[quote the specific disagreement from the other reviewer's output]

Your position:
[quote their specific position]

Do you stand by your position, or does the other reviewer's point change your assessment?
Be specific. End with VERDICT: APPROVED or VERDICT: REVISE.
DEBATE_EOF
```

Then invoke each debating reviewer:

**Team mode:** SendMessage the teammate:
```
SendMessage:
  Recipient: "<name>-reviewer"
  Content:
    "A debate prompt has been written to <WORK_DIR>/<name>-prompt.txt.
     Re-run: bash <SCRIPT_DIR>/invoke-acpx.sh "~/.claude/debate-acpx.json" "<WORK_DIR>" "<name>"
     Read <WORK_DIR>/<name>-exit.txt and report back.
     After completion, delete <WORK_DIR>/<name>-prompt.txt."
```

**Agent mode:** Spawn a fresh agent with `run_in_background: true` that calls the invoke script.

Read the updated `<name>-output.md` and present:

```text
### Debate Round N — [Topic]

**<Reviewer1>:** [response]
**<Reviewer2>:** [response]

**Resolution:** [resolved/unresolved, why]
```

---

## Step 6: Final Report

```text
---
## acpx Review — Final Report (Round N of 3)

### Consensus Points
- [Things all reviewers agreed on]

### Unresolved Disagreements
- [Contradictions that remained after debate]

### Claude's Recommendation
[Synthesis: highest-priority concern, is the plan ready?]

### Overall VERDICT
VERDICT: APPROVED — All reviewers approved the plan.
   OR
VERDICT: REVISE — [Reviewer(s)] identified concerns that should be addressed.
   OR
VERDICT: SPLIT — Reviewers disagree. [Summary]. Claude recommends: [proceed/revise].
```

---

## Step 7: Revision Loop (if REVISE or SPLIT, max 3 total rounds)

1. **Claude revises the plan** — address highest-priority concerns
2. Write revision summary:
   ```bash
   cat > <WORK_DIR>/revisions.txt << 'EOF'
   [Revision bullets]
   EOF
   ```
3. Show revisions to user:
   ```text
   ### Revisions (Round N)
   - [What changed and why]
   ```
4. Rewrite `<WORK_DIR>/plan.md` with the revised plan
5. For each reviewer, write a context-rich prompt file for the next round:
   ```bash
   cat > <WORK_DIR>/<name>-prompt.txt << 'REVISION_EOF'
   The plan has been revised based on reviewer feedback.

   Changes made:
   [content of revisions.txt]

   Updated plan:
   [content of plan.md]

   Re-review the updated plan. If your previous concerns were addressed, acknowledge it.
   End with VERDICT: APPROVED or VERDICT: REVISE.
   REVISION_EOF
   ```
6. Return to **Step 2** with incremented round counter

If max rounds (3) reached:
```text
## acpx Review — Max Rounds Reached

3 rounds completed. Remaining concerns:
[List unresolved issues]

Options:
- Address remaining concerns manually and re-run
- Proceed at your judgment given the feedback
```

---

## Step 8: Present Final Plan

Read `<WORK_DIR>/plan.md` and display:

```text
---
## Final Plan

[full plan content]

---
Review complete.
```

## Step 9: Cleanup

In team mode, shut down the review team first:
```
TeamDelete
```

If `TeamDelete` fails, log a warning and continue.

Then remove temp files:
```bash
rm -rf .claude/tmp/ai-review-${REVIEW_ID}
```

---

## Rules

- **acpx handles everything.** No provider CLIs needed. No API keys to manage. Each agent's auth is configured in acpx.
- **No session resume.** Each round is stateless — full context is injected via prompt files. acpx manages sessions internally.
- **Config is king.** Adding a reviewer = adding an entry to `~/.claude/debate-acpx.json`.
- **Security:** Never inline plan content or AI output in shell strings — use files and jq for JSON construction.
- **Timeout:** Each reviewer's timeout is in the config. The system `timeout` binary wraps acpx calls.
- **Graceful degradation:** If a reviewer fails, skip it in synthesis. If all fail, return UNDECIDED.
- **No persona fallback:** If an acpx agent fails, it's reported as failed — not substituted with a Claude persona.
- **Debate guard:** Skip debate if fewer than 2 reviewers succeeded.
- **Revision discipline:** Make real improvements, not cosmetic changes.
- **User control:** If a revision would contradict the user's explicit requirements, skip it and note it.
- **Team lifecycle:** `TeamCreate` once in Step 1e; `TeamDelete` once in Step 9. Never call `TeamCreate` inside Step 2 or between rounds.
- **Exec mode discipline:** In team mode, never spawn new reviewer agents after Round 1 — use `SendMessage`. In agent mode, spawn fresh agents each round.
- **Injection safety:** Never interpolate reviewer output or plan content directly into `SendMessage` content strings. Always write to a temp file first; in team mode, send only file paths.
