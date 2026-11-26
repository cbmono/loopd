# METRICS.json — the schema

`plugin/scripts/metrics.sh <bundle-root>` writes `.loopd/METRICS.json`. It is the one place a
metric is computed: the `/pane` Metrics view and `metrics-report.sh` read this file and
compute nothing. This page is the contract they code against.

## When it is written

* **Switch:** the board's. Written only where `.loopd/SNAPSHOT.json` exists and `board` in the
  tracked `instance.config.json` is not `false`. There is no metrics switch of its own.
* **Refresh:** tick step 8's render half (`plugin/tick-steps/step-8-render.md`), right after
  `write-snapshot.sh`. An IDLE tick and `refresh-state.sh` never run it, so the figures move
  at the next full tick.
* **Atomic:** written to a temp file under `.loopd/` and moved into place. Any failure (no
  `jq`, an unreadable task document, a config or usage store that does not parse, a failed
  `agent-usage.sh series`) prints a `metrics:` error, exits
  2 and leaves the previous file untouched.
* **Derived:** gitignored and recomputed from scratch on every run, so a deleted file is
  rebuilt by the next one. Nothing walks git history.
* **`gh`, cached:** only the PRs task documents name (`pr:` and `* TOTAL` lines) are read, one
  `gh pr view` each plus `pr-quality.sh --pr` and `review-rounds.sh --for coderabbit` once
  merged. Each lands in `.loopd/.pr-cache/<owner>__<repo>__<n>.json` (gitignored, ignores
  itself), keyed by repo plus PR number and **frozen** once the PR is merged or closed, so
  a run whose named PRs are all closed makes no `gh` call. An open PR is re-read every run.
  A PR the host answers with a 404 is cached as `MISSING` and never retried. An entry no
  task names is deleted. At most `METRICS_GH_MAX_PRS` (**20** when unset) PRs are read per
  run, least recently read first, so a deferred PR gets the next run's turn; until read it
  counts in `quality.prs_named`, not `prs_read`.
* **Offline:** a failed `gh` read (no `gh`, offline, rate-limited) still exits 0. The `gh`
  figures are the previous file's, each marked `"stale": true`. With no previous file they
  come from the cache, also marked stale.
* **Tick cost:** `tick-reap.sh` appends one row per reaped tick to
  `.loopd/.tick-cost/ticks.tsv` (gitignored, ignores itself): tick id, tokens, tools, ms
  and reap time, `unknown` on `usage UNKNOWN` and never 0, the newest 4,320 rows kept. The
  file is per clone, so another clone's ticks are never in it.

## Markers a reader draws

| In the JSON | Means | Draw |
|---|---|---|
| a number | computed from a file record | the number |
| `null` | unknown: the record exists but nothing in it measured this | `?` |
| `{"source": "none"}` in place of a figure, or as a family's `source` | no record holds this yet | `—` |
| `"stale": true` on a family | the previous figure was kept because a read failed | the figure, marked stale |

A `null` is never a zero, and a zero is never a guess. Every family carries `"stale"`. Only
the `gh` figures ever set it `true`: `self_merge`, `quality`,
`time.pr_open_to_merge_hours` and `owner_response.ready_pr_to_merge_hours`, each carrying
its own. A stale `headline.self_merge_rate` ends in ` (stale)`.

## Top level

| Key | Value |
|---|---|
| `schema_version` | `2` (task-004 added keys). Bumped only when a key is added |
| `generated_at` | UTC, `YYYY-MM-DDTHH:MM:SSZ` (`METRICS_NOW` pins it for tests) |
| `headline` | five ready-formatted strings, below |
| `delegation`, `time`, `tokens`, `idle_tick_spend`, `blocked_by_cause`, `owner_response`, `self_merge`, `quality`, `kb_efficiency` | one object per family |
| `tasks` | per-task objects keyed `<project-slug>/<task-id>` (a bare task id repeats across projects) |
| `projects` | per-project objects keyed by project slug, closed projects included |
| `periods` | monthly buckets keyed `YYYY-MM` |

`headline` holds `delegation_share`, `tokens_per_merged_pr`, `idle_tick_spend`,
`top_block_cause` and `self_merge_rate`. Each value is a string a renderer prints as it
stands: `?` is unknown and `—` is no source.

## Families

* **`delegation`.** The unit is **tokens**: fresh input + cache writes + output, the sum
  `agent-usage.sh` records. `role_agent_tokens` and `supervision_tokens` are
  `agent-usage.sh series`'s dispatch and tick figures. `share_role_agents` is
  role/(role+supervision), with `by_role` and `by_model` coming from the `* DISPATCH`
  lines. `main_session` is the machine's usage store labelled
  `unattributed (machine-wide)`. Its records carry no bundle key, so it is never summed into
  this bundle's figures.
* **`time`.** All values are hours. Per task, `draft_hours` runs from `timestamp:` to
  `promoted`, `queued_hours` from `promoted` to the first `* DISPATCH`, and
  `in_flight_hours` from that dispatch to `* TOTAL`, the reflect after the merge.
  **Working vs waiting:** `working_hours` is the sum of the measured `ms=` on the task's
  dispatch lines, and it is unknown if any dispatch is `usage UNKNOWN`. `waiting_hours` is
  `timestamp:` → `* TOTAL` minus working. `pr_open_to_merge_hours` (`source: gh`) is the
  mean of `createdAt` → `mergedAt` over the merged PRs read. Per project, `open_days` runs
  from the ledger's `Project added` heading to its `Project closed` heading.
* **`tokens`.** `supervision` is the ledger ticks' usage and `role_agents` is the dispatches'
  usage, both from `series`. `merged_prs` comes from the `* TOTAL` lines alone: `per_pr` is
  the measured TOTAL tokens divided by the PRs those lines name. `fix_rounds` counts
  `rounds` past the first. `pm_ticks` (`source: tick-cost`) is the PM ticks' **own** usage:
  the ledger's `open:` and idle tick ids joined to the tick-cost rows. `ticks` joined,
  `measured`, `unknown` (a row saying `unknown`), `tokens` over the measured ones, and
  `ticks_without_row`: this clone's ledger ticks with no row (before the writer, or a lock
  freed without `tick-reap.sh`). This clone is `ownerGithubUser`, else the logins of its
  joined ticks; with neither it is `null`. Another login's ticks are excluded.
* **`idle_tick_spend`.** Covers the ledger's `idle` lines. `tokens_measured` sums only the
  idle ticks measured: a tick-cost row's tokens first, else the idle line's usage.
  `unmeasured_share` is the share with neither, and those ticks are unknown, never zero.
  `tick_cost` is the idle ticks' tick-cost join alone, shaped as `pm_ticks`.
* **`blocked_by_cause`.** These are counts now, not hours (`hours` is `source: none`).
  `top` names the largest computed cause. A cause with no source is `null` (unknown):

  | Cause | Source |
  |---|---|
  | `owner` | live tasks with an open question or `status: blocked` |
  | `merge_gate` | `.loopd/.merge-holds/` marks for a PR a live task's `pr:` names |
  | `stalled_agent` | live tasks with `stall_count > 0` |
  | `classifier_block` | no source today: a denied command never runs, so nothing records it |
  | `usage_limit` | no source today: the stop ends the tick; a close line may say so in prose only |
  | `ci_flake` | no source today: nothing tells a flaky red from a real one |
* **`owner_response`.** `answers` counts the `answered_questions` entries stamped
  `by <login>`. `ready_pr_to_merge_hours` (`source: gh`) is the mean over PRs the owner
  merged of ready → `mergedAt`, ready being the PR's last activity before the merge: the
  latest of `createdAt`, its last commit and its last review. `needs_you_to_action_hours`
  reads `source: none`.
* **`self_merge`** (`source: gh+ledger`). Over the merged PRs read: `loop` counts those a
  ledger close line names as `merged <owner>/<repo>#<n> under yolo` (or `<repo>#<n>`, counted
  only when no other named PR shares that repo name and number), `owner` the rest, `rate` is
  loop/merged. `not_self_merged` maps each owner merge (`<owner>/<repo>#<n>`) to a reason
  and `reasons` counts them: `gated` (its project's `autonomy:` is not `yolo`),
  `criteria` (its body has a `✗` row), else `unknown`. `gh` cannot tell the loop's merge
  from the owner's — both run under the clone's login — hence the ledger.
* **`quality`** (`source: gh`). Over merged PRs with a cached `pr-quality.sh` row and
  `review-rounds.sh --for coderabbit` count: `cr_findings` (CodeRabbit inline comments,
  per PR it reviewed), `fix_rounds` (CodeRabbit rounds past the first, per PR),
  `first_round_merge_share` (merged after at most one round) and `x_rows_per_pr`.
  `prs_named` and `prs_read` show the cache's coverage. Not split by role or model tier.
* **`kb_efficiency`.** Always `"label": "estimate"`, never measured time saved.
  `citation_files` is the count of `.loopd/citations/` files read, and `pr_records` counts
  the per-PR merge records among them. `cited` and `not_cited` compare reflected tasks on
  tokens, rounds and in-flight hours. A task counts as cited when its `<task-id>.result` or a
  `<repo>-pr-<n>` record of its PRs keeps a citation. `.loopd/citations/` is partly untracked,
  so two clones can differ.

## Per task, per project, per period

* `tasks.<slug>/<id>` holds:
  * stamps: `project`, `status`, `created`, `promoted`, `first_dispatch`, `reflected`;
  * dispatches and usage: `dispatches`, `dispatches_measured`, `tokens`, `tokens_from`
    (`total` or `dispatch`);
  * rounds and PRs: `rounds`, `fix_rounds`, `merged_prs`;
  * the time figures above, plus `pr_opened` and `pr_merged`: the earliest `createdAt`
    and latest `mergedAt` of its PRs read through `gh` (`null` when none);
  * `stall_count`, `open_questions` and `cited` (`null` when no citation record names the
    task).
* `projects.<slug>` holds `state` (`live` or `closed`), `added`, `closed`, `open_days`,
  `tasks`, `tasks_reflected`, `dispatches`, `tokens` and `merged_prs`. A closed project
  whose folder was removed keeps its ledger dates. Its task figures go with its task docs.
* `periods.<YYYY-MM>` holds:
  * `series`'s `ticks`, `ticks_measured`, `tick_tokens`, `dispatches`,
    `dispatches_measured` and `dispatch_tokens`;
  * `idle_ticks`, `idle_measured`, `merged_prs` (by TOTAL month), `answers` and
    `citations`.

  Buckets are calendar months only. A `--since` filter selects months. A short trend needs
  three months.

**No backfill.** A metric logged for the first time starts empty, so its trend and
`--since` start empty too. Nothing reconstructs it from history.

## The report

`/loopd:metrics` runs `plugin/scripts/metrics-report.sh` from the bundle root and relays its
markdown. The script reads `METRICS.json`, `instance.config.json` and the ledger. It calls no
`gh` or `git`, writes nothing and recomputes nothing. It needs `jq`, never `python3`.

* **Off.** `board: false`, or no `METRICS.json`, prints that metrics are off and names the
  `board` switch. Exit 0.
* **Stale.** The report compares `generated_at` (UTC) with the newest full tick in the ledger:
  an `open:` and a `close:` line at one timestamp. An IDLE line and a reaped tick's close have
  no pair, so they are not a refresh. A close line pulled from another clone counts. Older ⇒
  one line saying the figures refresh on the next tick that changes something. There is no
  refresh verb.
* **Named errors.** Without `jq`, or outside a bundle root: exit 2. An empty, truncated,
  non-object or wrong-`schema_version` file: exit 4.
* **Flags.** Invalid input exits 3.
  * `--project <slug>` narrows the project and task tables. A slug not in `projects` exits 3;
    a closed project whose folder was removed is still there. Months stay bundle-wide.
  * `--since <YYYY-MM|YYYY-MM-DD>` (UTC) keeps the months from that one on, and the tasks
    created in them. A day selects its month. A future month prints empty tables.
  * The families and the suggestions are bundle-wide, all time, and ignore both flags.
* **Size.** At most 25 projects, 25 tasks (newest first), 24 months and 10 roles. Each
  table names what it cut. Data strings are stripped of control characters and `|`, then
  cut at 40–60 characters.
* **Markers.** `—  source: none` and `? unknown` print as named, never as 0. A family with
  `stale: true` carries `(stale)`. A trend shows the last three months and is omitted until
  three exist. The no-backfill line always prints.

### Suggested changes

A rule fires when its figure is a number past the threshold. A `null` or `source: none`
figure never fires. At most three print. Fewer fire ⇒ fewer print; none ⇒ one line saying
so.

| # | Metric | Fires when | Suggests |
|---|---|---|---|
| 1 | `idle_tick_spend.idle_share` | ≥ 0.5 | a longer `/loopd:dispatch` gap |
| 2 | `delegation.share_role_agents` | < 0.5 | moving work from supervision to role agents |
| 3 | `tokens.merged_prs.fix_rounds_per_pr` | ≥ 1 | tighter criteria before promoting |
| 4 | `blocked_by_cause.causes.owner.tasks` | ≥ 3 | clearing the queue with `/loopd:answer` |
| 5 | `blocked_by_cause.causes.stalled_agent.tasks` | ≥ 2 | looking at stalled tasks first |
| 6 | `time.mean_queued_hours` | ≥ 24 | dispatching sooner after promotion |
| 7 | `kb_efficiency` not-cited ÷ cited mean rounds, both groups ≥ 3 tasks | ≥ 1.25 | citing Findings in more briefs (an estimate) |

**Ranking.** Rules rank by how far past the threshold they are: value ÷ threshold, or
threshold ÷ value for rule 2. The lower rule number wins a tie.
