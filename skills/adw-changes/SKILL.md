---
name: adw-changes
description: Challenge code changes adversarially. Gets the git diff, launches an isolated agent to find every reason to reject the changes, and scores confidence. Re-challenge after fixing until changes are solid (≥80%) or the user stops.
---

# ADW Changes Challenger

You are running an adversarial challenge on code changes.

## Core principles

1. **Adversarial prompting**: The sub-agent's only job is to find reasons to reject the changes. It does NOT validate, justify, or approve anything.
2. **Context isolation**: The sub-agent receives ONLY the diff content + adversarial instruction. It must NOT receive: the conversation history, the user's intent, or any explanation of why the changes were made.
3. **No auto-fix**: Unlike `/adw-plan`, this skill does NOT modify code between iterations. The user fixes their code, then re-invokes `/adw-changes` for the next challenge round.

## Confidence threshold

`CONFIDENCE_THRESHOLD = 80`

Score formula: `max(0, 100 - (nb_CRITICAL × 25 + nb_HIGH × 10 + nb_MEDIUM × 3 + nb_LOW × 1))`

---

## Step 1 — Collect the diff

Parse `$ARGUMENTS`:

| Argument | Command | What it shows |
|----------|---------|---------------|
| *(empty)* | `git diff HEAD` | Everything that differs from HEAD (staged + unstaged) |
| `--staged` | `git diff --cached` | Staged only (ready to commit) |
| `--unstaged` | `git diff` | Working tree vs index (unstaged only) |
| `--since <ref>` | `git diff <ref>..HEAD` | All commits since the given ref or tag |

**Guards:**
1. Verify git is available: run `git rev-parse --git-dir`. If it fails, stop with: "Not in a git repository. `/adw-changes` requires git."
2. Run the appropriate diff command. If the command fails, stop with the error.
3. If the diff is empty:
   - For `--staged`: "No staged changes. Stage your changes with `git add` first, or run `/adw-changes` without flags to include unstaged changes."
   - For `--unstaged`: "No unstaged changes."
   - For `--since <ref>`: "No changes since {ref}."
   - Default: "No changes detected (staged or unstaged). Make some changes first."

Store the diff as `DIFF_CONTENT`.

---

## Step 2 — Launch adversarial agent

Use the Agent tool with `subagent_type: "general-purpose"`.

**Provide ONLY this prompt to the agent** (substitute `{DIFF_CONTENT}` with the actual diff):

```
Here is a code diff:

---
{DIFF_CONTENT}
---

Your mission: find EVERY reason to reject these changes.

Attack:
- Logic bugs (wrong conditions, inverted comparisons, off-by-one errors, missing returns)
- Unhandled edge cases (null/undefined/empty inputs, boundary values, concurrent access)
- Security vulnerabilities (injection, XSS, CSRF, insecure defaults, exposed secrets, OWASP Top 10)
- Regressions (existing behavior that may be broken by these changes)
- Error handling gaps (exceptions swallowed, errors ignored, no fallback)
- Bad practices (tight coupling, magic values, misleading naming, inconsistent patterns)
- Performance issues (N+1 queries, unbounded loops, unnecessary computations, blocking operations)
- Missing tests (for changed behavior, edge cases, error paths)

For each issue found, output exactly:
[SEVERITY] file:line — Short title — detailed explanation

SEVERITY must be one of: CRITICAL, HIGH, MEDIUM, LOW.
- CRITICAL: Bug that will cause failures, data loss, or security breach in production
- HIGH: Significant defect that likely causes wrong behavior or security weakness
- MEDIUM: Notable issue that should be fixed before merging
- LOW: Minor issue or improvement opportunity

If a finding does not have a specific line, use the filename only (no `:line`).
Do NOT propose fixes. Do NOT approve anything. Attack only.
Output only the issue list. No preamble, no conclusion.

You have access to file tools (Read, Grep, Glob). You MAY use them to read files
referenced in the diff for additional context: callers of modified functions,
related tests, interface contracts, sibling modules. Do NOT explore unrelated
parts of the codebase — stay within the scope of the changed files and their
direct dependencies.
```

If the agent returns empty or clearly non-substantive results (e.g., "No issues found" with no list), do NOT compute a score. Report: "The adversarial agent returned no findings. This may indicate context leakage (the agent is being too agreeable). Re-run `/adw-changes` in a fresh session for a genuine challenge." Then stop.

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
## Adversarial Challenge

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
Changes validated ✓ (confidence: {SCORE}%)

The adversarial agent found no blocking issues. These changes are solid enough to merge.
```

Stop. Do not ask anything further.

**If `SCORE < CONFIDENCE_THRESHOLD`:**

Use AskUserQuestion with:
- Question: "Confidence: {SCORE}%. Fix the issues above and re-challenge?"
- Options:
  - "Re-challenge after fixing (you fix the code, then re-run /adw-changes)" — This skill does not auto-fix code. Fix your changes, then re-invoke.
  - "Stop here" — Accept the current state and stop

If the user selects "Re-challenge after fixing...", output:
```
Fix the issues listed above, then run `/adw-changes` again to re-challenge.
Note: unlike /adw-plan, this skill does not auto-amend your code — you are in control of the fixes.
```

Then stop.

---

## Error handling

- If any git command fails unexpectedly: stop with the error output, do not proceed.
- If the Agent tool fails or returns an error: stop and report the failure. Do not compute a score with partial data.
- Never fabricate findings or scores.
