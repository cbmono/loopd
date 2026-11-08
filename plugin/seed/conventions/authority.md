# Conventions detail: authority and missing tools

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

### Exhaust your own tools before you hand work back

- **Exhaust your own tools before you hand work back — three rungs, in order.** The default
  when you cannot do something is **not** to report it back:

  1. **Do it yourself**, with the tools you hold — a CLI, an MCP server, a browser, a
     script you write. That a step is fiddly, or is a browser step, or is the kind of thing
     a human usually does, is not a reason to pass it up.
  2. **Else ask for access to the tool that would let you.** Record the request and carry
     on — the next bullet is the whole of how, and it never stops your work. Asking fixes
     the gap once; reporting it fixes nothing, and the same gap blocks the next task and
     the one after.
  3. **Only then hand back exact instructions** — the commands, the paths, the output to
     expect — for a human to run, and only when no tool could have let you do it. They
     go in the task's `open_questions`, never only in your final message.

  **THE LADDER COVERS CAPABILITY GAPS ONLY. AN AUTHORITY GAP STAYS HUMAN REGARDLESS OF
  WHAT TOOL IS AVAILABLE.** "I can't" has two meanings and only one of them is yours:

  | | Meaning | Whose |
  |---|---|---|
  | **Capability gap** | no tool, no access, no CLI, not authenticated | **Yours.** The three rungs apply exactly as written. |
  | **Authority gap** | you *can* act, and must not | **The human's, always.** No rung applies. |

  The authority class, non-exhaustively: promoting a task `draft → ready`; merging a pull
  request; **any destructive or irreversible action**; **anything outward-facing** —
  publishing, sending, posting, deploying. **And its principle, so a case not on that list
  still resolves correctly: tool availability was never what made these human.** They are
  the human's because the *decision* is the human's, so acquiring the tool, finding a
  token, or being handed a wider allowlist changes nothing about any of them. A case you
  cannot place is an authority gap until a human says otherwise.

  **Nothing in this bullet is licence over the authority class.** Rung 1 is not "do it if
  you can" — **it never reaches an authority gap at all**, because those were never yours
  to be capable of. An agent reading this rule as permission to merge, promote, publish or
  delete has read it exactly backwards, and would be reversing the deny baseline this
  bundle runs on (`.claude/settings.json`, `AUTONOMY.md`, `SCHEMA.md` → "Two human
  authorities"). That misreading is most dangerous exactly where this rule has most
  effect — a background dispatch tick, hours from anyone watching — which is why it
  is stated here as a prohibition rather than left to be inferred from the table.

### The middle rung NEVER BLOCKS

- **The middle rung NEVER BLOCKS: record the tool request, then carry on.** `blocked` is
  not the response to a missing tool, and an agent that halts at the first gap turns a
  missing CLI into a stalled task. On a capability gap: **write the request into the task's
  `open_questions`**, **continue**, finish everything that does not depend on the missing
  tool, and **report exactly what you could not reach** — named, so a reviewer can see it.
  You do not get to quietly take a worse route and call it done; the naming is what makes
  "continue" reviewable instead of silent.
  **Use the mechanism that already exists — nothing new is built for this.**
  `open_questions` → the tick surfaces it in `AWAITING.md` as a `🧰 **grant**` item (its own
  verb, distinct from `❓ **answer**`, because installing a thing is not typing an answer)
  → the human appends ` --- <answer>` to the entry → the next tick folds it in and
  re-dispatches the task **with** the tool. That is the entire path.
  **There is no live channel, and here is why, so nobody proposes one.** No role agent
  holds `AskUserQuestion`, and none is granted a message-sending tool, so a subagent's only
  upward channel is its final message on termination — bubbling up mid-run means dying and
  losing its context. A live grant would not help even if one existed: a subagent's tool
  list is fixed at dispatch and MCP servers connect at session start, so access granted
  mid-flight never reaches the running agent. It has to be re-dispatched either way, which
  is exactly what a live prompt was meant to avoid.
  **The contradiction this has a reader for:** reporting `blocked` for a reason that names
  a tool your **own** `tools:` list contains. `check-dispatch.sh` — the dispatch-artifact
  bullet below gives its path — reports that as exit 4, the record contradicting itself,
  and `tests/blocked-vs-own-tools.test.sh` in `cbmono/loopd` pins it. Re-read your
  allowlist before you write a blocker reason.
