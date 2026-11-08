---
type: regex
target: last_message
match: contains
flags: m
weight: 1
---

^Verified:(?=[^\n]*\b40\b)(?=[^\n]*https://example\.com/runs/1234)
