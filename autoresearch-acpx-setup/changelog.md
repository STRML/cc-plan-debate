# Autoresearch Changelog — acpx-setup.md
## Experiment 1 — KEEP

**Score:** 15/15 (100%)
**Change:** Added `model_id` field to OpenRouter reviewer entries in debate config (Step 2d), and updated Step 6 summary to read and display it as `— openrouter/<model_id>`.
**Reasoning:** E5 failed for T2/T3 because the summary template referenced the model ID (e.g., `inception/mercury-2`) but that data wasn't in the debate config — only `agent: mercury` was. Step 6 had no way to know the underlying OpenRouter model without reading the opencode per-agent config file.
**Result:** All 5 evals pass for all 3 scenarios. E5 now correctly shows model IDs for OpenRouter reviewers.
**Remaining gaps (not in evals):** Gemini API key guidance is reactive (shown on probe failure) rather than proactive (shown when gemini is selected during setup). Low risk since the probe catches it.

---



## Experiment 0 — baseline

**Score:** 13/15 (86.7%)
**Change:** None — original skill as-is
**Failing evals:**
- E5 (summary completeness) fails for T2 and T3: the Step 6 summary template shows
  `mercury  ✅ openrouter  (120s timeout, inception/mercury-2)` but the model ID
  (e.g., `inception/mercury-2`) is not stored in `~/.claude/debate-acpx.json` —
  only `agent: mercury` is there. The skill cannot reliably show the model ID in
  the summary because that information lives in `~/.acpx/agents/mercury/.opencode.json`,
  which is not read in Step 6.
