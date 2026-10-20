# Papercuts

The cheap end of the knowledge loop. A `Finding` costs 40 lines and a decision about
whether the thing is durable; a **papercut costs one line and no decision** — a tool that
failed, a doc that misled, a step you did twice. Write it and move on. The `cataloguer`
groups them by surface and turns each group into a proposed edit to the agent, skill or
script that hurt.

**One line per entry, appended, never edited.** The line:

```
DATE | TASK | KIND:NAME | what hurt
```

| Field | |
|---|---|
| `DATE` | `YYYY-MM-DD`, UTC |
| `TASK` | the task you were on — `<project>/task-0NN`, or `ad-hoc` |
| `KIND:NAME` | the surface to EDIT: `skill:`, `agent:` or `script:`, then its name |
| `what hurt` | **15-160 bytes**, one line — the symptom, not the fix |

Append with the tool, so the shape is checked before it lands rather than after:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/papercuts.sh add \
  --task checkout-v2/task-016 --surface script:validate-bundle.sh \
  --note "exits 0 on an unreadable file, so a dangling ref reads as clean"
```

**Never edit or delete a line here** — including your own. The record is a log: the value
is that ten entries naming one surface are visible as ten, and an edited record cannot
show that. A wrong entry is corrected by a new entry, not by a rewrite.

**A `<!-- pass ... -->` marker means the cataloguer has already grouped everything above
it.** It reads only what is below the last marker, so the record grows without the pass
getting slower.

## Entries
