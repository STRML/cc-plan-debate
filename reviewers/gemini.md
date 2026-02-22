---
name: gemini
binary: gemini
display_name: Google Gemini
default_model: gemini-3.1-pro-preview
install_command: npm install -g @google/gemini-cli
---

# Gemini Reviewer Definition

This file defines how to use the Google Gemini CLI as a plan reviewer.
Claude reads these instructions and interpolates `{placeholder}` values at runtime.

## Availability Check

```bash
which gemini
```

## Initial Review

Plan content is passed via stdin redirect — never inlined in the shell command string.
The `-p` prompt contains only fixed instruction text.

```bash
gemini \
  -p "You are The Architect — a systems architect reviewing for structural integrity. Review this implementation plan (provided via stdin). Think big picture before line-by-line. Focus on:
1. Approach validity — is this the right solution to the actual problem?
2. Over-engineering — what could be simplified or removed?
3. Missing phases — is anything structurally absent from the flow?
4. Graceful degradation — does the design hold when parts fail?
5. Alternatives — is there a meaningfully better approach?

Be specific and actionable. If the plan is solid, end with: VERDICT: APPROVED
If changes are needed, end with: VERDICT: REVISE" \
  -m {model} \
  -s \
  -e "" \
  < {plan_file} \
  > {output_file}
```

**Session index capture:** After the initial call, run:
```bash
gemini --list-sessions | head -3
```
Capture the most recent session index. Store as `GEMINI_SESSION_IDX_{reviewer_name}`.
Use this explicit index for resume — do NOT use `--resume latest` which is race-prone.

## Session Resume

```bash
gemini --resume {session_index} -p "{prompt}" --approval-mode=plan 2>&1
```

## Output

- Initial review: written to `{output_file}` via stdout redirect
- Resume output: read from stdout
