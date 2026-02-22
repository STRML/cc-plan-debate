---
name: codex
binary: codex
display_name: OpenAI Codex
default_model: gpt-5.3-codex
install_command: npm install -g @openai/codex
---

# Codex Reviewer Definition

This file defines how to use the OpenAI Codex CLI as a plan reviewer.
Claude reads these instructions and interpolates `{placeholder}` values at runtime.

## Availability Check

```bash
which codex
```

## Initial Review

Plan content is always passed via file path reference — never inlined in the shell command string.

```bash
codex exec \
  -m {model} \
  -s read-only \
  -o {output_file} \
  "Review the implementation plan in {plan_file}. Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. If the plan is solid, end with: VERDICT: APPROVED
If changes are needed, end with: VERDICT: REVISE"
```

**Session ID capture:** Read stdout for the line `session id: <uuid>`. Store as `CODEX_SESSION_ID_{reviewer_name}`.
This ID is required for session resume — do NOT use `--last` which is race-prone with concurrent sessions.

## Session Resume

```bash
codex exec resume {session_id} "{prompt}" 2>&1 | tail -80
```

**Note:** `codex exec resume` does NOT support `-o`. Capture output from stdout.

## Output

- Initial review: written to `{output_file}` via `-o` flag
- Resume output: read from stdout (pipe tail to skip startup lines)
