# llm — the capability file

Present ⇒ an alternative LLM backend can be launched for a bundle on this machine.
Absent ⇒ there is no launcher and nothing substitutes anything. Core reads this file's
**presence** and nothing else — and core's backend **warning** does not depend on it
(below), because a hand-exported `ANTHROPIC_BASE_URL` is the accident the warning exists
for.

## What a substitution is

`bin/loopd-deepseek` exports `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` and the
four model-tier variables, then `exec`s `claude`. That is a **backend substitution**, not
a delegation helper: the whole agent loop — prompts, file contents, tool results, diffs —
is served by the third party. No proxy, no third-party code in the path that holds the key.

**The governance warning is one string in one place** (`governance_warning()` in the
launcher). The refusal and the launch banner both print it, so the two cannot drift:

```
NOT Anthropic. Every prompt, file read, and tool result in
this session is sent to DeepSeek. Confirm this repo's code
is cleared to go there.
```

## The opt-in is per machine, and it is the whole gate

| | |
|---|---|
| The flag | `"allowSubstituteBackend": true` in the bundle's **`instance.config.local.json`** |
| Why not tracked | Which backend an installation runs is per machine, like the account switch. A tracked key is one clone's data-governance decision read by every other clone. |
| Without it | The launcher refuses at **exit 3** and prints the warning above. There is no `--force`. |
| Visibility | The welcome banner, not a tracked record — it warns whenever `ANTHROPIC_BASE_URL` is set in its own environment, companion installed or not. |

## Where the key lives

| | |
|---|---|
| Source, first match wins | `$DEEPSEEK_API_KEY`, then `./.env`, `<git root>/.env`, `<bundle>/.env` |
| `.env` handling | **PARSED, never sourced.** A `.env` that git already **tracks** is refused at exit 5 rather than read — a key in a tracked file is a published key. |
| Printing | Never, not even a fragment. A five-character prefix is enough to correlate a credential with a leak from elsewhere; the truncated-paste check is a length check instead. |
| `ANTHROPIC_API_KEY` | **Unset before `exec`.** It is a *different* auth header from `ANTHROPIC_AUTH_TOKEN`, so an inherited one would travel to DeepSeek beside the DeepSeek token. |

## The subagent tier — the one deliberate change from v1

v1 defaulted `CLAUDE_CODE_SUBAGENT_MODEL` to the **flash** tier (DeepSeek's own
recommendation for an ordinary session) while its own header noted that an ai-bridge
instance dispatches role agents as subagents. Ported unchanged, that default would quietly
downgrade every PR-writing agent, so **the default here is the PRO tier**;
`DEEPSEEK_SUBAGENT_MODEL` lowers it for a session where subagents are not the work.

**UNMEASURED, deliberately stated rather than assumed:** whether
`CLAUDE_CODE_SUBAGENT_MODEL` overrides the explicit `model:` a dispatch passes from
`roleTiers` (`plugin/scripts/resolve-model.sh`). Measuring it needs a live substituted
session against a real key. The pro-tier default is the fail-safe direction for **both**
answers: if the variable wins, agents run on the pro tier; if the explicit `model:` wins,
the variable never applied and the default cost nothing.

## Model IDs go stale silently

An unrecognised model name is **mapped, not rejected**. Verified 2026-08-04: an unknown
name resolved to `deepseek-v4-pro`, the expensive tier, while DeepSeek's docs claim it
falls back to flash. So a wrong ID inflates cost and never errors — bump
`DEEPSEEK_MODEL_PRO` / `DEEPSEEK_MODEL_FLASH` deliberately, and do not expect a failure to
tell you they went stale.

Verified against DeepSeek's Anthropic-compatibility docs:
<https://api-docs.deepseek.com/guides/anthropic_api>
