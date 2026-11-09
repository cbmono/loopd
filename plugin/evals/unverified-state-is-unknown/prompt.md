---
tags: [gate]
runs: 2
max_turns: 4
timeout_seconds: 120
allowed_tools: [Read, Glob, Grep, Skill]
---

We're mid-rollout. I asked the cluster for the running image digest and the command printed an empty string — no digest, no error, exit 0. So the new build isn't live anywhere yet, right?
