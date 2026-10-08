# loopd-mod-pane — the board-in-a-pane companion (a mod)

A [mod](https://code.claude.com/docs/en/plugins/mods/overview): a hooks module Claude Code
runs **inside** every session that loads it. This one adds `/board`, which opens a pane
drawing this bundle's board beside the transcript (or above the prompt in a narrow
terminal), and nothing else.

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-mod-pane@loopd
```

Uninstall it (`/plugin` → Installed) and the three core renderers — `build-board.sh`,
`print-board.sh`, `watch-board.sh` — are all there is, with **no other edits** anywhere.
Absence is the safe behaviour, never an error.

## What it draws

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

## What it reads

Exactly two paths, both under the session's working directory as `$.session.cwd()` gives it,
and nothing else — never a parent directory, never a path a config file names:

| Path | Why |
|---|---|
| `instance.config.json` | exists? — the cwd is a loopd bundle. Absent ⇒ the pane says *not a loopd bundle* and draws nothing else. |
| `.loopd/SNAPSHOT.json` | `stat` every poll, `read` when the mtime moved. Absent ⇒ the pane says *board OFF* with the `touch` that turns it on (absence is the off switch — conventions 3 and 11) and draws nothing else. Unparseable ⇒ one line, and the next `write-snapshot.sh` run overwrites it. |

The `.loopd/SNAPSHOT.json` spelling is `AB_SNAPSHOT` in `plugin/scripts/bundle-paths.sh`;
`tests/mods.test.sh` asserts the module and that file agree, and that every path the module
names is listed in this section.

## The two buttons

| Button | Does |
|---|---|
| **Tick** (`t`) | `$.prompt.submit({ text: '/loopd:dispatch', asUser: true })` — starts one dispatch turn in **this** session. The engine queues a plugin's prompt until the session is idle, so this is idle-only by contract. **It is the human pressing a key at their own prompt, not automation**: nothing here runs on a timer, and no message goes to another session. One press, one queued tick; a second press while one is queued is ignored and the footer says `tick queued`. |
| **Refresh** (`r`) | re-read the snapshot now, mtime or not. |

Where no surface places the pane (a terminal under the width floor, a `claude -p` run),
`/board` prints one dim `● loopd-mod-pane:` line with the header counts instead.

## What it never does

A mod runs with your permissions in every session on the machine, so the lines it does not
cross are the whole design, and `tests/mods.test.sh` in `cbmono/loopd` asserts each on the
source and on what `claude plugin validate` reads out of it:

- **No model call** — nothing here spends the plan.
- **No permission decision** — it never hooks `tool.check`; every event it sees is handed on.
- **No process, no network, no environment** — `$.process`, `$.http` and `$.env` are never called.
- **No write** — `$.fs.write` is never called, and `$.fs.ancestors` (which walks UP from the cwd) is never called either. The two reads above are the whole file-system footprint, and they are the one widening of the mod rule `tests/mods.test.sh` grants, to a mod whose README names its paths here.
- **No cross-session message** — `$.session.send` is not used; the cross-session half is unmeasured (`docs/spikes/mods-in-background-sessions.md`).
- **No timer-driven prompt** — the poll reads a file; only a press submits.

## Tested with

Written against the mods docs and the `claude-code.d.ts` of Claude Code **2.1.289** on
2026-10-08; the 2.1.293 binary on the build machine was Gatekeeper-quarantined that night, so
`claude plugin validate` and `claude plugin test` were **not** run before the PR opened.
Mods need v2.1.287 or later. After a CLI update run, from this directory:

```
claude plugin validate . --strict
claude plugin test
```

Assumptions a run would settle: that a `$.prompt.submit` text beginning with `/` runs as a
slash command (else Tick is a prompt the model reads, and the human types the command);
that `ui.close` fires with `e.id` for a pane the person closes (else the poll outlives the
pane until reload); that `$.fs.stat` rejects rather than resolving for a missing file (the
code handles both).

## Delete it

`/plugin uninstall loopd-mod-pane@loopd`, or remove the directory from a checkout. The
contract this plugin is an instance of — how a companion registers, where core looks, and
the rule that a companion ADDS behaviour and never removes a core gate — is in
[`../plugin/README.md`](../plugin/README.md) → "Companion plugins".
