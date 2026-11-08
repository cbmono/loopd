# Conventions detail: writing less

Detail for `../CONVENTIONS.md` — moved there verbatim, so the core stays short. Open a section only when the core's pointer to it names a trigger that applies. **The core wins on any disagreement**; fix this file to restate it.

### Write less

**Owner's verdict, 2026-09-06: agents write far too much, everywhere.** Measured on this
tree the same day — `init-bundle.sh` 1,115 comment lines of 2,400, `session-banner.sh`
1,016 of 1,463, PR bodies [#122](https://github.com/cbmono/loopd/pull/122) and
[#135](https://github.com/cbmono/loopd/pull/135) at 5,826 and 6,423 characters, 133
`Finding`s averaging 110 lines. **These are ceilings, not targets, and they bind every
agent on every surface below.**
**Four of these have readers, so they are not prose.**
`pr-body-clearance.sh` refuses a body over 2,500 characters or carrying more than 3 notes
(**exit 4**); `pr-verdict-clearance.sh` refuses a checker row with no `PASS`/`FAIL` or no
command (**exit 3**); `validate-bundle.sh` warns on a `Finding` over 40 lines or missing its
`lesson:` — **on the document you name (`validate-bundle.sh <path>`) as well as on the whole
bundle**, so the cap lands while you are writing rather than at the next full run; and
`tests/concision-contract.test.sh` in `cbmono/loopd` fails when a
`plugin/**/*.sh` file's comment-line share exceeds **35%**, ratcheting the files already
above it so none may grow its share.

### Write for a human who will not read it

- **Write for a human who will not read it.** They scan. Say the thing, then stop —
  a reader who wants depth will ask, and asking is cheap where re-reading to find the
  point is not. **One house style, for every surface below:**
  - **Short sentences.** One idea each.
  - **Bullets, tables and icons over paragraphs.** More than two of a thing is a table.
  - **Lead with the outcome** — what happened and what it means, before how you got there.

  **Trim the transmission, never the record.** This split decides every length question
  in this document, and getting it backwards deletes the reasoning the work runs on:

  | Surface | Rule |
  |---|---|
  | PR bodies, review comments and replies, status reports, code comments | **concise** — a reader is deciding something, now |
  | Commit messages, `Finding`s | **bounded, but wider** — 5 lines and 40 (→ "Write less"): the durable record still fits on a screen |
  | Task docs | **as long as the reasoning needs** — the ONE surface with no ceiling, and where everything the others cut belongs |

  **Brevity is never an excuse to drop evidence, a criterion or a caveat.** It is licence
  to drop *narration* — the story of how you got there — because that story belongs in the
  task doc, which travels with the change and is the one surface with no length limit.
  **So there is nowhere for reasoning to be lost:** every rule below that says "short" is
  telling you where to put it, not to delete it.

### Why this file is not in CLAUDE.md

**Read this before your first write in a target repo.** It lives here rather
than in the instance `CLAUDE.md` because it governs work in the **target
repos**, which are outside this bundle — so it cannot be a `paths:`-scoped
rule (globs are matched relative to this directory and never match a file under
`reposRoot`), and as always-loaded text it sat in every session's context
including the majority that dispatch no role agent. The `CLAUDE.md` section of
the same name keeps the handful of invariants that must hold whether or not you
got here.
