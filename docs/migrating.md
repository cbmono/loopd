# Migrating an existing install

For anyone running AI Bridge from **before the plugin** — a bundle whose
`.claude/commands/` still holds symlinks, and whose commands are the bare `/pm-loop`,
`/new-project`, `/answer`, … Nothing errors. Those files simply stopped being shipped,
and a dangling command still registers, so the bundle offers `/pm-loop` and fails when
you run it.

**And for anyone whose bundle still carries machinery symlinks at all** — which is every
bundle stamped by `install.sh`. The machinery ships in the plugin now, so a link into a
template checkout is frozen at whatever that clone last pulled and no plugin update ever
reaches it. [§ Converting a symlink-era bundle](#converting-a-symlink-era-bundle-in-place)
below is the one command that fixes it, in place, without touching your data.

**And for a bundle that still keeps its state in `.ai-bridge`** — any bundle stamped before
3.3.0. [§ The state directory is `.loopd`](#the-state-directory-is-loopd-330-onward) below
is the migration; `/loopd:init` refuses such a bundle until it has run.

**There are two ways forward and they are not equally safe.** Pick with the table, then
read only that section.

---

## Converting a symlink-era bundle, in place

**One command, idempotent, and it never touches your data.**

```
/loopd:init ~/workspace/<group>/_ai-bridge-<group>
```

That is the whole migration for the machinery half. It is safe to run on a bundle full of
somebody's work, and safe to run again.

| What it does | Detail |
|---|---|
| **Removes every machinery symlink** outside `repos/` | dangling ones, links whose target contains `/symlink/`, and links that resolve into a template checkout. One `retire <path> — <reason>` line each |
| **Retires the managed `.gitignore` block** | the `# >>> ai-bridge machinery (symlinked) >>>` pair and everything between it. Your own rules, outside the markers, are untouched |
| **Seeds what the removal left absent** | `SCHEMA.md`, `CONVENTIONS.md`, `agents/index.md` and `.claude/settings.json` become the bundle's **own files**, copied once |
| **Leaves data alone** | `projects/`, `knowledge/`, `objectives/`, `log.md`, `board.html`, your `instance.config.json` — none is read or written by the sweep |
| **Leaves a symlink of yours alone** | anything that is not a machinery link is reported `keep <path>` and left |
| **Removes emptied machinery directories** | `scripts/`, `.claude/hooks/` and friends, and only when `rmdir` succeeds — a directory still holding anything is kept |

**Two things to know before you run it.**

1. **`AUTONOMY.md` is not put back, on purpose.** It is the deletable delegated-authority
   capability, so shipping it with core would arm it everywhere. If your bundle had one,
   the conversion removes the link and says so loudly, and the bundle is back to
   ask-first — the safe end. To opt back in, install the companion plugin that carries it:
   `/plugin install loopd-yolo@loopd`; the run prints that line.
2. **Seed drift is reported, never merged.** A seed document this repo changed since your
   bundle was stamped is listed and left alone. `/loopd:welcome fix` — or
   `/loopd:init <dir> --refresh-seeds` — 3-way merges the ones that merge cleanly; a
   hand-diverged file is never forced, and its conflicted merge is saved beside it as
   `.bak.<epoch>`. `instance.config.json` is never merged at all.

**Afterwards**, `/loopd:welcome` should print no machinery alarm, and
`/loopd:welcome check` should say *"no symlinks outside repos/ — this bundle carries
no machinery and no template link"*. If it does not, it names what is left and the repair.

**You no longer need a clone of `cbmono/loopd` on the machine.** Once every bundle on
it is converted, the checkout is only useful for working on this repo itself. Deleting it
breaks nothing — that is the property this migration bought.

---

## The decision rule

**Upgrade in place. That is the default, and it is the right answer for almost everyone.**

| | **A — upgrade in place** | **B — fresh re-home** |
|---|---|---|
| The folder | you keep it | you stamp a **new** one, then delete the old |
| git history | **kept in full** — every task, review and decision the loop has recorded | left behind in the backup; the new folder starts at commit 1 |
| `projects/` and `knowledge/` | **never touched.** They are bundle *content*, not machinery, and no step of the upgrade reads or writes them | copied by hand, and every copy is a chance to miss one |
| What it costs | one report-first script | six steps, the last of which deletes something |
| Pick it when | you want the plugin era, and that is all | you **deliberately** want a clean folder — a new group, a rename, a bundle you are re-homing |

**B is not a better A.** It buys exactly one thing — a folder with no history — and pays
for it with the history. If you cannot name why you want that, you want A.

**Either way, the plugin is `loopd`.** `ai-bridge-v2` was the transition name; its
stub shipped for one version and was removed in 1.0.0, so install the bare name.
Every command is namespaced — `/loopd:dispatch`, `/loopd:welcome`,
`/loopd:new-project`, and the [rest](../README.md#commands) — and so is every role agent
(`loopd:software-engineer`), because a bare name does not resolve.

---

## Path A — upgrade in place (the default)

**Written once, in one place, and not repeated here:**
[operations.md § Moving a stamped bundle into the plugin era](operations.md#moving-a-stamped-bundle-into-the-plugin-era--run-this-once).

Three steps — plugin install (per machine), `/loopd:init <bundle>`, restart. The
stamp converts, so the sweep below removes the symlink-era command links for you, and it
never removes bundle content. `upgrade.sh` was the old spelling of this and is now a stub
that says so.

**Nothing on the [checklist](#what-you-must-not-lose-and-what-must-not-travel) below
applies to you**, because on path A nothing moves. It is there for path B.

---

## Path B — fresh re-home, in six steps

Placeholders throughout: `<group>` is the group folder, `<new-folder>` the instance
directory you are stamping, `<user>` your GitHub login. `_ai-bridge-<group>` is the
folder you are leaving, spelled under the convention bundles had before the rename; a
bundle already named `_loopd-<group>` substitutes its own name.

### 1. Back up the whole bundle — as a git repo, because it is one

There is no bespoke backup tool and there should not be: your instance is a git repo, so
git's own two answers are the backup.

```bash
cd ~/workspace/<group>/_ai-bridge-<group>
git status --short                                  # nothing outstanding before you start
git add -A && git commit -m "chore: pre-migration checkpoint" || echo "nothing to commit"
git push                                            # a remote is already a backup

# a second copy that survives the original being deleted — either form is complete
mkdir -p ~/backups                                  # git bundle will not create it
git clone --no-hardlinks . ~/backups/_ai-bridge-<group>-backup
git bundle create ~/backups/_ai-bridge-<group>.bundle --all
```

`--no-hardlinks` is not optional: a plain local clone shares object files with the
original, and you are about to delete the original.

**Then check the backup, before anything is deleted:**

```bash
git -C ~/backups/_ai-bridge-<group>-backup log --oneline -1
git bundle verify ~/backups/_ai-bridge-<group>.bundle
```

> "Bundle" is overloaded here. `git bundle` is git's single-file archive; an *OKF
> Knowledge Bundle* is what your instance **is**. This step makes the first out of the
> second.

### 2. Install the plugin — once per MACHINE

The two lines are in [README § Install step
1](../README.md#1-install-the-plugin--once-per-machine). Per machine, not per instance:
if this machine already has `loopd`, skip the step. If it has `ai-bridge-v2`, install
`loopd`, uninstall the old one from `/plugin` → Manage, and relaunch Claude Code.

### 3. Stamp the new folder

```
/loopd:init ~/workspace/<group>/<new-folder>
```

It creates the directory too. Name it `_loopd-<group>` unless you are deliberately
renaming ([README § 2](../README.md#2-make-the-bundle-directory)).

**Answer the roster prompt.** A first stamp at a terminal offers to collect
`<github-login> <commit-email>` pairs, and the same prompt writes this clone's
`instance.config.local.json` — the one file that must **not** come from the old folder.
Step 4 overwrites `instance.config.json` on top of what the prompt puts there, and that
is fine; the local file is what you are here for.

### 4. Copy the content over

**Copy from git, not from disk.** `git archive` emits exactly the tracked files, so every
derived and per-machine file on the do-not-copy list is excluded by construction rather
than by you remembering.

```bash
old=~/workspace/<group>/_ai-bridge-<group>
new=~/workspace/<group>/<new-folder>

git -C "$old" archive HEAD projects knowledge objectives log.md instance.config.json \
  | tar -x -C "$new"

# everything tracked, so you can see what you are choosing to leave behind
git -C "$old" ls-files | cut -d/ -f1 | sort -u
```

Drop any path that does not exist in `HEAD` — `git archive` fails on an unknown one. A
`cp -R` works too, but it copies the derived files as well, and then the
[checklist](#what-you-must-not-lose-and-what-must-not-travel) is yours to run by hand.

**Not on that list: `CLAUDE.md` and `README.md`.** They are seed content and yours to
edit, but the old copies still say `/pm-loop`. Port *your* edits onto the freshly stamped
ones — don't copy the files whole and re-import the dead command names you are migrating
away from.

### 5. Re-stamp, then re-home the git repo

Same shell as step 4 — `$old` and `$new` are still set.

```bash
# a) the SECOND stamp: reposRoot is real now, so repos/ is linked, and the derived
#    ignore lines are refreshed against the content you just copied
#      /loopd:init "$new"

# b) a fresh repo — the old history stayed in the backup, deliberately
cd "$new"
git init && git add -A && git commit -m "chore: bootstrap control panel"
gh repo create <user>/<new-folder> --private --source=. --push

# c) the documents, against the schema the machinery now ships
scripts/validate-bundle.sh
```

Two things this step is for:

- **The second stamp is not redundant.** Repo linking is skipped while `reposRoot` is the
  seeded placeholder, so it could not have run in step 3 — the real `reposRoot` only
  arrived with step 4.
- **The derived indexes come back on the first LIVE tick**, not now. Root `index.md` and
  `projects/*/index.md` are rewritten by the PM's curate step; a DRY RUN stops before it.
  If the stamp reports either as *tracked*, run the `git rm --cached` line it prints —
  they are views, and a committed view is a merge conflict every tick.

### 6. Verify

```bash
cd "$new" && claude
```

Then, in the session:

| Run | What proves it worked |
|---|---|
| `/loopd:welcome` | the banner renders and names **this** instance. *Unknown command* accuses the **plugin**, never the stamp |
| `/loopd:welcome check` | each line a fact with its evidence — read the `⚠` lines |
| `/loopd:dispatch`, then say **DRY RUN** | it reports what it *would* dispatch and spawns nothing. Your projects and tasks appearing **by name** is the proof `projects/` arrived intact |

Only once this passes do you delete anything — see
[below](#uninstalling-the-old-symlink-era-install).

---

## What you must not lose, and what must not travel

### Keep — this is the work

| Path | Why |
|---|---|
| `projects/` | every project, task, deliverable and per-project `log.md` |
| `knowledge/` | `Finding`s, `Service`s, `Runbook`s, `Team`s, `Reference`s — **including `knowledge/index.md`**, which is tracked and curated, not derived |
| `objectives/` | the `Objective` documents projects hang off |
| `log.md` | the instance ledger |
| `instance.config.json` | `org`, `reposRoot`, `worktreeRoot`, `people`, `defaultOwner`, `maxPrLoc` — tracked, and therefore shared, and therefore it travels |
| `CLAUDE.md`, `README.md` | seed content, **yours since the day it was copied** — but port your edits onto the fresh copies rather than copying the old files, which still name `/pm-loop` |
| `AUTONOMY.md` | the **decision** it encodes. A **real file** at your bundle root travels and still wins; a *symlink* by that name does not, see below |

### Do not copy — every one of these regenerates

| Path | What it is |
|---|---|
| `instance.config.local.json` | **per machine**: `ownerGithubUser`, `authorEmail`, `models`/`roleTiers`. Copying it to another machine is how a bundle ends up authoring as somebody else. `/loopd:init` writes a fresh one |
| `.tick-lock`, `.tick-lock.claim` | the dispatch lock, **per clone**. A copied lock is one nobody holds and nothing releases |
| `.tick-state` | the tick delta cache, per clone |
| `.board-live/`, `.board-others.json`, `board.html`, `SNAPSHOT.json` | the board's derived output and its caches |
| `AWAITING.md` | the derived awaiting-you queue, rewritten every tick |
| root `index.md`, `projects/*/index.md` | derived navigation, rewritten every tick. **One exception:** a *retained* project's `index.md` is written once at closeout and is committed |
| `repos/` | a derived symlink view of the group's repos; `scripts/link-repos.sh` rebuilds it |
| `scripts/`, `.claude/hooks/`, `AUTONOMY.md` | on a symlink-era bundle these are **absolute symlinks into a template checkout**. Copying one gets you a link into the old folder's template, or a dangling one. `/loopd:init` removes them; the machinery runs from the plugin |
| `tmp/`, `*.bak.*` | scratch, and the files a stamp moved aside |

**`SCHEMA.md`, `CONVENTIONS.md` and `agents/index.md` are seed content now**, not links:
copy your bundle's own edits across if you made any, exactly as for `CLAUDE.md`.

**`AUTONOMY.md` is the one file whose absence IS its setting**, and the stamp no longer
puts it back. Delegated autonomy is honoured when the file is found and every project is
`gated` when it is not, so a bundle that had `rm`'d it was making a decision — and one that
had it was making the other. Decide once, then turn it on by installing the companion that
ships it: `/plugin install loopd-yolo@loopd`. Nothing recreates anything for you.

**A v1-era bundle carrying a REAL `AUTONOMY.md` at its root keeps working unchanged, and
the root copy WINS.** `resolve-autonomy.sh` reads the bundle root first and only then an
installed companion, so such a bundle behaves byte for byte as it did — with or without
`loopd-yolo` installed, and a companion can never override what it says. There is
nothing to migrate: leave the file where it is. Turning it off there means deleting **that
file**, because uninstalling the companion alone would not reach it.
([autonomy.md](autonomy.md#the-onoff-switch-is-one-plugin))

---

## The state directory is `.loopd` (3.3.0 onward)

**A plugin at 3.3.0 or later reads a bundle's state from `.loopd` and does not resolve the
old `.ai-bridge` directory.** `/loopd:init` on a bundle that still has it exits 2, writes
nothing, and prints the two commands to run from the bundle root:

```
bash <plugin>/scripts/migrate-bundle.sh --layout-only           # report what would move
bash <plugin>/scripts/migrate-bundle.sh --layout-only --apply   # move it, and commit
```

| | |
|---|---|
| **Before** | commit or stash: the migration refuses a dirty tracked tree and a live `.tick-lock` |
| **What moves** | the directory, in one `git mv`, with its ignore lines, the status-line pin and any knowledge mount's `core.worktree`; a pre-3.0 bundle's root files move into it first. Then it commits |
| **What does not** | any document. `--layout-only` runs only the two directory steps and prints `content: NOT CHECKED`; the plain run also repairs documents ([schema.md § Keeping a bundle valid](schema.md#keeping-a-bundle-valid)) |
| **A mounted `knowledge/`** | skipped by the content pass in every mode and reported once: *lives in a knowledge mount; repair it from that repository, not here* |
| **Both directories exist** | an earlier stamp made an empty `.loopd` beside the old one. Move it aside first — the migration stops while it is there. The session banner and `/loopd:welcome check` name this state too |
| **Check it** | `test -d .loopd && ! test -e .ai-bridge`, then `/loopd:init` runs as usual |

---

## Uninstalling the old symlink-era install

| Path | What removes the old command links |
|---|---|
| **A** | `/loopd:init`'s **conversion sweep**. It removes a symlink outside `repos/` when it dangles, points through a `/symlink/` path, or resolves into a template checkout — so exactly the retired commands and the rest of the machinery, and nothing of yours. One `retire <path> — <reason>` line each ([operations.md § 2](operations.md#2-retiring-content-swept-vs-reported)) |
| **B** | you delete the whole old folder, so there is nothing to sweep |

**The sweep is not cosmetic and it is not optional.** Without it, the dangling files still
register and the bundle keeps offering commands that fail — and a link that still
*resolves* is worse, because it silently pins the bundle to one stale checkout.

Deleting the old folder — last, and only once step 6 passed:

```bash
# optional: detach the derived views first, so what is left is only your content
#   bash <plugin>/scripts/init-bundle.sh --uninstall ~/workspace/<group>/_ai-bridge-<group>
rm -rf ~/workspace/<group>/_ai-bridge-<group>
```

`--uninstall` removes only the symlinks it created; real files, `*.bak.*` backups and
your content are left alone. It is not required before the delete — it is there so you
can look at what remains and confirm every last file of it is yours.

**The plugin is not part of any of this.** It is per machine and every instance on that
machine uses it, so do not uninstall `loopd`. Uninstall `ai-bridge-v2` if it is still
listed. The optional `~/.claude` config layer is its own separate thing:
`init-bundle.sh --config --uninstall` ([README § Uninstall](../README.md#uninstall)).
