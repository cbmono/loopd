# The mods — usage, pane, signal

A [mod](https://code.claude.com/docs/en/plugins/mods/overview) is a hooks module Claude Code
runs **inside** every session that loads the plugin. loopd ships three in one module,
`hooks/register.ts`, registered by `hooks/hooks.json` beside the shell hooks. Each is **one
switch in `/config`** (the plugin's `userConfig`, read off `register`'s `options` and from
nowhere else — not a file, not the environment), default **on**; turn one off and it registers
no hook at all, with **no other edits** anywhere. Off is the behaviour core had before the mod
existed, never an error.

| Switch | Default | On | Off |
|---|---|---|---|
| `usage` | on | records what the session spent in the plugin store after every turn | `session-usage.sh` reads the transcript, as before |
| `pane` | on | `/pane` draws this bundle's board, or an inbox, in a pane beside the transcript | the three core renderers are all there is |
| `paneMode` | `operator` | `operator` draws the board from the snapshot; `simple` draws an inbox from the task documents | — |
| `signal` | on | a role agent's session tells the project-manager's session its turn is over, the moment it is | step 4 reads every session exactly as before |

Until 2026-10-28 these were three companion plugins — `loopd-mod-usage`, `loopd-mod-pane`,
`loopd-mod-signal`; `MIGRATION.md` at the repo root says how to uninstall those.

## usage — what the session spent

After every turn it writes one record to the plugin store, keyed by the session:

| Key | Value |
|---|---|
| `loopd.usage.<session id>` | `{ input, output, cacheRead, cacheWrite, requests, turns, ms, model, tools: { <tool name>: <calls> }, toolErrors }` — tokens from each request's usage (`turn.step`), or the turn's totals when a turn's requests carried none; `ms` is the sum of `durationMs` over turns; `toolErrors` counts tool results with `isError` |
| `loopd.usage.<session id>.ended` | `true`, written at `session.end` |

Core's `plugin/scripts/session-usage.sh <session-id>` reads that record **first** and prints the
same `usage tokens=N tools=N ms=N cached=N errors=N by=Name:N,…` line it prints from a
transcript (`tokens` = input + cacheWrite + output; `cached` = cacheRead; `tools` = the sum
over names; `errors` = toolErrors; `by` = the top five names by count, then name). No
record, two records, a corrupt store file, a non-number anywhere or a tool name outside the
line's grammar, and it reads the transcript exactly as before. The one visible thing: in an
interactive session, one dim `● loopd:` line at start saying it is recording. A `claude -p`
or `claude --bg` session gets no line. No store write without a session id — an
unattributable number is worse than none.

## pane — the board in a pane

`/pane` opens a pane drawing this bundle's board beside the transcript (or above the prompt
in a narrow terminal); `/pane` while it is open, or `/pane close`, closes it the way its `×`
does. `paneMode` decides what it draws:

| `paneMode` | Draws | Reads |
|---|---|---|
| `operator` (default) | the board below, with Answer Questions, Refresh and Close Pane | the snapshot, its numbers from `counts.json`, and `org` and the stamped version for its header |
| `simple` | an inbox — questions, stuck tasks, progress — and a form to start a project; nothing else | the task documents and the form |

### operator mode

The **fourth renderer** over the one board contract, `plugin/scripts/write-snapshot.sh` →
`.loopd/SNAPSHOT.json` (`docs/conventions.md` §11 in `cbmono/loopd`). It reads the snapshot
and `.loopd/counts.json`, plus `org` and the stamped version for its header, and never the
rest of the bundle, so the snapshot
writer's field allowlist holds here without being re-implemented: nothing this pane shows
is anything those files do not already carry. Its numbers — in progress, in review, sessions by state, need you — come from
`.loopd/counts.json`, which `status-line.sh` writes on every redraw through `counts.sh`, the
one definition, and `hooks/refresh-state.sh` has rewritten after every turn of a session on the
bundle (below); the pane computes none of them, so it agrees with the bar — except where another
owner's task is placed in IN PROGRESS or IN REVIEW: that heading counts only the rows it lists.

| Section | From |
|---|---|
| header | the welcome banner's mark (`LOGO_ROWS`, kept once in `register.ts` and read by `session-banner.sh`; pink `#ff7ac2` gate and `◀━`, blue `#5ea2ff` tube); beside row 2 `loopd v<version> · <group> · org: <org>`, the version being counts.json's `plugin_version` (the plugin whose status line wrote the file) when present, else the stamped version; a part it cannot read is left out (neither version ⇒ `loopd`), the group and org are what the width cuts with `…` (dropped whole when under two of their characters would show); beside row 3 a rule to the edge. Under the mark one line, the age at its right (the need-you count is NEEDS YOU's, not the header's): counts.json's `written_at` when the file parses and that is a valid timestamp (the bar rewrites it on every redraw, so it is live), else the snapshot's `generated_at`, which an idle tick leaves old: `just now`, `N min ago`, `N h ago` under 48 h, then `N d ago`; `age unknown` when it is unparseable or in the future. With counts.json absent or unparseable the layout stays, every number from it is `?`, and the info line under the buttons reads `counts unavailable — run /loopd:init` |
| PROJECTS (N) | one line per project, by folder `slug` (never `title`), a blank line between projects; pressing a name copies its slug: `●` active, `○` paused; `✓ … done` in green for a project with `awaiting_close` (its close is a NEEDS YOU row, not counted here); `✓ … closed` in grey for `status: done` (only a retained folder is in the snapshot). `N need you` counts its `awaiting_items` other than `close` (an older snapshot: its tasks' AWAITING verbs), only when N > 0. On your own projects that are not closed, `running` in green after any such count (`N need you · running`) while any of the project's keys in counts.json `task_sessions` is `working` — never for the PM tick, which has no key there, and never when `task_sessions` is absent. Needs-you first, then active, paused, done, snapshot order within each. Under each active project a 10-cell bar and `done/total` off its tasks' `status` (`cancelled` not counted; none, no bar), and `phase_progress` only when it has phases. **Other owners**: a project whose snapshot `mine` is `false` (write-snapshot.sh's `task-owner.sh` verdict — the board's resolution, project `owner:` → tracked `defaultOwner` → unowned is mine; an owner with no `ownerGithubUser` here is not) follows your own after one blank line, one grey line each, no bar: `@<owner>` (only when `owner` is a GitHub login) and `done/total`, `paused` or `done` at the right. `status: done` projects stay last, whoever owns them; no `mine` key is yours |
| IN PROGRESS (N) | N is counts.json's `in_progress`, `(0)` drawn; a blank line, then `W working · I idle · D dead` from its `sessions`, the dispatch tick named apart off `sessions.tick_working` (the working session `.loopd/.tick-lock` records): `1 working (tick)` when it is the only one, `2 working (1 tick)` beside role sessions. One row per task counts.json's `task_status` names `in-progress` (the task documents, as the count is — never the snapshot's `status`, which a tick writes; with no `task_status`, the snapshot's): `assignee` (a **role**, never a person), `title`, and its session word from `task_sessions` — `working`, `idle`, `dead`, or `—` when none is recorded; a task the snapshot lacks is `<slug> · <task id>`, no role; a task of another owner's project (task `owner:` is not in the snapshot) is not listed and leaves N, which then counts the rows listed: after the rows, one grey line `+<n> by @<owner>` per owner, joined by ` · ` in counts.json's order and wrapped between entries, never cut, `another owner` for an owner that is not a login, absent when there is none; with no own row `no task in progress — tick running` while the tick works, and `nothing right now`. Body rows indent 3 columns |
| IN REVIEW (N) | N is counts.json's `in_review`; one row per task `task_status` names `in-review`, placed, named and collapsed by owner as in IN PROGRESS, `assignee` and `title`, plus `PR <pr_mergeable>` when `prs` is non-empty and it is not `MERGEABLE`, else `none`. Drawn at `(0)`; rows indent 3 columns |
| NEEDS YOU (N) | last, next to the buttons. N is counts.json's `need_you`; rows numbered `1.`–`N.`, one per `awaiting_items` entry in AWAITING.md's order — every verb, `👉 do` and `👀 review` included — as `<slug> · <title>` (the title looked up by task id), or `<slug>` on a project row. An older snapshot without `awaiting_items`: one row per task whose `awaiting` is a verb, and one `close <slug>` per project with `awaiting_close` (print-board.sh's rule). Pressing a row's verb copies `projects/<slug>/tasks/<id>.md` (a task with no snapshot row too), or `<slug>` on a project row; none is a dim `nothing`. `awaiting_items: null` (AWAITING.md unreadable) is unknown: `(?)`, no rows, no fallback. Drawn at `(0)`; hidden only with the queue off, which also drops every PROJECTS `N need you` |
| buttons | a blank line, a `─` rule of the pane's width, a blank line, the three buttons (plain, no `[ ]`), a blank line |
| info line | under the buttons, so they never move, starting where they do; the latest of `copied: <ref>`, `copy sent <ref>` (the copy's result did not say), `copy failed: <reason>`, `copy refused: bad ref` or `answer refused: <reason>`, for 10 s after it is set (the poll redraws it away) and until the next re-read; else `answer queued` while an Answer run waits for the session to go idle; else the counts-unavailable hint. Cut to the width |
| update line | the pane's last line, under the info line when one shows, else under the buttons' blank line: `Update available! Run: /loopd:update, then /reload-plugins` in the mark's pink `#ff7ac2`, the two commands bold, when counts.json's `latest_version` is newer (numeric per field) than its `plugin_version`; absent when equal, older, or either is missing or not `x.y.z`. Too wide, it breaks after `/loopd:update,`, then after `Run:`, never inside a command |

The pane is padded 2 columns left and right; every row is drawn inside that, so width is the
pane's `bodyColumns` (45 when the surface gives none) less 4. The buttons' gap is 1 below 43
columns, so the three labels never pass the padding. A NEEDS YOU, IN PROGRESS or IN REVIEW
row wraps, continuation lines under its text, at most 3 lines, the third cut with `…`; a session
word or `PR` mark stays on the first line. Every other row is one line, its name cut by code
point with `…`. A count and the `running`/`paused`/`done`/`closed`
word are never cut, and a zero count is not drawn (`(0)` on IN PROGRESS, IN REVIEW and NEEDS YOU is); a count counts.json does not give — the file absent, unparseable, or the value `null` — is drawn `?`, never `0`. Colours are a pastel trial palette
(2026-11-11, before the rest of loopd adopts it): rose `#DA627D` needs you, peach `#FCA17D`
the bundle name and PROJECTS, sky `#86BBD8` work, teal `#06969A` a bar's done part, deep
blue `#33658A` the rule, green `#76d6a4` done, grey quiet. The kit's `Button` drops a
`color` prop, so each button's label is a coloured `Text` child in a muted tone: teal
`✎ Answer Questions`, deep blue `↻ Refresh`, plum `#9A348E` `✕ Close Pane`, each leading with
a monochrome symbol, the row indented 2 columns. Hover on a `plain` button was not measured: the kit's test mount draws no frame.

Not drawn, because the snapshot does not carry it: a round number, a session id, a usage
line, any question or blocker **text**, any document body, any author
identity (`owner` is in the file for the HTML board's partitioning and is deliberately not
drawn here), any URL. The two things that would make those appear are a field added to the
writer — read its header first — or a second reader of the bundle, which this must never be.

**Untrusted text, untrusted types.** Every string passes one `clean()` for the terminal
medium — every Unicode category-C code point is dropped (so ESC cannot repaint what you
already read and a newline cannot forge a row), whitespace controls become one space — and
every number passes one `toint()`, so a `"tasks": "many"` draws as `0` and never throws.
**A number is never truncated**: a clipped count is a wrong count.

The pane redraws from its two files every **5 seconds**, by `stat` first and `read` only
when a file's mtime moved, and also when an age it shows would change; Refresh re-reads both
and runs nothing; the poll starts when the pane opens — or, after a reload that left the pane
up, on its first draw — and stops when it closes.

**What keeps the two files current is outside the mod**, which starts no process. The shell
hook `hooks/refresh-state.sh` runs at a session's Stop, SubagentStop and UserPromptSubmit —
the main session, the tick's and every role session (a linked worktree reaches its bundle by
the `loopd-bundle` marker) — and starts `${CLAUDE_PLUGIN_ROOT}/scripts/refresh-state.sh` detached: `counts.json` is
rewritten through `counts.sh` (its `claude agents` cache skipped, as the session's word just
changed), and `SNAPSHOT.json` through `write-snapshot.sh`, its one writer, only when a document
it reads is newer than the snapshot and than the last attempt (`ab_snapshot_stale`, `-nt` with
no process). `status-line.sh` starts the same run for a stale snapshot, which covers a document
edited by hand with no turn. One run per bundle at a time; a burst coalesces in a 2-second
wait. No network: a PR merged on GitHub still reaches the files at the next tick, and
`AWAITING.md` (NEEDS YOU's rows) is still rebuilt by the tick alone.

No operator button has a hotkey: the kit draws a Button's `hotkey` as an `a:` hint before
its label (owner, 2026-11-11: no hints), so each is pressed, never keyed.

| Button | Does |
|---|---|
| **Answer Questions** | `$.command.run({ command: 'loopd:answer' })` — runs `/loopd:answer` once in **this** session, as if you had typed it. The engine queues a plugin's command run until the session is idle, so this is idle-only by contract. (Not `$.prompt.submit`: the host refuses a prompt text that begins with `/`, measured on 2.1.293.) A refused run is drawn on the info line as `answer refused: <reason>`, never swallowed. **It is the human pressing a key at their own prompt, not automation**: nothing here runs on a timer, and no message goes to another session. One press, one queued run; a second press while one is queued is ignored and the info line says `answer queued`. |
| **Refresh** | re-read the snapshot and `counts.json` now, mtime or not; it runs nothing. The snapshot is rewritten by each tick, `/loopd:board`, `hooks/refresh-state.sh` after any session's turn on the bundle, and — right after their commit — `answer.sh`, `unblock.sh`, `new-project-file.sh` and the `new-project`, `close-project` and `handoff` skills, so an in-session change needs no tick to show here. |
| **Close Pane** | `$.ui.close({ id: 'loopd-board' })`, the path `/pane close` takes; the poll stops. |
| a PROJECTS name, a NEEDS YOU verb | `$.ui.copy({ text, surface })` — the pane's **one outward action**: the slug or task path, built from the snapshot's `slug` and `id`, onto the clipboard of the surface the press came from, so you can paste it into the session with your reply. A slug or id that is not a folder-name shape (empty, `/`, `..`, whitespace) is never copied. |

Where no surface places the pane (a terminal under the width floor, a `claude -p` run),
`/pane` prints one dim `● loopd:` line with the header counts instead.

### simple mode

For someone who answers questions and does not run the loop. One inbox, top to bottom:

| Section | Shows |
|---|---|
| Questions for you | every unanswered `open_questions` entry across the projects, oldest task first (`docs/operations.md` → "The serve-time fill", the order rule): its task's `timestamp:`, then slug and task id, then `Q<n>` within the task — `board-serve.sh`'s keys; undated last, deferred ones after that. **Only the top one is open** — its code and project, its text, **Recommended: …** (option 1 of its `### Q<n>` block), the other options, a text field, **More** and **Later** — and *n more after this* counts the rest. Every other question is one line: code, project, text. |
| Stuck — you can help | each `status: blocked` task, pink, in the same order (no field records when it became blocked), as one sentence — *Unblock "…" in …: it cannot move until you do.* — and one **Unblock it** button. Never its blocker text, and it opens no card: its open questions are in the section above. |
| Stuck — we're on it | each `in-progress` or `in-review` task with `stall_count` ≥ 1, quiet, never pink: *"…" in …: nothing for you to do, we're on it.* (`last_blocker` is not the test — `stall-counter.sh` keeps it after a reset.) |
| Progress | per project, in creation order (`project.md` `timestamp:`, undated last), a done/total bar over its tasks (`cancelled` not counted); every finished project — `status: done`, or all its tasks done — folds into one green *✓ Finished:* line |
| New project | **New project** (*Start your first project* on an empty bundle); while a form is open it replaces the inbox — below |

No role, tick, pull request, session, usage, round, worktree or branch is drawn; the kit
test asserts their absence against task documents that carry all of them.

**Rose means you, green means done.** The open question's text and a blocked task's sentence
are drawn `#DA627D`; a sent answer and the finished line `#76d6a4` (Text's `color` prop);
every other line keeps the theme default or `dimColor`.

**Every button is one slash command** (`$.command.run`, as operator mode's Answer Questions is), and every hotkey is
unique on the screen:

| Key | Button | Runs |
|---|---|---|
| `1`–`9` | an option of the open question | `/loopd:answer <task> Q<n> <n>` |
| — | the text field | `/loopd:answer <task> Q<n> --text <words>` |
| `m` | More | `/loopd:answer <task> Q<n> more` |
| `l` | Later | `/loopd:answer <task> Q<n> later` — the question goes to the end; the next one opens |
| `c` `d` `e` | Unblock it (the first three stuck tasks; the rest by click) | `/loopd:answer <task>`, which routes a blocked task to `unblock.sh` — the blocker is shown in the session, never here |
| `n` | New project | `/loopd:new-project` — opens the form |
| — | the form's text field: a field number, then the text | `/loopd:new-project <n> "<text>"` |
| `y` | Start the project (form) | `/loopd:new-project submit` |
| `x` | Cancel (form) | `/loopd:new-project cancel` — back to the board, nothing saved |
| `r` | Refresh | nothing — re-reads now |

Keys act on the open card only. `answer.sh` and `unblock.sh` do the writing; this pane writes
nothing. A run is a model turn queued until the session is idle, and it resolves when queued,
before the document moves (measured on 2.1.300). While one is being queued the card shows
*Sending your answer to Q<n>…* and has no buttons, so a second `1` runs nothing; once it is
queued the line *✓ Sent your answer to Q<n> · project · task* names it, the answered question
is held out of the inbox until its document's mtime moves, and the next question opens in
the same place — `1` five times answers five questions. A deferred one is held at the end
until the later file moves. If the turn that ran it ends with nothing moved (`answer.sh`
refused), the question comes back with a note. A refused run is drawn. A read that fails is
retried on the next scan.

**The new project form is the skill's, not the pane's.** Five fields — 1 Title, 2 What, 3 For
whom, 4 Done when, 5 Target repo (prefilled with `defaultRepo`) — live in one gitignored file,
`.loopd/.new-project/form.json`, which `plugin/scripts/new-project-form.sh` writes on each run above;
the pane draws it in place of the inbox and writes nothing. A field just typed shows
*· saving…* until the file moves. **Start the project** asks the script to check every field:
one missing redraws the form with a pink *✗* and a plain fix under each, and nothing is
created; complete, the skill creates the project as `kind: build`, `autonomy: yolo`, with the
form's repo as `repo=` and `owner:` the creating clone's login, commits, pushes when the bundle
has an upstream, and removes the form. Field text is data: `autonomy=…` or `--no-ask` typed
into a field is that field's words. Until a new project whose title matches appears the board
shows *Creating "…"…*; then *Created "…".*, plus *Its first questions will appear here*, or,
when the project did not resolve to `yolo`, *It moves only as far as the operator approves.*
A refused run, or a turn that ends with nothing moved, is one line; nothing retries it.

## signal — the turn is over

One module side or the other, told apart by the session's working directory and nothing else:

| Side | Where | When | Writes | Sends |
|---|---|---|---|---|
| **PM** | the cwd holds `instance.config.json` (a bundle root) | `session.start` | `loopd.pm.<bundle root>` = `{ sessionId, at }` | nothing |
| **role agent** | the cwd is a linked worktree of a repo `link-repos.sh` marked (`<repo>/.git/loopd-bundle` names the bundle) | every `turn.complete` of the **main loop** (a subagent's turn, `agentId` set, is skipped) | `loopd.signal.<session id>` = `{ bundle, cwd, at, turns, durationMs, reason, isAborted, delivered }` | **one** line to the session `loopd.pm.<bundle>` names |

The line, exactly one per `turn.complete`, is the same delivery the `SendMessage` tool makes:

```text
loopd-signal: role session <id> finished a turn in <worktree> (reason <reason>, <ms> ms) — settle it first at step 4 of a /loopd:dispatch tick; this line orders the sweep and decides nothing
```

`turn.complete` is the end-of-work moment for a role agent, not `session.end`: a
`claude --bg` session stays alive and idle after its brief is answered and never fires
`session.end` (measured 2026-10-09 on 2.1.293,
`docs/spikes/mods-in-background-sessions.md` in `cbmono/loopd`). The store record is written
**before** the message, so step 4 can read it whether or not the message lands. Delivery is
best-effort by design — a PM session that holds or refuses inbound messages answers
`isDelivered: false` — and after **two** undelivered sends in one session the role side stops
sending and keeps writing the store: a session that said no is not spammed.

The bundle is resolved the way the plugin's `deny-destructive.sh` hook resolves it, read for
read: `<cwd>/.git` must be a **file** (so a human's main clone, where `.git` is a directory,
is never a role agent), its `gitdir:` names the worktree's git dir, that dir's `commondir`
names the repo's common dir (relative, `../..`, folded lexically — no symlink is resolved),
and `<common>/loopd-bundle` names a directory that must hold `instance.config.json`. Any link
missing ⇒ the hook hands the event on and does nothing: a repo with no marker (a bundle not
re-stamped since the marker shipped, or one outside `reposRoot`) leaves its agents silent,
exactly as it leaves them without a baseline (`docs/conventions.md` §19).

Core's `tick-steps/step-4-advance.md` says what the line is worth: **order, never a
verdict**. A tick that has received one settles that session first with the same three reads
it always ran; a tick that has received none runs as before; and a turn that ended is not a
PR that exists, so nothing is advanced on the message itself.

## What it reads

Only under the session's working directory as `$.session.cwd()` gives it, or along git's
own worktree layout from there — never a parent directory walked, never a path a config
file names. The pane alone looks first in the directory the session started in,
`$.session.root()`, which a Bash `cd` does not move (`status-line.sh`'s `CLAUDE_PROJECT_DIR`),
and uses the cwd only when that holds no `instance.config.json`; `<cwd>` below is whichever
of the two it chose. Every path literal the module spells is in this table; `tests/mods.test.sh` in
`cbmono/loopd` asserts it, and that a module which lists a directory spells its walk as a
quoted glob. The `.loopd/SNAPSHOT.json`, `.loopd/counts.json`, `.loopd/.answer-later` and
`.loopd/.new-project/form.json` spellings are `AB_SNAPSHOT`, `AB_COUNTS`, `AB_ANSWER_LATER` and
`AB_NEW_PROJECT_FORM` in `plugin/scripts/bundle-paths.sh`; `.git`, `commondir` and `loopd-bundle`
are git's and `link-repos.sh`'s.

| Path | Mod | Call | Why |
|---|---|---|---|
| `<cwd>/instance.config.json` | pane, signal | `exists` (pane: the start directory's, then the cwd's); pane (`operator`) also `read` on open and Refresh | the cwd is a loopd bundle. Pane: absent ⇒ *not a loopd bundle* and nothing else; its `org` is the header's `org:`. Signal: present ⇒ this is the PM side; a `turn.complete` here signals nothing |
| `.loopd/SNAPSHOT.json` | pane (`operator`) | `stat` every poll, `read` when the mtime moved | the board. Absent ⇒ *board OFF* with the `touch` that turns it on (absence is the off switch — conventions 3 and 11) and nothing else. Unparseable ⇒ one line, and the next `write-snapshot.sh` run overwrites it |
| `.loopd/counts.json` | pane (`operator`) | `stat` every poll, `read` when the mtime moved | the four numbers, session totals, per-task session words and per-task `in-progress`/`in-review` status `status-line.sh` writes on every redraw, and `plugin_version`, that plugin's own `VERSION`, for the header, and `latest_version`, the marketplace's as `check-template-version.sh` last read it, for the update line (each omitted unless `x.y.z`). Absent or unparseable ⇒ those numbers draw `?` |
| `.loopd/seed-base/VERSION` | pane (`operator`) | `read` on open and Refresh | the version `/loopd:init` last stamped (`$AB_DIR/seed-base/VERSION`), shown as the header's `v<version>` when counts.json carries no `plugin_version` — a mod cannot read the plugin's own `VERSION`, so that one arrives through counts.json. Absent or not `x.y.z` ⇒ left out |
| `projects/*/project.md` | pane (`simple`) | `list`, `read` | `title`, `status`, `autonomy` and `timestamp` |
| `projects/*/tasks/*.md` | pane (`simple`) | `list`, `read` | `title`, `status`, `timestamp`, `stall_count`, `open_questions` and the `### Q<n>` blocks. Listed every poll, read when an mtime moved. A list it cannot parse is drawn as *could not read*, never guessed |
| `.loopd/.new-project/form.json` | pane (`simple`) | `stat` every poll, `read` when the mtime moved | the new project form in progress, written by `new-project-form.sh`; absent ⇒ no form open. Its directory carries a `*` `.gitignore`, so it is never tracked |
| `.loopd/.answer-later` | pane (`simple`) | `stat` every poll, `read` when the mtime moved | the questions `answer.sh later` deferred, one `<task path>#Q<n>` a line; absent ⇒ nothing deferred. Per clone and gitignored, so a deferral on one clone is not one on another |
| `<cwd>/.git` | signal | `stat`, then `read` | a **file** in a linked worktree, naming the gitdir; a directory in a main clone, which stops the walk |
| `<gitdir>/commondir` | signal | `read` | the repo's common git dir, relative to the gitdir; absent ⇒ the gitdir is the common dir |
| `<common>/loopd-bundle` | signal | `read` | the marker `link-repos.sh` writes: the bundle root |
| `<bundle>/instance.config.json` | signal | `exists` | the marker names a real bundle; a marker naming nothing is ignored |

The usage mod reads no file. Simple mode reads the task documents and not the snapshot
because the snapshot carries no question text by design (conventions 11b) and is rewritten
only by a clone that dispatches. The pane is local, never published — it shows what
`AWAITING.md` and `/loopd:answer` already show this clone.

## What it never does

A mod runs with your permissions in every session on the machine, so the lines it does not
cross are the whole design, and `tests/mods.test.sh` in `cbmono/loopd` asserts each on the
source and on what `claude plugin validate` reads out of it:

- **No model call** — nothing here spends the plan.
- **No permission decision** — it never hooks `tool.check`; every event it sees is handed on.
- **No process, no network, no environment** — `$.process`, `$.http` and `$.env` are never called.
- **No write** — `$.fs.write` is never called, and `$.fs.ancestors` (which walks UP from the cwd) is never called either. The reads above are the whole file-system footprint; the plugin store is the only thing it writes, save the clipboard: `$.ui.copy`, on your press, of a slug or a task path and nothing else, in one function `tests/mods.test.sh` pins.
- **No decision about a task** — it reads no task document to decide anything, decides no status, re-dispatches nothing. `check-dispatch.sh` is report-only because a checker that acted on its own reading would automate the loop's most expensive failure (`seed/CONVENTIONS.md`); a signal that advanced a task would be that checker.
- **No prompt, no consumption** — `session.receive` passes every message through unchanged: a `loopd-signal:` line reaches Claude in the PM session as plain text, the tick decides what it is worth, and `$.prompt.submit` is never called. Nothing here starts a tick; every button that runs anything is a `$.command.run` the human pressed, and a copy button only copies.
- **No timer-driven run** — the pane's poll reads files; only a press runs a command.
- **More than one message per turn, or any message after two refusals** — never.
- **A store write without a session id** — an unattributable record is worse than none.

## Where the store lives

Claude Code keeps one JSON file per plugin under
`${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/store/`, named `<plugin name>_<marketplace>-<hash>.json`
(`<plugin name>_inline-<hash>.json` for a `--plugin-dir` load), a flat object of key → value;
this plugin's file is `loopd_loopd-….json` once it has written, and `plugin/scripts/session-usage.sh`
reads it by that glob. One `loopd.usage.*` record per session, one `loopd.pm.*` record per
bundle and one `loopd.signal.*` record per role session, a few hundred bytes each; the 4 MiB
store limit is the vendor's and nothing here prunes.

## Tested with

Claude Code **2.1.312** (`claude plugin validate plugin --strict` passes, `claude plugin test`
57/57 from the plugin root, 2026-10-28). Mods need v2.1.287 or later; `$.session.send` and
the `session.receive` event need v2.1.293. One event may be hooked once without a matcher per
module (measured on 2.1.312), which is why `session.start` and `turn.complete` are hooked once
in `register` and handed to each mod that is on. The events and methods can change between
releases, so after a CLI update run, from the repo root:

```
claude plugin validate plugin --strict
cd plugin && claude plugin test
```

The kit tests live under `hooks/tests/` — inside the plugin, because `claude plugin test` runs
only what sits under the plugin directory; they are not bash harnesses and `tests/` at the repo
root is where those live. `docs/spikes/mods-in-background-sessions.md` in `cbmono/loopd`
records what was and was not measured about mods in `claude -p` and `claude --bg` sessions —
the shape loopd's role agents run in. Not measured end to end: a real `--bg` role agent's
line arriving in a real PM session, which needs two live sessions and a stamped bundle; the
kit tests pin both halves against the documented shapes.
