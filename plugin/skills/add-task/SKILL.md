---
name: add-task
disable-model-invocation: true
description: Add a draft task to an open project instead of scaffolding a new one — writes the next task-NNN shaped like a seed task (kind and target_repo from the project, your description verbatim), validates it, commits it and pushes. The next tick refines it as usual.
argument-hint: "<project-slug> <description> [kind=<build|research>]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh:*), Bash(ls:*)
---

Add one `draft` task to an open project. Use it when the ask belongs to a project that is
still open — same kind, same target repo, same feature area. A new goal or an unrelated
area is `/loopd:new-project`; a closed project is never reopened, so a follow-up to it is
a new project that links to it.

## Run it

From the bundle root, split `$ARGUMENTS` into the slug (the first word), an optional
trailing `kind=build` or `kind=research`, and the description (everything between), then:

`${CLAUDE_PLUGIN_ROOT}/scripts/add-task.sh <slug> '<description>' [kind=<build|research>]`

Pass the description as **one quoted argument**, exactly as typed — the script collapses its
whitespace and writes it as `original_request`, so never reword, shorten or translate it. No
slug or no description: run `ls projects` and ask for the missing one; never guess a slug.

## Relay

Print the script's `added …` line, then one line per exit that is not 0:

| Exit | Say |
|---|---|
| 1, 3, 5, 6, 7 | its one `add-task:` line, unchanged — nothing was written |
| 2 | the line it printed, unchanged — usage text or an `add-task:` error |
| 4 | the task is written and kept, but not committed or not pushed — its line says which; never force |
| 8 | the draft failed `validate-bundle.sh` and was removed — relay the line and stop |

Never write the task file yourself, never edit `project.md`, and never promote: the task is
`draft` until a person promotes it after the project manager's refine.
