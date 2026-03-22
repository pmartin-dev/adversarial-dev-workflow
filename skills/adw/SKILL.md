---
name: adw
description: Adversarial Dev Workflow — 6-phase development process with adversarial quality gates. Combines adversarial prompting (breaks compliance bias) with context isolation (breaks anchoring bias) for genuinely effective code critique. Use /adw for guided mode or /adw [phase] for direct access.
---

# Adversarial Dev Workflow (ADW)

You are orchestrating a structured development workflow with adversarial quality gates.

## Core principles

1. **Adversarial prompting**: Instead of validating, you attack. Every critique/review phase must actively seek reasons to reject.
2. **Context isolation**: Sub-agents for critique and review read artifacts from `~/.adw/` files ONLY. They must NOT receive reasoning or justifications from the conversation. The less context they have about original decisions, the more effective their critique.
3. **Persistence on disk**: All state lives in `~/.adw/{project-name}/`. Never rely on conversation context for workflow state.

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

Before executing any phase, run these checks:

1. **Git required**: If not in a git repository, stop with: "This workflow requires a git repository. Run `git init` first."
2. **State directory**: Read `~/.adw/{project-name}/state.json` if it exists.
3. **Phase-specific guards**:

| Phase | Guard | Error message |
|-------|-------|---------------|
| `plan` | If `~/.adw/{project-name}/` exists, use AskUserQuestion: "Active workflow detected (Phase: {current_phase}, Scope: {scope}). Archive and start fresh, or amend?" Options: "Archive and restart", "Amend (if critique REVISE)", "Cancel" | — |
| `critique` | `plan.md` must exist | "No plan found. Run `/adw plan <description>` first." |
| `impl` | `critique.md` must exist with verdict APPROVE | "Plan not approved. Run `/adw critique` first." |
| `review` | Run `git diff {impl_start_ref}..HEAD` — must be non-empty. If no impl_start_ref, use `git diff HEAD` | "No code changes since implementation started. Nothing to review." |

## State management

### state.json structure
```json
{
  "current_phase": "plan",
  "scope": "standard",
  "scope_rationale": "Multiple components involved, cross-dependencies detected",
  "task_description": "Implement user authentication with OAuth2",
  "started_at": "2026-03-22T10:00:00Z",
  "impl_start_ref": null,
  "checklist_progress": [],
  "phase_history": []
}
```

### Creating/updating state
- Use the Write tool to create/update `~/.adw/{project-name}/state.json`
- Use the Write tool to create `plan.md`, `critique.md`, `review.md`
- **plan.md is IMMUTABLE** after writing. Never modify it. Track progress in `state.json.checklist_progress`.

### Archiving
When archiving: rename `~/.adw/{project-name}/` to `~/.adw/{project-name}.bak-{YYYYMMDD-HHmmss}/` using Bash `mv`.

---

## Phase 1: Plan (`/adw plan <description>`)

**Mode: READ-ONLY** — Do not create or modify any project files.

### Process

1. Create `~/.adw/{project-name}/` directory if needed.
2. Launch Explore sub-agents to analyze the codebase. Number of agents depends on estimated scope:
   - 1 agent: patterns, architecture, reusable code
   - 2 agents (standard+): add tests, conventions, impacted dependencies
   - 3 agents (full): add integrations, known edge cases, relevant git history

   ```
   Use the Agent tool with subagent_type: "Explore"
   Send ALL agent calls in a SINGLE message for parallel execution.
   ```

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
- [MEDIUM] {description}
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

5. Write `state.json` with current_phase: "plan", scope, scope_rationale, task_description.
6. Output: the plan, then "Next → run `/adw critique` to stress-test this plan."

### Output length targets
- light: ~30 lines
- standard: ~80 lines
- full: ~150 lines

### Amend mode
If `critique.md` exists with verdict REVISE when `/adw plan` is launched:
- Launch a sub-agent that receives:
  - The original plan (`plan.md`)
  - The critique (`critique.md`)
  - Codebase state (via Explore)
  - Instruction: "Address each critical flaw and warning from the critique. Preserve decisions not challenged. Mark every change with [AMENDED]."
- Reset `checklist_progress` to `[]`
- Archive previous plan in backup directory
- Output: "Plan amended. Changes: [list of [AMENDED] items]"

---

## Phase 2: Critique (`/adw critique`)

**Mode: READ-ONLY** — Do not create or modify any project files.

### Process

1. Read `~/.adw/{project-name}/plan.md` (source of truth — NOT conversation context).
2. Read scope from `state.json`.
3. Launch adversarial sub-agents. **CRITICAL: context isolation rules apply.**

   For each sub-agent prompt, provide ONLY:
   - The plan content (read from plan.md)
   - The adversarial instruction
   - The specific analysis focus
   - Do NOT include any reasoning, justifications, or "why" behind decisions

   ```
   Use the Agent tool with subagent_type: "general-purpose"
   Send ALL agent calls in a SINGLE message for parallel execution.
   ```

   **Agents by scope:**

   **Light (1 agent):**
   - Combined quick critique: assumptions, major omissions, obvious edge cases

   **Standard (2 agents):**
   - Agent 1 — Assumption & Omission Hunter: "Here is a software plan. Find every unvalidated assumption, missing scenario, and overlooked failure mode. Do not justify or defend any decisions — only attack."
   - Agent 2 — Edge Case & Flaw Finder: "Here is a software plan. Find every edge case not covered, every logical inconsistency, and evaluate whether this is over-engineered or under-engineered. Only attack."

   **Full (3 agents):**
   - Agent 1 — Assumption & Omission Hunter (same as standard)
   - Agent 2 — Edge Case & Flaw Finder (same as standard)
   - Agent 3 — Feasibility Auditor: "Here is a software plan. Evaluate whether the scope is proportionate to the problem, whether the approach is realistically feasible, and identify any accidental complexity. Only attack."

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

5. Update `state.json`: current_phase: "critique", add to phase_history with verdict.
6. Next step based on verdict:
   - APPROVE → "Next → `/adw impl`"
   - REVISE → "Run `/adw plan` to amend (critique findings will be incorporated automatically)."
   - REJECT → "Fundamental issues found. Re-think the approach and run `/adw plan <new description>`."

### Output length targets
- light: ~20 lines
- standard: ~50 lines
- full: ~100 lines

---

## Phase 3: Implementation (`/adw impl`)

**Mode: READ-WRITE** — All tools available.

### Process

1. Read `~/.adw/{project-name}/plan.md` as reference. **Do NOT modify plan.md.**
2. Store the current commit SHA in `state.json.impl_start_ref`:
   ```bash
   git rev-parse HEAD
   ```
3. Implement item by item from the Implementation Checklist.
4. After completing each item, update `state.json.checklist_progress` (array of completed item numbers).
5. Follow these rules:
   - **Tests**: Write tests AT THE SAME TIME as code, not after.
   - **Commits**: Recommend a logical commit per checklist item (or group trivial related items). Propose the commit with message prefixed `[ADW]`. Do NOT commit automatically — let the user validate.
   - **Intermediate tests**: Run tests after each item or group. If a test fails → report immediately and propose a fix before continuing.
   - **Item dependencies**: Implement in checklist order (assumed ordered by dependency). If an item depends on another not yet done, report it.
6. **Minor deviations** (rename, signature adjustment): OK, document with `// ADW: deviation — [reason]` in code.
7. **Structural deviations** (new component, architecture change): STOP. Inform the user. Propose re-planning with `/adw plan`.
8. **Scope re-evaluation**: If the actual scope diverges from estimation:
   - Files modified exceed 2x the estimate
   - Files outside the initial scope are touched
   - An unplanned public API change appears
   → Propose scope upgrade. If upgrading light→standard or standard→full, **propose running `/adw critique` before continuing** (new scope may reveal unidentified risks).
9. Update `state.json`: current_phase: "impl", checklist_progress.
10. When all items complete: "Next → `/adw review`"

---

## Phase 4: Adversarial Review (`/adw review`)

**Mode: READ-ONLY** — Do not modify any project files.

**Posture: "Review as if your goal is to REJECT this PR."**

### Process

1. Get the reference diff:
   ```bash
   git diff {impl_start_ref}..HEAD
   ```
   This captures all changes since implementation started, including intermediate commits.

2. Read `~/.adw/{project-name}/plan.md` AND `~/.adw/{project-name}/critique.md` (to verify critique warnings were addressed).

3. **Step 1 — Bug Inventory**: Launch adversarial sub-agents. **Context isolation rules apply.**

   For each agent, provide ONLY: the diff content + plan.md content + critique.md content + the adversarial instruction. No reasoning or justifications.

   ```
   Use the Agent tool with subagent_type: "general-purpose"
   Send ALL agent calls in a SINGLE message for parallel execution.
   ```

   **Agents by scope:**

   **Light (1 agent):**
   - Combined review: logic bugs, edge cases, basic security, plan conformity

   **Standard (2 agents):**
   - Agent 1 — Logic & Edge Case Agent: "Here is a code diff. Find every logic bug, off-by-one error, wrong condition, missing return, null/undefined issue, boundary problem, and type coercion issue. Only report problems — do not suggest fixes."
   - Agent 2 — Plan & Critique Conformity Agent: "Here is a code diff, an implementation plan, and a critique. Verify every checklist item is implemented. Check every invariant is respected. Verify every critique warning was addressed. Report any gap."

   **Full (3 agents):**
   - Agent 1 — Logic & Edge Case Agent (same as standard)
   - Agent 2 — Security & Performance Agent: "Here is a code diff. Find every security vulnerability (OWASP Top 10), N+1 query, unnecessary computation, unbounded loop, and blocking operation. Only report problems."
   - Agent 3 — Plan & Critique Conformity Agent (same as standard)

   Format for each finding: `[SEVERITY] file:line — Description. Why it matters.`
   Severities: CRITICAL / HIGH / MEDIUM / LOW
   **Do NOT propose fixes.**

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

6. Update `state.json`: current_phase: "review", add to phase_history with verdict.
7. If FAIL → "Fix blocking issues, then run `/adw review` again."
8. If PASS → "All quality gates passed. Code is ready."

### Convergence mechanism
Track review iteration count in `phase_history`. After 3 FAIL iterations:
- Signal: "3 review iterations completed. Consider whether remaining BLOCK issues are genuine blockers or over-engineering of the review."
- Propose to downgrade specific BLOCKs to WARNs if the user agrees.
- Never force a PASS — this is a signal, not an override.

### Output length targets
- light: ~30 lines
- standard: ~80 lines
- full: ~150 lines

---

## `/adw status`

Read `~/.adw/{project-name}/state.json` and display:
- Current phase
- Scope + rationale
- Phase history with verdicts
- Checklist progress: {completed}/{total} items
- If review FAIL: number of remaining BLOCK issues

**No action, no proposal — display only.**

---

## `/adw clean`

1. Read `~/.adw/{project-name}/state.json` and display current state.
2. Use AskUserQuestion: "Delete workflow state for {project-name}? This cannot be undone."
   - Options: "Delete", "Cancel"
3. If Delete → remove `~/.adw/{project-name}/` directory using Bash `rm -rf`.
4. If Cancel → do nothing.

---

## Guided mode (`/adw` with no arguments)

Read `~/.adw/{project-name}/state.json` to determine state:

1. **No state directory** → Use AskUserQuestion: "No active workflow. What would you like to build?" Then start Phase 1 with the user's description.

2. **State exists** → Read current_phase and phase_history, then propose next logical step:

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

3. Display a brief status summary before the question.
4. Use AskUserQuestion to confirm or let the user choose a different phase.

---

## Context isolation caveat

Claude Code sub-agents (Agent tool) are designed to start with fresh context, but some context leakage may occur depending on implementation. The effectiveness of isolation should be verified empirically. If sub-agents show signs of anchoring on the parent conversation, recommend users start a new Claude Code session for critique/review phases.
