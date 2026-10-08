# loopd-mod-signal — the turn-is-over companion (a mod)

A [mod](https://code.claude.com/docs/en/plugins/mods/overview): a hooks module Claude Code
runs **inside** every session that loads it. This one lets a role agent's session tell the
project-manager's session that its turn is over, the moment it is over, and nothing else.

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-mod-signal@loopd
```

Uninstall it (`/plugin` → Installed) and step 4 of the tick reads every session exactly as
it did before — `agent-sessions.sh state`, `session-usage.sh --settle`, `check-dispatch.sh`
— with **no other edits** anywhere. Absence is the safe behaviour, never an error.

## What it does

One module, loaded in every session on the machine, with two sides told apart by the
session's working directory and nothing else:

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

Core's `plugin/tick-steps/step-4-advance.md` says what the line is worth: **order, never a
verdict**. A tick that has received one settles that session first with the same three reads
it always ran; a tick that has received none runs as before; and a turn that ended is not a
PR that exists, so nothing is advanced on the message itself.

## What it reads

Five paths, every one of them a link in git's own worktree layout or the one marker the
plugin writes, and nothing else — never a parent directory walked, never a path a config
file names, never a task document:

| Path | Call | Why |
|---|---|---|
| `<cwd>/instance.config.json` | `exists` | the cwd is a bundle root ⇒ this is the PM side; a `turn.complete` here signals nothing |
| `<cwd>/.git` | `stat`, then `read` | a **file** in a linked worktree, naming the gitdir; a directory in a main clone, which stops the walk |
| `<gitdir>/commondir` | `read` | the repo's common git dir, relative to the gitdir; absent ⇒ the gitdir is the common dir |
| `<common>/loopd-bundle` | `read` | the marker `link-repos.sh` writes: the bundle root |
| `<bundle>/instance.config.json` | `exists` | the marker names a real bundle; a marker naming nothing is ignored |

The `.git`, `commondir` and `loopd-bundle` spellings are git's and `link-repos.sh`'s;
`tests/mods.test.sh` asserts that every path literal the module spells is named in this
section.

## What it never does

A mod runs with your permissions in every session on the machine, so the lines it does not
cross are the whole design, and `tests/mods.test.sh` in `cbmono/loopd` asserts each on the
source and on what `claude plugin validate` reads out of it:

- **No model call** — nothing here spends the plan.
- **No permission decision** — it never hooks `tool.check`; every event it sees is handed on.
- **No process, no network, no environment** — `$.process`, `$.http` and `$.env` are never called.
- **No write** — `$.fs.write` is never called, and `$.fs.ancestors` (which walks UP from the cwd) is never called either. The five reads above are the whole file-system footprint.
- **No decision about a task** — it reads no task document, decides no status, re-dispatches nothing. `check-dispatch.sh` is report-only because a checker that acted on its own reading would automate the loop's most expensive failure (`plugin/seed/CONVENTIONS.md`); a signal that advanced a task would be that checker.
- **No prompt, no consumption** — `session.receive` passes every message through unchanged: a `loopd-signal:` line reaches Claude in the PM session as plain text, the tick decides what it is worth, and `$.prompt.submit` is never called. Nothing here starts a tick.
- **More than one message per turn, or any message after two refusals** — never.
- **A store write without a session id** — an unattributable record is worse than none.

## Where the store lives

Claude Code keeps one JSON file per plugin under
`${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/store/`, named `<plugin name>_<marketplace>-<hash>.json`
(`<plugin name>_inline-<hash>.json` for a `--plugin-dir` load), a flat object of key → value;
`plugin/scripts/session-usage.sh` reads the usage companion's file of the same shape. One
`loopd.pm.*` record per bundle and one `loopd.signal.*` record per role session, rewritten on
every turn, a few hundred bytes each; the 4 MiB store limit is the vendor's and nothing here
prunes, which is the usage companion's rule too.

## Tested with

Claude Code **2.1.293** (`claude --version`, 2026-10-09). Mods need v2.1.287 or later; the
`$.session.send` call and the `session.receive` event need v2.1.293. The events and methods
can change between releases, so after a CLI update run, from this directory:

```
claude plugin validate . --strict
claude plugin test
```

Measured on 2.1.293: a `--plugin-dir` load of this mod fires in `claude -p` and in a detached
`claude --bg` session started from a trusted directory, and `turn.complete` carries `reason`,
`durationMs`, `isAborted` and — for a subagent's turn — `agentId`. Not measured end to end:
a real `--bg` role agent's line arriving in a real PM session, which needs two live sessions
and a stamped bundle; the kit tests pin both halves against the documented shapes
(`e.to` reaches the `session.send` event as a string, a stub answers `{ isDelivered }`).

## Delete it

`/plugin uninstall loopd-mod-signal@loopd`, or remove the directory from a checkout. The
contract this plugin is an instance of — how a companion registers, where core looks, and
the rule that a companion ADDS behaviour and never removes a core gate — is in
[`../plugin/README.md`](../plugin/README.md) → "Companion plugins".
