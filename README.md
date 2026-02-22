# debate

Get a second (and third) opinion on your implementation plan. The `debate` plugin sends your plan to OpenAI Codex and Google Gemini simultaneously, synthesizes their feedback, and has them argue out any disagreements — so you get independent review plus a consensus verdict before writing a line of code.

## Quick Start

```bash
# Install
/plugin marketplace add STRML/cc-plan-debate
/plugin install debate@cc-plan-debate

# Check prerequisites
/debate:setup

# Run a review (while in plan mode, or after describing a plan)
/debate:all
```

Restart Claude Code after installing.

## What it does

```
You: /debate:all

Claude: ✅ codex  ✅ gemini  — launching parallel review...

  [Codex and Gemini review your plan simultaneously]

  ## Codex Review — Round 1
  The retry logic in Step 4 doesn't handle the case where...
  VERDICT: REVISE

  ## Gemini Review — Round 1
  Missing error handling when the API is unavailable...
  VERDICT: REVISE

  ## Synthesis
  Unanimous: both reviewers flagged missing error handling
  Unique to Codex: retry logic gap in Step 4
  Contradictions: none

  ## Final Report
  VERDICT: REVISE — 2 issues to address before implementation

Claude: Revising plan... [updates the plan]
Claude: Sending revised plan back to both reviewers...

  ## Codex Review — Round 2  →  VERDICT: APPROVED ✅
  ## Gemini Review — Round 2  →  VERDICT: APPROVED ✅

  ## Final Report — Round 2 of 3
  VERDICT: APPROVED — unanimous
```

## Commands

| Command | Description |
|---------|-------------|
| `/debate:setup` | Check prerequisites, verify auth, print allowlist for unattended use |
| `/debate:all` | All available reviewers in parallel + synthesis + debate |
| `/debate:codex-review` | Single-reviewer Codex loop (up to 5 rounds) |
| `/debate:gemini-review` | Single-reviewer Gemini loop (up to 5 rounds) |

## Installation

### From GitHub

```
/plugin marketplace add STRML/cc-plan-debate
/plugin install debate@cc-plan-debate
```

### Local dev

```bash
git clone https://github.com/STRML/cc-plan-debate ~/debate-plugin
/plugin marketplace add ~/debate-plugin
/plugin install debate@debate-dev
```

Restart Claude Code after installing.

## Prerequisites

Run `/debate:setup` to check everything at once. Or manually:

### OpenAI Codex (for `/debate:codex-review` and `/debate:all`)

```bash
npm install -g @openai/codex
export OPENAI_API_KEY=sk-...    # add to ~/.bashrc or ~/.zshrc
```

### Google Gemini (for `/debate:gemini-review` and `/debate:all`)

```bash
npm install -g @google/gemini-cli
gemini auth
```

### GNU timeout — macOS only

macOS doesn't ship `timeout`. Without it the 120s per-reviewer timeout is disabled:

```bash
brew install coreutils
```

## Usage

### `/debate:all [skip-debate]`

Runs all available reviewers in parallel (120s timeout each). If reviewers disagree, Claude sends targeted questions back to each one to resolve contradictions. Iterates up to 3 revision rounds.

```
/debate:all              # full flow with debate
/debate:all skip-debate  # skip debate, go straight to final report
```

### `/debate:codex-review [model]`

Iterative loop with Codex only — good when you want faster turnaround or a focused Codex perspective.

```
/debate:codex-review
/debate:codex-review o4-mini
```

### `/debate:gemini-review [model]`

Same workflow with Gemini.

```
/debate:gemini-review
/debate:gemini-review gemini-2.0-flash
```

## Unattended / No-Prompt Use

Each command declares its tool permissions in frontmatter, so Claude Code will ask once per session and remember. To approve permanently across all sessions, run `/debate:setup` to get the exact JSON snippet to add to `~/.claude/settings.json`.

## Troubleshooting

**Gemini produces no output**
Gemini authentication may have expired. Run `gemini auth` to re-authenticate.

**`timeout: command not found`**
Install GNU coreutils: `brew install coreutils` (macOS) or `apt install coreutils` (Linux). Reviews will still work without it, but the 120s timeout won't be enforced.

**Codex session resume fails**
Codex sessions expire after a period of inactivity. The commands automatically fall back to a fresh call and recapture the new session ID.

**Gemini session not found after review**
The session UUID diff uses `gemini --list-sessions` before and after the review call. If sessions shift concurrently (multiple Gemini processes), the diff may be ambiguous and the command falls back to non-resume mode for subsequent rounds.

**Only one reviewer available**
Both single-reviewer commands (`/debate:codex-review`, `/debate:gemini-review`) and `/debate:all` work with a single reviewer. With only one reviewer, `/debate:all` skips the debate phase.

## Security

- Plan content is always passed via **file path or stdin redirect** — never inlined in shell strings
- Dynamic content (revision summaries, AI feedback) is written to temp files and read via `$(cat file)` — never interpolated directly into quoted strings
- Codex runs with `-s read-only` — can read the codebase for context but cannot write files
- Gemini runs with `-s` (sandbox) — cannot execute shell commands
- Gemini runs with `-e ""` — extensions and skills are disabled for each review call

## Custom Reviewers

Add reviewer definitions at `~/.claude/ai-review/reviewers/<name>.md`. These override built-in reviewers with the same `name:` frontmatter value. See `reviewers/codex.md` for the format.

## License

MIT
