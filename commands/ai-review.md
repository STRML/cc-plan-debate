---
description: Run ALL available AI reviewers in parallel on the current plan, synthesize their feedback, debate contradictions, and produce a consensus verdict. Supports Codex and Gemini with graceful fallback if either is unavailable.
allowed-tools: Bash(uuidgen:*), Bash(mkdir -p /tmp/ai-review-:*), Bash(rm -rf /tmp/ai-review-:*), Bash(which codex:*), Bash(which gemini:*), Bash(codex exec -m:*), Bash(codex exec resume:*), Bash(gemini -p:*), Bash(gemini --list-sessions:*), Bash(gemini --resume:*), Bash(cat /tmp/ai-review-:*), Bash(timeout:*), Bash(gtimeout:*), Bash(wait:*), Bash(kill:*)
---

# AI Multi-Model Plan Review

Run all available AI reviewers in parallel, synthesize their feedback, debate contradictions, and produce a final consensus verdict. Max 3 total revision rounds.

Arguments:
- `skip-debate` — skip the targeted debate phase, go straight to final report
- Model override per reviewer is not supported in this orchestrator (use `/codex-review` or `/gemini-review` for that)

---

## Step 1: Prerequisite Check & Setup

### 1a. Check available reviewers

Run both checks:

```bash
which codex
which gemini
```

Build an `AVAILABLE_REVIEWERS` list from the results. Then display a prerequisite summary:

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

**If at least one reviewer is available**, proceed with those that are. Note which reviewers were skipped.

### 1b. Generate session ID & temp dir

```bash
REVIEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)
mkdir -p /tmp/ai-review-${REVIEW_ID}
```

Temp file paths:
- Plan: `/tmp/ai-review-${REVIEW_ID}/plan.md`
- Codex output: `/tmp/ai-review-${REVIEW_ID}/codex-output.md`
- Codex exit code: `/tmp/ai-review-${REVIEW_ID}/codex-exit.txt`
- Gemini output: `/tmp/ai-review-${REVIEW_ID}/gemini-output.md`
- Gemini exit code: `/tmp/ai-review-${REVIEW_ID}/gemini-exit.txt`

### 1c. Capture the plan

Write the current plan to `/tmp/ai-review-${REVIEW_ID}/plan.md`.

If there is no plan in the current context, ask the user to paste it or describe what they want reviewed.

### 1d. Announce what's about to happen

```
Running parallel review with: codex, gemini
Timeout per reviewer: 120s
```

Also print the suggested permission allowlist so users can pre-approve without prompts:

```
To pre-approve all tool calls for this review, run once in settings or trust level:

  Bash(codex exec -m:*), Bash(codex exec resume:*), Bash(gemini -p:*),
  Bash(gemini --list-sessions:*), Bash(gemini --resume:*),
  Bash(uuidgen:*), Bash(timeout:*), Bash(which:*),
  Bash(rm -rf /tmp/ai-review-:*)
```

---

## Step 2: Parallel Review (Round N)

For each available reviewer, launch a background process wrapped in `timeout 120`. Capture PIDs.

### Codex (if available)

```bash
(
  timeout 120 codex exec \
    -m gpt-5.3-codex \
    -s read-only \
    -o /tmp/ai-review-${REVIEW_ID}/codex-output.md \
    "Review the implementation plan in /tmp/ai-review-${REVIEW_ID}/plan.md. Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE"
  echo $? > /tmp/ai-review-${REVIEW_ID}/codex-exit.txt
) &
CODEX_PID=$!
```

Also capture the Codex session ID from stdout (line `session id: <uuid>`) for later resume. Since the process runs in background, write it alongside the output: the `-o` flag writes the review, but session ID appears on stdout. Adjust: capture stdout separately:

```bash
(
  timeout 120 codex exec \
    -m gpt-5.3-codex \
    -s read-only \
    -o /tmp/ai-review-${REVIEW_ID}/codex-output.md \
    "Review the implementation plan in /tmp/ai-review-${REVIEW_ID}/plan.md. [same prompt]" \
    2>&1 | tee /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt
  echo $? > /tmp/ai-review-${REVIEW_ID}/codex-exit.txt
) &
CODEX_PID=$!
```

Parse session ID after wait: `grep 'session id:' /tmp/ai-review-${REVIEW_ID}/codex-stdout.txt | head -1`

### Gemini (if available)

```bash
(
  timeout 120 sh -c \
    "cat /tmp/ai-review-${REVIEW_ID}/plan.md | gemini \
      -p 'Review this implementation plan (provided via stdin). Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. End with VERDICT: APPROVED or VERDICT: REVISE' \
      -m gemini-3.1-pro-preview \
      --approval-mode=plan \
      > /tmp/ai-review-${REVIEW_ID}/gemini-output.md"
  echo $? > /tmp/ai-review-${REVIEW_ID}/gemini-exit.txt
) &
GEMINI_PID=$!
```

### Wait for all reviewers

```bash
wait $CODEX_PID $GEMINI_PID
```

### Check exit codes

Read each `*-exit.txt` file:
- Exit `0` → success
- Exit `124` → timed out (mark reviewer as timed-out, note in output)
- Other non-zero → error (mark reviewer as failed, note the exit code)

If Gemini was run, capture session index for later resume:
```bash
gemini --list-sessions | head -3
```
Store the most recent session index as `GEMINI_SESSION_IDX`.

---

## Step 3: Present Reviewer Outputs

For each completed reviewer, display their output:

```
---
## Codex Review — Round N

[content of /tmp/ai-review-${REVIEW_ID}/codex-output.md]

---
## Gemini Review — Round N

[content of /tmp/ai-review-${REVIEW_ID}/gemini-output.md]

---
```

For timed-out or failed reviewers:
```
## [Reviewer] Review — Round N

⚠️ [Reviewer] timed out after 120s. Skipping this reviewer for synthesis.
```

---

## Step 4: Synthesize

Read all reviewer outputs. Categorize findings:

```
## Synthesis — Round N

### Unanimous Agreements
- [Points all available reviewers agree on]

### Unique Insights
- [Reviewer name]: [Point raised only by this reviewer]

### Contradictions
- Point A: Codex says X, Gemini says Y
- Point B: ...
```

Extract each reviewer's verdict:
- `VERDICT: APPROVED` from each reviewer
- `VERDICT: REVISE` from each reviewer

Determine **overall verdict**:
- All available reviewers → APPROVED → skip debate, go to Step 6 (Final Report, approved)
- Any reviewer → REVISE → continue to Step 5 (Debate) or Step 6 if no contradictions

---

## Step 5: Targeted Debate (unless `skip-debate` argument was passed)

Max 2 debate rounds. Skip if there are no contradictions.

For each contradiction identified in Step 4:

1. Identify which reviewers are on each side
2. Send a targeted question to each reviewer via session resume:

**Codex resume prompt:**
```bash
codex exec resume ${CODEX_SESSION_ID} \
  "Gemini raised a concern about [specific point]: [Gemini's position].
You said [Codex's position]. Can you address this specific disagreement?
Do you stand by your position, or does Gemini's point change your assessment?" 2>&1 | tail -80
```

**Gemini resume prompt:**
```bash
gemini --resume ${GEMINI_SESSION_IDX} \
  -p "Codex raised a concern about [specific point]: [Codex's position].
You said [Gemini's position]. Can you address this specific disagreement?
Do you stand by your position, or does Codex's point change your assessment?" \
  --approval-mode=plan 2>&1
```

Display each debate response:

```
### Debate Round N — [Contradiction Topic]

**Codex:** [response]
**Gemini:** [response]

**Resolution:** [Claude's assessment: resolved/unresolved, why]
```

After max 2 debate rounds, note any still-unresolved contradictions.

---

## Step 6: Final Report

```
---
## AI Review — Final Report (Round N of 3)

### Consensus Points
- [Things all reviewers agreed on, including post-debate convergence]

### Unresolved Disagreements
- [Any contradictions that remained after debate, with each reviewer's position]

### Claude's Recommendation
[Claude's own synthesis: given the above, what does Claude think about the plan?
What's the highest-priority concern? Is the plan ready?]

### Overall VERDICT
VERDICT: APPROVED — All reviewers approved the plan.
   OR
VERDICT: REVISE — [Reviewer(s)] identified concerns that should be addressed.
   OR
VERDICT: SPLIT — Reviewers disagree. [Summary of split]. Claude recommends: [proceed/revise].
```

---

## Step 7: Revision Loop (if VERDICT: REVISE, max 3 total rounds)

If the overall verdict is REVISE (or SPLIT and Claude recommends revising):

1. **Claude revises the plan** — address the highest-priority concerns from all reviewers
2. Summarize what changed:
   ```
   ### Revisions (Round N)
   - [What was changed and why]
   ```
3. Rewrite `/tmp/ai-review-${REVIEW_ID}/plan.md` with the revised plan
4. Inform user: "Sending revised plan back to all reviewers for round N+1..."
5. Return to **Step 2** with incremented round counter

If max rounds (3) reached without unanimous approval:

```
## AI Review — Max Rounds Reached

3 rounds completed. Remaining concerns:
[List unresolved issues]

The plan has not received unanimous approval. You may:
- Address remaining concerns manually and re-run /ai-review
- Proceed at your own judgment given the reviewers' feedback
- Use /codex-review or /gemini-review for single-reviewer focused iteration
```

---

## Step 8: Cleanup

```bash
rm -rf /tmp/ai-review-${REVIEW_ID}
```

---

## Rules

- **Security:** Never inline plan content in shell command strings — always pass via file path or stdin pipe
- **Parallelism:** Always launch reviewers as background processes and wait for all before proceeding
- **Graceful degradation:** If only one reviewer is available, run the full flow with that single reviewer
- **Timeout handling:** A timed-out reviewer is skipped in synthesis but noted in the report
- **Debate scope:** Only query reviewers on points they specifically raised — don't cross-examine on unrelated topics
- **Revision discipline:** Claude should make real plan improvements, not cosmetic changes
- **User control:** If a revision would contradict the user's explicit requirements, skip it and note it
- **Custom reviewers:** Users can add reviewer definitions at `~/.claude/ai-review/reviewers/` — any `.md` file there overrides built-in reviewers by name (matching the `name:` frontmatter field)
