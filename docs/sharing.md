# Sharing one bundle — the front door for multi-person use

**Start here for anything with more than one human in it.** One organisation has **one**
OKF knowledge bundle: a single repo, cloned once per person, each clone running its own
`/loopd:dispatch` loop. Everyone sees one set of projects and one knowledge base, and
anyone can hand a project or a single task across.

## Step 0 — the bundle is the org's repo

```sh
/loopd:init ~/workspace/<group>/_loopd-<group> --org <org>
```

The **first** person runs it and gets `<org>/<org>-okf` created private, seeded and
pushed. **Everyone after them runs the same command** and gets a clone of it. The name is
`<org>-okf` because the repo *is* the org's Open Knowledge Format bundle (`--name <repo>`
overrides it).

| It says | What happened |
|---|---|
| `create <org>/<org>-okf (private)` | you are an org admin; this is the org's bundle |
| `bundle <you>/<org>-okf is under YOUR account` | creating it in the org was refused — **the normal path when you are not an admin**. The stamp and push are identical; it prints the `gh repo transfer` line for an admin to run later |
| `clone <org>/<org>-okf -> …` | it was already there |

Two refusals, and both are the point. It **will not create** until your access to `<org>`
is established (`gh api orgs/<org>/memberships/<you>`), because the host answers the same
404 for *absent* and for *private and invisible to you* — and seeding a fresh bundle over
the org's real one is not recoverable. And it **refuses by name** when `<org>/<name>`
exists but is not a bundle (no `instance.config.json`, no `SCHEMA.md`): pick another
`--name`.

The rest of this page is what the humans do around that repo.

**The board is not shared either — each clone renders its own, and that costs nothing.**
There is no published page to share: every `/loopd:dispatch` tick renders
`.board-live/board.html`
on the machine it runs on. Each human's own projects come from their own snapshot, and
every *other* owner's is a named, collapsed section read from the tracked task documents at
their current git `HEAD`. **Git is what two clones genuinely share**, which is why this
half survived deleting the publish path intact: the cross-owner view never came from a
shared page. (It briefly came from one per human. Publishing was account-scoped — only the
owning account could ever update a page — so a shared URL gave a bundle one working board
and one publish step that failed silently forever; then the page vanished from under its
own owner at the next login, and the whole path was deleted.)

**All of it is a no-op on a single-human instance.** Absence means today's behaviour at
every step — never an error.

**The second human's own first hour — install, the skills, the two gates — is
[first-hour.md](first-hour.md).** This page is only the shared-instance half that goes on
top of it: steps 1, 2 and 5 of the table below are the same steps they read there.

---

## The short way

`scripts/add-second-human.sh <instance> [--apply]` does the shared, tracked half of this
— the `people` map and `defaultOwner` — and prints the commands the second human runs on
their own machine. Report-only by default. It validates the login and address before
writing, parses the config back before claiming success, and refuses if `python3` is
absent rather than editing JSON line-wise.

It cannot do their half: their `ownerGithubUser` and their absolute paths live in a
gitignored file on their machine, which `/loopd:init` writes there.

## Do it in this order

**The second human's own machine is two commands**, and the last one clones the bundle
*and* writes their per-machine config for them:

```sh
# in Claude Code, once per machine:
#   /plugin marketplace add cbmono/loopd
#   /plugin install loopd@loopd
/loopd:init ~/workspace/<group>/_loopd-<group> --org <org>
```

They get the clone with the **tracked** config — `people`, `defaultOwner`, `org` — already
in it, and their **own** gitignored `instance.config.local.json`, which nobody else's clone
can carry because it is never committed.

**Already cloned it by hand?** Then it is three commands and the stamp is the same one:

```sh
git clone <bundle-remote> _loopd-<group>
cd _loopd-<group>
/loopd:init .
```

`/loopd:init` writes the gitignored `instance.config.local.json` itself when the clone
has none — deriving what the machine already knows, naming what it cannot, and guessing
nothing:

| Value | Derived from | When it cannot |
|---|---|---|
| `ownerGithubUser` | `gh api user`, else `git config github.user` | it prints `needs ownerGithubUser`; re-run with `--owner <login>` |
| `authorEmail` | the tracked `people[<login>]`, else `git config user.email` | `--email <address>` |
| `reposRoot` | the bundle's parent directory | `--repos-root <absolute path>` |

Two properties to keep in mind. A value the **tracked** config already carries is left
exactly where it is — a derived value never shadows an answer somebody gave — and an
**existing** local file is never rewritten by that step (the normaliser owns its shape).
`worktreeRoot` and `boardInstances` stay optional: absent, they mean `<reposRoot>/_wt` and
this instance alone.

**Since 3.5.0 the stamp also does the three things a second human used to do by hand.**

| | What `/loopd:init` does |
|---|---|
| **The knowledge base** | with `knowledge.repo` in the config and no mount, it seeds no `knowledge/` placeholders and runs `kb-sync.sh mount` itself. Real content in `knowledge/` is refused; a placeholder-only folder from an earlier stamp is named with the `rm` to run, never removed; an unreachable remote is a `warn` plus the `pull` to run later |
| **`authorEmail`** | filled from `people[ownerGithubUser]` into an *existing* local file that lacks it — the one key that step writes there, verified after the write, never overwriting a value |
| **The spawn grant** | at a terminal, when the exact auto-mode rule is absent, it asks `… [Y/n]` (Enter is yes) and writes it to `.claude/settings.local.json`, replacing the stale shapes on the same yes. With no terminal it writes nothing; `--spawn-grant` is the yes relayed from a session ([operations.md § The supported shape](operations.md#the-supported-shape-one-main-thread-auto-mode-always-on)) |

**The shared, tracked half is done once, from either clone:**

| # | Step | Where | Command / value |
|---|---|---|---|
| 1 | Record who is who | either clone | `people` map in `instance.config.json` |
| 2 | Name who owns unowned work | either clone | `defaultOwner` in `instance.config.json` |
| 3 | Turn the nudges on (a clone is not a first stamp) | second clone | `touch AWAITING.md` — `SNAPSHOT.json` is seeded by the stamp itself |
| 4 | Untrack the derived indexes if already committed | either clone | run the `git rm --cached` that `/loopd:init` prints |
| 5 | Assign work | either clone | `owner: <github-login>` on a `project.md` or one `tasks/<id>.md` |

## The config split at a glance

| Key | File | Absent means | Overridable per machine? |
|---|---|---|---|
| `people` (login → commit email) | tracked `instance.config.json` | fall through to `authorEmail` | **No** — both clones must agree |
| `defaultOwner` | tracked `instance.config.json` | unowned work is **every** clone's ⇒ double dispatch | **No** — an override is the disagreement that breaks it |
| `ownerGithubUser` | `instance.config.local.json` | this clone has no configured human; unowned tasks clear, owned ones refuse | **Local only** |
| `authorEmail` | either | fall through to `git config user.email` | Yes |
| `reposRoot` | either | required for dispatch | Yes |
| `worktreeRoot` | either | `<reposRoot>/_wt` | Yes |
| `boardInstances` | either | the board is just this instance | Yes |
| `board` | tracked `instance.config.json` | on: the snapshot is seeded and each tick renders the local page | **No** — one instance, one answer |
| `boardPort` | `instance.config.local.json` **only** | derived from the bundle path, in the 4xxxx band | Per machine — a port is a property of a laptop, and two clones on one machine must not derive the same one |

**No board artifact is shared any more, and that is the point.** The tracked `/board.html`
was the one file two clones contended for — both rendered it from their own snapshot and
pushed it every tick — and it is gone. Each clone now runs `/loopd:board serve` against
its own `.board-live/`, on its own port, and nothing about the board is pushed. Neither
clone loses anything: the cross-owner half of the page was always read from the tracked
task documents at `HEAD`, never from the other clone's page.

The **one** place the overridable set is listed — with what each key means when absent —
is [`SCHEMA.md` → "Per-machine config overrides"](../plugin/seed/SCHEMA.md). Every reader
must honour it.

---

## The reasoning

> Relocated verbatim. This is invariant 13 of
> [docs/conventions.md](conventions.md); it lives here because it is one topic and
> splitting it would leave half the argument on each side.

**A shared instance is three no-ops and one gate, and the gate is on the wrong verb if you get it backwards.**

### (a) `owner` gates DISPATCH, never promotion

`scripts/task-owner.sh` does **two things, and conflating them is the documentation bug review caught twice**: it *resolves* the task's owner — task `owner:` → project `owner:` → tracked **`defaultOwner`** → nobody (unowned) — and then *compares* that owner against `ownerGithubUser`. `ownerGithubUser` answers "who is this clone?" and is **never a source of ownership**; written into the chain as a third owner source it reads as though setting it assigns unowned work, which contradicts the next sentence in every doc that said it. Read from `instance.config.local.json`, else `instance.config.json`; **absent from both ⇒ this clone has no configured human**, so unowned tasks still clear and owned ones refuse), and **exit 0 is the only clearance** — the `required-checks.sh` discipline, for the same reason: exit 1 (someone else's) and exit 2 (unreadable frontmatter, a value that is not a GitHub username, not an instance root) are both refusals, because a clone that cannot prove a task is its own must not hand it to an agent. **No `owner:` anywhere means everything is this clone's**, which is exactly how the three existing single-human instances already behave — this must stay a no-op for them.

Promotion is deliberately *not* gated: `draft → ready` is the human's, and on a shared board it is *either* human's, so gating it would gate the wrong verb — the natural mistake here. **A promotion never runs anything on the promoter's machine — only the owner's loop dispatches — which is the approve/continue split, and it is why the promotion is stamped `by <login>` in the task's `# Notes` rather than inferred from whose tick acted on it (`SCHEMA.md` → "Decisions name the human").** Nor does it gate commits, the KB or `/close-project`. The loop must still **see and report** the other human's tasks (that is the entire point of sharing); only `AWAITING.md` narrows, and its layout is untouched because `session-banner.sh` greps for it literally. Say out loud that **it is not a lock** — it stops two loops dispatching the *same* task, not two loops acting in one tick window on tasks they each own; claiming more would claim a guarantee git cannot make.

The value is a **GitHub username, never an email**: public, stable, and it keeps addresses out of tracked documents, which is the no-PII rule applied to identity. `validate-bundle.sh` deliberately gains **no** `owner` check — it names a person outside the bundle, so nothing there can resolve it, and the shape is judged at dispatch where a refusal has somewhere to go.

**`owner` IS in the board snapshot, and that reverses an earlier rule** which excluded it because the allowlist excludes identity and the board's HTML can be published. It was reversed on 2026-08-26 for one reason: publishing is account-scoped, so each human publishes their own board, and a board that cannot say whose project is whose cannot separate your work from theirs. The concession stays narrow — a *username*, project-level, copied verbatim, with `authorEmail` still excluded — and it is stated in `write-snapshot.sh`'s own header rather than made quietly, so a reader who finds the old rule can tell which is current. `snapshot.test.sh` still fails on any *other* key added without reading why.

**`defaultOwner` is the piece that makes the chain sound, and it must stay tracked-only.** The final "unowned ⇒ every clone's" step is correct on one clone and a **double-dispatch bug** on two: the same task resolves to "mine" on both, so both loops dispatch it — the exact failure ownership exists to prevent. `defaultOwner` names, in the file **both** clones read, who unowned work belongs to, so exactly one matches. That holds only while both clones agree, which is why it is read from the tracked config **only**: a local override is precisely the disagreement that breaks it. It is the one key here deliberately excluded from the override set, and `task-owner.test.sh` pins both halves — one tracked config plus two local `ownerGithubUser` values clears on exactly one clone, and with `defaultOwner` absent it clears on **both** (the hazard, asserted rather than described).

### (b) Identity and machine paths belong in the per-machine file, and shared facts do not

`instance.config.json` is *tracked*, so a single `authorEmail` there authors both humans' commits as one person — destroying the per-agent provenance `commit-as.sh` exists to create. The fix that scales is a **tracked `people` map** (GitHub login → commit email) plus a local file carrying one key, `ownerGithubUser` — the same key the ownership gate already needs — so a second human's setup is one line and they never write their own address down.

**The address is per-INSTANCE, not per-person, and that is the reason the map lives in each instance's own config rather than anywhere shared**: the same login maps to a different address in each group's bundle, because the address says which entity the work belongs to (one person working three clients commits as three addresses). Two consequences to preserve — never *derive* the address from the login (the mapping is a business fact, not a naming convention), and never move it into the local file, because that file says which login this clone *is* and reversing the split would let two clones of one instance disagree about which entity the work belongs to while git history recorded both.

`instance.config.local.json` (gitignored) also covers `authorEmail`, `reposRoot`, `worktreeRoot` and `boardInstances`, which are absolute paths on one machine and so cannot be right for two. **The overridable set is listed in exactly one place — `SCHEMA.md` → "Per-machine config overrides" — and every reader must honour it**: a half-honoured override (the loop dispatching against one `reposRoot` while `link-repos.sh` links from another) is worse than none, because nothing looks broken, so `config-override.test.sh` exercises all four readers *and* keeps a static check that a newly-added reader does the two-file lookup. The split has a rule behind it: **the tracked file holds facts both clones share, the local file holds facts about this machine and this human** — a key that must be *the same* on both clones to be correct (`defaultOwner`, `people`) is never overridable. Absence changes nothing at every step, which is the property every single-human instance depends on.

A derived `<login>@users.noreply.github.com` was **rejected, not skipped**: GitHub requires the ID-prefixed `<id>+<login>@…` form for accounts created after 2017-07-18, so a derived plain address silently fails to link — and the linking behaviour cannot be verified from here without pushing as that account. Real addresses in a private instance repo are fine; **this template is public, so `plugin/seed/instance.config.json` ships placeholder logins VERIFIED UNCLAIMED on github.com (`example-user-007`/`008`, both 404) and addresses at `example.com` (RFC 2606, cannot receive mail), and says so in a `$people` note** — the real map belongs in the instance. **Verify any new placeholder the same way**: `alice`, `bob` and `jane-doe` are all real accounts, so a plausible-looking example names a stranger, and an example is the thing people copy verbatim. Test fixtures follow the same rule, and `commit-as-identity.test.sh` asserts the seed carries no live-account name and no address outside `example.com`.

`/loopd:init` **does** ask for the map on a first stamp now — the tracked table's steps 1 and 2, collected at install time instead of hand-edited afterwards — and on a **clone**, where no first stamp ever happens, it derives this clone's own three values rather than leaving them to be hand-written. The three things that would have broken existing flows are the three guards it carries; they, and the failure the prompt's shape is designed around, are written up in ["The installer asks, once"](#the-installer-asks-once) at the end of this page.

### (c) The derived `index.md` files become gitignored

…and only *untracked* when a human runs the printed command — and the split was decided per file. Root `index.md` and `projects/*/index.md` are rewritten every tick from the documents they summarise, so two loops conflict on them on every push, and nothing is lost — `validate-bundle.sh` never validated them (an earlier version did, and buried 6 real errors under 77 warnings). `knowledge/index.md` stays **tracked**: it changes only when the KB changes rather than every tick, its rows are curated prose, and every agent is told to scan it, so a fresh clone needs it present — do not blanket-ignore `index.md`, which as a bare pattern would swallow it silently. Unlike `AWAITING.md`/`SNAPSHOT.json` these have **no off switch and need none** — they are navigation, re-seeded by `/loopd:init` and rewritten unconditionally.

Two properties worth keeping in mind when you touch it. **A `.gitignore` line is inert for a file git already tracks**, so `/loopd:init` appends the lines (outside the managed block, the `/repos/` pattern, because the seed is copied only when absent) and then *reports* the exact `git rm --cached` — it never untracks anything itself. And **the index lines must NOT go in `plugin/seed/.gitignore`**: that file is an active `.gitignore` inside the template's own `plugin/seed/` directory, so a `/index.md` line there matches `plugin/seed/index.md` and silently stops this repo from tracking its own seed file — measured, it broke the `/loopd:welcome fix` fixture, which re-inits a repo over a copy of `plugin/seed/`. `instance.config.local.json` sits in both places because no seed file is named that. `derived-indexes.test.sh` asserts the trap stays closed, against `git check-ignore --no-index` rather than the pattern text.

Covered by `tests/task-owner.test.sh` (74 assertions, mostly refusals), `commit-as-identity.test.sh` (46), `derived-indexes.test.sh` (26) and `config-override.test.sh` (39).

---

## One thing a second clone does not get automatically

The second clone is **not a first stamp** (`instance.config.json` arrives tracked), so
`/loopd:init` there will **not** create `AWAITING.md`. It says so, with the `touch` to turn
it on. See [conventions.md invariant 3](conventions.md#3-awaitingmd-is-loopds-only-status-artifact-and-it-is-opt-in-by-presence)
for why that creation is gated on the first stamp.

`SNAPSHOT.json` is **not** gated that way and needs no `touch`: the installer seeds it on
any stamp where it is missing, unless `board` is `false`. The board's off switch is that
key, not the file's absence.

Two rules survive the per-machine override and are checked against the *effective*
values: `worktreeRoot` must never sit inside the synced `reposRoot`, and `reposRoot` must
not be the instance directory itself.

**The tick syncs for you; ownership does not.** Since
[#26](https://github.com/cbmono/ai-bridge/pull/26) and
[#27](https://github.com/cbmono/ai-bridge/pull/27), a `/loopd:dispatch` tick pulls
`--rebase`
before it re-derives anything and pushes after it commits, whenever the bundle has a
remote — so neither human runs git by hand for the loop's own work. A dirty tree
**defers** that pull to the end of the tick rather than blocking it, because concurrent
agents share one working tree here and a sibling mid-write is normal.

Two things it deliberately does not do. **A conflict stops the tick** rather than being
auto-resolved — conflicted task documents are contested state between two humans, and a
guessed resolution writes a `status:` nobody chose. And **nothing force-pushes**. Work
*you* commit by hand outside a tick is still yours to push. Ownership stops two loops
dispatching the same task; it was never a lock on pushing.

## Handing off a project with work in flight

`/loopd:handoff <path> <github-login> [context]` moves `owner:` and records why. An
`in-progress` task whose `worktree:`, `branch:` and `session:` live on the old owner's
machine is **named, not handed over silently** — the new owner's clone can neither observe
nor settle that session — with its two routes: the old owner finishes it, or releases it
(`status: ready`, drop `worktree:`/`branch:`/`session:`) and pushes. The skill changes
nothing on that task itself.

---

## The installer asks, once

The tracked roster used to be an eight-step checklist somebody performed
after the stamp. On a **first stamp**, at a terminal, `/loopd:init` now offers to collect
them instead: one line per person (`<github-login> <commit-email>`), yourself first, and
it writes the tracked `people` map, the tracked `defaultOwner`, and this clone's
gitignored `instance.config.local.json`. Nothing about the model above changed — this is
only the collection step it was missing.

**Three guards, each protecting a flow that already worked.**

| Guard | Why it exists |
|---|---|
| Only on the **first stamp** | `/loopd:welcome fix` calls `/loopd:init` on *every* run, including its non-interactive report-only mode, so an unguarded prompt would block every upgrade. It reuses the same `FIRST_STAMP` that gates `AWAITING.md`, rather than inventing a second notion of "new" |
| Only when **stdin is a terminal** | otherwise it skips, leaves the placeholder, and prints the instruction. A prompt nobody can see is a hang, and a hang in a background agent is invisible |
| **Never overwrite** | only the seeded placeholder is ever rewritten, and the local file only when absent. Seeds-if-absent is what makes the installer safe to re-run on a repo full of somebody's work |

**One batched prompt, and the reason is the failure mode rather than the keystrokes.**
Asked person by person, a roster accumulates state across reads: enter one pair, hit
ctrl-C, and the instance is left with a map that resolves for one human and silently
falls through for the other. So the whole roster arrives as one block, and **nothing is
written until a separate confirmation** — an interrupt, EOF, an unreadable line and a
declined confirmation all take the same exit: write nothing, and say which happened. It
is also two reads regardless of team size, which is why `/new-project` batches its
capability questions the same way.

**Two more properties worth keeping if you touch it.** The write is *verified by parsing
it back* — before the temp file lands and again after — and if neither `jq` nor `python3`
is on the machine the prompt is **not offered at all**: a broken `instance.config.json`
breaks every later script in the instance, and this repo has a recorded incident of a
script printing success for a write that never landed
([conventions 9](conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default)).
And **validation is the escaping**: a login must match the GitHub-username rule
`task-owner.sh` already applies and an address a conservative mail shape, so no accepted
value can carry a character that would need escaping into a JSON string. What counts as
"still the placeholder" is deliberately name-independent — an entry whose login equals
the local part of its address at `example.com` — so renaming the seed's example logins
cannot silently switch the prompt off.

Covered by `tests/team-setup.test.sh` (94 assertions, most of them refusals: a non-TTY
stamp, a refresh, an existing value, a real `SIGINT` delivered mid-answer, EOF, a
declined confirmation, unreadable input, and `--config`).
