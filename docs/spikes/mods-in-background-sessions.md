# Spike: do mods fire in a non-interactive session, and can they write the store?

**Attempted 2026-10-08, Claude Code 2.1.293 installed (`/opt/homebrew/Caskroom/claude-code@latest/2.1.293/claude`),
macOS (Darwin 25.5.0).** Probe mod: [`mods-probe/`](mods-probe/) (hooks `session.start`,
`turn.start`, `turn.step`, `tool.call`, `turn.complete`, `session.measure`, `session.end`,
each recording the event's field names and its usage/model/duration fields under
`probe.<session id>.<n>.<event>` via `$.store.set`, plus a `/probe-dump` command that prints
the store). Runner: `bash docs/spikes/mods-probe.sh --live`.

**Verdict: NOT MEASURED. The question is open, and nothing below is a measurement of it.**

## What happened instead

Every `claude` invocation on the machine — `claude --version`, `claude --help`,
`claude plugin validate`, `claude -p … --plugin-dir ./mods-probe` — stalled at exec: the
process existed with 32 bytes resident and 0 CPU for minutes, with and without the Bash
sandbox, until killed. Measured cause, not inferred: the cask had been upgraded to **2.1.293
at 00:30 that night** and the new binary still carried `com.apple.quarantine`
(`xattr -l` showed `0381;…`), so its first launch was waiting on Gatekeeper, which needs
the operator. The running session was a **deleted** 2.1.289 binary (`$CLAUDE_CODE_EXECPATH`
no longer exists on disk), so there was no second binary to fall back to. Removing the
attribute is a machine-security change and was refused by the harness policy, correctly;
it is the operator's to make (`xattr -d com.apple.quarantine <that path>`, or launch
`claude` once from a terminal and accept the prompt).

So: **the probe plugin is written, the runner is written, neither was run; the CLI's own
`claude plugin validate` and `claude plugin test` were not run either**, on the probe or on
`plugin-mod-usage`. The types file `.claude-plugin/types/claude-code/index.d.ts`, written
only by a `--plugin-dir` session, does not exist yet.

## What the docs claim (unverified here — trust the types file over this once it exists)

From `code.claude.com/docs/en/plugins/mods/{overview,events,reference,test}` as fetched
2026-10-08:

| Question | The docs' answer |
|---|---|
| Do hooks run under `claude -p` and the Agent SDK? | **Yes** — "Hooks run: Yes; what the mod draws appears: No" (overview → Where mods run). `--bg` is not named in that table. |
| `session.start` fields | `surface`, `isInteractive`, `cwd` (the test kit fires it with exactly those) |
| `turn.step` | async-generator hook; `yield* next(e)` resolves to the request's result, whose `usage` carries `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` and `model`; `e.agentId` is set for a subagent's request |
| `turn.complete` | `e.turnId`, `e.answer`, `e.durationMs`, `e.isAborted`, `e.usage` (the turn's totals), `e.agentId` for a subagent's turn |
| `tool.call` result | `{ result }`, `{ deny }`, or a result with `isError` set |
| `session.end` | `e.reason` ∈ `clear`, `resume`, `logout`, `prompt_input_exit`, `other`; all `session.end` hooks share a 1.5 s budget |
| `$.session.id()` | exists (test kit stubs it as `on('session.id', () => ({ value: 'abc123' }))`) |
| `$.store` | "a key-value store that every session on the machine shares", 4 MiB total |
| `$.ui.ask` in `-p` | rejects — "in a claude -p run with nobody to ask" |

**Measured on this machine, independent of the probe:** the store is one JSON file per
plugin under `~/.claude/plugins/store/`, named `<plugin>_<marketplace>-<12 hex>.json`, a flat
object of key → value — `cc-plugin-diff_builtin-3903e77c01b1.json` holds `{"open": false}`.
`plugin/scripts/session-usage.sh` reads exactly that shape and falls back to the transcript on
anything else.

## What follows for `loopd-mod-usage`

Built against the docs, with every field access guarded so a missing or renamed field costs a
count, never a throw. Three things are **assumed, not verified**, and the morning's first
job is the two commands that verify them (`claude plugin validate ./plugin-mod-usage --strict`,
`cd plugin-mod-usage && claude plugin test`), then `bash docs/spikes/mods-probe.sh --live`:

1. that `turn.step` results carry `usage` under `-p`/`--bg` (else the mod falls back to
   `turn.complete`'s `e.usage`, which is what the second test case covers);
2. that `$.session.id()` returns the same id the transcript is filed under, so
   `session-usage.sh <id>` finds the record — the id is the only join key;
3. that `claude --bg` accepts `--plugin-dir`, or that an installed plugin loads in a `--bg`
   session at all. If neither, the role-agent half of this mod is inert and the morning tick
   keeps reading transcripts, exactly as before — absence is the safe behaviour.

Until (3) is measured, **the morning tick reads the transcript**: role agents are
`claude --bg` sessions that load the companion only if the operator installs it on that
machine, and nothing here installs anything.
