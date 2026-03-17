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

```text
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

```bash
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

1. **acpx** — the unified CLI for communicating with coding agents via the [Agent Client Protocol](https://github.com/openclaw/acpx)
   ```bash
   npm install -g acpx@latest
   ```

2. **jq** — JSON processing (used by config parsing)
   ```bash
   brew install jq          # macOS
   apt install jq           # Linux
   ```

3. **Agent CLIs** — install the agents you want to use as reviewers. acpx auto-downloads ACP adapters on first use, but the underlying agent CLIs must be installed separately.

Run `/debate:setup` to check everything at once, or `/debate:acpx-setup` for interactive setup.

## Setting Up Providers

Each reviewer in your config maps to an **acpx agent**, which wraps a coding agent CLI. You need to install and authenticate each agent you want to use.

### OpenAI Codex

```bash
npm install -g @openai/codex
export OPENAI_API_KEY=sk-...    # add to ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish
```

Verify: `codex --version`

Config entry:
```json
"codex": { "agent": "codex", "timeout": 120, "system_prompt": "You are The Executor — a pragmatic runtime tracer focused on shell correctness, exit codes, race conditions, and file I/O." }
```

### Google Gemini

```bash
npm install -g @google/gemini-cli
gemini auth
```

Verify: `echo "PONG" | gemini -s -e ""`

Config entry:
```json
"gemini": { "agent": "gemini", "timeout": 240, "system_prompt": "You are The Architect — a systems architect reviewing for structural integrity, over-engineering, missing phases, and graceful degradation." }
```

### Claude (Opus)

Already installed if you're running Claude Code. No additional setup needed.

Config entry:
```json
"opus": { "agent": "claude", "timeout": 300, "system_prompt": "You are The Skeptic — a devil's advocate focused on unstated assumptions, unhappy paths, second-order failures, and security." }
```

Note: if you're running this plugin **inside** Claude, adding `claude` as a reviewer means Claude reviews its own plan. This can still be useful (different persona, fresh context), but for independent perspectives, prefer non-Claude agents.

### Other built-in agents

acpx supports many more agents with native ACP support: kimi, kiro, qwen, cursor, copilot, opencode, kilocode, droid, iflow, pi, openclaw. See the [acpx docs](https://github.com/openclaw/acpx) for the full list and install instructions. Each works the same way — install the CLI, add a config entry with the agent name.

### Any model via OpenRouter (using opencode)

For models that don't have a dedicated acpx agent (DeepSeek, Mercury, Mixtral, etc.), you can route through [OpenRouter](https://openrouter.ai) using [opencode](https://opencode.ai) as the ACP bridge:

```text
acpx → opencode → OpenRouter → any model
```

**Prerequisites:**
1. Install opencode: see [opencode.ai](https://opencode.ai) for install instructions
2. Get an OpenRouter API key from [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys)

**For each OpenRouter model you want as a reviewer:**

1. Create a wrapper directory and config:

```bash
mkdir -p ~/.acpx/agents/mercury
```

2. Write `~/.acpx/agents/mercury/.opencode.json` with the API key and model:

```json
{
  "provider": {
    "openrouter": {
      "apiKey": "sk-or-v1-..."
    }
  },
  "agents": {
    "coder": {
      "model": "openrouter/inception/mercury-2"
    }
  }
}
```

3. Write `~/.acpx/agents/mercury/start.sh`:

```bash
#!/bin/bash
export OPENCODE_CONFIG_CONTENT='{"model":"openrouter/inception/mercury-2"}'
exec opencode acp "$@"
```

4. Make it executable and secure the config:

```bash
chmod +x ~/.acpx/agents/mercury/start.sh
chmod 600 ~/.acpx/agents/mercury/.opencode.json
```

5. Register the agent in `~/.acpx/config.json`:

```json
{
  "agents": {
    "mercury": {
      "command": "/Users/you/.acpx/agents/mercury/start.sh"
    }
  }
}
```

6. Add the reviewer to `~/.claude/debate-acpx.json`:

```json
"mercury": { "agent": "mercury", "timeout": 120, "system_prompt": "You are The Contrarian..." }
```

**Or just run `/debate:acpx-setup`** — it automates all of this interactively.

### Custom agents

acpx supports custom ACP servers via config. Add to `~/.acpx/config.json`:

```json
{
  "agents": {
    "my-agent": { "command": "/path/to/my-acp-server" }
  }
}
```

Then use it in your debate config:
```json
"my-reviewer": { "agent": "my-agent", "timeout": 120 }
```

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

```bash
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

## Migrating from v1.x

If you're upgrading from v1.x (CLI mode, LiteLLM, or OpenRouter), see [MIGRATING.md](MIGRATING.md) for a complete guide covering config migration, removed commands, and settings.json changes.

## Security

- Plan content is always passed via **file path** — never inlined in shell strings
- Dynamic content (revision summaries, AI feedback) is written to temp files — never interpolated directly into shell strings
- acpx is invoked with `--approve-reads` — agents can read the codebase for context but cannot write files
- Work directories in `.tmp/ai-review-*` are cleaned up by the command's final cleanup step

## License

MIT
