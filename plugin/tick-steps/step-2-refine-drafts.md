# Step 2 — Refine drafts

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

2. **Refine drafts.** For each `draft` whose `acceptance_criteria` are empty/thin
   (not yet refined): enrich it, add concrete `acceptance_criteria`, and record
   reasoning in `# Notes`. For **`kind: build`** also resolve `target_repo` (confirm
   it exists under `<reposRoot>/`) and suggest an `assignee` (see `agents/index.md`).
   For **`kind: research`** instead turn the project's `deliverables` into concrete,
   reviewable `acceptance_criteria` — no `target_repo`, no code `assignee`. If it has
   blocking ambiguities, fill `open_questions`, **numbering every entry (`Q1:`,
   `Q2:`, …)**; otherwise leave it a clean `draft`. **Promotion follows the owning
   project's `autonomy`** (see Authority boundaries): leave it `draft` for the human
   unless that project delegates promotion and `AUTONOMY.md` defines the mode.


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

   **Approach critique — MANDATORY on its trigger, advisory in what it may decide.**
   For a genuinely complex **`kind: build`** task — spans multiple files/services, or
   its `acceptance_criteria` had to be heavily inferred — you **must** dispatch the
   `plan-architect` agent (installed globally in `~/.claude/agents/`; skip silently if
   absent) on the task's `# Context` + `acceptance_criteria`, **before the human is
   asked to promote**. On that trigger it runs: not a judgement call, not a budget call.
   (The cost objection is answered in `docs/pm-design.md#step-2`.)
   **The trigger itself is unchanged** — what stopped being discretionary is WHEN the
   critique runs, never WHAT it may decide. **Not** on `kind: research` tasks.

   Record its findings in `advisor_notes` — **only there: never `open_questions`,
   never `# Notes`** — which `SCHEMA.md` defines as deliberately not a gate: it
   does not block promotion, puts no row in `AWAITING.md`, and no validator reads it.
   One entry per concern, `<ISO 8601> · <the concern, as a question>`; you triage the
   list on a later tick. The critique sets no status, gates no `draft → ready`, and
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
   of `roles`.


<!-- end of step 2 -->
