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
in a narrow terminal). `paneMode` decides what it draws:

| `paneMode` | Draws | Reads |
|---|---|---|
| `operator` (default) | the board below, with Tick and Refresh | the snapshot |
| `simple` | an inbox — questions, stuck tasks, progress — and a form to start a project; nothing else | the task documents and the form |

### operator mode

The **fourth renderer** over the one board contract, `plugin/scripts/write-snapshot.sh` →
`.loopd/SNAPSHOT.json` (`docs/conventions.md` §11 in `cbmono/loopd`). It reads the snapshot,
never the bundle, so the snapshot writer's field allowlist holds here without being
re-implemented: nothing this pane shows is anything the file does not already carry.

| Section | From the snapshot's fields |
|---|---|
| header | `group`, `counts.projects`, `counts.tasks`, `counts.awaiting` |
| need you | the AWAITING verbs — `approve · answer · merge · unblock · close` — counted off each task's `awaiting` verb, plus one `close` per project with `awaiting_close` (print-board.sh's rule) |
| in flight | each task with `in_flight`: `<project slug>/<task id>`, `assignee` (a **role**, never a person), `status`, the PR's `pr_mergeable` when `prs` is non-empty, `title` |
| projects | per project: `slug`, `status`, `phase_progress.done/total`, the task count, in-flight count, awaiting count, `title` |
| footer | `generated_at` — when the writer last wrote the file — and `tick queued` while a Tick is waiting for the session to go idle |

Not drawn, because the snapshot does not carry it: a round number, a session id, a usage
line, a `continue` verb, any question or blocker **text**, any document body, any author
identity (`owner` is in the file for the HTML board's partitioning and is deliberately not
drawn here), any URL. The two things that would make those appear are a field added to the
writer — read its header first — or a second reader of the bundle, which this must never be.

**Untrusted text, untrusted types.** Every string passes one `clean()` for the terminal
medium — every Unicode category-C code point is dropped (so ESC cannot repaint what you
already read and a newline cannot forge a row), whitespace controls become one space — and
every number passes one `toint()`, so a `"tasks": "many"` draws as `0` and never throws.
**A number is never truncated**: a clipped count is a wrong count.

The pane redraws from the file every **5 seconds**, by `stat` first and `read` only when
the mtime moved; the poll starts when the pane opens and stops when it closes.

| Button | Does |
|---|---|
| **Tick** (`t`) | `$.command.run({ command: 'loopd:dispatch' })` — runs `/loopd:dispatch` once in **this** session, as if you had typed it. The engine queues a plugin's command run until the session is idle, so this is idle-only by contract. (Not `$.prompt.submit`: the host refuses a prompt text that begins with `/`, measured on 2.1.293.) A refused run is drawn in the footer as `tick refused: <reason>`, never swallowed. **It is the human pressing a key at their own prompt, not automation**: nothing here runs on a timer, and no message goes to another session. One press, one queued tick; a second press while one is queued is ignored and the footer says `tick queued`. |
| **Refresh** (`r`) | re-read the snapshot now, mtime or not. |

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

**Pink means you, green means done.** The open question's text and a blocked task's sentence
are drawn `#ff7ac2`; a sent answer and the finished line `#76d6a4` (Text's `color` prop);
every other line keeps the theme default or `dimColor`.

**Every button is one slash command** (`$.command.run`, as Tick is), and every hotkey is
unique on the screen:

| Key | Button | Runs |
|---|---|---|
| `1`–`9` | an option of the open question | `/loopd:answer <task> Q<n> <n>` |
| — | the text field | `/loopd:answer <task> Q<n> --text <words>` |
| `m` | More | `/loopd:answer <task> Q<n> more` |
| `l` | Later | `/loopd:answer <task> Q<n> later` — the question goes to the end; the next one opens |
| `c` `d` `e` | Unblock it (the first three stuck tasks; the rest by click) | `/loopd:unblock <task>` — the blocker is shown in the session, never here |
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
file names. Every path literal the module spells is in this table; `tests/mods.test.sh` in
`cbmono/loopd` asserts it, and that a module which lists a directory spells its walk as a
quoted glob. The `.loopd/SNAPSHOT.json`, `.loopd/.answer-later` and
`.loopd/.new-project/form.json` spellings are `AB_SNAPSHOT`, `AB_ANSWER_LATER` and
`AB_NEW_PROJECT_FORM` in `plugin/scripts/bundle-paths.sh`; `.git`, `commondir` and `loopd-bundle`
are git's and `link-repos.sh`'s.

| Path | Mod | Call | Why |
|---|---|---|---|
| `<cwd>/instance.config.json` | pane, signal | `exists` | the cwd is a loopd bundle. Pane: absent ⇒ *not a loopd bundle* and nothing else. Signal: present ⇒ this is the PM side; a `turn.complete` here signals nothing |
| `.loopd/SNAPSHOT.json` | pane (`operator`) | `stat` every poll, `read` when the mtime moved | the board. Absent ⇒ *board OFF* with the `touch` that turns it on (absence is the off switch — conventions 3 and 11) and nothing else. Unparseable ⇒ one line, and the next `write-snapshot.sh` run overwrites it |
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
- **No write** — `$.fs.write` is never called, and `$.fs.ancestors` (which walks UP from the cwd) is never called either. The reads above are the whole file-system footprint; the plugin store is the only thing it writes.
- **No decision about a task** — it reads no task document to decide anything, decides no status, re-dispatches nothing. `check-dispatch.sh` is report-only because a checker that acted on its own reading would automate the loop's most expensive failure (`seed/CONVENTIONS.md`); a signal that advanced a task would be that checker.
- **No prompt, no consumption** — `session.receive` passes every message through unchanged: a `loopd-signal:` line reaches Claude in the PM session as plain text, the tick decides what it is worth, and `$.prompt.submit` is never called. Nothing here starts a tick; every button is a `$.command.run` the human pressed.
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
