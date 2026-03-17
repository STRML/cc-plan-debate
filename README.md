# debate

Get a second (and third, and fourth) opinion on your implementation plan. The `debate` plugin sends your plan to multiple AI reviewers simultaneously via [acpx](https://github.com/openclaw/acpx), synthesizes their feedback, and has them argue out any disagreements — so you get independent review plus a consensus verdict before writing a line of code.

## Quick Start

```bash
# Install
/plugin marketplace add STRML/cc-debate
/plugin install debate@cc-debate

# Install acpx
npm install -g acpx@latest

# Configure reviewers
/debate:acpx-setup

# Check prerequisites
/debate:setup

# Run a review (while in plan mode, or after describing a plan)
/debate:all
```

Restart Claude Code after installing.

## What it does

```
You: /debate:all

Claude: Launching parallel review via acpx...

  Reviewers:
    codex  → agent: codex   (120s)
    gemini → agent: gemini  (240s)
    kimi   → agent: kimi    (120s)

  [All reviewers review your plan simultaneously via acpx]

  ## Codex Review — Round 1
  The retry logic in Step 4 doesn't handle the case where...
  VERDICT: REVISE

  ## Gemini Review — Round 1
  Missing error handling when the API is unavailable...
  VERDICT: REVISE

  ## Kimi Review — Round 1
  Unstated assumption: this plan assumes the temp directory is writable...
  VERDICT: REVISE

  ## Synthesis
  Unanimous: all reviewers flagged missing error handling
  Unique to Codex: retry logic gap in Step 4
  Unique to Kimi: temp directory writability assumption

  ## Final Report
  VERDICT: REVISE — 3 issues to address before implementation

Claude: Revising plan... [updates the plan]
Claude: Sending revised plan back to all reviewers...

  ## Codex Review — Round 2  →  VERDICT: APPROVED ✅
  ## Gemini Review — Round 2  →  VERDICT: APPROVED ✅
  ## Kimi Review — Round 2   →  VERDICT: APPROVED ✅

  ## Final Report — Round 2 of 3
  VERDICT: APPROVED — unanimous
```

## Commands

| Command | Description |
|---------|-------------|
| `/debate:setup` | Check prerequisites, create symlinks, print permission allowlist |
| `/debate:acpx-setup` | Configure reviewers: create/validate `~/.claude/debate-acpx.json`, probe agents |
| `/debate:all [reviewers] [skip-debate]` | All configured reviewers in parallel + synthesis + debate |
| `/debate:opus-review` | Single-reviewer Opus loop (up to 5 rounds) |
| `/debate:opus-review-subagent` | Single-round Opus review via Task subagent — no CLI, no temp files |

## Installation

### From GitHub

```
/plugin marketplace add STRML/cc-debate
/plugin install debate@cc-debate
```

### Local dev

```bash
git clone https://github.com/STRML/cc-debate ~/debate-plugin
/plugin marketplace add ~/debate-plugin
/plugin install debate@cc-debate
```

Restart Claude Code after installing.

## Prerequisites

1. **acpx** — the unified CLI for communicating with coding agents
   ```bash
   npm install -g acpx@latest
   ```

2. **jq** — JSON processing
   ```bash
   brew install jq          # macOS
   apt install jq           # Linux
   ```

3. **Agent CLIs** — install the agents you want to use as reviewers. acpx auto-downloads adapters on first use, but the underlying agents must be installed separately:

   | Agent | Install |
   |-------|---------|
   | codex | `npm install -g @openai/codex` + set `OPENAI_API_KEY` |
   | gemini | `npm install -g @google/gemini-cli` + run `gemini auth` |
   | claude | Already installed (part of Claude Code) |
   | kimi | `npm install -g @anthropic-ai/kimi-cli` |
   | cursor | Install Cursor IDE |
   | copilot | `gh extension install github/gh-copilot` |

Run `/debate:setup` to check everything at once.

## Config

Reviewers are configured in `~/.claude/debate-acpx.json`. Run `/debate:acpx-setup` to create it interactively, or create it manually:

```json
{
  "reviewers": {
    "codex": {
      "agent": "codex",
      "timeout": 120,
      "system_prompt": "You are The Executor — a pragmatic runtime tracer focused on shell correctness, exit codes, race conditions, and file I/O."
    },
    "gemini": {
      "agent": "gemini",
      "timeout": 240,
      "system_prompt": "You are The Architect — a systems architect reviewing for structural integrity, over-engineering, missing phases, and graceful degradation."
    },
    "kimi": {
      "agent": "kimi",
      "timeout": 120
    }
  }
}
```

Each reviewer entry:

| Field | Required | Description |
|-------|----------|-------------|
| `agent` | Yes | acpx agent name (codex, gemini, claude, kimi, kiro, qwen, etc.) |
| `timeout` | No | Seconds before the review is killed (default: 120) |
| `system_prompt` | No | Persona and focus areas sent as the prompt prefix |

### Adding a reviewer

Add an entry to the `reviewers` object. That's it — no scripts, no binaries, no code changes.

### Available acpx agents

codex, claude, gemini, cursor, copilot, kimi, kiro, qwen, opencode, kilocode, droid, iflow, pi, openclaw.

See [acpx docs](https://github.com/openclaw/acpx) for the full list.

## Usage

### `/debate:all [reviewers] [skip-debate]`

Runs all configured reviewers in parallel via acpx. If reviewers disagree, Claude sends targeted questions back to each one to resolve contradictions. Iterates up to 3 revision rounds.

```
/debate:all                    # all configured reviewers
/debate:all codex,gemini       # specific reviewers only
/debate:all skip-debate        # skip debate, straight to report
```

### `/debate:opus-review`

Iterative loop with Claude Opus as **The Skeptic** — focused on unstated assumptions, unhappy paths, second-order failures, and security. Up to 5 rounds.

### `/debate:opus-review-subagent`

Single-round Opus review using Claude's built-in Task tool. No CLI subprocess, no temp files, no session management — just fast feedback.

## Unattended / No-Prompt Use

Each command declares its tool permissions in frontmatter, so Claude Code will ask once per session and remember. To approve permanently across all sessions, run `/debate:setup` to get the exact JSON snippet to add to `~/.claude/settings.json`.

## Troubleshooting

**acpx agent fails or times out**
Check that the underlying agent CLI is installed and authenticated. Run `/debate:acpx-setup` to probe each configured agent.

**`timeout: command not found`**
Install GNU coreutils: `brew install coreutils` (macOS). Reviews will still work without it, but the per-reviewer timeout won't be enforced.

**Empty response from reviewer**
The agent returned no content. Check `<work_dir>/<reviewer>-stderr.log` for error details.

## Security

- Plan content is always passed via **file path** — never inlined in shell strings
- Dynamic content (revision summaries, AI feedback) is written to temp files — never interpolated directly into shell strings
- acpx is invoked with `--approve-reads` — agents can read the codebase for context but cannot write files
- Work directories in `.tmp/ai-review-*` are cleaned up by the command's final cleanup step

## License

MIT
