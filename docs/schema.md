# Document types (orientation)

**The normative contract is [`plugin/seed/SCHEMA.md`](../plugin/seed/SCHEMA.md), not this page.**

That file is **seed**, not machinery: `/loopd:init` copies it into a bundle once and
the bundle owns it from then on, with `/loopd:welcome fix` 3-way merging a later
template change onto local edits. Every role agent reads it, and
`scripts/validate-bundle.sh` enforces it. Duplicating its field lists here would
create a second copy that drifts, so this page is a **map** — what the types are, where
they live, and which section of `SCHEMA.md` to open. Every field, enum and lifecycle rule
comes from there.

---

## What the bundle holds

An instance is an [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
Knowledge Bundle: plain markdown documents with YAML frontmatter. OKF defines no
task/project/objective/agent constructs — those are producer-defined extensions, and
`SCHEMA.md` is the contract for them.

## The types

| `type` | Lives at | What it is |
|---|---|---|
| `Objective` | `objectives/<slug>.md` | **optional** — a goal that outlives one project, with `success_criteria` that `/audit` grounds progress against |
| `Project` | `projects/<slug>/project.md` | a `build` or `research` effort; carries its own `success_criteria` and the value gate (`need`, `cost_of_not_doing`, `no_owner`), plus `autonomy`, `owner`, `target_repo`, `clis`, `browser`, `retain`, and an optional `timebox` — permission to stop an experiment |
| `Phase` | `projects/<slug>/phases/<n>-<slug>.md` | an ordered stage of a project |
| `Task` | `projects/<slug>/tasks/<id>.md` | the unit a role agent is dispatched on |
| `Agent` | `agents/index.md` | the role roster |
| `Service` | `knowledge/services/<name>.md` | a system in the estate |
| `Finding` | `knowledge/findings/<slug>.md` | one durable conclusion |
| `Team` | `knowledge/teams/<slug>.md` | who owns what |
| `Runbook` | `knowledge/runbooks/<slug>.md` | a procedure |
| `Reference` | `knowledge/references/<slug>.md` | a spec or contract — the **fifth** knowledge kind |

**`objectives/` is an optional layer.** A project is normally self-contained and measured
against its own `success_criteria`; an `Objective` is for a goal that outlives one project.
A plain `/loopd:init <dir>` creates no `objectives/` directory —
`--with-objectives` does, and an existing one is never touched. Why:
[pm-design.md § Why `objectives/` is optional](pm-design.md#objectives-optional).

`knowledge/<kind>/` is a **shape, not a list of names**: a new kind directory is validated
the moment it exists. That is why `references/` was already covered before it was declared
— see [conventions.md invariant 14](conventions.md#14-knowledgereferences-is-the-fifth-knowledge-kind).

## Task lifecycle

```
draft ──│ HUMAN promotes │──► ready ──► in-progress ⇄ in-review ──► done
                                            └─ changes requested ─┘
```

| Status | Meaning | Who sets it |
|---|---|---|
| `draft` | initial state; refined once `acceptance_criteria` are filled, then **awaiting human approval**. Non-empty `open_questions` = blocked on a human answer | Human or PM |
| `ready` | approved for execution — the human, or the loop where `autonomy` delegates it | Human, or the loop |
| `in-progress` | dispatched to a role; agent working (no PR yet, or changes requested) | PM / role agent |
| `in-review` | PR(s) open, awaiting review/merge | role agent |
| `blocked` | external/dependency blocker; returns to its prior status when cleared | anyone |
| `cancelled` | abandoned, superseded, or decided-against (terminal) | Human / PM |
| `done` | **all** of the task's PR(s) merged | PM / Human |

A task may fan out to several PRs (`pr:` is a list) and stays `in-review` until **all** of
them merge.

## Closing a project

`/close-project <slug>` runs once every task is terminal. Its folder step is one tested
command — `scripts/close-project-folder.sh <slug>` reports, `--apply` writes — and what it
does is decided by one optional field, `retain:` (absent = false).

| `project.md` | The folder at closeout |
|---|---|
| **no `retain:`** (default) | `git rm -r projects/<slug>/`. Git history + `knowledge/` are the record — there is **no `archive/`**. Right for `build`, whose real output is merged PRs living in the product repo |
| **`retain: true`** | kept, and *frozen* first: `deliverable_paths:` stamped into `project.md`, working files pruned and reported, `index.md` refreshed and **committed** as the front door. Right for `research`, whose output **is** the folder |

`retain:` governs the **folder only** — a retained project still ends `status: done` with
every task terminal, and is not reopenable. Full rules, including exactly which working
files are pruned: [`SCHEMA.md`](../plugin/seed/SCHEMA.md) → "Project & objective completion".

## What validation checks — and what it deliberately does not

| Checked | Not checked |
|---|---|
| every concept document has `type`, a `status` from its type's closed enum, and a `timestamp` | `index.md`, `log.md`, `sources/`, `deliverables/` — navigation and content, no frontmatter by design |
| every **frontmatter** reference (`objective:`, `project:`, `phase:`, `depends_on:`) resolves | body prose — a body may legitimately cite a closed project as history |
| — | `owner:` — it names a person outside the bundle, so nothing here can resolve it |
| — | `answered_questions:` — free text, neither an enum nor a reference |
| `artifacts:` — **warns**, because a research task may declare a deliverable before writing it | |

Two fields the v2 plan asked for and the data rejected: a required **`id`** (the file path
is already the identifier, so a second one can only drift) and renaming `timestamp` to
**`updated`** (OKF names it `timestamp`). Why the scope is exactly this and no wider:
[conventions.md invariant 8](conventions.md#8-validate-bundlesh-was-scoped-by-measuring-first-and-that-is-the-point).

## Keeping a bundle valid

| Command | What it does |
|---|---|
| `scripts/validate-bundle.sh` | reports schema errors and dangling frontmatter references. Run it after any structural edit, and always before closing a project |
| `scripts/migrate-bundle.sh` | reports the mechanical fixes it *can* make; `--apply` writes them |
| `scripts/migrate-bundle.sh --apply` | normalises a closed set of status values and fills a missing `timestamp` and knowledge `provenance` from git |
| `scripts/migrate-bundle.sh --layout-only [--apply]` | only the directory steps (the 3.0 layout move, the 3.3 rename of the state directory to `.loopd/`); no content repair, and the report says so. A mounted `knowledge/` is skipped by name in every mode |

`migrate-bundle.sh` refuses three things by design — an unrecognised status, a file git
cannot date, and a dangling reference. Each needs a decision, not a rewrite. See
[conventions.md invariant 9](conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default).

## Deeper sections of `SCHEMA.md`

| Section | Covers |
|---|---|
| Validation | what `validate-bundle.sh` enforces, and the schema-defined locations |
| Which document wins | the authority table — per concern, which instruction document is right when two disagree, and that the other one is fixed, never asked about |
| Task lifecycle | the full status table, multi-PR tasks, the `okf-verdict` trailer |
| Independent verification gate | **the normative clearance predicate** — implement from here, nowhere else |
| Ownership on a shared instance | `owner`, `defaultOwner`, and what `task-owner.sh` decides |
| Per-machine config overrides | **the one** authoritative list of overridable config keys |
| Project & objective completion | when a project is closable |
| Browser access | the agent-facing browser rules |
