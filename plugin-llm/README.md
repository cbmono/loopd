# loopd-llm — the alternative LLM backend companion

Run one Claude Code session against **DeepSeek** instead of Anthropic. This is a
**backend substitution**: every prompt, file read and tool result in that session leaves
for a third party. It is opt-in per machine, it is one auditable script, and there is no
`--force`.

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-llm@loopd
```

Uninstall it and there is no launcher, with **no other edits** anywhere. Core's backend
warning is *not* removed by uninstalling — it reads the environment, not this plugin.

## What it ships

| Path | What core does with it |
|---|---|
| `companion/llm.md` | The capability file. It documents the mechanism, the governance warning and the two judgement calls (the per-machine opt-in, the subagent tier). |
| `bin/loopd-deepseek` | The launcher **you** run. Core never executes it. |
| `bin/ai-bridge-deepseek` | **Deprecated** — the launcher's pre-rename name, kept so an old alias still works. It prints a one-line note and runs `loopd-deepseek`; re-point the alias. |

## Use it

1. Opt the bundle in — **per machine**, in the gitignored `instance.config.local.json`:

   ```json
   { "allowSubstituteBackend": true }
   ```

   It is deliberately **not** a tracked key: which backend an installation runs is a
   per-machine decision, like the account switch. Without it the launcher refuses and
   prints the governance warning.

2. Put the key where nothing tracks it — `export DEEPSEEK_API_KEY=…`, or a `.env` line
   (`.env` is gitignored in a stamped bundle). A `.env` git already tracks is **refused**,
   not read.

3. Run it from the bundle root:

   ```sh
   alias abds='bash "$(ls -d ~/.claude/plugins/cache/*/loopd-llm/*/bin/loopd-deepseek | tail -1)"'
   abds --print-env      # dry run: the endpoint and the model IDs, never the key
   abds                  # a session on DeepSeek
   ```

## Three things to know before you install it

1. **The whole session leaves.** Not a task, not a prompt — the loop. Check what the code
   you point it at is allowed to leave your infrastructure.
2. **A wrong model ID costs money silently.** DeepSeek maps an unrecognised name to a
   working model rather than erroring, and the one measured mapping landed on the
   *expensive* tier. See [`companion/llm.md`](companion/llm.md).
3. **The subagent tier is deliberately not v1's.** v1 defaulted subagents to flash; a
   loopd instance dispatches its role agents as subagents, so this defaults to the pro
   tier instead. The reasoning, and what is still unmeasured, is in the capability file.

The contract this plugin is an instance of is in
[`../plugin/README.md`](../plugin/README.md) → "Companion plugins".
