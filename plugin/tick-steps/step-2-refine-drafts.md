# Step 2 — Refine drafts

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

2. **Refine drafts.** For each `draft` whose `acceptance_criteria` are empty/thin
   (not yet refined): enrich it, add concrete `acceptance_criteria`, and record
   reasoning in `# Notes`. For **`kind: build`** also resolve `target_repo` (confirm
   it exists under `<reposRoot>/`) and suggest an `assignee` (see `agents/index.md`).
   For **`kind: research`** instead turn the project's `deliverables` into concrete,
   reviewable `acceptance_criteria` — no `target_repo`, no code `assignee`. **Before you
   write any `open_questions` entry**, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/service-doc.sh <task-doc>` and
   `${CLAUDE_PLUGIN_ROOT}/scripts/kb-select.sh <task-doc>` on the draft and read what they name: a
   question the matched Service doc or a listed Finding already answers is folded into the task, never asked. If it still has
   blocking ambiguities, fill `open_questions`, **numbering every entry (`Q1:`,
   `Q2:`, …)**, and for each new `Q<n>` write its `### Q<n>` block under the body's
   `## Question details` (`SCHEMA.md` → "Question details"): choose the recommendation,
   list it first under `Options:`, and write `Depth 1`, `Depth 2` and `Depth 3` once,
   now — nothing calls a model at answer time; otherwise leave it a clean `draft`.
   **No login, no browser-reproduction criterion.** For an app with no known login, refine
   does not draft one: it writes it as a `✗ — needs a login` row, or leaves it out.

   **A measured criterion names its command and today's value.** A criterion whose purpose
   is to move a measured number — faster, more, smaller, cheaper — also names a guard
   metric — the number that must not get worse — as a second criterion with its own command
   and today's value. Default candidates: tail latency, loss or error rate, memory under
   load, cost. A criterion that merely reports a count (`N harnesses green`, `0 validator
   errors`) is not one. When the guard metric cannot be measured yet, write the criterion
   as `a measurement exists for <X>` with one `# Notes` line saying so, instead of a
   placeholder value. A docs or behaviour criterion needs no guard metric, and a guard
   metric is not `/audit`'s counter-metric.

   **Promotion follows the owning project's `autonomy`** (see Authority boundaries):
   leave it `draft` for the human unless that project delegates promotion and
   `AUTONOMY.md` defines the mode.


   **Bake the answer in FIRST, then run the script for the move.** The human answers by
   appending ` --- <answer>` to an `open_questions` entry on the same line (answering
   in-session works too). Bake each answer into the task itself — `# Context`, a tightened
   `acceptance_criteria`, or `# Notes`. **That half is yours, and the script neither writes
   it nor checks it.** Refine never writes or changes `original_request:` — it is written
   once at creation and is the one place the human's own wording survives the rewrite of
   `# Context` (`SCHEMA.md`). Then do the mechanical move with

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/fold-answers.sh <task-doc>
   ```

   It moves **every** ` --- `-answered entry into `answered_questions`, stamped
   `<ISO 8601> by <login> · <entry verbatim>`, and resolves the login itself
   (`decision-stamp.sh --author`, `--self` where the answer arrived in this session) — so
   the stamp's shape is never yours to compose. **It exits non-zero rather than write a
   state where one entry appears in both lists** (exit 4), which is the failure that
   silently blocks a draft forever; exit 3 is a list it could not round-trip. Either way it
   changes nothing and the tick reports the line it printed. Exit 0 having moved nothing
   means nothing was answered. A **moot** question is answered the same way, with the
   reason as its answer. `open_questions` still holds only questions awaiting an answer, so
   a `draft` becomes clean once **that** list empties.

   **Never hand-edit either list.** They are quoted YAML lists carrying backticks,
   commas and ` --- `, which is the exact shape a hand-rolled parse was already measured
   mis-reading (2026-09-12). **No customer PII in `answered_questions`** — it persists for
   the life of the repo, and that is the one clause the script cannot check for you.

   **Record what you decided on the owner's behalf.** For every technology, topology,
   data-model, consistency or caching, security-model or external-dependency choice a
   refined draft relies on that `original_request` did not state, append one `D<n>` to the
   project's `decisions:` (`SCHEMA.md`), numbered after the highest in `decisions:` and
   `acknowledged_decisions:` — the tick lock makes you its only writer:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/fold-answers.sh --keys decisions acknowledged_decisions \
     --add <project.md> "D<n>: <decision> — alternatives: …; why: …; reversible: …"
   ```

   **Naming a file or a function is not one.** Each renders one `👀 review` row; none
   withholds the `approve` row.

   **The decision fold is this step's whatever the project's task statuses** —
   `tick-delta.sh digest` names step 2 for any ` --- `-answered `D<n>`, even with every task
   promoted. ` --- ok` or ` --- ack` acknowledges. Any other answer is an **overturn**: fold
   it into each affected task first, the same way as an answer, and `--add` the new choice
   as a fresh `D<n>`. **A `done` or `in-review` task already built the old choice**: the
   change it now needs is a new `draft` task, never a rewrite of that one — and the new
   draft keeps the project from closing until it lands. Then
   `${CLAUDE_PLUGIN_ROOT}/scripts/fold-answers.sh --keys decisions acknowledged_decisions <project.md>`
   moves every answered entry, acknowledged or overturned, to `acknowledged_decisions:` with
   its answer verbatim, so `decisions:` holds only unanswered entries, nothing re-folds and
   nothing is deleted.

   **Propose a split when the expected diff will exceed `maxPrFiles`.** Read it with
   `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh` (**absent, 100**), beside `maxPrLoc`
   (**absent, 500**).
   Where a draft's own scope already says it will be past either — a rename sweep, a
   codemod, a generated-file refresh, "every file under `x/`" — say so in `# Notes` and
   propose the split as concrete sibling tasks, then leave the draft where it is. **You
   propose; the human decides**, exactly as with every other refinement, and a task the
   human leaves whole is dispatched whole: this is the same suggest-never-block heuristic
   role agents apply to a PR, moved one step earlier because before dispatch is the only
   point at which the split is cheap. **`maxPrFiles` is this instance's reviewability
   threshold** — propose the split before a task exceeds it, and let the human decide
   whether to keep the work together.

   **Design diagram — you write `projects/<slug>/design.md` yourself, once per
   `kind: build` project, after its last draft is refined.** The file's presence is the
   once-only receipt: do not redraw a project that has one, except under the redraw rule
   below. Never on a `kind: research` project. Its shape is `SCHEMA.md` → `type: Design`:
   frontmatter `type: Design`, `timestamp:` and a `tasks:` list of
   `"<component or edge> → task-NNN"` entries, then one fenced `mermaid` block
   (`flowchart` or `graph`) of the components the project adds or touches — frontends,
   APIs, services, data stores, caches, queues, functions, infra — with integrations as
   edges and trust boundaries as `subgraph`s, then one paragraph reading it: what is new,
   what changes, what is reused. **No internal hostnames, no secrets and no customer PII
   in design.md** — the board links it, so name a component by its role, never by its
   address. The approach critique reads design.md when it runs and may challenge it in
   `advisor_notes`.
   **Redraw rule:** when a task of the project is refined whose id design.md's `tasks:`
   list lacks, redraw it — diagram, paragraph and mapping — in the same tick.
   `tick-delta.sh check` reports that state as a `DELTA` naming the project.

   **Approach critique — MANDATORY on its trigger, advisory in what it may decide.**
   For a genuinely complex **`kind: build`** task — spans multiple files/services, or
   its `acceptance_criteria` had to be heavily inferred — you **must** dispatch the
   `loopd:plan-architect` agent on the task's `# Context` + `acceptance_criteria`,
   **before the human is asked to promote**. It ships in the `loopd` plugin beside you
   and resolves only under that namespace — a bare `plan-architect` does NOT resolve;
   skip silently if absent (an older plugin that does not ship it): mandatory on its
   trigger is not mandatory to exist, and a missing critic never parks a task. On that trigger it runs: not a judgement call, not a budget call.
   (The cost objection is answered in `docs/pm-design.md#step-2`.)
   **The trigger itself is unchanged** — what stopped being discretionary is WHEN the
   critique runs, never WHAT it may decide. **Not** on `kind: research` tasks.

   Record its findings in `advisor_notes` — **only there: never `open_questions`,
   never `# Notes`** — which `SCHEMA.md` defines as deliberately not a gate: it
   does not block promotion, puts no row in `AWAITING.md`, and no validator reads it.
   One entry per concern, `<ISO 8601> · <the concern, as a question>`; you triage the
   list on a later tick. **The triage — your decision, not the critique's findings — writes
   exactly one `* <ISO 8601> triage: …` line under `# Notes`**, and that line is what
   `tick-delta.sh check` reads: a `draft` whose newest concern is dated after it, or that
   has none, is a `DELTA`, so a critique left for "next tick" gets one. Not a gate, a
   receipt. The critique sets no status, gates no `draft → ready`, and
   leaves the human's promotion gate exactly where it was — an aid, not a new authority.

   **Once per task, and a tick can tell that it already ran.** Refinement is itself
   once-only, but do not lean on that alone: a mandatory dispatch with no marker turns
   every tick into a fresh apex-tier session on the same draft. So the critique always
   leaves a trace, and the trace is what you read BEFORE dispatching: concerns raised ⇒
   one `advisor_notes` entry each; none raised ⇒ one `advisor_notes` line,
   `<ISO 8601> · advisor: approach critique — no concerns`. **Either marker means the
   critique has run: do not dispatch it again.** Neither is a gate — they are a receipt.
   **The no-concerns receipt goes in `advisor_notes`, not `answered_questions`**, which
   only `fold-answers.sh` writes and only from an answered `open_questions` entry — a
   critique that raised nothing has no such entry, so the receipt had nowhere it was
   allowed to be written.
   **Every critique this tick owes is launched in ONE message, concurrently, in the
   background** (`Agent` with `run_in_background: true`), never one at a time and never
   waited on before the walk moves on: take the answers into `advisor_notes` when they
   return, before step 8. Each running critique counts as one agent against
   `maxAgentsInFlight` (absent ⇒ 4) while it runs; a critique that finds no free slot waits
   for the next tick, which its missing receipt already arranges.
   Its model comes from `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh plan-architect` — `roleTiers`
   (`apex`) through `models` — never a hard-coded alias; and `plan-architect` stays out
   of `roles`. Its `effort:` is what `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-effort.sh plan-architect`
   prints; nothing printed ⇒ pass none. **The resolvers take the bare `roleTiers` key,
   `plan-architect`; the dispatch takes the namespaced agent, `loopd:plan-architect`** —
   the key names a row in the config, the namespace names a file in the plugin.


<!-- end of step 2 -->
