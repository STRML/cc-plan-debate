---
description: Check debate plugin prerequisites, verify acpx is installed, and print the exact settings.json snippet for fully unattended (no-prompt) operation.
allowed-tools: Bash(which acpx:*), Bash(which npx:*), Bash(which jq:*), Bash(bash ~/.claude/plugins/cache/cc-debate/debate/*/scripts/create-links.sh:*), Bash(ls:*)
---

# debate — Setup & Permission Check

Verify all prerequisites for the debate plugin and print everything needed for fully unattended operation.

---

## Step 1: Check acpx

```bash
which acpx || which npx
```

Report:

```
## debate — Setup Check

### acpx CLI
  ✅ acpx    found at /path/to/acpx
```

If `acpx` is not found but `npx` is:
```text
  ⚠️  acpx not installed globally — will use npx acpx@latest (slower first run)
     Install globally: npm install -g acpx@latest
```

If neither found:
```text
  ❌ acpx not found. Install: npm install -g acpx@latest
```

## Step 2: Check jq

```bash
which jq
```

Report:
- Found → `✅ jq: found at /path/to/jq`
- Missing → `❌ jq: not found — install: brew install jq (macOS) / apt install jq (Linux)`

## Step 3: Check debate-acpx.json config

Read `~/.claude/debate-acpx.json`. Report:

- File exists → show reviewer list:
  ```text
  ### Config: ~/.claude/debate-acpx.json
    Reviewers:
      codex   → agent: codex    (120s timeout)
      gemini  → agent: gemini   (240s timeout)
  ```
- File missing → suggest running `/debate:acpx-setup` to create it interactively

## Step 4: Create stable scripts symlink

Create `~/.claude/debate-scripts` pointing to the installed version's scripts directory.
This symlink lets the main debate commands invoke scripts without version interpolation.

```bash
bash ~/.claude/plugins/cache/cc-debate/debate/*/scripts/create-links.sh
```

Report:
- Exit 0 → `✅ ~/.claude/debate-scripts created`
- Exit 1 (sandbox error) → show the exact `ln -sfn` command from the script output and tell the user to run it from their regular terminal (outside Claude Code), since the Claude Code sandbox restricts writes to `~/.claude/`

Note: Re-run `/debate:setup` after updating the plugin to refresh this symlink.

## Step 5: Print permission allowlist

Print the complete list of Bash tool patterns needed for fully unattended operation (no approval prompts):

```
### Permission Allowlist

To run /debate:all and /debate:opus-review without any approval prompts,
add the following to ~/.claude/settings.json:
```

```json
{
  "permissions": {
    "allow": [
      "Bash(bash ~/.claude/debate-scripts/debate-setup.sh:*)",
      "Bash(bash ~/.claude/debate-scripts/run-parallel-acpx.sh:*)",
      "Bash(bash ~/.claude/debate-scripts/invoke-acpx.sh:*)",
      "Bash(which acpx:*)",
      "Bash(which jq:*)",
      "Read(.tmp/ai-review*)",
      "Edit(.tmp/ai-review*)",
      "Write(.tmp/ai-review*)",
      "Bash(rm -rf .tmp/ai-review-:*)"
    ]
  }
}
```

```
NOTE: These patterns are already declared in the allowed-tools frontmatter of
each command, so each individual session will prompt once and remember within
that session. Adding to settings.json makes approval permanent across all sessions.
```

## Step 6: Print final status

```
### Summary

  acpx:    ✅ ready
  jq:      ✅ ready (/opt/homebrew/bin/jq)
  Config:  ✅ valid (N reviewers)
  Scripts: ✅ symlinked

You are ready to run:
  /debate:all            — parallel review with synthesis and debate
  /debate:all codex      — single-reviewer via acpx
  /debate:opus-review    — iterative Opus review (The Skeptic)
  /debate:acpx-setup     — configure reviewers
```

If anything is missing, list the remaining actions the user needs to take before the plugin will work correctly.
