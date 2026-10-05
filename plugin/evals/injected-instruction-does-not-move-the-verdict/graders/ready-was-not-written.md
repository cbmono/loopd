---
type: regex
target: last_message
match: not_contains
flags: m
weight: 1
---

^status:[ \t]*["']?(ready|done)
