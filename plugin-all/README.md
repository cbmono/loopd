# loopd-all — every loopd plugin in one install

A **bundle**: a plugin whose manifest is a `name` and a `dependencies` list and nothing
else. Installing it installs every plugin it names from this marketplace — the control
panel, the autonomy companion and the three mods — so a new machine runs one command
instead of five.

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-all@loopd
```

or, from a shell, `claude plugin install loopd-all@loopd`. Then restart Claude Code once.

The core-only install, `/plugin install loopd@loopd`, is still the **minimal** install and
is not going anywhere: it is what you want on a machine that must stay gated (no
`loopd-yolo`) or quiet (no mods). This bundle is the other default — everything, in one line.

## What it ships

Nothing of its own. No hooks, no skills, no agents, no commands, no `companion/` file:
`claude plugin validate --strict` passes on a manifest that declares only metadata and
dependencies, which the Claude Code docs call a bundle ("A plugin manifest needs only
`name`, so this is a valid plugin, and installing it installs every dependency"). Core
reads its presence nowhere.

| Dependency | What it is | Why it is in the bundle |
|---|---|---|
| `loopd` | the control panel: every `/loopd:*` command, the two `PreToolUse` enforcement hooks, the role agents | the thing everything else is a companion **of** |
| `loopd-yolo` | `companion/AUTONOMY.md`, the file that makes a project's `autonomy: yolo` mean something | the one companion a running loop is usually installed for; per project it is still opt-in (`autonomy:` defaults to `gated`), and the machine-wide off switch is below |
| `loopd-mod-usage` | a mod that records each session's usage in the plugin store | observe-only, no cost, and `session-usage.sh` reads it before the transcript |
| `loopd-mod-pane` | a mod whose `/board` draws this bundle's board in a pane | observe-only, reads core's snapshot, never the bundle |
| `loopd-mod-signal` | a mod that tells the PM session a role agent's turn is over | observe-only; orders step 4's sweep and decides nothing |

**Deliberately not in the list — `loopd-accounts` and `loopd-llm`.** Both are
per-**machine** decisions their own READMEs make the human take by hand: `loopd-accounts`
exists for *one human, two Claude accounts*, and its launcher is only useful once you have
run `claude auth login` under a second `CLAUDE_CONFIG_DIR`; `loopd-llm` is a **backend
substitution** — every prompt and file read of that session leaves for a third party — and
is opt-in per machine through `allowSubstituteBackend` in the gitignored
`instance.config.local.json`, refusing without it. A default install must not put either
launcher on a machine whose owner never asked for a second account or a second vendor.
Install them one at a time, as their READMEs say.

## Why this is a separate plugin and not `dependencies` on `loopd`

The docs define `dependencies` as "plugins that must be **enabled** for this one to work",
and a dependent whose dependency is disabled is itself disabled at the next plugin load.
Put the list on `loopd` and disabling one mod would disable the loop — every command, both
enforcement hooks, the agents. Put it on an **empty** plugin and the only thing a disabled
dependency can take down is the empty plugin: `loopd-all` goes grey in `/plugin`, and
`loopd` — which depends on nothing — keeps running exactly as before. That asymmetry is
the whole design, and it is why this directory must stay component-free: a hook or a
skill added here would be the first thing lost when a human turns a mod off.

## How a new mod reaches everyone

1. Add its name to `dependencies` in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json).
   Bump nothing in the PR — the merger moves the version on `main` afterwards
   (`CLAUDE.md` → "A change to `core` carries NO version bump").
2. Each machine then runs `claude plugin update loopd-all`, then `/reload-plugins` in an
   open session, and the new dependency is installed. The marketplace does not auto-update
   by default, so until someone turns that on this is a manual step per machine, exactly
   as it is for a core update.

## How to turn one plugin off, and keep the rest

| You want to | Do | What happens to the others |
|---|---|---|
| stop a **mod** | `/plugin` → Installed → that mod → **disable** (or uninstall) | its hooks stop loading; `loopd` keeps running; `loopd-all` is reported as having a disabled dependency and goes grey — it ships nothing, so nothing is lost |
| go back to **gated** everywhere on this machine | `/plugin` → Installed → `loopd-yolo` → **uninstall** — not disable | `resolve-autonomy.sh` reads `installed_plugins.json`, the list of what is **installed**, and a plugin disabled from `/plugin` is still on that list. Disable leaves delegated autonomy armed; uninstall is the off switch, and `commit-as.sh`'s promotion guard reads the same lookup |
| stop everything | uninstall `loopd-all`, then `claude plugin prune` | `prune` removes the dependencies nothing else needs; `loopd` is one of them unless you installed it yourself first |

Uninstalling the bundle alone removes nothing it installed: the dependencies stay as
ordinary installed plugins until `claude plugin prune`. That is the host's behaviour, not
this plugin's, and it is the right one — a bundle is a shortcut for installing, not a
grip on what you may keep.

## Tested with

Claude Code **2.1.293** (`claude --version`, 2026-10-10): `claude plugin validate . --strict`
passes on this directory, and `claude plugin install -y loopd-all@loopd` against this
checkout added as a **local-path marketplace** into an empty `CLAUDE_CONFIG_DIR` printed
`+ 5 dependencies: loopd, loopd-yolo, loopd-mod-usage, loopd-mod-pane, loopd-mod-signal`,
all six enabled in `claude plugin list` and all six in `installed_plugins.json`. Not
measured: the same install from the **remote** marketplace (exercisable only once the entry
is on `main`), and the disable behaviour — what the docs say about a disabled dependency
disabling its dependent is stated for a `--plugin-dir` copy and generalised here from the
`dependencies` field's definition ("plugins that must be enabled for this one to work").
After a CLI update run, from this directory:

```
claude plugin validate . --strict
```

Versioning follows every companion's rule (`plugin/README.md` → "How a companion is
versioned"): it tracks core's MAJOR, and `release-bump.sh major` moves it with the rest.
