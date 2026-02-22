# cc-plugin-ai-review

A Claude Code plugin that sends implementation plans to multiple AI models for parallel review, synthesizes their feedback, debates contradictions, and produces a consensus verdict.

## Commands

| Command | Description |
|---------|-------------|
| `/codex-review` | Iterative review with OpenAI Codex (up to 5 rounds) |
| `/gemini-review` | Iterative review with Google Gemini (up to 5 rounds) |
| `/ai-review` | All available reviewers in parallel + synthesis + debate |

## Installation

### Via GitHub (once published)

```
/plugin marketplace add strml/cc-plan-debate
/plugin install cc-plugin-ai-review@cc-plan-debate
```

### Local dev

```bash
git clone https://github.com/STRML/cc-plan-debate ~/git/oss/cc-plugin-ai-review
/plugin marketplace add ~/git/oss/cc-plugin-ai-review
/plugin install cc-plugin-ai-review@cc-plugin-ai-review-dev
```

Then restart Claude Code.

## Prerequisites

### OpenAI Codex CLI (for `/codex-review` and `/ai-review`)

```bash
npm install -g @openai/codex
export OPENAI_API_KEY=<your-key>   # add to ~/.bashrc or ~/.zshrc
```

### Google Gemini CLI (for `/gemini-review` and `/ai-review`)

```bash
npm install -g @google/gemini-cli
gemini auth
```

The commands check prerequisites at startup and print specific install instructions for anything missing.

## Usage

### `/codex-review [model]`

Run from a session that has a plan (e.g., after `/plan` or during plan mode):

```
/codex-review
/codex-review o4-mini    # override model
```

Claude writes the current plan to a temp file, submits it to Codex, revises based on feedback, and iterates until Codex approves or 5 rounds are exhausted.

### `/gemini-review [model]`

Same workflow, using Gemini CLI:

```
/gemini-review
/gemini-review gemini-2.0-flash   # override model
```

### `/ai-review [skip-debate]`

Runs all available reviewers in parallel (timeout: 120s each), synthesizes, debates contradictions, then iterates up to 3 total revision rounds:

```
/ai-review              # full flow with debate
/ai-review skip-debate  # skip targeted debate, go straight to final report
```

**At startup**, the command checks which reviewers are installed and tells you exactly what's missing and how to install it.

## Security

- Plan content is **always passed via file path or stdin pipe** — never inlined in shell command strings. This prevents argument-length issues with large plans and avoids injection risks.
- Codex always runs with `-s read-only` — it can read the codebase for context but cannot write files.
- Gemini always runs with `--approval-mode=plan` — prevents it from executing shell commands.
- Custom reviewer files are fully trusted: they are loaded as instruction templates. Only add reviewer files from sources you trust.

## Custom Reviewers

Add reviewer definitions at `~/.claude/ai-review/reviewers/<name>.md`. These override built-in reviewers with the same `name:` frontmatter value. See `reviewers/codex.md` for the required format.

## How Debate Works

When `/ai-review` finds contradictions between reviewers, it sends targeted questions to each reviewer via session resume (maintaining conversation context). Max 2 debate rounds. Each round only queries reviewers about their own specific disagreements — no cross-examination on unrelated topics.

## Temp Files

All temp files use the prefix `/tmp/ai-review-<8-char-uuid>/` and are cleaned up after each session (or on error). No plan content is persisted beyond the review session.

## License

MIT
