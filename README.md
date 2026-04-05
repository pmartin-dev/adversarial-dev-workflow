# Adversarial Dev Workflow

Two [Claude Code](https://claude.com/claude-code) skills that challenge your plans and code changes adversarially — using context-isolated agents that have no incentive to be agreeable.

## Why adversarial?

Two mechanisms work together:

1. **Adversarial prompting** — Instead of "is this good?", the agent is asked to "find every reason to reject it." This breaks the LLM's natural compliance bias.
2. **Context isolation** — The challenging agent receives only the artifact (plan or diff), not the reasoning behind it. No justifications, no conversation history. This breaks anchoring bias and enables genuine critique.

Neither works alone: an adversary needs both the motivation to criticize AND a genuinely fresh perspective.

## Skills

### `/adw-plan` — Challenge a plan

Takes a plan (file or text), launches an isolated adversarial agent, and iterates until the plan is solid.

**Flow:**

```
/adw-plan path/to/plan.md
  → Adversarial agent attacks the plan
  → Confidence score computed (0–100%)
  → Score ≥ 80%? → "Plan validated ✓"
  → Score < 80%? → Ask: iterate?
       → Yes → Plan is amended, summary of changes shown → re-challenge
       → No  → Stop
```

**Confidence score:** `max(0, 100 − (CRITICAL×25 + HIGH×10 + MEDIUM×3 + LOW×1))`

**Example:**
```
/adw-plan my-feature-plan.md
/adw-plan The plan is to add OAuth2 login by delegating to an external provider...
```

---

### `/adw-changes` — Challenge code changes

Gets the git diff, launches an isolated adversarial agent, and scores confidence on the changes.

**Flow:**

```
/adw-changes              → git diff HEAD (staged + unstaged)
/adw-changes --staged     → git diff --cached
/adw-changes --unstaged   → git diff
/adw-changes --since <ref> → git diff <ref>..HEAD

  → Adversarial agent attacks the diff
  → Confidence score computed (0–100%)
  → Score ≥ 80%? → "Changes validated ✓"
  → Score < 80%? → Ask: fix and re-challenge?
       → Fix code → re-invoke /adw-changes
```

**Example:**
```
/adw-changes
/adw-changes --staged
/adw-changes --since main
```

---

## What the isolated agent does NOT see

- The conversation history
- The user's explanations or justifications
- The reasoning behind the plan or code
- Previous iterations

It receives **only**: the artifact (plan text or diff) + the adversarial instruction.

## Quick Start

```bash
# Clone the repo
git clone <repo-url> adversarial-dev-workflow
cd adversarial-dev-workflow

# Install the skills
./install.sh

# Use in any Claude Code session
/adw-plan path/to/my-plan.md
/adw-changes
```

## Uninstall

```bash
cd adversarial-dev-workflow
./uninstall.sh
```

## Requirements

- [Claude Code](https://claude.com/claude-code)
- A git repository (required for `/adw-changes`)
