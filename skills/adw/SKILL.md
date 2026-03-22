---
name: adw
description: Adversarial Dev Workflow — 4-phase development process with adversarial quality gates. Combines adversarial prompting (breaks compliance bias) with context isolation (breaks anchoring bias) for genuinely effective code critique. Use /adw for guided mode or /adw [phase] for direct access.
---

# Adversarial Dev Workflow (ADW)

You are orchestrating a structured development workflow with adversarial quality gates.

## Core principles

1. **Adversarial prompting**: Instead of validating, you attack. Every critique/review phase must actively seek reasons to reject.
2. **Context isolation**: Sub-agents for critique and review read artifacts from `~/.adw/` files ONLY. They must NOT receive reasoning or justifications from the conversation. The less context they have about original decisions, the more effective their critique. Provide ONLY: the artifact content + the adversarial instruction + the specific analysis focus. Note: Claude Code sub-agents are designed to start with fresh context, but some leakage may occur. If sub-agents show signs of anchoring, recommend starting a new session for critique/review.
3. **Persistence on disk**: All state lives in `~/.adw/{project-name}/`. Never rely on conversation context for workflow state.

## Error handling rules

1. **After every Write tool call** for state files (state.json, plan.md, critique.md, review.md), verify success. If the Write tool reports an error, stop with: "Failed to save workflow state to ~/.adw/{project-name}/. Check disk space and permissions. Your {phase} results were displayed above but NOT persisted."

2. **After launching sub-agents**, verify each agent returned non-empty, substantive results. If any agent returns empty or error output:
   - Do NOT write a verdict based on incomplete results
   - Report: "Sub-agent {N} ({role}) returned no results. Re-run `/adw {phase}` to retry."
   - If at least one agent succeeded, inform which failed and proceed with partial results ONLY after user confirmation via AskUserQuestion

3. **State directory creation**: Before writing any file to `~/.adw/{project-name}/`, ensure the directory exists using Bash `mkdir -p`. If it fails, stop with an error.

## Routing

Parse `$ARGUMENTS` to determine the action:

| Arguments | Action |
|-----------|--------|
| *(empty)* | Guided mode — detect state and propose next phase |
| `plan <description>` | Phase 1: Planning |
| `critique` | Phase 2: Adversarial critique |
| `impl` | Phase 3: Implementation |
| `review` | Phase 4: Adversarial review |
| `status` | Display state without action |
| `clean` | Delete workflow state |

The `{project-name}` is the basename of the current working directory.
The state directory is `~/.adw/{project-name}/`.

## Guards (check BEFORE every phase)

Before executing any phase, run these checks in order:

1. **Project name**: Compute `{project-name}` as `basename "$PWD"`. If the result is empty, ".", or "..", stop with: "Cannot determine project name from current directory. Navigate to your project directory and try again."
2. **Git required**: If not in a git repository, stop with: "This workflow requires a git repository. Run `git init` first."
3. **Git has commits**: Run `git rev-parse HEAD`. If it fails, stop with: "This repository has no commits. Create an initial commit first."
4. **State integrity**: If `~/.adw/{project-name}/state.json` exists, read it. If it cannot be parsed as valid JSON, is missing required fields (`current_phase`, `scope`, `task_description`), or `current_phase` is not one of `plan`, `critique`, `impl`, `review`, stop with: "Workflow state is corrupted. Run `/adw status` to inspect, or `/adw clean` to reset." Missing optional fields (`impl_start_ref`, `checklist_progress`, `review_iterations`) should be treated as their zero-value (`null`, `[]`, `0`).
5. **Phase-specific guards**:

| Phase | Guard | Error message |
|-------|-------|---------------|
| `plan` | If state dir exists: read critique.md verdict. AskUserQuestion with options: "Archive and restart" (always), "Amend plan" (ONLY if critique.md exists AND contains `## Verdict: REVISE`), "Cancel" (always). If Cancel → stop, "Workflow unchanged." If Amend selected but no REVISE verdict → "Cannot amend: no REVISE verdict found." | — |
| `critique` | `plan.md` must exist, be non-empty, and contain `## Implementation Checklist`. `current_phase` must NOT be `impl` or `review`. If `critique.md` exists and contains `## Verdict: REVISE`, stop — plan must be amended first | "No plan found. Run `/adw plan <description>` first." / "Cannot run critique during {current_phase} phase." / "Plan has a pending REVISE verdict. Run `/adw plan` to amend first, or `/adw clean` to reset." |
| `impl` | `critique.md` must exist and contain `## Verdict: APPROVE`. `current_phase` must NOT be `review` | "Plan not approved. Run `/adw critique` first." / "Review is in progress. Fix blocking issues and run `/adw review` again, or `/adw clean` to start over." |
| `review` | `impl_start_ref` must be non-null. Run `git diff {impl_start_ref}..HEAD`. If git diff fails (ref not found): "The implementation start reference ({ref}) is no longer valid — git history may have been rewritten. Set impl_start_ref manually in state.json, or `/adw clean` to start over." If diff is empty, check `git diff --cached`: if staged changes exist → "Changes are staged but not committed. Commit first, then re-run `/adw review`." Otherwise → "No code changes since implementation started." | See inline |

---

## State management

### state.json structure
```json
{
  "current_phase": "plan",
  "scope": "standard",
  "task_description": "Implement user authentication with OAuth2",
  "started_at": "2026-03-22T10:00:00Z",
  "impl_start_ref": null,
  "checklist_progress": [],
  "review_iterations": 0
}
```

### Rules
- **plan.md is IMMUTABLE** — never edit it directly. The only way to change it is via the formal amend flow (archive + rewrite), triggered by a REVISE verdict.
- Track implementation progress in `state.json.checklist_progress`, not in plan.md.

### Archiving
When archiving: rename `~/.adw/{project-name}/` to `~/.adw/{project-name}.bak-{YYYYMMDD-HHmmss}/` using Bash `mv`. If `mv` fails, stop with: "Could not archive existing workflow state. Check permissions on ~/.adw/."

---

## Phase 1: Plan (`/adw plan <description>`)

**Mode: READ-ONLY** — Do not create or modify any project files.

### Process

1. Create `~/.adw/{project-name}/` directory with `mkdir -p`.
2. Launch Explore sub-agents to analyze the codebase. Number depends on estimated scope:
   - 1 agent: patterns, architecture, reusable code
   - 2 agents (standard+): add tests, conventions, impacted dependencies
   - 3 agents (full): add integrations, known edge cases, relevant git history

   Use the Agent tool with `subagent_type: "Explore"`. Send ALL calls in a SINGLE message for parallel execution.

3. Evaluate scope heuristic based on agent findings:
   - **light**: localized change, 1-3 files estimated, no public API change
   - **standard**: multiple components, 4-15 files estimated, cross-dependencies
   - **full**: architecture impact, 15+ files estimated, transversal change or critical security

4. Write the plan to `~/.adw/{project-name}/plan.md` with these mandatory sections:

```markdown
# Plan: {task description}

## Objective
{1-2 sentences}

## Scope
{light|standard|full} — {rationale}

## Architecture
{components, data flow, integration points}

## Implementation Checklist
- [ ] 1. {atomic task}
- [ ] 2. {atomic task}
...

## Edge Cases
- [CRITICAL] {description}
- [HIGH] {description}
...

## Risk Zones
- {risk} → Mitigation: {mitigation}
...

## Invariants
- {precondition/postcondition that must always hold}
...

## Test Strategy
- Unit: {what to test}
- Integration: {what to test}
- E2E: {what to test}
- Priority: {what to test first}

## Open Questions
- {unresolved point}
...
```

5. Write `state.json` with current_phase: "plan", scope, task_description.
6. Output the plan, then: "Next → run `/adw critique` to stress-test this plan."

### Output length targets
- light: ~30 lines | standard: ~80 lines | full: ~150 lines

### Amend mode
If `critique.md` exists with verdict REVISE when `/adw plan` is launched:
1. Read `plan.md` and `critique.md` content into memory
2. Archive previous state directory (using the archiving procedure above)
3. Create fresh `~/.adw/{project-name}/` directory with `mkdir -p`
4. Launch a sub-agent with the read content + codebase state (via Explore). Instruction: "Address each critical flaw and warning from the critique. Preserve decisions not challenged. Mark every change with [AMENDED]."
5. Write amended plan to `plan.md`, reset `checklist_progress` to `[]`, write `state.json`
6. Output: "Plan amended. Changes: [list of [AMENDED] items]"

---

## Phase 2: Critique (`/adw critique`)

**Mode: READ-ONLY** — Do not create or modify any project files.

### Process

1. Read `~/.adw/{project-name}/plan.md` (source of truth — NOT conversation context).
2. Read scope from `state.json`.
3. Launch adversarial sub-agents. **Context isolation rules apply** (see Core principles).

   Use the Agent tool with `subagent_type: "general-purpose"`. Send ALL calls in a SINGLE message.

   **Light (1 agent):**
   - Combined quick critique: assumptions, major omissions, obvious edge cases

   **Standard (2 agents):**
   - Agent 1 — Assumption & Omission Hunter: "Here is a software plan. Find every unvalidated assumption, missing scenario, and overlooked failure mode. Do not justify or defend any decisions — only attack."
   - Agent 2 — Edge Case & Flaw Finder: "Here is a software plan. Find every edge case not covered, every logical inconsistency, and evaluate whether this is over-engineered or under-engineered. Only attack."

   **Full (3 agents):** All Standard agents + Agent 3 — Feasibility Auditor: "Here is a software plan. Evaluate whether the scope is proportionate to the problem, whether the approach is realistically feasible, and identify any accidental complexity. Only attack."

4. Consolidate results and write to `~/.adw/{project-name}/critique.md`:

```markdown
# Critique

## Verdict: {APPROVE|REVISE|REJECT}

## Critical Flaws
{must fix before implementing — only if REVISE/REJECT}

## Warnings
{should address}

## Missing Edge Cases
{new cases to add to plan}

## Suggested Revisions
{concrete amendments to the checklist}
```

5. Update `state.json`: current_phase: "critique".
6. Next step based on verdict:
   - APPROVE → "Next → `/adw impl`"
   - REVISE → "Run `/adw plan` to amend (critique findings will be incorporated automatically)."
   - REJECT → "Fundamental issues. Re-think the approach and run `/adw plan <new description>`."

### Output length targets
- light: ~20 lines | standard: ~50 lines | full: ~100 lines

---

## Phase 3: Implementation (`/adw impl`)

**Mode: READ-WRITE** — All tools available.

### Process

1. Read `~/.adw/{project-name}/plan.md` as reference. **Do NOT modify plan.md.**
2. If `impl_start_ref` is null in state.json, store the current commit SHA (`git rev-parse HEAD`). If already set (resuming after scope upgrade re-critique), do NOT overwrite it.
3. Implement item by item from the Implementation Checklist.
4. After completing each item, update `state.json.checklist_progress` (array of completed item numbers).
5. Follow these rules:
   - **Tests**: Write tests AT THE SAME TIME as code, not after.
   - **Commits**: Recommend a logical commit per checklist item (or group trivial related items). Propose the commit with message prefixed `[ADW]`. Do NOT commit automatically — let the user validate.
   - **Intermediate tests**: Run tests after each item or group. If a test fails → report immediately and propose a fix before continuing.
   - **Item dependencies**: Implement in checklist order (assumed ordered by dependency). If an item depends on another not yet done, report it.
6. **Minor deviations** (rename, signature adjustment): OK, document with `// ADW: deviation — [reason]` in code.
7. **Structural deviations** (new component, architecture change): STOP. Inform the user. Propose re-planning with `/adw plan`.
8. **Scope re-evaluation**: If the actual scope diverges (files exceed 2x estimate, files outside initial scope, unplanned public API change) → propose scope upgrade. If upgrading, **propose running `/adw critique` before continuing**.
9. Update `state.json`: current_phase: "impl", checklist_progress.
10. When all items complete: "Next → `/adw review`"

---

## Phase 4: Adversarial Review (`/adw review`)

**Mode: READ-ONLY** — Do not modify any project files.

**Posture: "Review as if your goal is to REJECT this PR."**

### Process

1. Get the reference diff: `git diff {impl_start_ref}..HEAD`. This captures all changes since implementation started, including intermediate commits.

2. Read `~/.adw/{project-name}/plan.md` AND `critique.md` (to verify critique warnings were addressed).

3. **Step 1 — Bug Inventory**: Launch adversarial sub-agents. **Context isolation rules apply** (see Core principles).

   Use the Agent tool with `subagent_type: "general-purpose"`. Send ALL calls in a SINGLE message.

   **Light (1 agent):**
   - Combined review: logic bugs, edge cases, basic security, plan conformity

   **Standard (2 agents):**
   - Agent 1 — Logic & Edge Case Agent: "Here is a code diff. Find every logic bug, off-by-one error, wrong condition, missing return, null/undefined issue, boundary problem, and type coercion issue. Only report problems — do not suggest fixes."
   - Agent 2 — Plan & Critique Conformity Agent: "Here is a code diff, an implementation plan, and a critique. Verify every checklist item is implemented. Check every invariant is respected. Verify every critique warning was addressed. Report any gap."

   **Full (3 agents):** All Standard agents + Agent 3 — Security & Performance Agent: "Here is a code diff. Find every security vulnerability (OWASP Top 10), N+1 query, unnecessary computation, unbounded loop, and blocking operation. Only report problems."

   Format: `[SEVERITY] file:line — Description. Why it matters.`
   Severities: CRITICAL / HIGH / MEDIUM / LOW. **Do NOT propose fixes.**

4. **Step 2 — Verdict**: Evaluate the mandatory checklist (every item MUST be evaluated, none skipped):

   | # | Category | Pass/Fail | Evidence |
   |---|----------|-----------|----------|
   | 1 | Correctness | | |
   | 2 | Edge Cases | | |
   | 3 | Security | | |
   | 4 | Performance | | |
   | 5 | Readability | | |
   | 6 | Plan Conformity | | |
   | 7 | Error Handling | | |
   | 8 | Test Coverage | | |

   For each issue, cite: exact file:line, problematic snippet, reason, severity (BLOCK/WARN/NOTE).

5. Write to `~/.adw/{project-name}/review.md`:

```markdown
# Adversarial Review

## Bug Inventory
{findings from Step 1}

## Checklist
| # | Category | Result |
|---|----------|--------|
...

## Blocking Issues
{BLOCK severity items with file:line citations}

## Warnings
{WARN severity items}

## Verdict: {PASS|FAIL}
```

6. Update `state.json`: current_phase: "review". Increment `review_iterations`.
7. If FAIL → "Fix blocking issues, then run `/adw review` again."
8. If PASS → "All quality gates passed. Code is ready."

### Convergence mechanism
After 3 FAIL iterations (`review_iterations >= 3`):
- Signal: "3 review iterations completed. Consider whether remaining BLOCK issues are genuine blockers or over-engineering of the review."
- Propose to downgrade specific BLOCKs to WARNs if the user agrees.
- Never force a PASS — this is a signal, not an override.

### Output length targets
- light: ~30 lines | standard: ~80 lines | full: ~150 lines

---

## `/adw status`

Read `~/.adw/{project-name}/state.json` and display:
- Current phase
- Scope
- Checklist progress: {completed}/{total} items
- Review iterations count
- If review FAIL: number of remaining BLOCK issues

**No action, no proposal — display only.**

---

## `/adw clean`

1. Read `~/.adw/{project-name}/state.json` and display current state.
2. Use AskUserQuestion: "Delete workflow state for {project-name}? This cannot be undone."
   - Options: "Delete", "Cancel"
3. If Delete → expand `$HOME` and verify the resolved absolute path starts with `$HOME/.adw/` and the project-name component contains no slashes. Then remove using Bash `rm -rf`.
4. If Cancel → do nothing.

---

## Guided mode (`/adw` with no arguments)

Read `~/.adw/{project-name}/state.json` to determine state.

**Interrupted session detection**: If `current_phase` is X but the corresponding artifact file is missing (e.g., phase is "review" but review.md absent), treat as interrupted: "Phase {phase} was interrupted before completing. Re-run `/adw {phase}` to retry."

1. **No state directory** → Use AskUserQuestion: "No active workflow. What would you like to build?" Then start Phase 1 with the user's description.

2. **State exists** → Read current_phase, then propose next logical step:

   | State | Proposal |
   |-------|----------|
   | plan completed, no critique | "Plan ready. Run critique?" |
   | critique APPROVE | "Plan approved. Start implementation?" |
   | critique REVISE | "Plan needs revision. Amend plan with critique findings?" |
   | critique REJECT | "Plan rejected. Start fresh with a new approach?" |
   | impl in progress (checklist incomplete) | "Implementation in progress ({n}/{total} items). Continue?" |
   | impl in progress + scope upgraded | "Scope was upgraded. Run critique before continuing?" |
   | impl complete | "Implementation complete. Run adversarial review?" |
   | review PASS | "All quality gates passed! Workflow complete." |
   | review FAIL | "Review found blocking issues. Fix them and re-run review?" |
   | *(any other value)* | "Workflow is in an unrecognized state (phase: {current_phase}). Run `/adw status` to inspect or `/adw clean` to reset." |

3. Display a brief status summary before the question.
4. Use AskUserQuestion to confirm or let the user choose a different phase.
