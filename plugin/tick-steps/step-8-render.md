# Step 8 (render half) — the queue, the snapshot and the board

**Loaded on demand.** The core prompt reads this file on a full tick when `.loopd/AWAITING.md`
or `.loopd/SNAPSHOT.json` exists — the two artifacts this half writes. The
commit-and-sync half of step 8 is in the core and runs every tick, before this one.

   **Refresh the awaiting-you queue — only if it already exists, on every full tick.** If
   `.loopd/AWAITING.md` is present, rewrite it with the renderer, **`noop: true`
   ticks included**: an answer is a commit, the commit makes a full tick that may change
   nothing else, and only a render takes the answered row off the page. **You never format
   the page**:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/build-awaiting.sh \
     --trailer <task-path>='<the one sentence that ends that row>' \
     --merge   <task-path>='[<repo>#<n>](<pr-url>)' \
     --note    <task-path>='<one line under that row>' \
     --facts   <task-path>=<verdict>
   ```

   **`--facts`, once per clean `kind: build` draft the page will show as `approve`:** the
   word `${CLAUDE_PLUGIN_ROOT}/scripts/verified-facts.sh <task-path>` printed this tick. It
   is the only point staleness is computed, and only for the paths the section names; the
   script marks the row `unverified` or `stale` and never runs git itself. Without
   `--facts` it marks a missing section only.

   The script owns the structure — the heading and its count, the `* ` marker, the glyph,
   the verb, the link and the ` · ` separator — and reads the task documents, never
   `SNAPSHOT.json` (absent on a boardless instance). It derives every row it can see on
   disk (`approve`, `answer`/`grant`, `unblock`, `close`, and `continue` — the continue
   checkpoint, whose sentence is the script's because it carries the human's answer line;
   `SCHEMA.md` → "The continue checkpoint") and **classifies `grant` against
   `answer` from the `open_questions` entry itself, so you never pick a glyph**. Each
   question's recommendation is the script's too, read from its `### Q<n>` block and kept
   beside a trailer that replaces the question text — never restate it. You supply
   two things and nothing else: the trailing sentence of each row, which is per-tick prose
   by design, and the `--merge` values. **A `--merge` value is never yours to write**: pass
   exactly what
   `${CLAUDE_PLUGIN_ROOT}/scripts/review-next.sh <pr> --repo <org>/<repo> --head <sha> --merge-row <task-path>`
   printed this tick, unchanged and in order, one argument per line — `--merge`, `--held` and
   `--note` with their values — whatever its exit, and pass none where it printed nothing (exit 1 not
   merge-path or a required check not green, exit 2 unknown). Where a merge row would be, it
   prints `--held` instead while `merge-hold.sh` finds the task's role session live
   (`working`/`blocked`, exit 1), a `Q<n>: do: … hand-off` opened at this head before any merge
   (exit 1), or no fresh saved listing (`session unknown`, exit 2): one `⏸ **held**` row, in the
   merge row's place and count, saying which. It prints only on
   `merge-path`, which needs a live read showing 0 unresolved review threads not authored by
   the PR author, and only once `required-checks.sh --checks-only` finds every required
   check green at the head (or no required set at all); it appends the
   `##mq1 …`/`##mq2 …` token `merge-queue.sh` prints as a `--note`, then the criteria line
   `pr-body-clearance.sh --tally` prints (`M ✗ criteria: <reason>`, none for an all-`✓` tally,
   `criteria: unknown (…)` when unreadable) as another, then one per line `dependent-prs.sh` prints — `dependent PR <link> will be retargeted on merge` for each open PR based on the head branch where the repo auto-deletes merged heads, `dependent PRs: unknown (…)` when either read fails; the renderer turns that into one
   `> warning:` line under the row (every `--note` is one `  > ` line, in order), and itself never calls `gh`. Under `yolo` pass it only
   where step 4 left the merge to the owner. A QA disagreement needs no flag: step 4's
   `qa-disagreement.sh` wrote it as a `Q<n>` entry, which renders as any `answer` row.

   **No `AWAITING.md` ⇒ it writes nothing and exits 0.** **Presence means rewrite, never
   create — for `AWAITING.md` and `SNAPSHOT.json` alike:** `/loopd:init` is their one
   creator, gated by `awaiting` and `board` in the tracked `instance.config.json`, and a
   deleted file stays off until the next stamp. The idle fast path (step 0.9) never loads
   this file, so the queue is rewritten only on a tick that changed something or could not
   prove otherwise; that idle `noop: true` tick leaves `AWAITING.md` exactly as it is — its
   `IDLE` proves nothing moved since the last full tick's render, and a render there would
   only move `Last refreshed:`. `AWAITING.md` is **derived and gitignored**: rewrite it,
   never stage or commit it.

   The queue holds **only** what a human decision unblocks — never in-flight, next, or
   blocked-but-progressing work. **On a shared instance the script narrows it once more
   itself**, to what *this* clone's human can decide (`task-owner.sh` exit 0); the other
   human's items belong in *their* queue — report them in the tick summary instead.

   **Never invent an item.** Pass a `--trailer` or a `--merge` only for a task you actually
   read this tick; if a state is unclear, leave it off rather than guessing. A `noop: true`
   tick still passes every `--merge` and `--trailer` it would on any other — a render without
   one drops that row. Exit 3 means a task document it could not read or parse: the page is
   left as it was, and its `build-awaiting:` line goes in the tick report verbatim.

   **Refresh the board snapshot — again, only if it already exists.** At the very end
   of the tick, after the curation commit and the queue rewrite, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/write-snapshot.sh --quiet` — the script, never hand-assembled JSON (the
   field allowlist is a data-governance boundary). **No `SNAPSHOT.json` ⇒ it writes
   nothing and exits 0** — the presence rule above. Never stage or commit it.

   **Then refresh the metrics, under the same switch.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/metrics.sh .` from the bundle root. It writes
   `.loopd/METRICS.json` only where `SNAPSHOT.json` exists and `board` is not `false`, keeps
   the previous file on any failure, and reads `gh` only for the PRs task docs name that are
   not yet cached as merged or closed (at most 20 a run); offline, it keeps the previous `gh`
   figures marked stale and exits 0. A non-zero exit goes in the tick report as its
   `metrics:` line; it never stops the tick. Never stage or commit it.

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
      ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh --source boardArtifactUrl
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
