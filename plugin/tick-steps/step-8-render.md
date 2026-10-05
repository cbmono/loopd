# Step 8 (render half) — the queue, the snapshot and the board

**Loaded on demand.** The core prompt reads this file on a full tick when `AWAITING.md`
or `SNAPSHOT.json` exists at the bundle root — the two artifacts this half writes. The
commit-and-sync half of step 8 is in the core and runs every tick, before this one.

   **Refresh the awaiting-you queue — only if it already exists, and only on a tick that
   changed something.** If `AWAITING.md` is present at the bundle root **and this tick will
   report `noop: false`** — or this tick's `tick-delta.sh check` named a moved `checkpoint`
   line — rewrite it with the renderer; **you never format the page**:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/build-awaiting.sh \
     --trailer <task-path>='<the one sentence that ends that row>' \
     --merge   <task-path>='[<repo>#<n>](<pr-url>)'
   ```

   The script owns the structure — the heading and its count, the `* ` marker, the glyph,
   the verb, the link and the ` · ` separator — and reads the task documents, never
   `SNAPSHOT.json` (absent on a boardless instance). It derives every row it can see on
   disk (`approve`, `answer`/`grant`, `unblock`, `close`, and `continue` — the continue
   checkpoint, whose sentence is the script's because it carries the human's answer line;
   `SCHEMA.md` → "The continue checkpoint") and **classifies `grant` against
   `answer` from the `open_questions` entry itself, so you never pick a glyph**. You supply
   two things and nothing else: the trailing sentence of each row, which is per-tick prose
   by design, and a `--merge` row per PR you have found verified and green at its current
   head — merge-eligibility is this tick's judgement and is written down nowhere the script
   can read.

   **No `AWAITING.md` ⇒ it writes nothing and exits 0** — absence is the off switch, and
   never create the file. A `noop: true` tick leaves `AWAITING.md` exactly as it is — not
   rewritten with the same items, not restamped: the `Last refreshed:` line moves on every
   render, so an unconditional rewrite churns the file the SessionStart banner reads and
   makes a stale queue indistinguishable from a fresh one, and the queue derives from
   documents a `noop` tick just proved unmoved. `AWAITING.md` is **derived and
   gitignored**: rewrite it, never stage or commit it.

   The queue holds **only** what a human decision unblocks — never in-flight, next, or
   blocked-but-progressing work. **On a shared instance the script narrows it once more
   itself**, to what *this* clone's human can decide (`task-owner.sh` exit 0); the other
   human's items belong in *their* queue — report them in the tick summary instead.

   **Never invent an item.** Pass a `--trailer` or a `--merge` only for a task you actually
   read this tick; if a state is unclear, leave it off rather than guessing. Exit 3 means it
   was handed a task path it could not read — report that line and change nothing.

   **Refresh the board snapshot — again, only if it already exists.** At the very end
   of the tick, after the curation commit and the queue rewrite, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/write-snapshot.sh --quiet` — the script, never hand-assembled JSON (the
   field allowlist is a data-governance boundary). **No `SNAPSHOT.json` ⇒ it writes
   nothing and exits 0** — absence is how a human takes this instance off the board.
   Never create the file, never stage or commit it.

   **Then re-render the page, if this instance has a board.** Nothing here publishes
   anything (that path is deleted — `docs/pm-design.md#step-8`). Immediately after the
   writer:

   1. Read `board` from `instance.config.json` — the **tracked** file, the same key
      the installer reads as `cfg_bool board true` at stamp time (not per-machine
      overridable). `false` ⇒ **skip the rest of this step in silence**.
      Absent or `true` ⇒ render.
   2. Render to the bundle's live path:
      `${CLAUDE_PLUGIN_ROOT}/scripts/build-board.sh --standalone`, from the bundle
      root. `--standalone` is required (a file opened straight in a browser needs the
      full HTML wrapper). **Pass no `--out`**: the renderer resolves `AB_BOARD_DIR`
      itself — today `.loopd/.board-live/board.html` — which is the path
      `watch-board.sh` writes, `board-serve.sh` serves and `/loopd:init` gitignores. A hardcoded `--out` overrides that resolver, and
      the one that used to stand here named the pre-3.0 root path — so the page
      landed where nothing reads it, untracked and un-ignored. Never stage or commit it. No
      readable snapshot ⇒ the renderer writes nothing and exits 0 ⇒ stop here, in
      silence.
   3. End your report with exactly one line — `BOARD: rendered <path>` — giving the
      **absolute** path from item 2. **No tracked `/board.html` is written or
      committed**: the bundle's board is served locally by `/loopd:board serve`
      (`board-serve.sh`), which reads the very file item 2 just wrote.
   4. **If this machine publishes a board, say that it is now stale, and stop there.**
      `boardArtifactUrl` in `instance.config.local.json` records the page this clone
      published. Ask the resolver, never the file:

      ```bash
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh --source boardArtifactUrl
      ```

      Exit 1, or a first field of `tracked`, ⇒ **no line**. `tracked` is the deleted shape
      — publishing is account-scoped, so a shared URL is a page this clone cannot write —
      and the SessionStart banner ignores it for the same reason; the two must agree.
      A first field of `local` ⇒ add exactly one more line to your report:

      ```text
      BOARD: run /loopd:board publish to refresh the published page
      ```

      An instance that has never published does not need telling about a page it does not
      have, which is why the absent case is silence rather than an invitation.

      **You cannot publish it yourself, and that is measured rather than assumed.** On
      Claude Code 2.1.261 a headless `claude -p` session's tool inventory carries no
      artifact tool, and a tool search for one returns nothing — so a tick that tried
      would fail, and a tick that stayed silent would leave a human reading a page whose
      data moved this tick. The line is the whole of what the tick can do about it. Do
      not attempt a publish, and do not treat the absence as an error.

   **Say the path, never that it is live.** A rendered file is only as fresh as the
   tick that wrote it; the masthead timestamp says how stale. A human who wants a live
   view runs `/loopd:board serve`, or `${CLAUDE_PLUGIN_ROOT}/scripts/watch-board.sh`.

   **A render is not a state change.** A tick whose only act was refreshing the
   snapshot and the live page still reports `noop: true` (`/loopd:dispatch` step 3).
   Nothing in this step stages, commits or pushes anything.

<!-- end of step 8 -->
