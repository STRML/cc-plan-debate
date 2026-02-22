# debate

A Claude Code plugin that sends implementation plans to multiple AI models for parallel review, synthesizes their feedback, debates contradictions, and produces a consensus verdict.

## Commands

| Command | Description |
|---------|-------------|
| `/debate:codex-review` | Iterative review with OpenAI Codex (up to 5 rounds) |
| `/debate:gemini-review` | Iterative review with Google Gemini (up to 5 rounds) |
| `/debate:all` | All available reviewers in parallel + synthesis + debate |

## Installation

### Via GitHub

```
/plugin marketplace add STRML/cc-plan-debate
/plugin install debate@cc-plan-debate
```

### Local dev

```bash
git clone https://github.com/STRML/cc-plan-debate ~/git/oss/cc-plugin-ai-review
/plugin marketplace add ~/git/oss/cc-plugin-ai-review
/plugin install debate@debate-dev
```

Then restart Claude Code.

## Prerequisites

### OpenAI Codex CLI (for `/debate:codex-review` and `/debate:all`)

```bash
npm install -g @openai/codex
export OPENAI_API_KEY=<your-key>   # add to ~/.bashrc or ~/.zshrc
```

### Google Gemini CLI (for `/debate:gemini-review` and `/debate:all`)

```bash
npm install -g @google/gemini-cli
gemini auth
```

The commands check prerequisites at startup and print specific install instructions for anything missing.

## Usage

### `/debate:codex-review [model]`

Run from a session that has a plan (e.g., after `/plan` or during plan mode):

```
/debate:codex-review
/debate:codex-review o4-mini    # override model
```

Claude writes the current plan to a temp file, submits it to Codex, revises based on feedback, and iterates until Codex approves or 5 rounds are exhausted.

### `/debate:gemini-review [model]`

Same workflow, using Gemini CLI:

```
/debate:gemini-review
/debate:gemini-review gemini-2.0-flash   # override model
```

### `/debate:all [skip-debate]`

Runs all available reviewers in parallel (timeout: 120s each), synthesizes, debates contradictions, then iterates up to 3 total revision rounds:

```
/debate:all              # full flow with debate
/debate:all skip-debate  # skip targeted debate, go straight to final report
```

At startup, the command checks which reviewers are installed and prints exact install commands for anything missing.

## Security

- Plan content is **always passed via file path or stdin pipe** — never inlined in shell command strings. This prevents shell injection and argument-length issues with large plans.
- Dynamic content (revision summaries, AI feedback) is written to temp files and read into variables — never interpolated directly into quoted shell strings.
- Codex always runs with `-s read-only` — it can read the codebase for context but cannot write files.
- Gemini always runs with `-s` (sandbox) — prevents it from executing shell commands.

## Efficiency

Gemini is invoked with `-e ""` (no extensions) to suppress skill/extension loading on every review call, reducing startup time and improving cache hit rate.

## How Debate Works

When `/debate:all` finds contradictions between reviewers, it sends targeted questions to each reviewer via session resume (maintaining conversation context). Max 2 debate rounds. Each round only queries reviewers about their own specific disagreements.

## Session Tracking

- **Codex:** session ID is captured from stdout (`session id: <uuid>`) and used explicitly for resume — never `--last`
- **Gemini:** session UUID is captured by diffing `--list-sessions` before and after the initial call — never positional indexes or `--resume latest`, both of which are race-prone

## Temp Files

All temp files use the prefix `/tmp/ai-review-<8-char-uuid>/` and are cleaned up after each session. No plan content is persisted beyond the review session.

## Custom Reviewers

Add reviewer definitions at `~/.claude/ai-review/reviewers/<name>.md`. These override built-in reviewers with the same `name:` frontmatter value. See `reviewers/codex.md` for the required format.

## License

MIT
