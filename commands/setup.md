---
description: Check debate plugin prerequisites, verify reviewers are installed and authenticated, and print the exact settings.json snippet for fully unattended (no-prompt) operation.
allowed-tools: Bash(which codex:*), Bash(which gemini:*), Bash(which claude:*), Bash(which jq:*), Bash(command -v:*), Bash(codex --version:*), Bash(claude --version:*), Bash(timeout 30 gemini:*)
---

# debate — Setup & Permission Check

Verify all prerequisites for the debate plugin and print everything needed for fully unattended operation.

---

## Step 1: Check reviewer binaries

```bash
which codex
which gemini
which claude
which jq
```

Report:

```
## debate — Setup Check

### Reviewer Binaries
  ✅ codex    found at /path/to/codex
  ✅ gemini   found at /path/to/gemini
  ✅ claude   found at /path/to/claude

### Tools
  ✅ jq       found at /path/to/jq
```

For anything missing, show the install command:

| Binary | Install Command |
|--------|----------------|
| codex | `npm install -g @openai/codex` |
| gemini | `npm install -g @google/gemini-cli` |
| claude | `npm install -g @anthropic-ai/claude-code` |
| jq | `brew install jq` (macOS) / `apt install jq` (Linux) |

## Step 2: Check Codex version and auth

```bash
codex --version
```

If codex is found, report the version. Codex stores credentials in `~/.codex/auth.json` — check:

```bash
[ -f "$HOME/.codex/auth.json" ] && echo "auth.json: present" || echo "auth.json: NOT FOUND"
```

Report:
- Present → `✅ codex: authenticated (v0.x.x)`
- Not found → `❌ codex: not authenticated — run: codex auth` (or launch `codex` interactively to complete sign-in)

## Step 3: Check Gemini authentication

`--list-sessions` hangs in the Claude Code sandbox, so use a real invocation instead:

```bash
echo "reply with only the word PONG" | timeout 30 gemini -s -e "" 2>/dev/null
```

Report:
- Output contains "PONG" (case-insensitive) → `✅ gemini: authenticated`
- Non-zero exit or no output → `❌ gemini: not authenticated — run: gemini auth`

## Step 3b: Check Claude CLI

```bash
unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
claude --version
```

Report:
- Exit 0 → `✅ claude: ready (v1.x.x)` — uses Claude Code's stored credentials, no separate API key needed
- Not found → `❌ claude: not installed — run: npm install -g @anthropic-ai/claude-code`

Note: `--version` confirms binary presence only. Authentication is validated at first use.

## Step 3c: Check Codex sandbox exclusion

Codex panics when run inside the Claude Code sandbox (macOS `SystemConfiguration` NULL crash). It must be listed in `sandbox.excludedCommands` in `~/.claude/settings.json`.

```bash
jq -e '.sandbox.excludedCommands | index("codex:*")' "$HOME/.claude/settings.json" > /dev/null 2>&1
```

Report:
- Exit 0 (index found) → `✅ codex: sandbox excluded`
- Non-zero → `❌ codex: will panic in sandbox — add "codex:*" to sandbox.excludedCommands in ~/.claude/settings.json`

If missing, show the exact snippet to add:
```json
"sandbox": {
  "excludedCommands": ["codex:*"]
}
```

## Step 4: Check timeout binary

```bash
command -v timeout || command -v gtimeout
```

Report:
- Found → `✅ timeout: /path/to/timeout`
- Not found → `❌ timeout: not found — install: brew install coreutils` (macOS) or `apt install coreutils` (Linux)

## Step 5: Print permission allowlist

Print the complete list of Bash tool patterns needed for fully unattended operation (no approval prompts):

```
### Permission Allowlist

To run /debate:all, /debate:codex-review, /debate:gemini-review, and /debate:opus-review
without any approval prompts, add the following to ~/.claude/settings.json:

{
  "permissions": {
    "allow": [
      "Bash(uuidgen:*)",
      "Bash(command -v:*)",
      "Bash(which codex:*)",
      "Bash(which gemini:*)",
      "Bash(which claude:*)",
      "Bash(which jq:*)",
      "Bash(jq:*)",
      "Bash(mkdir -p /tmp/claude/ai-review-:*)",
      "Bash(rm -rf /tmp/claude/ai-review-:*)",
      "Bash(chmod +x /tmp/claude/ai-review-:*)",
      "Bash(/tmp/claude/ai-review-:*)",
      "Bash(diff:*)",
      "Bash(codex exec -m:*)",
      "Bash(codex exec resume:*)",
      "Bash(gemini -p:*)",
      "Bash(gemini --resume:*)",
      "Bash(claude -p:*)",
      "Bash(claude --resume:*)",
      "Bash(timeout:*)",
      "Bash(gtimeout:*)"
    ]
  }
}

NOTE: These patterns are already declared in the allowed-tools frontmatter of
each command, so each individual session will prompt once and remember within
that session. Adding to settings.json makes approval permanent across all sessions.
```

## Step 6: Print final status

```
### Summary

  Codex:   ✅ ready (v0.x.x, authenticated, sandbox excluded)
  Gemini:  ✅ ready (authenticated)
  Claude:  ✅ ready (v1.x.x)
  jq:      ✅ ready (/opt/homebrew/bin/jq)
  Timeout: ✅ /opt/homebrew/bin/timeout

You are ready to run:
  /debate:all           — parallel review with synthesis and debate (Codex + Gemini + Opus)
  /debate:codex-review  — single-reviewer Codex loop
  /debate:gemini-review — single-reviewer Gemini loop
  /debate:opus-review   — single-reviewer Opus loop (The Skeptic)
```

If anything is missing, list the remaining actions the user needs to take before the plugin will work correctly.
