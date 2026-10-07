# loopd-mod-usage — the usage-recording companion (a mod)

A [mod](https://code.claude.com/docs/en/plugins/mods/overview): a hooks module Claude Code
runs **inside** every session that loads it. This one records what the session spent and
nothing else.

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-mod-usage@loopd
```

Uninstall it (`/plugin` → Installed) and `session-usage.sh` reads the transcript as it
did before, with **no other edits** anywhere. Absence is the safe behaviour, never an error.

## What it does

After every turn it writes one record to the plugin store, keyed by the session:

| Key | Value |
|---|---|
| `loopd.usage.<session id>` | `{ input, output, cacheRead, cacheWrite, requests, turns, ms, model, tools: { <tool name>: <calls> }, toolErrors }` — tokens from each request's usage (`turn.step`), or the turn's totals when a turn's requests carried none; `ms` is the sum of `durationMs` over turns; `toolErrors` counts tool results with `isError` |
| `loopd.usage.<session id>.ended` | `true`, written at `session.end` |

Core's `plugin/scripts/session-usage.sh <session-id>` reads that record **first** and prints
the same `usage tokens=N tools=N ms=N cached=N errors=N by=Name:N,…` line it prints from a
transcript (`tokens` = input + cacheWrite + output; `cached` = cacheRead; `tools` = the sum
over names; `errors` = toolErrors; `by` = the top five names by count, then name). No
record, two records, a corrupt store file, a non-number anywhere or a tool name outside the
line's grammar, and it reads the transcript exactly as before. The one visible thing: in an interactive session,
one dim `● loopd-mod-usage:` line at start saying it is recording. A `claude -p` or
`claude --bg` session gets no line.

## What it never does

A mod runs with your permissions in every session on the machine, so the lines it does not
cross are the whole design, and `tests/mods.test.sh` in `cbmono/loopd` asserts each on the
source and on what `claude plugin validate` reads out of it:

- **No model call** — nothing here spends the plan.
- **No permission decision** — it never answers the permission event; every hook hands the
  event on unchanged.
- **No process, no network, no file** — the plugin store is the only thing it writes.
- **No store write without a session id** — an unattributable number is worse than none.

## Where the store lives

Claude Code keeps one JSON file per plugin under
`${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/store/`, named `<plugin name>_<marketplace>-<hash>.json`,
a flat object of key → value (measured on the built-in `cc-plugin-diff_builtin-….json`;
this plugin's file is `loopd-mod-usage_loopd-….json` once it has written). The 4 MiB store
limit is the vendor's; a record here is a few hundred bytes.

## Tested with

Claude Code **2.1.293** (`claude --version`, 2026-10-08). Mods need v2.1.287 or later. The
events and methods can change between releases, so after a CLI update run, from this
directory:

```
claude plugin validate . --strict
claude plugin test
```

`docs/spikes/mods-in-background-sessions.md` in `cbmono/loopd` records what was and was not
measured about mods in `claude -p` and `claude --bg` sessions — the shape loopd's role agents
run in — and the probe that measures it.

## Delete it

`/plugin uninstall loopd-mod-usage@loopd`, or remove the directory from a checkout. The
contract this plugin is an instance of — how a companion registers, where core looks, and
the rule that a companion ADDS behaviour and never removes a core gate — is in
[`../plugin/README.md`](../plugin/README.md) → "Companion plugins".
