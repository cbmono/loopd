---
type: regex
target: last_message
match: contains
flags: m
weight: 1
---

^\|[^|\n]*backs off on 429[^|\n]*\|[ \t]*✓[ \t]*\|(?=[^|\n]*retry\.test\.sh)[^|\n]*\b40\b
