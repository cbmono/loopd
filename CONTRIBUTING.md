# Contributing to loopd

How to change loopd itself: the version, the rules for each part of the repo, and the tests.
Using loopd rather than changing it? The [README](README.md) and
[docs/getting-started.md](docs/getting-started.md) are for you.

---

## Changing this repo

Read [docs/conventions.md](docs/conventions.md) first. It records the design invariants and
what went wrong to produce each one — the reasoning is the asset, so relocate it rather
than shortening it.

- Machinery goes in `plugin/`. Keep it **generic**: no org, repo, path, team or channel literals — those belong in a bundle's `instance.config.json` / `CLAUDE.md`.
- Starting content goes in `plugin/seed/`. Retiring a seed file needs an entry in [`RETIRED`](plugin/RETIRED) in the same commit.
- Tests live in `tests/`, never under `plugin/` — everything there ships to every machine that installs the plugin.
- **Adding a pin to the plugin's skill contract? Two harnesses, and which one is not a judgement call:**

  | The property you want to hold | Where it goes |
  |---|---|
  | Something is **written** in a skill file — frontmatter, a named non-action, a phrase the contract turns on | [`tests/plugin-skills.test.sh`](tests/plugin-skills.test.sh) |
  | Something is **true of what the model does** with the plugin loaded — a skill it must not reach for, a tool order, a refusal | a case under [`plugin/evals/`](plugin/evals/README.md) |
  | The eval suite's own shape, and running it | [`tests/plugin-eval.test.sh`](tests/plugin-eval.test.sh) |

  Prefer the first: it is free, offline and runs on every machine. The eval costs real model
  runs and needs `claude plugin eval`, ungated on 2.1.270 and **early access** on builds up to
  2.1.263 — where it is unavailable the harness prints
  `skipped: plugin eval unavailable — <why>` rather than passing quietly.
  [→](plugin/evals/README.md)
- Run `tests/run.sh --changed` while you work and `tests/run.sh --all` once before you push. The required check **`harness suite`** calls the same script (`tests/run.sh --ci`): the full suite by default, and for a PR whose every changed path is under `plugin/` or `.claude-plugin/` a selected set of plugin harnesses instead; `main`'s branch protection requires it and is strict about it — so be up to date with `main`. [→](docs/conventions.md#repo-conventions-that-are-not-invariants)
- Adding to the harness itself? Measure what your diff adds under `plugin/**/*.sh`, and at or above ~150 lines ask in the PR body instead of assuming. [→](docs/conventions.md#repo-conventions-that-are-not-invariants)
- The user-facing docs have a drift check of their own: [`tests/docs-drift.test.sh`](tests/docs-drift.test.sh) fails when the README's team or commands fall out of step with `plugin/`, or a link in the README, `docs/getting-started.md`, `docs/reference.md` or this file stops resolving.
- This repo is **public**. Placeholders must be verified unclaimed: `example-user-007` / `example-user-008` and `example.com`.

Agent-facing rules are in [`CLAUDE.md`](CLAUDE.md) and [`.claude/rules/`](.claude/rules).

---

## Versioning and drift

The version lives at this root — [`VERSION`](VERSION), one line, no extension — and is
MIRRORED byte-for-byte into [`plugin/VERSION`](plugin/VERSION), because an installed plugin
has no checkout around it to read the root copy from. `cat VERSION` reads it;
`tests/template-version.test.sh` fails if the two disagree, so they only ever move together.
Nothing parses prose for it and there is no `package.json` and no tag. **There is no release
process here and none is wanted.**

**There are no release notes.** No per-version note is written; the git history and each
PR's description are the record of what changed and why. (`docs/releases/` held one note per
version until it was retired; the notes are in git history.)

**A change to `core` is bumped for AFTER it merges, by you, on `main`.** `core` is
`plugin/` (which carries `seed/`, `RETIRED` and the shipped `VERSION`), and it is exactly
what the path-scoped rule files ([`.claude/rules/machinery.md`](.claude/rules/machinery.md),
[`.claude/rules/installer.md`](.claude/rules/installer.md)) already govern, so an agent
editing one of those paths meets the rule as it opens the file. A PR touching only `docs/`,
`tests/`, `.claude/`, `.github/` or the root `scripts/` needs no bump at all. **No PR ever
edits the five places the number lives in** — merge it, then run
[`plugin/scripts/release-bump.sh`](plugin/scripts/release-bump.sh) `<major|minor|patch>` on `main`
and push the one commit it makes. That is what lets two core PRs be open at once: while
each carried its own bump they conflicted on the same five files and had to land one at a
time, at a full suite run each. The procedure, and the eval read that comes before it:
[docs/operations.md → Cutting a release](docs/operations.md#cutting-a-release-merge-bump-push).

Rough scale, enough to act on without a policy document: **patch** for a fix inside
behaviour that already shipped, **minor** for a new capability or a new file under
`plugin/`, **major** for anything a bundle has to be repaired by hand to survive.

**Why the number matters more than a label.** A bundle consumes nothing from this checkout
— the machinery ships in the plugin, replaced whole on every update — but `plugin/seed/`
content is copied into a bundle once, ever, so a seed edit reaches a stamped bundle only
through `/loopd:init`. That gap has cost real time: two hooks merged and sat inert in every
bundle for a week, back when a stamp was the only route.

So the session banner prints one line — and only one, and only sometimes. The two numbers
below are an example, not this repo's current pair; the only place the current one is
written down is [`VERSION`](VERSION):

```text
⬆️  TEMPLATE UPDATE (loopd) — this machine runs 0.9.1, origin/main has 0.11.0
```

`check-template-version.sh` decides it, and **silence is its normal answer**. Equal or
ahead prints nothing; so do offline, unauthenticated, no remote-tracking ref, a missing
`VERSION` on either side, and a version it cannot parse — a false "you are behind" would
train you to ignore the true one. On a plugin install it fetches the marketplace clone with
a two-second cap and caches the answer for six hours, so a session is never blocked on the
network and most sessions make no call at all; `--fetch` forces past the cache. Against a
checkout of this repo it fetches nothing unless you pass `--fetch`.

What it cannot see: a checkout parked on an old commit whose `VERSION` happens to match the
remote's. The number moves when the bump convention says it moves, so this catches drift
**across a bump** and nothing finer.
