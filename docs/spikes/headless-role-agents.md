# Spike: a role agent as a headless `claude -p` process

**Measured 2026-10-05, Claude Code 2.1.289, macOS.** Haiku sessions launched from a trusted,
linked worktree of a repo carrying the `.git/loopd-bundle` marker, against scratch
repositories with a local bare remote. No task document, product repo or tick lock was
touched. Reproduce: `bash docs/spikes/headless-role-agents-probe.sh --live <trusted-worktree>`.
The probe runs in the default headless permission mode with `--allowedTools Write` at most;
only its deny-baseline step uses `bypassPermissions`, restricted to the Bash tool, and it
is skipped unless the worktree's repo carries the hook's marker.

This picks up where [`headless-tick.md`](headless-tick.md) stopped. That spike measured the
**tick** under `-p` (plugin agents, skills and hooks load; the budget cap; a killed tick) and
recommended adopting it. This one asks the four things it left open for a **role agent**,
which today is a detached `claude --bg` session.

**Verdict: adoptable, and it buys the two bounds a `--bg` agent cannot have.** A role agent
under `-p` can be capped in turns and killed on a wall clock by the process that launched
it, records its session id *before* the spawn, hands its usage back in the result, and is
refused by the deny baseline exactly as a `--bg` agent is. The price is one reader:
`claude agents` does not list it.

## Why this question exists

`maxRepeatedToolCalls` and `maxAgentMinutes` do not reach a top-level `--bg` role agent:
`agent-control.sh` keys on `agent_id`, which only a subagent's call carries
(`docs/pm-design.md`). Auto mode is not a substitute — on 2.1.289 a detached session started
with `--permission-mode auto` records `default` and parks as `blocked` before its first turn
(6 of 6, measured 2026-10-05). So nothing bounds a role agent today but `claude stop <id>`,
run by a human.

## What was measured

| Question | Answer |
|---|---|
| Is `--session-id <uuid>` honoured under `-p`, with a plugin `--agent`? | **Yes.** The envelope's `session_id` is the minted one and the transcript is written under it. `--bg` ignores the flag, which is why `session:` is recorded *after* the spawn today |
| Is `--max-turns` enforced? | **Yes.** `--max-turns 3` on a four-step task: exit **1**, `subtype: "error_max_turns"`, `is_error: true`, `result: null`, three of four steps done |
| Can a capped run be continued? | **Yes.** `claude -p --resume <same id>` finished the fourth step: `subtype: "success"`, same `session_id` |
| What does a wall-clock kill leave? | `SIGTERM` at 12 s: exit **143**, **zero bytes of stdout**, the transcript on disk, and `session-usage.sh` still reads what was spent (`usage tokens=13584 tools=1 ms=4000 cached=17915`). `headless-tick.md` measured no orphaned children and a clean tree for the same kill |
| Does the deny baseline fire? | **Yes.** `git push --force origin main` from the marked worktree was **refused in 5 of 5 runs that attempted it**: remote unchanged, rule `force_push_protected` in the transcript, one entry in `permission_denials[]`. In two further runs the model never issued the command — an unchanged remote alone proves nothing, so the probe prints whether it was attempted |
| Does the result's usage agree with `session-usage.sh`? | **Yes**, to the token (14,920 fresh in both) |
| Is the run listed by `claude agents`? | **No**, 0 of 4. `agent-sessions.sh state` cannot see it |

A capped run and a killed run are **different exits with different evidence**: the cap
returns an envelope naming itself; the kill returns nothing on stdout and is known only by
the exit status the launcher holds. Both leave a resumable transcript.

## What it would change

| Today (`--bg`) | Under `-p` |
|---|---|
| `session:` written after the spawn, because `--bg` mints the id | written **before** it — the same window `worktree:`/`branch:` already close |
| `usage UNKNOWN` until step 4 settles it from the transcript | in the result envelope when the process exits; the transcript reader stays as the fallback for a kill |
| no turn bound | `--max-turns`, from the effort band the brief already states |
| no wall-clock bound | the launcher holds the pid: kill at `maxAgentMinutes`, exit 143 |
| `agent-sessions.sh state` reads `claude agents --json` | reads a pid and a result file the launcher wrote — `working` while the pid lives, `done` on `success`, `capped` on `error_max_turns`, `killed` on 143 |
| `claude stop <id>` | `kill <pid>` |
| `claude attach <id>` to watch one | not available; `claude --resume <id>` opens it afterwards |

`--max-budget-usd` is deliberately **not** proposed: it is a money figure, it is checked
between turns and overshoots (`headless-tick.md` saw $0.11 against a $0.05 cap), and
`agent-usage.sh` records tokens and never money.

## Recommendation

Adopt for **one role first** — `qa-reviewer`, whose rounds are short and already capped at
two — behind a launcher script that owns the pid, the cap and the result file, with
`agent-sessions.sh` taught the second source. Leave the engineers on `--bg` until that role
has run a week. **This PR migrates nothing**: it adds the measurement and the probe.
