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

Build `AVAILABLE_REVIEWERS` from the results. Track CLI availability per reviewer for all modes:
- `CODEX_CLI_AVAILABLE=true/false` — `which codex` succeeds
- `GEMINI_CLI_AVAILABLE=true/false` — `which gemini` succeeds

Display a prerequisite summary:

```text
## AI Review — Prerequisite Check

Reviewers found:
  ✅ codex    (OpenAI Codex CLI)
  ✅ gemini   (Google Gemini CLI)
  ✅ claude   (Anthropic Claude Opus)

Reviewers missing:
  ❌ [none]

Tools:
  ✅ jq       (shell mode only — for Opus CLI output parsing)
```

If a reviewer binary is missing, show how to install it:

| Reviewer | Install Command |
|----------|----------------|
| codex | `npm install -g @openai/codex` + set `OPENAI_API_KEY` |
| gemini | `npm install -g @google/gemini-cli` + run `gemini auth` |
| claude | `npm install -g @anthropic-ai/claude-code` |

If `jq` is missing and `claude` is available, note:
In shell mode (`EXEC_MODE=shell`), `jq` is required for Claude output parsing — install: `brew install jq` (macOS) / `apt install jq` (Linux). Skip Claude reviewer in shell mode until jq is installed.
In team/agent mode, Opus runs natively and jq is not required.

If Gemini CLI is available, verify it is authenticated:

```bash
echo "reply with only the word PONG" | timeout 30 gemini -p "Reply with only the word PONG." -s -e "" 2>/dev/null
```

If output does not contain "PONG" (case-insensitive), set `GEMINI_CLI_AVAILABLE=false` and warn: `Gemini CLI found but not authenticated — run: gemini auth (will use persona fallback)`

**If NO reviewers are available AND shell-mode was requested**, stop and display the full install guide, then exit. In team/agent mode, reviews always proceed — Codex/Gemini use persona fallback if CLIs are unavailable, and Opus always runs natively.

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
CODEX_MODEL=<CODEX_MODEL|>
GEMINI_MODEL=<GEMINI_MODEL|>
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

### 1e. Execution Mode Check

Check if the `TeamCreate` tool is available in this session. (`TeamCreate`, `SendMessage`, `TeamDelete`, `TaskCreate`, and `TaskUpdate` are Claude Code built-in tools provided as part of the teams API, currently in beta. They are present when Claude Code's teammate feature is enabled.)

**If user passed `shell-mode`:** Set `EXEC_MODE=shell`. Skip to Step 2.

**For team/agent mode (not shell):**

Codex and Gemini reviewers **prefer the real CLI** when the binary is available and authenticated. The teammate agent calls the invoke script (`invoke-codex.sh` / `invoke-gemini.sh`) to get a genuine external review. If the CLI is unavailable, the reviewer falls back to a Claude persona that role-plays the review perspective — but this is a fallback, not the preferred path.

Set `AVAILABLE_REVIEWERS = [codex, gemini, opus]` (all three, always) in team/agent mode.

Build `TEAM_REVIEWER_PLAN` based on CLI availability from Step 1a:
- codex → type: `cli` if `CODEX_CLI_AVAILABLE`, else `persona` (The Executor)
- gemini → type: `cli` if `GEMINI_CLI_AVAILABLE`, else `persona` (The Architect)
- opus → type: `persona` (The Skeptic) [always — Opus IS Claude]

Display the reviewer plan (show `🔌 cli` for real CLI calls, `⚡ persona` for Claude agent perspective):

```text
Reviewer plan (team mode):
  🔌 cli       codex   — Real Codex CLI via invoke script
  🔌 cli       gemini  — Real Gemini CLI via invoke script
  ⚡ persona   opus    — The Skeptic (native Claude)
```

**If `TeamCreate` is available:**

Attempt to create the review team:

```
TeamCreate: name="debate-<REVIEW_ID>", description="Parallel AI plan review"
```

- On success → Set `EXEC_MODE=team`. Announce: `Execution mode: team (persistent agents across rounds)`
- On failure → log the error, Set `EXEC_MODE=agent`. Announce: `TeamCreate failed — falling back to agent mode`

**The team lives for the entire review session. Do NOT call `TeamCreate` again on subsequent rounds. `TeamDelete` is called only at Step 9.**

**If `TeamCreate` is not available:** Set `EXEC_MODE=agent`. Announce: `Execution mode: agent (subagents with context injection for rounds 2+)`

---

## Step 2: Parallel Review (Round N)

### Option A — Shell Mode (`EXEC_MODE=shell`)

**Execute the parallel runner script** from the plugin:

```bash
bash "<SCRIPT_DIR>/run-parallel.sh" "<REVIEW_ID>"
```

The script is pre-built in the plugin — Codex runs with 120s, Gemini with 240s, Opus with 300s (the `claude` CLI has more startup overhead). Session capture is handled inside each invoke-*.sh script.

**Important:** this Bash call blocks until all reviewers complete (up to 300s for Opus). Use `timeout: 360000` on the Bash tool call to avoid the default 2-minute kill.

### Option B — Team Mode (`EXEC_MODE=team`)

The review team was created in Step 1e and persists for the full session. Do NOT call `TeamCreate` here.

**Round 1 — Spawn reviewer agents in parallel:**

For each reviewer in `TEAM_REVIEWER_PLAN`, use the Agent tool with `team_name: "debate-<REVIEW_ID>"` and the explicit `name` below. Spawn all in parallel.

Use the prompt variant matching each reviewer's type from `TEAM_REVIEWER_PLAN`.

**Codex reviewer — CLI type** (when `CODEX_CLI_AVAILABLE`):

Agent `name`: `codex-reviewer`
```
Your job is to get a REAL review from the OpenAI Codex CLI. Do NOT write the review yourself.
Do NOT role-play or emulate Codex. You MUST call the actual CLI binary.

Step 1: Run the Codex invoke script:
  bash <SCRIPT_DIR>/invoke-codex.sh "<WORK_DIR>" "" "<CODEX_MODEL>"

  Use timeout: 180000 on the Bash call.

Step 2: Read <WORK_DIR>/codex-exit.txt for the exit code.
  - If "0": Read <WORK_DIR>/codex-output.md — this is the REAL Codex review.
    Message me: "Codex complete. Exit: 0"
  - If non-zero (77 sandbox panic, 124 timeout, or other failure):
    Fall back to persona mode. Read the plan at <WORK_DIR>/plan.md and write your
    own review as The Executor — a pragmatic runtime tracer. Focus on shell correctness,
    exit code handling, race conditions, file I/O, command availability.
    Write your review to <WORK_DIR>/codex-output.md. End with VERDICT: APPROVED or VERDICT: REVISE.
    Write "0" to <WORK_DIR>/codex-exit.txt.
    Message me: "Codex complete (CLI failed, persona fallback). Exit: 0"

Wait for further instructions — you may be asked to debate or re-review.
```

**Codex reviewer — persona fallback** (when NOT `CODEX_CLI_AVAILABLE`):

Agent `name`: `codex-reviewer`
```
You are The Executor — a pragmatic runtime tracer. The Codex CLI is not installed,
so you are providing this review as a Claude persona. Find what will actually break at runtime.

Focus: shell correctness, exit code handling, race conditions, file I/O, command availability,
error propagation, missing dependencies, timing assumptions.

Read the plan at: <WORK_DIR>/plan.md

Write your complete review to <WORK_DIR>/codex-output.md. Be specific and direct — cite
the exact step or command that will fail and why. End your review with either:
  VERDICT: APPROVED
  VERDICT: REVISE

Then write "0" to <WORK_DIR>/codex-exit.txt.
Send me (the team lead) a message: "Codex complete (persona). Exit: 0"
Wait for further instructions — you may be asked to debate or re-review.
```

**Gemini reviewer — CLI type** (when `GEMINI_CLI_AVAILABLE`):

Agent `name`: `gemini-reviewer`
```
Your job is to get a REAL review from the Google Gemini CLI. Do NOT write the review yourself.
Do NOT role-play or emulate Gemini. You MUST call the actual CLI binary.

Step 1: Run the Gemini invoke script:
  bash <SCRIPT_DIR>/invoke-gemini.sh "<WORK_DIR>" "" "<GEMINI_MODEL>"

  Use timeout: 300000 on the Bash call.

Step 2: Read <WORK_DIR>/gemini-exit.txt for the exit code.
  - If "0": Read <WORK_DIR>/gemini-output.md — this is the REAL Gemini review.
    Message me: "Gemini complete. Exit: 0"
  - If non-zero (124 timeout or other failure):
    Fall back to persona mode. Read the plan at <WORK_DIR>/plan.md and write your
    own review as The Architect — a systems architect reviewing for structural integrity.
    Focus on approach validity, over-engineering, missing phases, graceful degradation.
    Write your review to <WORK_DIR>/gemini-output.md. End with VERDICT: APPROVED or VERDICT: REVISE.
    Write "0" to <WORK_DIR>/gemini-exit.txt.
    Message me: "Gemini complete (CLI failed, persona fallback). Exit: 0"

Wait for further instructions — you may be asked to debate or re-review.
```

**Gemini reviewer — persona fallback** (when NOT `GEMINI_CLI_AVAILABLE`):

Agent `name`: `gemini-reviewer`
```
You are The Architect — a systems architect reviewing for structural integrity.
The Gemini CLI is not installed or not authenticated, so you are providing this review
as a Claude persona.

Focus: approach validity, over-engineering, missing phases, graceful degradation,
better alternatives, scalability risks, cross-cutting concerns.

Read the plan at: <WORK_DIR>/plan.md

Write your complete review to <WORK_DIR>/gemini-output.md. Be specific — cite the step
or design decision that is structurally flawed. End your review with either:
  VERDICT: APPROVED
  VERDICT: REVISE

Then write "0" to <WORK_DIR>/gemini-exit.txt.
Send me (the team lead) a message: "Gemini complete (persona). Exit: 0"
Wait for further instructions — you may be asked to debate or re-review.
```

**The Skeptic (Opus reviewer)** — always persona (Opus IS Claude):

Agent `name`: `opus-reviewer`
```
You are The Skeptic — a devil's advocate. Find what everyone else missed.

Focus:
1. Unstated assumptions — what is assumed true that could be false?
2. Unhappy path — what breaks when the first thing goes wrong?
3. Second-order failures — what does a partial success leave behind?
4. Security — is any user-controlled content reaching a shell string?
5. The one fatal flaw — if this plan has one, what is it?

Read the plan at: <WORK_DIR>/plan.md

Write your complete review to <WORK_DIR>/opus-output.md. Be specific and direct. End with either:
  VERDICT: APPROVED
  VERDICT: REVISE

Then write "0" to <WORK_DIR>/opus-exit.txt.
Send me (the team lead) a message: "Opus complete. Exit: 0"
Wait for further instructions — you may be asked to debate or re-review.
```

Wait for `SendMessage` from all spawned reviewer agents (they arrive as new conversation turns). When all have reported (or 360s elapses from when the last agent was spawned), proceed.

If an agent fails to report within 360s, treat that reviewer as timed-out (exit 124).

**Do NOT call `TeamDelete` here.** The team remains active for debates and revision rounds.

**Round 2+ — Message existing teammates (do NOT spawn new agents):**

For CLI-type reviewers (codex/gemini with CLI available), send:

```
Recipient: "<reviewer-name>"
Content:
  "The plan has been revised. Before re-running the invoke script, write a revision-aware
   prompt to <WORK_DIR>/<name>-prompt.txt that includes:
   1. What changed in the revision (read <WORK_DIR>/revisions.txt)
   2. A note to focus on whether the previous concerns were addressed
   Then re-run the invoke script (use the captured session ID — CODEX_SESSION_ID or GEMINI_SESSION_UUID):
   bash <SCRIPT_DIR>/invoke-<name>.sh "<WORK_DIR>" "<REVIEWER_SESSION_ID>" "<MODEL>"
   Read the exit code from <WORK_DIR>/<name>-exit.txt and report back.
   After the invoke script completes, delete <WORK_DIR>/<name>-prompt.txt to avoid
   stale prompts on subsequent rounds."
```

For persona-type reviewers (opus, or codex/gemini without CLI), send:

```
Recipient: "<reviewer-name>"
Content:
  "The plan has been revised. Re-read <WORK_DIR>/plan.md (file has been updated).
   Write your updated review to <WORK_DIR>/<name>-output.md, overwriting the previous.
   End with VERDICT: APPROVED or VERDICT: REVISE.
   Write '0' to <WORK_DIR>/<name>-exit.txt. Then message me: '<Name> complete.'"
```

**Per-reviewer fallback:** If a teammate-type reviewer fails to respond within 360s in Round 2+, fall back to a fresh agent spawn for that reviewer only, with injected context (see Option C below for the context injection pattern). The other teammates continue in team mode. Track each reviewer's active mode: `REVIEWER_MODE[<name>]=team|agent`.

### Option C — Agent Mode (`EXEC_MODE=agent`)

**Every round:** Spawn reviewer agents using the Agent tool with `run_in_background: true`.

**Round 1 prompt** — use the same CLI-first / persona-fallback prompts as Option B, matching each reviewer's type from `TEAM_REVIEWER_PLAN`.

**Round 2+ prompt — CLI-type reviewers:** Write a revision-aware prompt to `<WORK_DIR>/<name>-prompt.txt`, then spawn an agent whose job is to call the invoke script:

```bash
# Write revision-aware prompt for the CLI to use
cat > <WORK_DIR>/<name>-prompt.txt << 'EOF'
The plan has been revised. Here is what changed:
[content of <WORK_DIR>/revisions.txt]

Re-review the updated plan. Focus on whether the previous concerns were addressed.
End with VERDICT: APPROVED or VERDICT: REVISE.
EOF
```

Spawn a fresh agent with prompt: "Run `bash <SCRIPT_DIR>/invoke-<name>.sh "<WORK_DIR>" "<REVIEWER_SESSION_ID>" "<MODEL>"` (use timeout: 300000). Read `<WORK_DIR>/<name>-exit.txt` for the exit code. If non-zero, fall back to persona review. After completion, delete `<WORK_DIR>/<name>-prompt.txt`."

**Round 2+ prompt — persona-type reviewers:** Write context to a temp file first, then pass file path to agent:

```bash
# Write injected context to file — never interpolate review content into prompt strings
cat > <WORK_DIR>/<name>-r<N>-context.md << 'EOF'
[reviewer persona — same as Round 1]

Your previous review (Round N-1):
[content of <WORK_DIR>/<name>-output.md]

Revision summary:
[content of <WORK_DIR>/revisions.txt]

Updated plan (review this carefully):
[content of <WORK_DIR>/plan.md]

Re-review the updated plan. You previously said [X]; if the revision addressed that concern, say so.
End with VERDICT: APPROVED or VERDICT: REVISE.
Write your review to <WORK_DIR>/<name>-output.md and write "0" to <WORK_DIR>/<name>-exit.txt.
EOF
```

Spawn the agent with the context file path as its only instruction. Round 2+ spawns are sequential (acceptable — Round 1 parallelism is the critical path). Collect results via `TaskOutput`.

### Check exit codes (all modes)

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

For each contradiction, send a targeted question to each reviewer in the disagreement.

**Shell mode — CLI reviewers:** Use the invoke scripts with session IDs. Build debate prompts from files — never interpolate reviewer output directly into shell strings:

```bash
# For Codex:
{
  echo "There is a disagreement on [topic]."
  echo "The other reviewer's position is in: <WORK_DIR>/<other>-output.md"
  echo "Your position is in: <WORK_DIR>/codex-output.md"
  echo "Read both files. Do you stand by your position, or does their point change your assessment?"
} > <WORK_DIR>/codex-prompt.txt

bash "<SCRIPT_DIR>/invoke-codex.sh" "<WORK_DIR>" "<CODEX_SESSION_ID>" "<CODEX_MODEL>"
```

```bash
# For Gemini:
{
  echo "There is a disagreement on [topic]."
  echo "The other reviewer's position is in: <WORK_DIR>/<other>-output.md"
  echo "Your position is in: <WORK_DIR>/gemini-output.md"
  echo "Read both files. Do you stand by your position, or does their point change your assessment?"
} > <WORK_DIR>/gemini-prompt.txt

bash "<SCRIPT_DIR>/invoke-gemini.sh" "<WORK_DIR>" "<GEMINI_SESSION_UUID>" "<GEMINI_MODEL>"
```

```bash
# For Opus:
{
  echo "There is a disagreement on [topic]."
  echo "The other reviewer's position is in: <WORK_DIR>/<other>-output.md"
  echo "Your position is in: <WORK_DIR>/opus-output.md"
  echo "Read both files. Do you stand by your position, or does their point change your assessment?"
} > <WORK_DIR>/opus-prompt.txt

bash "<SCRIPT_DIR>/invoke-opus.sh" "<WORK_DIR>" "<OPUS_SESSION_ID>" "<OPUS_MODEL>"
```

After each invoke call: check the exit code; on success read the reviewer's `*-output.md` and updated `*-session-id.txt`. If a session resume fails, skip that reviewer's debate response and note it.

**Team mode — CLI-type reviewers:** Write the debate prompt to `<WORK_DIR>/<name>-prompt.txt`, then SendMessage the teammate with explicit instructions to re-run the invoke script:

```bash
{
  echo "There is a disagreement on [topic]."
  echo "The other reviewer's position is in: <WORK_DIR>/<other>-output.md"
  echo "Your position is in: <WORK_DIR>/<name>-output.md"
  echo "Read both files. Do you stand by your position, or does their point change your assessment?"
} > <WORK_DIR>/<name>-prompt.txt
```

```
SendMessage:
  Recipient: "<reviewer-name>"
  Content:
    "A debate prompt has been written to <WORK_DIR>/<name>-prompt.txt.
     Re-run the invoke script to get the CLI's debate response:
     bash <SCRIPT_DIR>/invoke-<name>.sh "<WORK_DIR>" "<REVIEWER_SESSION_ID>" "<MODEL>"
     Read <WORK_DIR>/<name>-exit.txt for the exit code. Report back.
     After completion, delete <WORK_DIR>/<name>-prompt.txt."
```

Wait for the teammate's response. After the debate exchange completes, verify `<WORK_DIR>/<name>-prompt.txt` was deleted (delete it yourself if the teammate didn't).

**Team mode — persona-type reviewers:** Write the debate prompt to a file and have the reviewer read the output files itself — never include raw reviewer output in the SendMessage content:

```bash
{
  echo "There is a disagreement on [topic]."
  echo "The other reviewer's position is in: <WORK_DIR>/<other>-output.md"
  echo "Your position is in: <WORK_DIR>/<name>-output.md"
  echo "Read both files. Do you stand by your position, or does their point change your assessment?"
  echo "Write your response to <WORK_DIR>/<name>-output.md. Then message me: '<Name> debate complete.'"
} > <WORK_DIR>/<name>-debate-instructions.txt
```

SendMessage the teammate with only a brief summary and the file path to read — not the raw content. Wait for the teammate's response message before proceeding.

**Agent mode:** For CLI-type reviewers, write the debate prompt to `<WORK_DIR>/<name>-prompt.txt` and spawn a fresh agent that calls the invoke script. After the agent completes, delete `<WORK_DIR>/<name>-prompt.txt` to prevent stale prompts. For persona-type reviewers, spawn a fresh agent with full context injected via temp file (reviewer's prior output + other reviewer's position + debate question). Agent writes to `<name>-output.md` and exits.

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
5. Return to **Step 2** with incremented round counter. In team mode, do NOT call `TeamCreate` again — the team from Step 1e is still active; teammates will be messaged (Option B Round 2+).

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

In team mode, shut down the review team first:

```
TeamDelete
```

If `TeamDelete` fails, log a warning: `"TeamDelete failed for debate-<REVIEW_ID> — manual cleanup may be needed"` and continue.

Then remove temp files:

```bash
rm -rf /tmp/claude/ai-review-${REVIEW_ID}
```

If any step failed before reaching this step, still run both cleanup steps (TeamDelete if in team mode, then rm -rf).

---

## Rules

- **Security:** Never inline plan content or AI-generated text in shell strings — pass via file path, stdin redirect, or `$(cat file)` with a pre-written temp file
- **Parallelism:** Execute the static runner script from the plugin (`scripts/run-parallel.sh`) — it manages job control and PID capture correctly. Never write a runner script dynamically.
- **Timeout binary:** Resolve `TIMEOUT_BIN` at setup. Each invoke-*.sh script self-detects it via `command -v timeout`. Do NOT prefix bash calls with `TIMEOUT_BIN=...` — the env var prefix changes the command string and prevents sandbox exclusion pattern matching. Model vars go in `config.env`, not env var prefixes.
- **Exit codes:** Check `$?` after each `bash "$SCRIPT_DIR/invoke-*.sh"` call — the script propagates the reviewer's exit code
- **Graceful degradation:** If only 1 reviewer is available, run the full flow and skip the debate phase
- **All-fail handling:** If all reviewers fail/timeout, return `UNDECIDED` with retry guidance
- **Session tracking:** Always recapture session IDs from `*-session-id.txt` after each invoke script call — stale IDs cause silent failures on next resume; each script handles fallback internally
- **CLI-preferred reviewers:** In all modes, Codex and Gemini teammates prefer calling the real CLI binary via invoke scripts when the CLI is available and authenticated. If the CLI is unavailable, they fall back to persona-based review (Claude role-playing that perspective). Sandbox restrictions (Codex: `SCDynamicStoreCreate` panic; Gemini: outbound HTTPS blocked) may cause CLI calls to fail from subagent processes — configure `sandbox.excludedCommands` as shown by `/debate:setup`, or accept persona fallback.
- **Opus session ID (shell mode only):** Read `OPUS_SESSION_ID` from `opus-session-id.txt` (written by invoke-opus.sh); script guards `--resume` with `[ -n "$OPUS_SESSION_ID" ]` internally. Not applicable in team/agent mode.
- **Opus nested sessions (shell mode only):** `invoke-opus.sh` handles `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT` and `CLAUDE_CODE_SIMPLE=1` internally. Not needed in team/agent mode where all reviewers are native teammates.
- **jq dependency (shell mode only):** Skip Claude reviewer in shell mode if `jq` is not installed; show install guidance. In team/agent mode, all reviewers run natively — jq is not required.
- **Debate guard:** Explicitly skip Step 5 if fewer than 2 reviewers succeeded
- **Revision discipline:** Make real plan improvements, not cosmetic changes
- **User control:** If a revision would contradict the user's explicit requirements, skip it and note it
- **Team lifecycle:** `TeamCreate` once in Step 1e; `TeamDelete` once in Step 9 (failure is logged, not fatal). Never call `TeamCreate` inside Step 2 or between rounds. Never `TeamDelete` before Step 9 except on error cleanup.
- **Exec mode discipline:** In team mode, never spawn new reviewer agents after Round 1 — use `SendMessage`. Per-reviewer fallback to agent-mode is allowed if a teammate goes silent (360s timeout). In agent mode, always inject full context via temp file for Round 2+ spawns.
- **Injection safety — all modes:** Never interpolate reviewer output or plan content directly into `SendMessage` content strings or agent prompt strings. Always write to a temp file first; in team mode, send only file paths and have teammates read output files directly using their own filesystem access.
