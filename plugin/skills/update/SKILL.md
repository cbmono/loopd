---
name: update
description: Update this plugin in one command — refresh the marketplace, update every plugin of it installed at user scope, re-stamp the current bundle with the NEW version's init, then tell you to run /reload-plugins.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/update-plugin.sh), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/update-plugin.sh --verbose), Bash(pwd)
---

Run this from the bundle root, and **relay what it prints** — it is already the short form:

```
${CLAUDE_PLUGIN_ROOT}/scripts/update-plugin.sh
```

By default it prints the version lines, init's summary (one `init:` count line, each
`CONFLICT` or `UNKNOWN` seed file as one line with its `diff -u` command, any `needs`, note,
warning or failing check) and the reload step. Add `--verbose` only when the human asks for
the full report: every step, every other-scope install and init's whole output. Every
decision lives in the script, so a terminal and this session get the same answer:

| Step | What it does |
|---|---|
| 1 | `claude plugin marketplace update <marketplace>`. A failure stops here: nothing updated, nothing stamped |
| 2 | `claude plugin update <p>@<marketplace> -s user` for each plugin of that marketplace **already installed at user scope**, one line each: `<p> <old> → <new>` or `<p> up to date`. A plugin you never installed stays uninstalled; project, local and managed installs are never touched, and listed only with `--verbose`; this bundle's own draws a `warn` when it is older than user scope |
| 3 | In a bundle root, runs the **new** version's `init-bundle.sh` — the path comes from the registry's user-scope entry, never from this session's plugin root, which is still the old version. It hands init `--verbose` only when it was given it. Anywhere else (a subdirectory too) it prints one skip line |
| 4 | Ends with `Now run /reload-plugins` — it registers a newly added skill too, no restart |

A skill cannot run `/reload-plugins`; the human types it.

## What the init step says

- **A `needs` line or the spawn-grant note** (`init writes no \`claude --bg\` grant without
  your yes`): relay it as **after `/reload-plugins`, run `/loopd:init <flag>`** — the flag
  the `needs` line names, or `--spawn-grant` for the grant. Never re-run
  `${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh` from here: it is the old version until
  the reload. Never pass a flag on the human's behalf.
- `stale`, `CONFLICT`, `UNKNOWN` and a vanished `AUTONOMY.md`: the same non-actions as
  `/loopd:init` → "What you must not do with the output".

## Exit status

0 done · 1 a plugin update failed (the others and init still ran) · 2 the marketplace update
failed, or the registry had no usable entry (no init ran) · anything else is init's own.
