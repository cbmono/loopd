---
name: board
disable-model-invocation: true
description: The board, two ways. Bare or `serve` runs the local board server on a fixed localhost port — a script, no tokens. `publish` publishes the board as a PRIVATE artifact at a stable URL. Run from the instance root.
argument-hint: "[serve] | publish"
---

**Two forms, and `$ARGUMENTS` picks one. `serve` is the default: no argument means
`serve`.** Anything else is a typo: say so, name the two forms, and stop. Never guess, and
never read a typo as `publish` — publishing leaves the machine, so it is only ever what the
human typed.

| `$ARGUMENTS` | What it does |
|---|---|
| empty or `serve` | the **local** board server, on this machine only. One command, no tokens. **The default.** |
| `publish` | the **private artifact**, at a stable URL. Interactive only, and it leaves the machine. |

## `serve` — the local board server, and what a bare `/loopd:board` does

**Confirm you are at an instance root first** — `instance.config.json` in the cwd and
`SCHEMA.md` at the resolved schema path (`AB_SCHEMA`; the root on a legacy layout), with exactly
`ls instance.config.json "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_SCHEMA)" 2>/dev/null || ls instance.config.json SCHEMA.md`. If it fails, say which directory this is, say that an instance root
carries those two files, and stop. Do not run the script: it exits 0 and prints nothing
when the check fails, so a session that delegated the refusal would leave the human
looking at a blank line.

Then run it from the instance root and relay what it prints:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/board-serve.sh
```

That is the whole form. The script binds `127.0.0.1` on `boardPort`
(`instance.config.local.json`; absent, a port derived from the bundle path in the 4xxxx
band), renders `.loopd/.board-live/board.html` from `SNAPSHOT.json`, re-renders in two seconds
of that file changing, and serves nothing outside `$AB_BOARD_DIR`. Each open question's text
is filled in from its task document as the page is served — never into the file, so
`publish` below never carries it. **No model is in that
path** — do not render, summarise or reformat the board yourself, and do not read the page
back into the session. It runs until the human stops it; a second start on the same bundle
says the port is already served and exits 0. The next session's banner prints the URL.

## `publish` — the private artifact

Publish this instance's board as a **private artifact**, at **one URL that never
changes**. Run it from the instance root.

**Only ever on an explicit `publish`.** A bare `/loopd:board` serves, and no default,
typo or empty argument reaches this section.

The page is the same page the tick already renders — `${CLAUDE_PLUGIN_ROOT}/scripts/build-board.sh`, from
`SNAPSHOT.json` and nothing else. This skill adds no markup, no heading and no note of
its own; what it publishes is the bytes the renderer wrote.

## The seven steps

1. **Confirm you are at an instance root** — `instance.config.json` is present. If it is
   not, say which directory this is and stop. Never improvise a board.
2. **Refresh the data**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-snapshot.sh --quiet`. No `SNAPSHOT.json` ⇒ the
   writer writes nothing and exits 0 — that is how a human takes this instance off the
   board, so say so in one line and stop. Never create the file.
3. **Read `board` from the tracked `instance.config.json`** — the same key `/loopd:init`
   reads at stamp time, and deliberately *not* per-machine overridable. `false` ⇒ say the
   board is switched off and stop. Absent or `true` ⇒ carry on.
4. **Render, scoped to this instance**, from the instance root:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/build-board.sh --out "$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-paths.sh AB_BOARD_DIR)/artifact-body.html" .
   ```

   **No `--standalone`**: the artifact host supplies `<!doctype>`, `<html>`, `<head>` and
   `<body>`, and a page that ships its own gets double-nested. The default output is
   exactly that body.

   **The trailing `.` is load-bearing — never drop it.** Given no instance directory the
   renderer discovers instances from `boardInstances`, which on a real machine names
   **other bundles**. This output is published, so a bare render would put another
   bundle's project titles on a page with a different audience. `.` renders this
   instance's snapshot and nothing else. No readable snapshot ⇒ nothing written, exit 0 ⇒
   stop here.

   `$AB_BOARD_DIR` is gitignored, so the rendered body is never committed.
5. **Publish it, updating the same artifact.** Read the rendered file and publish its
   contents with this session's artifact capability:

   - a URL already recorded (step 6)? **update that artifact in place**, so the URL a
     human bookmarked, or shared, keeps working. Never create a second one;
   - no URL recorded? create one, **private** — the default, and the only setting this
     skill ever asks for. It shares the page with nobody. **A create is irreversible and
     its URL is not durable until step 6 writes it**: carry the URL straight to step 6,
     and if that write cannot be made, report the failure line in step 7 rather than a
     success. A created URL that exists only in this transcript is an orphaned artifact —
     the next run finds no record, creates a second one, and the first page is stale
     forever.

   **Title it with the page's own `<h1>`** — the masthead the renderer already wrote from
   the snapshot's `group`. Do not compose a title, a description or a summary: an org, a
   person, a repo or a path you type in is a literal the field allowlist never cleared,
   and it would sit on the page next to data that did.
6. **Record the URL in `instance.config.local.json`**, under `boardArtifactUrl`, creating
   the file if it is absent and preserving every key already in it. **Record before you
   report**: step 7 reports *this* step, not step 5, because step 5 is where the
   irreversible act happened and step 6 is where the URL becomes durable.

   **The write cannot be made durable — not writable, edit rejected, anything?** The
   artifact exists and nothing on disk names it. Do not retry silently and do not stop
   quietly: go to step 7's failure line, which quotes the URL so a human can paste it in
   by hand.

   **That file and no other.** It is per-machine and gitignored;
   `instance.config.json` is tracked, and a tracked URL is the failure this design exists
   to avoid — publishing is **account-scoped**, so exactly one account can ever update a
   given artifact, and a shared value produces one working board and one silently dead
   publish step on the other clone (`SCHEMA.md` → "Per-machine config overrides").
7. **Report one line, and only after the URL is recorded** — `BOARD: published <url>` —
   and nothing else. The next session's banner prints the same URL.

   **Step 6 did not complete? The report is a failure, and it quotes the URL:**

   ```
   BOARD: PUBLISHED BUT NOT RECORDED <url> — add "boardArtifactUrl": "<url>" to instance.config.local.json
   ```

   That line is the whole recovery: it is the only place the URL survives the session, and
   pasting it into the file makes the next run update that page instead of creating a
   second one. Never report `BOARD: published` for an artifact whose URL is not recorded —
   the human reads that line as "done", and the URL goes with the transcript.

## When this session cannot publish

**A headless tick cannot, and that is measured, not assumed.** On Claude Code 2.1.261 a
`claude -p` session's tool inventory carries no artifact tool and a tool search for one
returns nothing, so the dispatch tick never publishes — it renders the local page, and
says `run /loopd:board publish to refresh` instead.

So if this session has no artifact capability either: **say that in one line, name the
rendered file, and stop.** It is not an error and not a failure of the instance —
`$AB_BOARD_DIR/artifact-body.html` is on disk and nothing is half-published.

## Two artifacts, one instance

The state the ordering above exists to prevent, and how to leave it if you are already in
it. A run created an artifact, step 6 never recorded the URL, and a later run found no
record and created a second one — or two sessions ran this skill at once on a first run
and both took the create branch. Both pages are private to the same account, both render
the same board, and only one of them is ever updated again; the other is stale forever,
and it is the one that may have been bookmarked or shared.

The tell is a `BOARD: PUBLISHED BUT NOT RECORDED` line in an earlier session, or a
bookmarked board that stopped moving.

**This skill never picks between them.** Which page was bookmarked or shared is a fact
only the human has, so the recovery is theirs: delete one artifact, put the surviving URL
in `instance.config.local.json` under `boardArtifactUrl`, and the next run updates that
page in place. Handed a URL that disagrees with the recorded one? Say so and stop — never
overwrite the recorded key on a guess. Publishing is **account-scoped**, so nobody else
can resolve this for you either.

## Sharing it with a second human

Share the artifact from its own share control, read-only. The URL does not change, so
every later run of this form updates the page they already have.

**Sharing does not grant publishing.** No share level makes a second account able to
update your artifact; each human publishes their own board from their own clone, and the
cross-owner half of the page comes from the tracked task documents at your git `HEAD` —
never from anybody's published page.

## What must not happen here

- **Never write `/board.html`.** No tick commits that file any more; `publish` only ever
  writes under `$AB_BOARD_DIR`.
- **Never put the URL in `instance.config.json`**, and never remove or rewrite a key
  already in the local file.
- **Never report `BOARD: published` before the URL is recorded**, and never end a session
  that created an artifact without printing its URL somewhere the human can read it. A
  published page nobody can name is the failure this whole ordering is for.
- **Never widen what the page carries.** The renderer's input is the snapshot, whose
  field allowlist is a data-governance boundary (`docs/operations.md` → "Before it leaves
  the machine, know what it carries"). Publishing does not license adding to it.
- **Never share the artifact as part of this command.** Sharing is a human decision made
  once, in the step above.
