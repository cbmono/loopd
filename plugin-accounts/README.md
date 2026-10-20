# loopd-accounts — the per-bundle Claude account companion

One human, two Claude accounts, one bundle per organisation. A running session cannot
change account, so the switch is **at launch**: the bundle names its account, the launcher
starts `claude` on it, and core's welcome banner says which one you are on.

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-accounts@loopd
```

Uninstall it and core prints no account line and switches nothing, with **no other edits**
anywhere — a bundle's `account:` key goes inert.

## What it ships

| Path | What core does with it |
|---|---|
| `companion/accounts.md` | The capability file. `resolve-account.sh` reads its presence; the file itself documents the mechanism and the measurement behind it. |
| `bin/loopd-claude` | The launcher **you** run. Core never executes it — the banner only prints its path when it has to tell you to. |
| `bin/ai-bridge-claude` | **Deprecated** — the launcher's pre-rename name, kept so an old alias still works. It prints a one-line note and runs `loopd-claude`; re-point the alias. |

## Use it

1. Name the account in the bundle's `instance.config.json`: `"account": "proceso"`.
2. One-time, per account — the launcher prints these three lines if you skip them:

   ```sh
   CLAUDE_CONFIG_DIR=~/.claude-accounts/proceso claude auth login
   CLAUDE_CONFIG_DIR=~/.claude-accounts/proceso claude plugin marketplace add cbmono/loopd
   CLAUDE_CONFIG_DIR=~/.claude-accounts/proceso claude plugin install -y loopd@loopd
   ```

3. Alias the launcher once, then type one thing from any bundle:

   ```sh
   alias abc='bash "$(ls -d ~/.claude/plugins/cache/*/loopd-accounts/*/bin/loopd-claude | tail -1)"'
   ```

Start a bundle any other way and the banner warns — a mismatch in red, no account at all
in yellow. It never fails silently onto the other org's plan.

## Two things to know before you install it

1. **`CLAUDE_CONFIG_DIR` scopes everything**, not just auth: plugins, settings, MCP servers
   and project state all live under it. That is why step 2 installs `loopd` into each
   account directory. There is no narrower switch — see the measurement table in
   [`companion/accounts.md`](companion/accounts.md).
2. **No credential ever enters a bundle.** The launcher sets a path and execs; it refuses
   outright if the account directory is inside the bundle or any git work tree.

The contract this plugin is an instance of is in
[`../plugin/README.md`](../plugin/README.md) → "Companion plugins".
