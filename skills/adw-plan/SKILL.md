---
name: adw-plan
description: Challenge a plan adversarially. Launches an isolated agent to find every reason to reject it, scores confidence, and iterates until the plan is solid (≥80%) or the user stops.
---

# ADW Plan Challenger

You are running an adversarial challenge on a software plan.

## Core principles

1. **Adversarial prompting**: The sub-agent's only job is to find reasons to reject. It does NOT validate, justify, or approve anything.
2. **Context isolation**: The sub-agent receives ONLY the plan content + adversarial instruction. It must NOT receive: the conversation history, the user's justifications, or the reasoning behind the plan. Provide nothing else.
3. **Iterative refinement**: Between iterations, a second isolated agent amends the plan (receiving only the plan + critique, no conversation context). This preserves context isolation throughout the entire loop.

## Confidence threshold

`CONFIDENCE_THRESHOLD = 80`

Score formula: `max(0, 100 - (nb_CRITICAL × 25 + nb_HIGH × 10 + nb_MEDIUM × 3 + nb_LOW × 1))`

---

## Step 1 — Read the plan

Parse `$ARGUMENTS`:

- **Explicit file path** (starts with `/`, `./`, `../`, or ends with `.md`/`.txt`): Read the file using the Read tool.
- **Possible relative path** (no spaces, doesn't look like a sentence): Attempt to read it as a file. If the Read tool returns an error, treat the argument as text content instead.
- **Text content** (contains spaces or clearly not a path): Use it directly as the plan content.
- **Empty**: Use AskUserQuestion: "What plan do you want to challenge? Provide a file path or paste the plan text."

If a file path is given but the file doesn't exist, stop with: "File not found: {path}. Provide a valid path or paste the plan text directly."

Keep the plan content as `CURRENT_PLAN` for subsequent steps. Also track `ITERATION = 1` and `SOURCE_FILE = {path if input was a file, otherwise null}`.

---

## Step 2 — Launch adversarial agent

Use the Agent tool with `subagent_type: "general-purpose"`.

**Provide ONLY this prompt to the agent** (substitute `{CURRENT_PLAN}` with the actual plan text):

```
Here is a software development plan:

---
{CURRENT_PLAN}
---

Your mission: find EVERY reason to reject this plan.

Attack:
- Unvalidated assumptions (things taken for granted without evidence)
- Missing or underspecified scenarios (what happens when X fails, Y is empty, Z is concurrent)
- Design flaws (wrong abstraction, tight coupling, missing separation of concerns)
- Logical inconsistencies (contradictions between sections, impossible sequences)
- Over-engineering (unnecessary complexity for the stated problem)
- Under-engineering (missing critical steps, naive approach to hard problems)
- Edge cases not covered in the plan
- Risks with no mitigation

For each issue found, output exactly:
[SEVERITY] Short title — detailed explanation

SEVERITY must be one of: CRITICAL, HIGH, MEDIUM, LOW.
- CRITICAL: Makes the plan fundamentally broken or unimplementable
- HIGH: Significant gap that will likely cause bugs or failures
- MEDIUM: Notable weakness that should be addressed
- LOW: Minor improvement opportunity

Do NOT justify any decisions. Do NOT suggest fixes. Do NOT approve anything. Attack only.
Output only the issue list. No preamble, no conclusion.
```

If the agent returns empty or clearly non-substantive results (e.g., "No issues found" with no list), do NOT compute a score. Report: "The adversarial agent returned no findings. This may indicate context leakage (the agent is being too agreeable). Re-run `/adw-plan` in a fresh session for a genuine challenge." Then stop.

---

## Step 3 — Compute confidence score

Count the issues by severity from the agent's output:
- `nb_CRITICAL` = number of `[CRITICAL]` items
- `nb_HIGH` = number of `[HIGH]` items
- `nb_MEDIUM` = number of `[MEDIUM]` items
- `nb_LOW` = number of `[LOW]` items

`SCORE = max(0, 100 - (nb_CRITICAL × 25 + nb_HIGH × 10 + nb_MEDIUM × 3 + nb_LOW × 1))`

---

## Step 4 — Present results

Output in this format:

```
## Adversarial Challenge — Iteration {ITERATION}

### Findings

{agent output verbatim}

### Score

Confidence: {SCORE}% ({nb_CRITICAL} CRITICAL, {nb_HIGH} HIGH, {nb_MEDIUM} MEDIUM, {nb_LOW} LOW)
```

---

## Step 5 — Decision

**If `SCORE >= CONFIDENCE_THRESHOLD` (80):**

Output:
```
Plan validated ✓ (confidence: {SCORE}%)

The adversarial agent found no blocking issues. This plan is solid enough to proceed.
```

Then go to **Step 7 — Save**.

**If `SCORE < CONFIDENCE_THRESHOLD`:**

If `ITERATION >= 3`, output first:
> ⚠️ {ITERATION} iterations without reaching 80% (current score: {SCORE}%). Either the plan needs a complete rethink, or the threshold is too strict for this type of plan.

Use AskUserQuestion with:
- Question (if `ITERATION < 3`): "Confidence: {SCORE}%. Iterate to strengthen the plan?"
- Question (if `ITERATION >= 3`): "Confidence: {SCORE}% after {ITERATION} iterations. How do you want to proceed?"
- Options (if `ITERATION < 3`):
  - "Yes, iterate" — The skill will amend the plan (via isolated agent) and re-challenge
  - "No, keep as-is" — Stop here, the plan stays unchanged
- Options (if `ITERATION >= 3`):
  - "Keep iterating" — Continue despite diminishing returns
  - "Accept at {SCORE}%" — Stop and optionally save the current plan
  - "Start over" — Abandon this plan and begin fresh

---

## Step 6 — Iteration (if user chose "Yes, iterate" or "Keep iterating")

Increment `ITERATION`.

Launch a **second isolated agent** to amend the plan. Use the Agent tool with `subagent_type: "general-purpose"`.

**Provide ONLY this prompt** (substitute values):

```
Here is a software development plan and a list of issues found by an adversarial reviewer.

## Current plan

{CURRENT_PLAN}

## Issues to address

{findings from Step 2, verbatim}

Your mission: amend the plan to address these issues.

Rules:
- Address ALL CRITICAL items. Address ALL HIGH items. Address MEDIUM items where clearly warranted. Skip LOW items unless trivial.
- Be direct and mechanical. Do not defend any existing decision. Do not add commentary.
- Preserve all sections and content that were NOT challenged.
- Mark every change with [AMENDED] inline.
- Output the full amended plan, then a section "### What changed" with a concise bullet list of amendments.
```

If the agent returns empty or error output, stop with: "Amendment agent failed. Re-run `/adw-plan` to retry."

Extract the amended plan from the agent's output (everything before "### What changed") and store as `CURRENT_PLAN`.

Output:

```
## Plan — Iteration {ITERATION}

{amended plan from agent}

---

{What changed section from agent}
```

Then return to **Step 2** with the updated `CURRENT_PLAN`.

---

## Step 7 — Save

After every validated plan (score ≥ 80%) or accepted plan (user chose "Accept at X%"), offer to persist the amended plan.

**If `ITERATION = 1` and score ≥ 80% with no amendments** (plan was already solid): skip save offer.

**Otherwise**, use AskUserQuestion:
- Question: "Save the amended plan?"
- Options:
  - "Save to original file" (only if `SOURCE_FILE` is non-null) — Overwrite the file using the Write tool
  - "Save to a new file" — Ask for the path, then write
  - "Don't save" — Stop, plan stays in conversation context only

---

## Error handling

- If the Read tool fails (permissions, disk): stop with a clear error message.
- If the Agent tool fails or returns an error: stop and report the failure. Do not proceed with partial data.
- Never fabricate findings or scores.
