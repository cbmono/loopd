# loopd-mod-pane — the board-in-a-pane companion (a mod)

A [mod](https://code.claude.com/docs/en/plugins/mods/overview): a hooks module Claude Code
runs **inside** every session that loads it. This one adds `/pane`, which opens a pane
drawing this bundle's board beside the transcript (or above the prompt in a narrow
terminal), and nothing else.

**One switch, `mode`**, in `/config` (the plugin's `userConfig`; nothing else decides it):

| `mode` | Draws | Reads |
|---|---|---|
| `operator` (default) | the board below, with Tick and Refresh | the snapshot |
| `simple` | an inbox — questions, stuck tasks, progress — and a form to start a project; nothing else | the task documents |

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-mod-pane@loopd
```

Uninstall it (`/plugin` → Installed) and the three core renderers — `build-board.sh`,
`print-board.sh`, `watch-board.sh` — are all there is, with **no other edits** anywhere.
Absence is the safe behaviour, never an error.

## What it draws — operator mode

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

## What it draws — simple mode

For someone who answers questions and does not run the loop. One inbox, top to bottom:

| Section | Shows |
|---|---|
| Questions for you | every unanswered `open_questions` entry across the projects, oldest task first (`docs/operations.md` → "The serve-time fill", the order rule): its task's `timestamp:`, then `Q<n>`, then slug and task id; undated last, deferred ones after that. **Only the top one is open** — its code and project, its text, **Recommended: …** (option 1 of its `### Q<n>` block), the other options, a text field, **More** and **Later** — and *n more after this* counts the rest. Every other question is one line: code, project, text. |
| Stuck — you can help | each `status: blocked` task, pink, in the same order (no field records when it became blocked), as one sentence — *Unblock "…" in …: it cannot move until you do.* — and one **Unblock it** button. Never its blocker text, and it opens no card: its open questions are in the section above. |
| Stuck — we're on it | each `in-progress` or `in-review` task with `stall_count` ≥ 1, quiet, never pink: *"…" in …: nothing for you to do, we're on it.* (`last_blocker` is not the test — `stall-counter.sh` keeps it after a reset.) |
| Progress | per project, in creation order (`project.md` `timestamp:`, undated last), a done/total bar over its tasks (`cancelled` not counted); every finished project — `status: done`, or all its tasks done — folds into one green *✓ Finished:* line |
| New project | four fields — Title, What, For whom, Done when — and **Create** |

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

**Create is one `/loopd:new-project` run**, only with all four fields filled:
`"<what>" kind=build autonomy=yolo title="<title>" need="<for whom>" success_criteria="<done when>" --no-ask`.
`--no-ask` makes the skill ask nothing and take its defaults; its step-8 scaffold review runs
unchanged. Until a new project directory appears whose `project.md` carries the title typed the form shows
*Creating "…"…*; then *Created "…".*, plus *Its first questions will appear here* — they come
from the loop's first read of the task, as any question does — or, when the project did not
resolve to `yolo`, *It moves only as far as the operator approves.* A refused run, or a turn
that ends with no new project, is one line and the form comes back filled; nothing retries it.
The skill commits and, when the bundle has an upstream, pushes. A push it could not make is one
line in the session's reply, not in the form: *Created* then means created on this clone only.

## What it reads

Only under the session's working directory as `$.session.cwd()` gives it — never a parent
directory, never a path a config file names:

| Path | Mode | Why |
|---|---|---|
| `instance.config.json` | both | exists? — the cwd is a loopd bundle. Absent ⇒ *not a loopd bundle* and nothing else. |
| `.loopd/SNAPSHOT.json` | operator | `stat` every poll, `read` when the mtime moved. Absent ⇒ *board OFF* with the `touch` that turns it on (absence is the off switch — conventions 3 and 11) and nothing else. Unparseable ⇒ one line, and the next `write-snapshot.sh` run overwrites it. |
| `projects/*/project.md` | simple | `title`, `status`, `autonomy` and `timestamp`. |
| `projects/*/tasks/*.md` | simple | `title`, `status`, `timestamp`, `stall_count`, `open_questions` and the `### Q<n>` blocks. Listed every poll, read when an mtime moved. A list it cannot parse is drawn as *could not read*, never guessed. |
| `.loopd/.answer-later` | simple | the questions `answer.sh later` deferred, one `<task path>#Q<n>` a line (`AB_ANSWER_LATER` in `plugin/scripts/bundle-paths.sh`). `stat` every poll, `read` when the mtime moved; absent ⇒ nothing deferred. Per clone and gitignored, so a deferral on one clone is not one on another. |

Simple mode reads the task documents and not the snapshot because the snapshot carries no
question text by design (conventions 11b) and is rewritten only by a clone that dispatches.
The pane is local, never published — it shows what `AWAITING.md` and `/loopd:answer` already
show this clone.

The `.loopd/SNAPSHOT.json` spelling is `AB_SNAPSHOT` in `plugin/scripts/bundle-paths.sh`;
`tests/mods.test.sh` asserts the module and that file agree, that every path the module
names — every quoted literal an fs call is given included — is listed in this section, and
that a module which lists a directory spells its walk as a glob.

## The two buttons — operator mode

| Button | Does |
|---|---|
| **Tick** (`t`) | `$.command.run({ command: 'loopd:dispatch' })` — runs `/loopd:dispatch` once in **this** session, as if you had typed it. The engine queues a plugin's command run until the session is idle, so this is idle-only by contract. (Not `$.prompt.submit`: the host refuses a prompt text that begins with `/`, measured on 2.1.293.) A refused run is drawn in the footer as `tick refused: <reason>`, never swallowed. **It is the human pressing a key at their own prompt, not automation**: nothing here runs on a timer, and no message goes to another session. One press, one queued tick; a second press while one is queued is ignored and the footer says `tick queued`. |
| **Refresh** (`r`) | re-read the snapshot now, mtime or not. |

Where no surface places the pane (a terminal under the width floor, a `claude -p` run),
`/pane` prints one dim `● loopd-mod-pane:` line with the header counts instead.

## What it never does

A mod runs with your permissions in every session on the machine, so the lines it does not
cross are the whole design, and `tests/mods.test.sh` in `cbmono/loopd` asserts each on the
source and on what `claude plugin validate` reads out of it:

- **No model call** — nothing here spends the plan.
- **No permission decision** — it never hooks `tool.check`; every event it sees is handed on.
- **No process, no network, no environment** — `$.process`, `$.http` and `$.env` are never called.
- **No write** — `$.fs.write` is never called, and `$.fs.ancestors` (which walks UP from the cwd) is never called either. The reads above are the whole file-system footprint, and they are the one widening of the mod rule `tests/mods.test.sh` grants, to a mod whose README names its paths here.
- **No cross-session message** — `$.session.send` is not used; the cross-session half is unmeasured (`docs/spikes/mods-in-background-sessions.md`).
- **No timer-driven run** — the poll reads files; only a press runs a command, and nothing here ever submits a prompt.

## Tested with

Claude Code **2.1.302** (`claude plugin validate . --strict` passes, `claude plugin test`
29/29, 2026-10-18), written against the mods docs and the 2.1.289 `claude-code.d.ts`. Mods need
v2.1.287 or later. After a CLI update run, from this directory:

```
claude plugin validate . --strict
claude plugin test
```

Settled by that run: `$.prompt.submit` refuses a text beginning with `/` ("would run a
command as the user; run one with `$.command.run`"), so Tick is a `$.command.run`. Measured on
2.1.300: an interactive session lists `loopd-mod-pane.mode` in `/config` as a choice (a `-p`
run lists no plugin rows), and a plugin's `$.command.run` runs a `disable-model-invocation`
skill. Still assumed: that a `/config` change reaches a loaded module without a reload; that
`ui.close` fires with `e.id` for a pane the person closes (else the poll outlives the
pane until reload); that `$.fs.stat` rejects rather than resolving for a missing file (the
code handles both).

## Delete it

`/plugin uninstall loopd-mod-pane@loopd`, or remove the directory from a checkout. The
contract this plugin is an instance of — how a companion registers, where core looks, and
the rule that a companion ADDS behaviour and never removes a core gate — is in
[`../plugin/README.md`](../plugin/README.md) → "Companion plugins".
