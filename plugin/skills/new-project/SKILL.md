---
name: new-project
disable-model-invocation: true
description: Scaffold a new project under projects/<slug>/ — schema-valid files, registered in the bundle index/log and linked to its objective, with seed draft tasks. Supports build (code/PRs) and research (in-bundle deliverables) projects.
argument-hint: <one-line project description>  [kind=build|research] [objective=<slug>] [repo=<name|owner/name>] [deliverables="a; b"] [timebox=<N>d|<N>w] [--no-commit]
allowed-tools: Bash(date:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh:*), Bash(git add:*), Bash(git config:*), Bash(git rev-parse:*), Bash(command -v:*), Bash(cr:*), Bash(coderabbit:*), Bash(ls:*), Read, Write, Edit, Glob, Agent
---

Scaffold a new **Project** in this bundle: the `projects/<slug>/` folder and its
files, registered in the bundle index and log and linked to an Objective, with
one or more seed `draft` tasks. Everything lands `draft`/`active` — nothing
becomes dispatchable until the human promotes a task `draft → ready`.

**Two kinds** (see `SCHEMA.md`): `kind=build` (default) ships code to a product
repo via PRs (role agents execute); `kind=research` produces **deliverables inside
this bundle** (docs, marp/pptx decks, assets) under `projects/<slug>/deliverables/`
— no repo, no PRs, human-driven (you work the tasks in-session; the PM tracks but
never dispatches them). Research projects are typically the strategic **entry
point** whose conclusions later graduate into `knowledge/` and spawn objectives +
build projects.

> **Generic plugin file** (ships inside the `loopd` plugin, never copied into a bundle). It reads
> the bundle's own `SCHEMA.md` and `instance.config.json` for shapes and values —
> never hardcode org/repo/path literals here.

## Inputs
`$ARGUMENTS` = a one-line description of the project, plus optional tokens:
- `kind=build|research` — project kind (default `build`).
- `objective=<slug>` — link to `objectives/<slug>.md` instead of inferring one. Optional:
  `objectives/` is an opt-in layer, and a project's own `success_criteria` are the default anchor.
- `repo=<name|owner/name>` — **build only.** `target_repo` (bare name is qualified
  with `org` from `instance.config.json`). Omitted → `<org>/<defaultRepo>` from
  config; if there's no `defaultRepo`, ask. Ignored for research.
- `deliverables="a; b; …"` — **research only.** What the project produces. If
  omitted, infer from the description or ask.
- `autonomy=<mode>` — how much the loop may do without you (default `gated`). The
  available modes, and any shorthand flag for one, are defined in `AUTONOMY.md` at the
  bundle root; **if that file doesn't exist, `gated` is the only mode** — don't offer or
  accept another. A flag naming a mode this bundle doesn't define (any mode when
  `AUTONOMY.md` is absent) is **downgraded to `gated` and reported**, not honoured and not
  treated as an error. Captured now; enforced by later machinery.
- `clis="a; b"` (shorthand `/cli a, b`) — external CLIs/integrations this project's
  agents may use (e.g. `render`, `supabase`). **Build-shaped**: research projects
  dispatch no agents, so it is never *asked* for one — but an explicit flag is still
  honoured (the in-session escape hatch for a research project that queries a datasource).
- `browser=off|claude-for-chrome` (shorthand `/claudeforchrome`) — let agents drive the
  browser via the claude-in-chrome MCP when present (default `off`).
- `owner=<github-username>` — **only for a bundle shared by more than one human**:
  whose project this is. A GitHub username, never an email. Like `clis`, it is
  **never asked for** — an instance with one human has no use for it and the question
  would be noise — but an explicit flag is recorded. Omitted ⇒ the key is left out
  entirely (no placeholder, no empty value), which resolves to this clone's human.
  See `SCHEMA.md` → "Ownership on a shared instance".
- `timebox=<N>d|<N>w` — this project is an experiment, and stopping it when the box runs
  out is the plan (`SCHEMA.md` → "Time-boxed projects"). **Never asked, on either kind**,
  and never suggested: most projects have no time-box, and none should pay a question for
  it. Recorded verbatim from the flag. A value outside the grammar is refused in one line
  and left out. Omitted ⇒ the key is left out entirely, never written empty.
- `--no-commit` — scaffold only; don't commit (default is to commit).

If `$ARGUMENTS` has no description, **ask** for a one-line goal before doing anything.

## Steps

1. **Ground the shapes (don't guess).** Read `SCHEMA.md` (the `Objective`,
   `Project`, `Phase`, `Task` sections + the lifecycle) and **one existing
   project** as a copy-reference: its `project.md`, `index.md`, `log.md`, and a
   `tasks/*.md`. Read `instance.config.json` for `org` and `defaultRepo`.

2. **Derive the slug.** Kebab-case from the description (or an explicit slug if the
   user gave one). Confirm `projects/<slug>/` does **not** already exist — if it
   does, stop and report.

3. **Resolve the goal — the project's own `success_criteria` first.** Propose 2-4
   **measurable** lines for `success_criteria:` (name the command and today's number),
   and get the user's OK. That is the project's anchor and `/audit` grounds against it.
   **`objectives/` is an OPTIONAL layer** (`SCHEMA.md` → type: Objective): if the
   directory is absent, do not create it and do not ask — the criteria are enough. If
   `objective=` was given, use it. Otherwise, where `objectives/*.md` exists, offer the
   best-fitting one and accept "none"; **never mint an objective silently**, and only
   propose a new one for a goal that outlives this project.

   **Then the value gate — three questions, asked HERE and on BOTH kinds.** Ask for
   `need:` (who needs this, and what breaks for them if it never exists),
   `cost_of_not_doing:` (what that need costs if it never ships) and `no_owner:` (who is
   allowed to say no — a decision with no owner is a trap). They are **not**
   `success_criteria` and never merge into them: the criteria answer *how will we know it
   worked*, these answer *should it exist at all* (`SCHEMA.md` → the value gate). Asked in
   this step, **before `kind` is settled in step 4** — they describe no machinery, so the
   build/research asymmetry at the end of this file does not reach them, and a speculative
   research project is where they bite hardest. **Present is required, filled is not**:
   *"nobody needs this yet, it is an experiment"* is a good answer — record it verbatim and
   never press for a stakeholder. An empty value is legal too; an omitted key is not.

4. **Resolve capabilities & kind-specific fields (capabilities first).**

   **a. Capabilities (flags-first, else ask).** Settle `kind`, `autonomy`, `clis`, and
   `browser` **before** the kind-specific fields below — otherwise a project could be
   asked build-only questions on a research project, or vice versa. For any supplied as
   a flag (`kind=`, `autonomy=` or a mode's shorthand, `/cli …` / `clis=`,
   `/claudeforchrome` / `browser=`), use it and **don't** ask — with one exception, the
   `autonomy` bullet below: a flag never grants a mode this bundle doesn't have. For those NOT supplied,
   ask the missing ones in **one batched `AskUserQuestion`** — except that **`kind` is
   settled first**, because it decides whether `clis` is offered at all: no `kind=` flag ⇒
   ask kind on its own, then batch the rest. One extra round-trip, and only when the flag
   was omitted; batching kind alongside a question its own answer suppresses is what puts
   `render` and `supabase` in front of a research project.
   - **kind** — build / research.
   - **autonomy** — resolve `AUTONOMY.md` first, with
     `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-autonomy.sh --bundle <bundle>` (bundle root,
     then an installed companion — exit 1 means absent). **Absent ⇒ don't ask at
     all**: `gated` is the only mode, so record it and move on — and that holds **even
     against an explicit flag**. `autonomy=<anything-else>` with no `AUTONOMY.md` records
     `gated` and says so in one line; it is never recorded verbatim and never errors out.
     Absence means the safe behaviour, not a failure — the same rule the rest of this
     machinery follows — and the announcement is what stops the human assuming they got
     the delegation they typed. Present ⇒ offer `gated` (default) plus the modes it
     defines, described in that file's own terms; a flag naming a mode that file **does**
     define is used as given, without asking.
   - **clis** (multi-select) — **build only; on `kind=research`, don't ask and don't
     probe.** `clis` declares what this project's *agents* may use (`SCHEMA.md`), and a
     research project dispatches none — offering the machine's whole MCP/CLI menu there
     asks the human to authorise tools nothing will ever run. An explicit `clis=` flag is
     still recorded on a research project; the *question* is what's build-only. On a build
     project, **pre-populate from what's actually available**: run `claude mcp list` for
     connected MCP servers and probe `PATH` for likely CLIs; show each with a ✓/✗ on
     whether it looks authenticated, plus "other" for free entry. Declarations — agents
     still verify a CLI works before relying on it.
   - **browser** — off (default) / claude-for-chrome. **Asked on both kinds** — web
     research is the clearest case for it, so don't skip it the way `clis` is skipped.
     Ask it as the opt-IN it is ("grant browser access to this project?"), and **state
     in one line what granting it means before they answer**: agents get **read access to
     every site this human is logged into** in their browser, and browser **writes** ask
     first unless the chosen `autonomy` mode delegates them (below), which is what makes
     granting it defensible. Where the answer is `claude-for-chrome`, record **why** in
     `# Context` beside the key.
   If **browser = claude-for-chrome** and the chosen mode **delegates browser writes**,
   don't block it — that combination is supported and deliberate. State once what it means
   so the choice is informed: agents may **write** in the human's logged-in browser
   (submit forms, change settings) without asking, including from background `/loopd:dispatch`
   dispatches, and the extension's **per-site permissions** are then the effective
   boundary. Record that in `# Context` and continue. Otherwise browser writes ask first
   (see `SCHEMA.md` → "Browser access").
   If the chosen mode **delegates merging** on a build project, **run that mode's
   preflight now** (`AUTONOMY.md`) rather than letting the loop discover mid-run that the
   authority isn't exercisable: check whether the repo has an external PR reviewer, and
   whether it has any required status checks. Report the result in one line and record it
   in `# Context` — if either is missing, say plainly that every PR will still be surfaced
   for the human, and offer to fix it (configure the reviewer / branch protection) or to
   proceed knowing merges stay manual. Also flag at scaffold time that the project will
   otherwise **self-merge**, so the human knows before work starts.

   **b. Kind-specific fields.** Now that `kind` is settled: for `build`, resolve
   `target_repo` per the Inputs rules; for `research`, resolve the `deliverables` list
   (from `deliverables=`, the description, or ask) — no repo. Get an ISO timestamp once:
   `date -u +%Y-%m-%dT%H:%M:%SZ` — reuse it for every file's `timestamp`.

   These capability fields are **captured now, enforced later** (`autonomy` by the PM
   loop, per `AUTONOMY.md`; `browser` by the claude-in-chrome integration): creating a
   project never itself promotes, merges, or drives a browser.

5. **Scaffold `projects/<slug>/`**, matching the schema/example exactly:
   - `project.md` — `type: Project` frontmatter (`title`, `description`,
     `original_request:` — the owner's one-line description from `$ARGUMENTS`
     **verbatim**, with the option tokens stripped, as a quoted single-line YAML string
     (a multi-line ask collapsed to one line, inner double quotes escaped); written here
     **once and never rewritten** by refine or any tick step (`SCHEMA.md`), because
     `title`, `description` and `# Context` are what you *made* of the ask and this is
     the ask itself — `kind`, `success_criteria: [...]` from step 3, the step-3 value gate `need:`,
     `cost_of_not_doing:` and `no_owner:` — **all three, always, on both kinds**, empty
     where the answer was empty and never omitted — `status: active`, `timestamp`; plus
     `objective: /objectives/<slug>.md` only where step 3 resolved one) — plus
     `target_repo` for **build**, or `deliverables: [...]` for **research**; plus the
     capabilities from step 4: `autonomy:` (always; default `gated`), and `clis:` /
     `browser:` / `owner:` only when non-default or explicitly given (omit them
     otherwise); plus `timebox:` only from a valid `timebox=` flag — and a `# Context` body
     that states what the project does and why, ending by linking its `index.md` and
     `log.md`.
   - `index.md` — `# <title> — tasks`, one bullet per seed task with its status.
     **Derived and gitignored** (the PM rewrites it each tick): create it, but it is
     not part of the commit in step 7.
   - `log.md` — `# <title> — log`, a `## <date>` heading and a **Created** bullet.
   - `tasks/` — derive seed tasks from the description. For a **research** project
     split by domain/team, create **one task + one deliverable stub per chunk**
     (`tasks/task-001-<chunk>.md` → `deliverables/<chunk>.md`). Otherwise a single
     `task-001-<slug>.md` capturing the main goal. Each task: `type: Task`, `kind`
     (matching the project), `status: draft`, `assignee:` empty,
     `original_request:` — the same verbatim description the project carries, since
     a seed task is derived from it and nothing else (same quoting; write-once, see
     `SCHEMA.md`) — `acceptance_criteria: []`, `open_questions: []`, `timestamp`,
     body with a `# Context`. **Build** tasks carry `target_repo` (omit if same as project
     default) + `pr:`; **research** tasks carry `artifacts: [ <deliverable path> ]`
     instead. **Never invent `acceptance_criteria`** — leave them for the PM's refine.
     **And no placeholders when they *are* written** (PM refine, or a human): not
     "add appropriate error handling", not "similar to <other task>", not "write
     tests for the above". Each is unfalsifiable, so a reviewer cannot check it and
     the agent that reads it must guess — which is the same failure as inventing
     one, arrived at from the other direction. A criterion has to name the outcome.
   - For **research**, also create the `deliverables/` directory with a stub file per
     task (a title + a one-line "TODO: …" so the path exists and is committable).
   - `sources/` — always create it, with a short `sources/README.md` explaining that
     the user can drop any raw context here (images, transcripts, spreadsheets, PDFs,
     etc.) that serves as background or raw data for the project. The README makes the
     otherwise-empty folder committable.

6. **Register the project** (keep the bundle navigable). The root `index.md` is
   **derived and gitignored** — edit it so the bundle reads correctly now, but it is
   not committed; `log.md` and the objective are the tracked registration:
   - Add a bullet under `## Projects` in the root `index.md`. For build:
     `[<title>](/projects/<slug>/project.md) - target: \`<target_repo>\` · <n> seed task(s)`.
     For research: `[<title>](/projects/<slug>/project.md) - research · <n> deliverable(s)`.
   - **Where the project has an `objective:`**, add it to that objective's "Projects
     serving this objective" list; if you created a new objective in step 3, also add
     it under `## Objectives` in the root `index.md`. A project with no objective skips
     this bullet entirely.
   - Prepend a dated **Project added** bullet to the root `log.md` (newest-first:
     reuse today's `## <date>` heading if present, else add it at the top of the
     dated entries).

7. **Show & commit.** Print the created tree, the `project.md` frontmatter, and the
   seed task titles. On a **build** project, **record the current `HEAD` sha before
   committing** — step 8 needs it as a review base. Then (unless `--no-commit`) stage and
   commit to this repo via
   the per-agent helper, naming **every** path steps 5 and 6 touched — the scaffold
   and its registration belong in one commit, or the tree records a project that
   nothing links to:
   `${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh human "feat: add <slug> project" --stage -- projects/<slug> log.md objectives/<objective>.md`
   (drop `objectives/<objective>.md` where there is no objective, or where step 3 left
   it untouched). The root and
   per-project `index.md` are **not** in that list — they are derived and gitignored,
   so `git add` skips them and naming them would only produce a confusing "nothing
   staged" refusal.
   Remind the user of the next step: the PM refines the drafts, then **you** promote
   `draft → ready`. For **build**, the PM then dispatches to a role agent → PR →
   you merge. For **research**, *you* work each task in-session (Claude + any
   available authoring/brand/slides skills) and write the deliverable; the PM only
   tracks status — `done` when you approve the deliverable.

8. **Second-opinion review of the scaffold — build projects only, in three stages.** A
   fresh reviewer catches what a scaffolding pass cannot see in itself: a `depends_on`
   missing a real prerequisite, a cross-reference left stale by a rename, a design rule
   with a hole in it. Run it **after** step 7 so the scaffold is a reviewable diff.
   **The whole chain is skipped on `kind=research`** and **under `--no-commit`** (no
   committed scaffold to diff against). When it does run, be precise about what blocks what:

   * The project is **already created and committed** by step 7, so nothing here can block
     creation.
   * **Stage 1 errors block the rest of the chain** — they are defects in the scaffold you
     just wrote, so fix them before spending a review session.
   * **Reviewer verdicts (stages 2 and 3) are advisory** — you triage them; they gate nothing.

   The three stages run in order, cheapest first:

   | Stage | What | When it is skipped |
   |---|---|---|
   | **1. `${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh projects/<slug>/project.md projects/<slug>/tasks/*.md`** | Deterministic, and scoped to the files just written — a DIRECTORY argument checks 0 documents and passes vacuously.  Dangling references, unknown enum values, missing required fields, a frontmatter/body mismatch. Free, no tokens, no false positives. | never, once the chain runs at all |
   | **2. External reviewer** — `externalReviewer` from `instance.config.json`, else the CodeRabbit CLI | Judgement on the scaffold's substance. | **none configured** ⇒ stage 3 *is* the route. **Configured but refusing** ⇒ stage 3 is a **spend**, and step e asks first |
   | **3. `qa-reviewer` scaffold mode** | The **declared fallback** where nothing is configured; a **spend the human authorises** where a reviewer is configured and refused. Never a skip, either way. | only when the human has said not to dispatch agents |

   **Stage 1 is not optional and runs first**, because the consistency class is exactly
   what a fresh scaffold gets wrong and a parser answers it for free. If it reports errors,
   fix them before spending a review session — an external reviewer re-deriving a dangling
   path by reading prose costs a full run to reach a conclusion `grep` already had.

   *Why a declared fallback replaced "skip when the CLI is missing":* `SCHEMA.md`'s
   merge-time gate has said all along that the independent reviewer is "an external one
   when the repo configures it, **else the `qa-reviewer` agent**". Step 8 skipping to
   nothing was the inconsistency, and a project scaffolded on a machine without the CLI got
   no second opinion at all.

   *Why research is out:* what a code reviewer is good at — authorization holes, injection,
   the security shape of what the project describes — is what a research scaffold doesn't
   have, and what's left (stale cross-refs, `project.md` contradicting `index.md`) is
   markdown consistency, at the cost of a full CodeRabbit session per project. The one check
   with teeth, PII/secrets in committed text, has nothing to read at scaffold time:
   `sources/` holds only its README. The risk arrives when the human drops raw exports in
   later, which a creation-time review never sees either.

   **a. Gate on applicability, then run stage 1.** First, if `kind` is `research`, stop
   here — nothing below runs. Then, if step 7 ran with `--no-commit`, stop here too.

   Now run **`${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh projects/<slug>/project.md projects/<slug>/tasks/*.md`**
   — the FILES you just created, **never the whole bundle**. It takes file paths, not directories:
   a directory argument checks **0 documents and exits 0**, which would make this gate pass
   vacuously. Name the files. Zero errors is the gate for continuing.
   Any error is a defect in the scaffold you just wrote: fix it, amend or add a commit, and
   re-run until clean. Errors here are never "by design" — the validator only reports
   things the schema forbids.

   **Why scoped:** this gate asks one question — is the scaffold I just wrote well-formed? An
   unscoped run answers that question and also reports every pre-existing warning in the bundle,
   which on a mature instance is a dump measured in tens of thousands of tokens entering a session
   that has no use for it (measured 2026-09-25 on a live bundle: 281 documents, 0 errors,
   **290 warnings — 582 lines, 64 KB**, every one of them a legacy `Finding` style warning
   unrelated to the new project). That is this repo's own stated failure mode: a validator that
   reports problems nobody has is one people learn to ignore, and the next real error arrives
   buried on line 291. The bundle-wide run is the cataloguer's job and the human's, not this
   step's.

   Then resolve the external reviewer, in this order:

   1. **`externalReviewer` in `instance.config.json`**, when set — the command to run, so a
      site that uses something other than CodeRabbit is not forced through the fallback.
      This is what makes "or an equivalent" real rather than decorative. Resolve it with
      `command -v`; if the named command is missing, say so and treat the reviewer as
      unavailable — never silently substitute CodeRabbit for the one that was configured.
   2. **The CodeRabbit CLI**, which ships under two names: try `command -v cr`, then
      `command -v coderabbit`.

   Keep whatever resolves as `<cli>`. Anything short of a working reviewer → **say so in
   one line and go to step e** — do not stop. But **carry WHICH of the two it was**, because
   step e treats them differently and this is the one place the answer is knowable:

   | What you found | Class | Because |
   |---|---|---|
   | nothing resolved — no `externalReviewer`, no `cr`, no `coderabbit` | **none configured** | there is no reviewer to be broken; stage 3 is simply this instance's reviewer |
   | a `<cli>` resolved but is not signed in, `doctor` errors, or the run refuses | **configured but refusing** | a reviewer exists and is unusable — someone has to fix it or authorise a substitute |

   **"No usable reviewer" is NOT one condition, and collapsing it back into one is the
   regression this table exists to stop.** They differ by who decides: the first was
   already decided when the instance was set up, and the second is a fresh decision about
   spending a review session.

   One environment note that would otherwise waste a run: CodeRabbit resolves the base
   branch from `origin/HEAD`, so an instance with **no git remote** fails with *"Unable to
   determine base branch"*. Pass it explicitly instead —
   **`--base "$(git rev-parse --abbrev-ref HEAD)"`** — rather than persisting
   `git config coderabbit.baseBranch`, which the CLI's own error text suggests but which
   writes to the human's repo config for a one-off review. A remote-less repo also falls
   back to the free CLI allowance whatever you pass.

   **b. Dispatch it scoped to the new project — don't wait for it.** A review takes ~1–2
   min, and it was the one place in this flow where the main session sat idle. The bundle
   already has the pattern for exactly this shape — long-running and read-only, with nothing
   else here depending on its result to proceed — and `CLAUDE.md` names it for failure
   diagnosis: dispatch with `run_in_background: true` and report when it lands, instead of
   blocking on it. Run the CLI the same way: start it with `run_in_background: true`,
   capturing stdout for the triage in step c, and continue immediately, rather than waiting
   on the process to exit.
   This backgrounds only the **review** — the scaffolding in steps 1–7 stays exactly as it
   was, synchronous and in the main thread, because that's the interactive pass where the
   slug, the objective, the seed tasks and the phases get decided, and it is also the
   "someone in this conversation has read the project" this gate relies on before the human
   is ever asked to promote it. Only the *fresh second opinion* moves to the background. Use
   the `<cli>` resolved in step a in place of `cr` below:

   ```bash
   cr review --agent --committed --base-commit <sha-from-step-7> \
             --dir <instance-root>/projects/<slug> -c CLAUDE.md SCHEMA.md
   ```

   `--dir` keeps it on the new project rather than the whole commit; `--base-commit` is the
   pre-commit `HEAD`; `-c` hands it the bundle's own rules so it reviews against `SCHEMA.md`
   and the instance `CLAUDE.md` instead of generic style; `--agent` returns structured
   findings. Confirm the flags with `cr review --help` before running — don't assume this
   surface, the CLI moves.

   Tell the user the review is dispatched, then go straight to step 7's reminder — the human
   sees the scaffold and may promote `draft → ready` right away. This review was already
   advisory and gated nothing (this step's own preamble: "they gate nothing"), so promoting
   before it lands is no less safe than promoting after. **The verdict is not lost either
   way**: when the run finishes, triage its captured stdout per steps c, d and f exactly as
   before — step f's `log.md` bullet is where it lands, the same file and shape whether the
   review finished before or after the human promoted. If it lands after, the human still
   reads it there; nothing about a late verdict is silent.

   **c. Triage before applying. On a fresh scaffold most findings are the reviewer not
   knowing the OKF lifecycle.** These are **by design — do not "fix" them**:
   - `acceptance_criteria: []` and `open_questions: []` — the PM fills these during refine;
     step 5 explicitly forbids inventing them.
   - every task sitting at `status: draft` — that's the human's promotion gate.
   - a task carrying an empty `pr:` and no assignee — both are filled at dispatch, not now.
   - the control panel committing straight to `main`.

   **Take these seriously** — each is a real defect worth a follow-up commit:
   - a `depends_on` that omits a genuine prerequisite, or a dependency cycle;
   - stale names, paths, or counts after a rename — typically the one file the restructure
     missed;
   - `project.md`, `index.md`, and the task bodies contradicting each other;
   - a security, privacy, or authorization hole in something the project *describes*
     (identity propagation, tenant boundaries, who may read what);
   - PII, secrets, tokens, or credentials in committed text — including in `sources/`;
   - a durable, verified discovery asserted in the scaffold but captured nowhere in
     `knowledge/findings/` — write the `Finding` and link it from the task.

   **d. Fail closed on an empty result.** Zero findings is a pass only if the command exited
   successfully **and** the output names the files it reviewed — an auth failure, an
   unconnected-organization notice, or a truncated run can exit non-zero or still read as
   "clean" with nothing reviewed. Check the exit status and confirm a files-reviewed line
   before calling it green; if either is missing, treat the run as indeterminate and say so
   rather than reporting a pass. **An indeterminate run is `configured but refusing`** —
   step a's table cannot see it, because a reviewer that resolves and signs in can still
   refuse once it runs — so carry that class into step e and take its ask, not its
   automatic branch.

   **e. No usable external reviewer ⇒ `qa-reviewer` in scaffold mode. Not a skip — but
   whether it is automatic depends on WHICH class step a found, because the ask fires on
   the SPEND, never on the hiccup.** Dispatching `qa-reviewer` costs a deep-tier session;
   a reviewer that is merely rate-limited is back within the hour (measured 2026-08-31 on
   four PRs), so spending one on it buys nothing.

   * **None configured ⇒ dispatch it, no ask.** Stage 3 is this instance's reviewer, not a
     substitute for one, and that was settled when the instance was set up. Nothing here
     is a fresh decision.
   * **Configured but refusing ⇒ ASK, in this session, in one line.** You are in the
     **main thread and the human is right here** — that is the whole difference from the
     PM tick, which is a subagent, cannot ask, and writes the same question into the
     task's `open_questions` instead. Ask exactly this and act on the answer:

     > `<the reviewer>` is unavailable (`<the one-line reason>`). Spend a `qa-reviewer`
     > session on the scaffold review, or record that it did not run?

   * **…unless a mode `AUTONOMY.md` defines as delegating this is in force ⇒ dispatch it
     automatically** and say you did. That mode replaces the ask above and nothing else.
     This is the existing autonomy switch on one more decision, never a new flag;
     **`AUTONOMY.md` absent means `gated`**, so the ask stands.

   **Whatever the answer, RECORD IT — this step is ONE-SHOT and nothing re-runs it.**
   "Hold and ask again next tick" is the PM's move and it does not exist here: a scaffold
   review that is deferred is a scaffold review that never happens, silently. So if the
   review does not run — the human declines the spend, or is not there to answer — write a
   dated bullet into the project's `log.md` per step f saying **the scaffold got no second
   opinion, and why**, and say the same in your summary to the human. An unrun advisory
   review is an acceptable outcome; an unrun advisory review nobody knows about is not.

   When it does run, brief it with the instance root, the project slug, and the pre-commit
   SHA from step 7, and ask
   for **mode C**. It reviews the committed bundle diff and writes its verdict into the
   project's `log.md` — there is no PR to comment on. Triage its findings exactly as in
   step c; its verdict is advisory, like the external one, and never gates creation.

   Being schema-aware, it should not raise the by-design findings in step c's list. If it
   does, that is a defect in the agent worth fixing rather than a finding worth triaging.

   **f. Record the verdicts.** Add a dated bullet to the project's `log.md` naming what you
   applied **and what you rejected, with the reason** — and make sure that entry is committed,
   not just the accepted fixes. Stage `log.md` alongside the fixes so they land in one commit,
   or record it in a follow-up commit if the fixes already landed; an uncommitted verdict
   record doesn't survive. Without it, the next reviewer re-raises the same by-design findings
   and someone eventually "fixes" them — deleting the PM's refine step or filling empty
   `acceptance_criteria` with invented content.

## Notes
- This repo commits straight to `main` — that's intended (see `CLAUDE.md`); the
  human gates are promote-to-`ready` and (build) merge / (research) approve the
  deliverable, **not** file creation.
- For a big project, slice it into `phases/` (see `SCHEMA.md` `Phase`) — optional;
  skip unless the description clearly spans sequential stages.
- No customer PII in any task/project/log/deliverable text. `sources/README.md` should warn
  about **secrets as well as PII** — raw exports, HAR files, browser screenshots and support
  transcripts can be PII-free and still carry access tokens, API keys, signed URLs or
  internal hostnames. A committed token is leaked: rotate it, don't just delete the file.
- The step-8 review is **build-only and advisory**. It never promotes, never merges, and
  never gates creation — it produces findings you triage. Treat a rejected finding as a
  decision worth recording (in the project's `log.md`), not as something to argue with the
  tool about.
- **A research project asks fewer questions on purpose.** No `target_repo`, no `clis`
  prompt, no CodeRabbit pass — each was dropped because it describes machinery a research
  project never runs (agents, PRs, code), not to save a click. Don't restore one for
  symmetry with `build`; the two kinds are deliberately asymmetric. **The value gate is
  not one of them**: `need:`, `cost_of_not_doing:` and `no_owner:` describe no machinery,
  so step 3 asks all three on both kinds and step 5 writes all three keys.
