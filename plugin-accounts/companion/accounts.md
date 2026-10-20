# accounts — the capability file

Present ⇒ per-bundle account switching exists on this machine. Absent ⇒ core prints no
account line and switches nothing. `plugin/scripts/resolve-account.sh` reads this file's
**presence** and nothing else.

## The mechanism, and why this one

**One `CLAUDE_CONFIG_DIR` per account.** Measured on **Claude Code 2.1.263**, 2026-09-06:

| Probe | Result |
|---|---|
| `claude --help`, `claude auth --help` | `auth` offers `login`, `logout`, `status` only — **no** account or profile switch, and no `--account`/`--profile` flag anywhere in the CLI |
| `CLAUDE_CONFIG_DIR=$(mktemp -d) claude auth status --json` | `loggedIn: false`, while the default config dir reports `loggedIn: true` with an `orgName` |
| `CLAUDE_CONFIG_DIR=$HOME/.claude claude -p …` | `Not logged in · Please run /login` — on macOS the OAuth credential lives in the **Keychain** and is read only when the variable is unset |
| `AI_BRIDGE_ACCOUNT=probe123 claude -p '…env…'` | the variable reaches a session subprocess, so a launcher can label the session for the banner |

So there is no native switch to prefer, and setting the variable is a **complete**
isolation: it scopes auth, plugins, settings, MCP servers and projects, not auth alone.
That is the cost of the mechanism — each account directory needs its own one-time
`claude auth login` **and** its own `/plugin install loopd@loopd`.

## Where things live

| | |
|---|---|
| The label | `"account": "<label>"` in the bundle's `instance.config.json` — a label, never a secret |
| The config dir | `${LOOPD_ACCOUNTS_HOME:-~/.claude-accounts}/<label>` — **always outside the bundle**; the launcher refuses a directory inside one. `AI_BRIDGE_ACCOUNTS_HOME`, the pre-rename name, is still read (with a note) while the new one is unset |
| The credential | wherever Claude Code puts it for that directory. **Never in a bundle repo**, and nothing here ever reads or copies one |
| The launcher | `bin/loopd-claude`, run from a bundle root. `bin/ai-bridge-claude` is its deprecated pre-rename name: it notes the rename and runs `loopd-claude` |

## The seam for another backend

The launcher `exec`s `claude` after exporting `CLAUDE_CONFIG_DIR` and `LOOPD_ACCOUNT`, plus
`AI_BRIDGE_ACCOUNT` with the same value for one release — the name a pre-rename core reads.
A companion that swaps the backend replaces the `exec` line and reuses everything above it
— it is not built here.
