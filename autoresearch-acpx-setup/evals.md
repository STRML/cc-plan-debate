# Eval Suite — acpx-setup.md

Max score per experiment = 5 evals × 3 runs = 15

## Test Inputs

1. **T1 — Fresh/built-in**: "Set up debate for my project. I want to use codex and gemini as reviewers."
2. **T2 — Fresh/OpenRouter**: "Set up debate. I want to review with mercury (inception/mercury-2) from OpenRouter."
3. **T3 — Fresh/mixed**: "Set up debate with codex, mercury, and kimi. I have an OpenRouter API key."
4. **T4 — Existing/healthy**: Config exists with codex + mercury — just verify.
5. **T5 — Existing/gemini no key**: Config exists with gemini, but GEMINI_API_KEY not set.

## Evals

EVAL 1: Agent probe
Question: When a reviewer is added/configured, does the output include a connectivity probe that actually tests the agent responds?
Pass: Output shows a probe step (sessions new + PONG test or equivalent) for each agent
Fail: No probe shown, or probe step is missing for one or more agents

EVAL 2: Gemini API key guidance
Question: When gemini is selected or configured, does the output mention GEMINI_API_KEY and provide the settings.json snippet to add it?
Pass: Output includes GEMINI_API_KEY mention, aistudio.google.com link, and the "env" JSON snippet
Fail: Gemini selected/configured but no API key guidance shown

EVAL 3: OpenRouter wrapper completeness
Question: When an OpenRouter model is requested, does the output provide all 3 required artifacts: .opencode.json, start.sh, AND the ~/.acpx/config.json registration?
Pass: All 3 files shown with correct content (provider/apiKey, OPENCODE_CONFIG_CONTENT, command path)
Fail: Any of the 3 is missing or malformed (e.g., missing start.sh, or config.json not shown)

EVAL 4: Permission allowlist
Question: Does the final output include the complete permission allowlist JSON snippet?
Pass: Output contains the 7-entry permissions.allow array with debate-scripts paths and .tmp/ai-review* entries
Fail: Allowlist missing, incomplete (fewer than 5 entries), or not shown

EVAL 5: Final summary completeness
Question: Does the final summary show each configured reviewer with a status (✅/❌) and its agent name?
Pass: Summary lists every reviewer with status indicator and agent identifier (e.g., "codex ✅ built-in")
Fail: Summary absent, or lists reviewers without status, or missing agent name
