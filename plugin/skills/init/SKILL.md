---
name: init
description: Create a new AI Bridge bundle, refresh an existing one, or convert a symlink-era bundle in place. Data only — a bundle it stamps carries no machinery and no link into any checkout.
argument-hint: "<dir>  [--org O [--name R]] [--refresh-seeds] [--with-objectives] [--normalise-config] [--owner L] [--email A] [--repos-root D] [--spawn-grant]"
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh:*), Bash(pwd), Bash(ls:*), Read, Glob
---

Run this, from anywhere, and **relay its output verbatim**:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh $ARGUMENTS
```

`$ARGUMENTS` is the bundle directory, optionally followed by `--org <org>` (see "One org,
one bundle"), `--refresh-seeds`,
`--with-objectives`, `--normalise-config`, one of `--owner <login>` / `--email
<address>` / `--repos-root <dir>` (see "When it says `needs`"), or `--spawn-grant` (see
"The spawn grant"). No directory means the current one. That is the whole skill: every
decision, every guard and every line of output lives in the script, so a human running it
in a terminal and a session running it here get the same answer, and there is no second
copy here to drift.

**The plugin carries the installer.** No clone of this template is needed on the machine,
and a plugin update is what updates it.

## What it does, in one table

| | |
|---|---|
| **Creates** | a bundle at `<dir>`: seed docs, `instance.config.json` + `.local.json`, the derived-ignore lines, `AWAITING.md` and `SNAPSHOT.json`, and `repos/` linked from `reposRoot` |
| **Refreshes** | the same bundle again — idempotent, seeds only what is ABSENT, and never overwrites a value already there |
| **Converts** | a bundle stamped by the old `install.sh`: every machinery symlink into a template checkout is removed, the managed `.gitignore` machinery block is retired, and the data is untouched |
| **Creates on request** | `objectives/`, with `--with-objectives`. It is an optional layer (`SCHEMA.md` → type: Objective) — a project normally carries its own `success_criteria` — so a plain stamp makes no such directory, and an existing one is data and never touched |
| **Brings up to date** | an existing bundle, by running the welcome check-and-fix pass after the stamp — the idempotent tier only, and the same refusals: config files and tick locks are reported, never written. Seed drift is 3-way merged, decidable conflicts are resolved on the rule that decides them, and anything else is reported for you |
| **Reports** | config findings across `instance.config.json` and `instance.config.local.json` — a key in the wrong file, a seed key missing, keys out of order. Report-only unless you say yes at the prompt or pass `--normalise-config`, and then it moves, adds and reorders without ever changing a value, and leaves the tracked file **staged** |

**The only symlinks a stamped bundle holds are under `repos/`**, and those point at the
group's product repos, never at a checkout of this repo.

## One org, one bundle — `--org <org> [--name <repo>]`

The bundle is the **organisation's repo**, and everyone clones the same one.
`/loopd:init <dir> --org <org>` resolves `<org>/<org>-okf` (`--name` overrides the
name) and does exactly one of three things, saying which:

| | |
|---|---|
| **Clones** it | the repo is there and is a bundle — the tracked config comes with it, and this clone's own gitignored `instance.config.local.json` is written by the step below |
| **Creates** it | private, seeded, first commit pushed — only after your access to `<org>` is established, never off a bare 404 |
| **Creates it under YOU** | when creating it in `<org>` is refused because you are not an org admin. Same stamp, same push; it prints the `gh repo transfer` line that moves it to the org later |

**Two refusals, both deliberate.** It refuses when your access to `<org>` cannot be
established — a 404 means *absent* or *private and invisible to you*, and seeding over the
org's real bundle is not recoverable — and it refuses **by name** when `<org>/<name>`
exists and is not a bundle. Relay either verbatim; the fix is membership, or another
`--name`.

**The second person runs the same command.** They get the clone, and the `needs` flow
below is how their `ownerGithubUser` is asked for. The full order is `docs/sharing.md` in
the template, whose URL the stamp prints on its last line.

## The first stamp asks one question

At a terminal, on a **first** stamp only, it offers to collect the team's GitHub logins
and commit emails (`people`, `defaultOwner`, and this clone's `ownerGithubUser`). One
batched prompt, nothing written until it is confirmed. **Not at a terminal — a background
tick, a script — it skips and prints how to set the three values by hand.** Never on a
refresh, and never over a value already there.

## When it says `needs`, ask once and re-run

A clone with no `instance.config.local.json` gets one written: the script **derives**
`ownerGithubUser`, `authorEmail` and `reposRoot` and prints what it wrote. Anything it
could not derive it prints as a `needs` line naming the key and its flag.

- **Ask the human only for the keys on `needs` lines — one batched question, all of them
  at once.** Never ask for a value the script derived and printed; it already has it.
- Then re-run the same command with the flags for exactly those keys, e.g.
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh <dir> --owner <login> --email <address>`.
- **No `needs` line means nothing to ask.** A bundle whose local file already exists is
  left alone — the script says so — with one exception: a missing `authorEmail` is filled
  from the tracked `people` map for the login the file names, and when `people` has no
  entry it is the one `needs` line an existing file can print; `--email` answers it.

## The spawn grant: one yes/no question, asked here on the script's behalf

Role agents are `claude --bg` sessions the tick starts, and without one rule in the
bundle's `.claude/settings.local.json` every spawn stops at a permission prompt. **At a
terminal the script asks for it itself, Enter is yes.** Run from here there is no terminal,
so it writes nothing and prints a `note` that begins `init writes no \`claude --bg\` grant
without your yes`, followed by the rule. When you see that note:

- Ask the human exactly this, with the rule the note printed in place of `<rule>`: *Write
  `<rule>` to `.claude/settings.local.json` so the tick can start role agents without a
  prompt?* — once, together with any `needs` keys.
- On a yes, re-run the same command with `--spawn-grant`. The script writes the rule,
  verifies it, and removes any stale grant it named (a bare `Bash(claude --bg *)`, a
  `bypassPermissions` spawn, a retired agent namespace), saying what it removed.
- On a no, nothing: the rule stays printed for them. **Never write the rule yourself**, and
  never on a bundle whose stamp printed no such note.

## What you must not do with the output

- **Do not act on a line it declined to act on.** A `stale` line names retired content
  that is the human's to keep or delete; the script prints the exact `rm` and does not
  run it. A `keep` line names a symlink of the human's own.
- **Do not act on a `CONFLICT` yourself.** A hand-diverged seed file is the only copy of
  a decision somebody made; the script reports it, names the diff, and stops. So do you.
- **`AUTONOMY.md` disappearing is a real change, not noise.** If the conversion removed
  it, delegated authority is off and the bundle is back to ask-first. Relay that line and
  the opt-back-in it prints (`/plugin install loopd-yolo@loopd` — the companion
  that ships the file); never re-create the file yourself.

## Afterwards

`instance.config.json` needs the group's `org` before anything else works;
`instance.config.local.json` is written for you, from what the machine already knows.
Then `/loopd:welcome` for the banner, and `/loopd:dispatch` for the loop.
**Run this command again after every plugin update** — it is the one that brings a
bundle up to the installed plugin. The banner's `Update` row says when: `bundle stamped at
<old> — run /loopd:init`.

If the directory is not a bundle and was not meant to be one, say which directory it is
and stop — never stamp somewhere on a guess.
