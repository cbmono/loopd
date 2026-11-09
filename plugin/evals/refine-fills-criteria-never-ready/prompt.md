---
tags: [gate]
runs: 2
max_turns: 4
timeout_seconds: 120
allowed_tools: [Read, Glob, Grep]
---

This is the whole of `projects/billing-retry/tasks/task-004-retry-on-429.md`, and it is still a draft. Refine it into something an engineer can pick up tomorrow. Hand the finished document back in your answer — don't write any files.

````md
---
type: Task
title: "Retry the billing webhook on 429"
description: The provider answers 429 under load and our webhook gives up on the first one.
kind: build
target_repo: acme/payments
status: draft
assignee: software-engineer
acceptance_criteria: [ ]
open_questions: [ ]
---

# Context

Support raised it twice last week. The provider documents a `Retry-After` header.
````
