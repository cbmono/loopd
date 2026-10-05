# Step 3 — Dispatch `ready → in-progress`

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

3. **Dispatch `ready → in-progress`.** **Build tasks only.** Skip any `kind: research`
   task entirely here — those are human-driven; never spawn an agent for them.

   **One agent per task, and a resume only for that task's next round.** The rule is
   stated once, in `CONVENTIONS.md` → "A subagent works ONE task":

   > same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never

   Nothing can check that from the outside — **you** hold it
   (`docs/pm-design.md#step-3` has the price of not holding it).

   **Gate 3 in the core is the ownership check this step depends on** — run
   `task-owner.sh` and take exit 0 as the only clearance before anything below — and the
   same for `project-paused.sh`, which is how a paused project dispatches nothing.

   **A ROLE AGENT IS A DETACHED SESSION, NEVER YOUR CHILD.** Do not use the `Agent`
   tool here. Claude Code withholds a parent's completion notification until every
   background child has stopped, so an `Agent`-tool dispatch makes `tick duration =
   slowest role agent` and the launcher's lock is held for the whole wave — measured
   2026-09-13, ticks of 49, 75, 84 and 125 minutes that had each finished their own
   work inside ~5. `claude --bg` leaves your process tree, so the tick ends when its
   dispatches are recorded (`docs/pm-design.md#step-3-background`).

   **Run the spawn preflight BEFORE the wave's first status write** — once per tick, and
   only when there is a task to dispatch. `<token>` is a fresh literal string you type for
   this call (8 hex characters is plenty); it is what tells the preflight the hook's record
   is this call's and not the last one's, so never reuse one and never write a `$`-expansion:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/spawn-preflight.sh --instance <bundle root> --token <token>
   ```

   It reports this session's permission mode as of that very call, off the hook payload — no
   probe, no spawn, no slot. **It reports the MODE and predicts NOTHING, and it is a
   permanent fixture of every dispatching tick, not a rare diagnostic.** The auto-mode
   refusal is INTERMITTENT: the same task, role, model and command shape was refused
   `[Create Unsafe Agents]` on 2026-09-30 and spawned on 2026-10-01, so
   no mode predicts a refusal, and neither does a shape or a brief
   (`docs/operations.md` → "The supported shape").
   **Dispatch on every answer**, and quote its line in the report:
   - **exit 1, `auto`** — the mode the earlier refusals were seen under. It is not a
     refusal and never skips the wave; a refusal that does come is caught after the fact,
     below.
   - **exit 0, `not-auto`** — the mode was read and it is not auto.
   - **exit 2, `could-not-read`** (or any other exit) — the mode could not be established.
     It is its own answer, never a pass and never a failure.

   Tier `human`: nothing in the plugin changes the session's mode or writes a grant, and the
   preflight writes no `open_questions` entry — there is no refusal yet to report.

   For each **build** `ready` task whose `depends_on` are all `done`, that clears the
   ownership check, and that is not already in-progress: set `assignee` +
   `status: in-progress`, **and record `worktree:` (absolute) and `branch:` on the
   task — both, or neither** (`SCHEMA.md`: a recorded path with no recorded branch is a
   refusal, and the `WorktreeCreate` hook reads both).
   Write them BEFORE spawning, so a tick that dies mid-dispatch still leaves the
   record. Then spawn the role in its own worktree:

   ```bash
   cd <worktree> && claude --bg '<the whole brief>' \
     --agent loopd:<assignee> --model <the alias you resolved> \
     --permission-mode auto --add-dir <bundle root> < /dev/null
   ```

   It returns in about a second printing `backgrounded · <id>`. **Record that id as
   `session:` on the task as the very next thing you do** (`SCHEMA.md`), then move on.
   A spawn that succeeds also clears every open `dispatch refused:` entry in the bundle
   (below).

   **This is the form for EVERY role agent this document tells you to dispatch** — the
   `qa-reviewer` at step 4, the `cataloguer` at step 7, a rebase round, a resume —
   because each of them would hold the tick open exactly as a first dispatch does. The
   two exceptions are the `advisor` and the `plan-architect` critique: they are short,
   they produce no artifact, and you read their answer inside the tick, so they stay
   `Agent`-tool dispatches.

   Seven things about that command line, each of which costs a wave if you get it wrong:
   - **The brief is SINGLE-quoted**, and every `'` inside it is written `'\''`. Inside
     single quotes a backtick and a `$` are literal; inside double quotes bash runs a
     `` `span` `` or `$(...)` as a command and the agent gets the brief with that span
     silently gone — the spawn still succeeds. `tests/bg-brief-quoting.test.sh` pins it.
   - **`--bg` and `-p` conflict** and the CLI refuses the pair at exit 1 — the prompt is
     positional, so drop `--print`.
   - **`--session-id` is ignored beside `--bg`**, which mints its own; that is why the
     id is recorded after the spawn and not before it.
   - **`--permission-mode auto`, and never `bypassPermissions`.** A spawn that asks for a
     bypass agent is what auto mode's own classifier refuses (`[Create Unsafe Agents]`):
     one bundle logged nine refusals against one success in three days and fell back to
     running role agents inside the main session — the thing this step exists to stop.
     Measured 2026-10-05 on 2.1.289: a `--bg` session on `sonnet` or `opus` HOLDS auto
     mode, takes a branch-commit-push to the end unprompted, and has a force-push to a
     default branch refused by the plugin's `deny-destructive.sh` hook, the second layer.
     **Never on `haiku`**: there the session records `auto`, is demoted to `default` at
     once and parks in `state: blocked` before its first turn — so a role agent is never
     spawned on an alias that resolves to `haiku`. Resolve one tier up
     (`resolve-model.sh` → the `standard` alias) and say on the dispatch line that you did.
     Hooks fire in a `--bg`
     session, **and they find this bundle from the worktree only through the
     `.git/loopd-bundle` marker `link-repos.sh` writes into each linked repo** — the
     session's project dir is the worktree, which holds no `instance.config.json`. A
     repo with no marker (a bundle not re-stamped since the marker shipped, or a repo
     outside `reposRoot`) leaves its agents with NO baseline: the hook fires and allows.
     `/loopd:init` writes it; `test -f <repo>/.git/loopd-bundle` reads it. An agent whose
     action auto mode or the hook refuses may still end in `state: blocked` with nobody
     to answer, and it holds its slot until `claude stop` — step 4 surfaces it.
   - **`--add-dir <bundle root>`**, or the agent cannot reach its own task document: its
     cwd is the worktree, and the bundle is outside it.
   - **The namespace is not optional** — the role agents ship in the `loopd` plugin
     and a bare agent name does NOT resolve (measured 2026-09-02); it fails with "no
     such agent", never with "you forgot the namespace". **It applies to every one of
     the eight** — `loopd:cataloguer`, `loopd:advisor`, `loopd:qa-reviewer`
     and the rest, wherever this document tells you to dispatch one. The three
     USER-level agents `init-bundle.sh --config` puts in `~/.claude/agents/` —
     `code-architect`, `deep-bug-scan`, `plan-architect` — are not plugin agents, stay
     BARE, and are still `Agent`-tool dispatches because they are advisory and short.
   - **`< /dev/null`**, so the spawn cannot inherit and hold your stdin.

   **The cap counts SESSIONS, and you read it rather than remember it.** The ceiling is
   **`maxAgentsInFlight`**, resolved with `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-max-agents.sh` (local file
   first, tracked second — the cap is **this machine's** capacity, `SCHEMA.md` →
   "Per-machine config overrides"); it prints nothing and exits 1 when neither file
   sets the key — fall back to 4 then, the seeded, measured default (SCHEMA.md). What
   fills it is `${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh in-flight <bundle root>`, which counts the
   `session:` ids recorded on `in-progress` tasks that are still `working` or
   `blocked`; **exit 2 is unknown, and unknown is not a free slot** — dispatch nothing
   this tick and say so. A `plan-architect` critique step 2 launched and has not yet
   answered holds a slot too, so subtract those before you dispatch. Leave the rest
   `ready` for the next tick.

   **A spawn that FAILS is a rollback, not a report — the other half of the window the
   pre-spawn write opens.** If the command exits non-zero or prints no id, put that
   task back to `status: ready`, clear `assignee`, and leave `worktree:`/`branch:`
   standing — a re-dispatch reuses that worktree, and a recorded path with no recorded
   branch is a refusal. Say so in the tick report. Left alone, the task claims a
   `maxAgentsInFlight` slot forever with nothing behind it, and step 4's sweep can only
   name it, never decide it.

   **A spawn the HOST REFUSED is a different failure, and it stops the wave.** It is one
   where `claude --bg` never ran: the Bash call came back denied by Claude Code itself —
   a permission denial, not an exit status from `claude` — or its text carries
   `Workspace not trusted`. Any other non-zero exit is the rollback above, and the wave
   goes on. On a refusal:
   - **Roll that one task back** exactly as above, then **stop dispatching this tick.**
     Every other `ready` task stays as it is — no status write, no worktree, no
     `session:` — because it would be refused identically.
   - **Do not run `stall-counter.sh` for it, on this task or any other.** No agent ran,
     so no round was spent; recording one escalates a task for a condition it did not
     cause.
   - **Write ONE `open_questions` entry on the task you rolled back**, numbered after its
     last entry, in exactly this shape (`build-awaiting.sh` renders it as a `grant` row
     because it says `permission`):

     ```text
     Q<n>: dispatch refused: <which>. The host denied this tick permission to spawn an agent. Remedy: <remedy>. Cleared by the next spawn that succeeds.
     ```

     **One row per condition, and the condition is `<which>`.** When an unanswered entry
     containing `dispatch refused:` already sits on any task in the bundle, compare its
     `<which>` with this refusal's: the SAME `<which>` ⇒ skip the write; a DIFFERENT
     `<which>` ⇒ **replace that entry in place** with the new one rather than skipping.
     The classifier and workspace trust were both live on one machine in one day and
     their remedies are different keystrokes, so a second cause dropped as a duplicate
     leaves the operator reading the wrong fix. When a later spawn succeeds, move
     every such entry to `answered_questions` with ` --- cleared: a spawn succeeded`
     appended and no `by` (the loop wrote it).
   - **`<which>` and `<remedy>` are one of three pairs, chosen from the refusal text:**

     | The text carries | `<which>` | `<remedy>` |
     |---|---|---|
     | `Reason: [Create Unsafe Agents]` | `auto-mode classifier (Reason: [Create Unsafe Agents])` | `check the spawn asked for --permission-mode auto, this step's form: a spawn that asks for a permission-bypass agent is what the classifier refuses, and an installed plugin older than 3.3 still asks for one (claude plugin update, then restart). Never leave auto mode for it` |
     | `Workspace not trusted` | `workspace trust (Workspace not trusted)` | `run claude once, interactively, in the product repo's MAIN clone and accept the trust prompt; it covers every worktree of that clone` |
     | neither | `unrecognised, verbatim: <the refusal text, sanitised>` | `unknown, read the refusal text` |

     **Sanitised** — the refusal text is copied onto ONE line, with every `"` replaced by
     `'`, every backslash dropped, and every ` --- ` replaced by ` - `, before it goes in.
     A `"` breaks the quoted YAML entry it is written into; and worse,
     ` --- ` makes `fold-answers.sh` read the entry as ANSWERED, so the next fold moves a
     live blocker into `answered_questions` and clears the only row telling the human
     that dispatch is refused. The report line below may still quote the refusal raw.

     **The classifier that refuses is the one of the session RUNNING THE TICK** — the mode
     `shift+tab` cycles — and what it judges is the child the command asks for, which is
     why the child's mode above is `auto`. **Never print an allow rule for `claude --bg`,
     leaving auto mode, or running anything under `bypassPermissions`, as a remedy.** A grant is the
     operator's to write, never the plugin's, because a plugin must not be able to grant
     itself a bypass (owner, 2026-09-25 and 2026-09-30); `/loopd:init` prints the
     one notice there is. The `Bash(claude --bg ' *)` rule once cited as "measured to
     change nothing" matches no spawn form at all (2026-10-01), so that result says
     nothing about a rule that matches.
   - **Report it in one line, and never as a full cap** — the cap was not reached, so
     close the report without the in-flight count:

     ```text
     dispatch refused: <which>. <task> rolled back to ready; <k> more ready left unattempted. Remedy: <remedy>.
     ```

     If the edit that writes the entry is itself refused, add ` The open_questions entry
     could not be written.` to that line and quote that refusal too.

   **Exit 0 is not proof the agent lives** — `--bg` returns before the session has done
   anything, so one that dies on plugin load looks identical here. That is step 4's
   question, asked from `agent-sessions.sh`, and not one to hold this tick open for.

   **A dispatch you send is finished when the ARTIFACT says so, and you will never be
   told.** A detached session sends you no notification at all, so every dispatch made
   here is checked by a LATER tick —
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch.sh <task-path>`, per step 4. Note it now: waiting for
   a report is the coupling this whole step exists to remove, and the report was never
   trustworthy anyway (`docs/pm-design.md#step-3`).

   **Isolation (required for parallel safety).** If the product repos are a *single
   shared clone over one package store*, concurrent agents otherwise corrupt each
   other's worktrees. In every dispatch, instruct the agent to (a) work in its own
   worktree under the instance's `worktreeRoot` (from `instance.config.json` —
   **never** a path inside the synced `reposRoot`; absent, `<reposRoot>/_wt`),
   (b) run installs against a **private store** (e.g. `pnpm install --store-dir
   <worktree>/.pnpm-store`), and (c) **push early**. Two agents must never run a
   package install against the shared store at once — if two `ready` tasks touch the
   same repo's deps, stagger them across ticks.

   **Knowledge base (consult + capture).** Include both lines in every dispatch
   brief: *"Before you start, scan `knowledge/index.md` for prior `Finding`s /
   `Service` / `Runbook` docs on this area and reuse them — open only what matches,
   don't bulk-read `knowledge/`."* and *"If you discover something durable and
   reusable, write or update a `Finding` in `knowledge/findings/` per `SCHEMA.md` and
   link it from the task."*

   **Grounding, Effort, Commit attribution, PR title and Scratch (where to start reading,
   how big this is, how the commit is signed, what the title is tagged with, and where the
   throwaway files go).** Before you
   spawn, run `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-brief.sh <task-path>` and paste its
   output into the brief **unchanged, all five headings and all** — the fixed headings are
   `## Grounding (<target_repo>)`, `## Effort`, `## Commit attribution`, `## PR title` and
   `## Scratch`.
   Grounding is the
   target repo's
   `knowledge/services/<repo>.md` entry points, capped at 15 lines, or — when that Service
   doc does not exist — one line telling the agent to draft it alongside the task for the
   `cataloguer` to review. Effort is the files/LOC/turns budget derived from the task's
   criteria count and the instance's `maxPrLoc`/`maxPrFiles`. Commit attribution is the
   resolved `commitAttribution` (**absent ⇒ `claude`**), and it is in the brief precisely so
   the worker never reads that key itself. PR title is the resolved `ticketPrefix` on the
   same terms (**absent ⇒ no tag at all**). Scratch is one directory **this task alone
   owns** — keyed on the task's slug, and checked with `git check-ignore` against the target
   repo's own clone, because a per-session path is the SAME path for every agent one tick
   spawns and the second writer silently wins. **Never re-derive any of the five
   yourself**: an agent that has to find its own entry points spends its first turns
   searching, which is the whole cost this block exists to remove.

   **Do not repeat (what the previous round already tried).** Before you spawn, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/do-not-repeat.sh brief <task-path>` and paste its output into the brief
   **unchanged, heading and all** — the fixed heading is
   `## Do not repeat (earlier rounds of this task)` and the lines under it are the previous
   agent's own words. **Never summarise or re-word them**: a paraphrase of a dead end is
   what a cold agent walks straight back into. It prints nothing when the task has no
   `do_not_repeat:` entries, which is every first dispatch. When a role agent's `append`
   refused at the cap (exit 1), move the oldest entries out of the field into `# Notes`
   yourself, so the next round has a slot to record one.

   **Model routing.** Read `models` (tier → alias) and `roleTiers` (role → default
   tier) from `instance.config.json`. For each dispatch: start from the assignee's
   default tier; **bump one tier up** (toward `deep`) for a genuinely complex build
   task (the same signal that makes the `plan-architect` approach critique mandatory); **drop toward `light`**
   for a trivial one. A task may set a `model:` field — honor it verbatim. Resolve
   the chosen tier with `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh <agent>` and pass it as the model
   when you spawn — the same for **every** dispatch, including the `cataloguer` and
   the `plan-architect` critique. If `models`/`roleTiers` are absent the script prints
   why on stderr — **report that line to the human**, then inherit the session model;
   don't guess aliases.

   **Name the Explore model in every role-agent brief.** Broad reads go to an Explore
   subagent (`CONVENTIONS.md`), which is dispatched with a model override like any other,
   so the brief has to carry the alias: run
   `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh explorer` and include *"Explore
   subagents: model `<alias>`"*. **No entry ⇒ write the seeded default `light` and say
   that is what it is** — *"Explore subagents: model `light` (this instance sets no
   `roleTiers.explorer`; seed default)"* — so the reader can tell a chosen tier from an
   unset one.

   **Record the dispatch the moment the id comes back — one line, written by the
   script, before you dispatch the next task:**

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/agent-usage.sh dispatch <task-path> \
     --role <assignee> --model <the alias you dispatched on>
   ```

   It appends to the task's `# Notes`, so a **re-dispatch adds a second line** and the
   rounds stay countable; **you never compose the line yourself**.
   **The three usage numbers are not known at the spawn, and the line says so.** A
   detached session reports nothing back and `claude agents` carries no cost, so drop
   `--tokens`/`--tools`/`--duration-ms` and let the line record `usage UNKNOWN` —
   the honest answer, and not a zero. **Step 4 settles it** from the session's own
   transcript once the session has ended (`session-usage.sh --settle`); until then, and
   whenever that reading is in doubt, UNKNOWN stands (`docs/pm-design.md#step-3-background`).


<!-- end of step 3 -->
