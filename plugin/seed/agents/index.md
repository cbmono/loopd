# Agent Roster & Routing

The roles the Project Manager can assign tasks to. Executable definitions ship in the
**`loopd` plugin**, installed once per machine (`/plugin install
loopd@loopd`) — the bundle no longer carries a copy. This is the routing
reference.

**Dispatch by the NAMESPACED name, `loopd:<role>`.** A bare agent name does not
resolve (measured 2026-09-02), and it fails with *no such agent* rather than with
anything that names the omission. **A task's `assignee:` field stays BARE** — it is a
role name, not a dispatch string, and the PM adds the namespace when it spawns.

> **Seed file — copied once, then yours.** Copied into this bundle from the `loopd`
> plugin and owned by it since; `/loopd:welcome fix` 3-way merges a later template
> change onto your edits.

## Roles

**Task assignees** — the PM dispatches human-approved `ready` build tasks to these:
* `loopd:software-engineer` - features and bug fixes in product code
* `loopd:devops-engineer` - CI/CD, GitHub Actions, Helm, ArgoCD, Terraform, Docker images, observability
* `loopd:qa-reviewer` - writing/extending tests, reviewing PRs, and reviewing a new project scaffold when no usable external reviewer is available (the quality gate)

**Orchestration & read-only roles** — **never** task assignees (the PM invokes them, but they aren't dispatched a `ready` task):
* `loopd:project-manager` - orchestrator: refines, assigns, reviews, curates.
* `loopd:cataloguer` - librarian for the knowledge base (service catalog, findings, runbooks); read-only on product repos.
* `loopd:failure-analyst` - read-only diagnostician for a failing build / red CI / failed deploy (incl. from a pasted PR). Reports root cause + ranked next steps; never changes code. Dispatched ad-hoc (usually in the background).
* `loopd:auditor` - read-only audit loop (slow counter-metric): grounds objectives against reality and flags Goodhart drift / stale knowledge / green-but-not-progressing work / weakened anchors. Writes only an audit report; never acts. Run via `/audit`.

**Advisory review agents** — **never** task assignees, never in `roles`; dispatched with the `Agent` tool by the PM and the `qa-reviewer`, and by `/plan` and `/scan`. They ship in the same plugin and take the same namespace (a bare name does not resolve):
* `loopd:plan-architect` - critiques an implementation plan before any code is written (the PM's approach critique, step 2; priced by the `plan-architect` row of `roleTiers`).
* `loopd:code-architect` - staff-level review of a diff: architecture, patterns, trade-offs (the `qa-reviewer`'s escalation, on a trigger).
* `loopd:deep-bug-scan` - deep scan of the directories a PR touches for real bugs (the other half of that escalation).

## Routing guide

| If the task is about… | assignee |
|---|---|
| Application code, APIs, business logic, bug fixes | `software-engineer` |
| Pipelines, workflows, infra, deploys, images, monitoring | `devops-engineer` |
| Tests, verification against acceptance criteria, PR review, scaffold review | `qa-reviewer` |
| Diagnosing a red CI / build / failed deploy **without changing code** (incl. from a pasted PR) | `failure-analyst` (read-only, reports back) |

Notes:
- `failure-analyst` **diagnoses only** — it reports root cause + next steps and never
  opens a PR. When the fix is known, dispatch `loopd:devops-engineer` (CI/infra) or
  `loopd:software-engineer` (product code) to actually make it. It's usually fired in
  the **background** so the main session isn't blocked; not a task assignee.
- A task may benefit from a review pass by `qa-reviewer` after the implementing
  role opens its PR — the PM can chain these.
- No role merges. Merge is always the human's decision (`in-review` → `done`).
