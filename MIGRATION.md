# Migrating

## 2026-10-28 — two plugins: the mods are core, seven entries retired

The marketplace now lists exactly two plugins, `loopd` and `loopd-yolo`. The three mods live
**in core** as `plugin/hooks/register.ts`, each a switch in `/config` (the plugin's
`userConfig`: `usage`, `pane` + `paneMode`, `signal` — all on by default, off registers
nothing). Everything else is retired, so on **each machine**:

```text
/plugin update loopd@loopd
/plugin uninstall loopd-mod-usage@loopd
/plugin uninstall loopd-mod-pane@loopd
/plugin uninstall loopd-mod-signal@loopd
/plugin uninstall loopd-all@loopd
/plugin uninstall ai-bridge@loopd
/plugin uninstall loopd-accounts@loopd
/plugin uninstall loopd-llm@loopd
```

Restart Claude Code. A name you never installed errors harmlessly; `/plugin` → Installed
shows what is there.

| Retired | Why | What replaces it |
|---|---|---|
| `loopd-mod-usage`, `loopd-mod-pane`, `loopd-mod-signal` | a mod observes, records or draws and removes no gate, so the companion shape bought nothing a switch does not | core — `/config` → `usage`, `pane` (`paneMode`), `signal`; `plugin/hooks/MODS.md`. The store keys are unchanged (`loopd.usage.*`, `loopd.pm.*`, `loopd.signal.*`); the store **file** is now core's own, `loopd_loopd-….json`, so a session still running the old mod is read from its transcript — the same fallback as before |
| `loopd-all` | with the mods in core it would bundle only core and `yolo`, and a one-command install that includes `yolo` makes delegated autonomy a default instead of a choice — the reason `yolo` is separate | `/plugin install loopd@loopd`, and `loopd-yolo@loopd` only where you mean it |
| `ai-bridge` (the rename alias) | kept for one release since 3.0.0 (2026-10-01) | the section below, if you still run `/ai-bridge:*` |
| `loopd-accounts`, `loopd-llm` | verified 2026-10-28: installed nowhere, no bundle sets `account`, no `~/.claude-accounts`, no launcher on any PATH | nothing — core already behaved as if they were absent. `resolve-account.sh`, the banner's account row, the seed's `account` key and SCHEMA's `allowSubstituteBackend` row are gone; an `account: null` left in an older bundle's `instance.config.json` is inert. The banner's `NOT ANTHROPIC` warning still reads `ANTHROPIC_BASE_URL` from its own environment |

Nothing in a bundle changes. Re-pin a `permissions.allow` rule or a shell alias that named
`cache/*/loopd-accounts/*` or `cache/*/loopd-llm/*` by deleting it.

## 2026-10-01 — from ai-bridge to loopd

The plugin, its marketplace, its companions and this repository are renamed `loopd`
(loopd/task-007) and released as 3.0.0 (task-008). Until that release reaches your
machine, keep running `/ai-bridge:*`.

Two parts, in order: the owner renames the repository once; then every machine and every
bundle moves over.

## 1. The owner's runbook — once, for the repository

| # | Step | Why here |
|---|---|---|
| 1 | Merge the prep PR (name derived, harnesses parametrised) | the plugin keeps working under `ai-bridge` |
| 2 | **Do not enable GitHub Pages under the old name.** Enable it at step 7 | GitHub redirects everything on a rename **except project-site URLs** — see below |
| 3 | Merge the flip PR | manifest, slugs and namespaces move together |
| 4 | `gh repo rename loopd --repo cbmono/ai-bridge`, right after the merge | the owner's step — no agent renames the repository; `cbmono/loopd` resolves from here |
| 5 | `plugin/scripts/release-bump.sh major` on `main`, push | 3.0.0 is what `claude plugin update` offers |
| 6 | `git remote set-url origin https://github.com/cbmono/loopd.git` in each clone | the old URL redirects, but only until a repo reuses the name |
| 7 | Settings → Pages → deploy from `main`, `/docs` | the site appears at `https://cbmono.github.io/loopd/` |

**Never create a new repository called `ai-bridge` afterwards.** GitHub drops every
redirect from the old name the moment one exists.

**The Pages URL is not redirected.** GitHub's
[renaming a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository)
page: *"all existing information, with the exception of project site URLs, is
automatically redirected to the new name"*. Checked 2026-09-30: Pages is **not enabled**
on `cbmono/ai-bridge` (`gh api repos/cbmono/ai-bridge/pages` → 404,
`https://cbmono.github.io/ai-bridge/` → 404), and no tracked file links that URL. So
nothing breaks, provided step 2 holds: a site first published at `/loopd/` never had an
old URL to lose.

## 2. Every machine, then every bundle on it

```text
/plugin marketplace add cbmono/loopd
/plugin install loopd@loopd
```

Restart Claude Code. Then, in **each** bundle:

```text
/loopd:init <bundle-path>
```

**`init` seeds only what is absent and never overwrites**, so three name-scoped copies a
bundle already holds are yours to edit. Each names the marketplace cache, whose path is
**name- and version-scoped**: `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.

| File | Old | New |
|---|---|---|
| `CLAUDE.md` — the scripts-path line | `ls -d ~/.claude/plugins/cache/*/ai-bridge/*/scripts \| sort -V \| tail -1` | `ls -d ~/.claude/plugins/cache/*/loopd/*/scripts \| sort -V \| tail -1` |
| `CLAUDE.md` — every command and dispatch name | `/ai-bridge:<cmd>`, `ai-bridge:<role>` | `/loopd:<cmd>`, `loopd:<role>` — a bare role name does not resolve |
| `.claude/ai-bridge-statusline.sh` | `"$cache"/*/ai-bridge/*/scripts/status-line.sh` | `"$cache"/*/loopd/*/scripts/status-line.sh` |
| `.claude/settings.local.json` | `Bash(…/plugins/cache/ai-bridge/ai-bridge/*/scripts/*)` | `/loopd:init` adds the `loopd/loopd` rule; delete the old pair |

Find them with `grep -rn 'ai-bridge[:@]\|/ai-bridge/' CLAUDE.md .claude/`. Commit the edit.

**Only then uninstall the old plugin:**

```text
/plugin uninstall ai-bridge@ai-bridge
/plugin marketplace remove ai-bridge
```

Companions move with core, because a companion counts only when it comes from core's own
marketplace:

| Old | New |
|---|---|
| `ai-bridge-yolo@ai-bridge` | `loopd-yolo@loopd` |
| `ai-bridge-accounts@ai-bridge` | `loopd-accounts@loopd` — its launcher is now `bin/loopd-claude`; re-point your alias at `cache/*/loopd-accounts/*/bin/loopd-claude` (the old `bin/ai-bridge-claude` still runs it, with a deprecation note) |
| `ai-bridge-llm@ai-bridge` | `loopd-llm@loopd` — likewise `bin/loopd-deepseek` under `cache/*/loopd-llm/*` (`bin/ai-bridge-deepseek` is the deprecated alias) |

Uninstall each old one and install the new one. Until you do, `yolo` projects read as
`gated` and no account line prints, which is the safe direction.

**The `ai-bridge` entry left in the marketplace is an alias, for one release.** Updating
`ai-bridge@ai-bridge` installs a stub with no hooks and no agents whose one skill,
`/ai-bridge:renamed`, prints these steps. It keeps nothing working; it tells you to move.

Edit first, uninstall second. The cache keeps old versions on disk, so an unedited
scripts-path line may keep resolving to stale `ai-bridge` scripts instead of failing.

**Done when** the grep above prints nothing in every bundle and `/loopd:welcome` shows the
banner.

## The names the plugin itself still carried

A later sweep renamed what the plugin wrote or read under the old name. You run nothing:

| Old | New | What happens to the old one |
|---|---|---|
| `# >>> ai-bridge index ignore >>>` / `# <<< ai-bridge index ignore <<<` in `.gitignore` | `# >>> loopd index ignore >>>` / `# <<< loopd index ignore <<<` | `/loopd:init` renames the pair in place, once; a duplicate block or an orphan END line goes with it. Commit the `.gitignore` change |
| `bin/ai-bridge-claude`, `bin/ai-bridge-deepseek` | `bin/loopd-claude`, `bin/loopd-deepseek` | a deprecated alias: it prints a note and runs the new launcher |
| `AI_BRIDGE_ACCOUNTS_HOME`, `AI_BRIDGE_ACCOUNT` | `LOOPD_ACCOUNTS_HOME`, `LOOPD_ACCOUNT` | still read while the new one is unset; the launcher notes it |
| `AI_BRIDGE_KB_TIMEOUT`, `AI_BRIDGE_INIT_PASS` | `LOOPD_KB_TIMEOUT`, `LOOPD_INIT_PASS` | still read while the new one is unset |
| board snapshot `_schema` `ai-bridge board snapshot v1` | `loopd board snapshot v1` | nothing reads it; the other-owners cache under the old name is rebuilt once |

**On a bundle shared by two clones, update the plugin on every clone before you commit
the renamed `.gitignore`.** An older `/loopd:init` does not know the `loopd` pair, splices
its own back in, and the two versions then flip the tracked file on every stamp. No rule is
lost either way; the churn stops once every clone runs this version.
