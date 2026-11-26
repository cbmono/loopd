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

## Markers a reader draws

| In the JSON | Means | Draw |
|---|---|---|
| a number | computed from a file record | the number |
| `null` | unknown: the record exists but nothing in it measured this | `?` |
| `{"source": "none"}` in place of a figure, or as a family's `source` | no record holds this yet | `—` |
| `"stale": true` on a family | the previous figure was kept because a read failed | the figure, marked stale |

A `null` is never a zero, and a zero is never a guess. Every family carries `"stale"`. Only
the `gh`-backed families planned after this slice ever set it `true`, so it is `false` today.

## Top level

| Key | Value |
|---|---|
| `schema_version` | `1`. Bumped on any change a reader must handle |
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
  `timestamp:` → `* TOTAL` minus working. PR open and merge times read `source: none`. Per
  project, `open_days` runs from the ledger's `Project added` heading to its
  `Project closed` heading.
* **`tokens`.** `supervision` is the ledger ticks' usage and `role_agents` is the dispatches'
  usage, both from `series`. `merged_prs` comes from the `* TOTAL` lines alone: `per_pr` is
  the measured TOTAL tokens divided by the PRs those lines name. `fix_rounds` counts
  `rounds` past the first.
* **`idle_tick_spend`.** Covers the ledger's `idle` lines. `tokens_measured` sums only the
  idle lines that carry usage. `unmeasured_share` is the share with none, and those ticks
  are unknown, never zero.
* **`blocked_by_cause`.** These are counts now, not hours (`hours` is `source: none`).
  `owner` counts live tasks with an open question or `status: blocked`. `merge_gate` counts
  `.loopd/.merge-holds/` marks for a PR a live task's `pr:` names. `stalled_agent` counts
  live tasks with `stall_count > 0`. `classifier_block`, `usage_limit` and `ci_flake` read
  `source: none`. `top` names the largest computed cause.
* **`owner_response`.** `answers` counts the `answered_questions` entries stamped
  `by <login>`. Both response times read `source: none`.
* **`self_merge`, `quality`.** Both read `source: none`.
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
  * the time figures above, plus `pr_opened` and `pr_merged` (`source: none`);
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
