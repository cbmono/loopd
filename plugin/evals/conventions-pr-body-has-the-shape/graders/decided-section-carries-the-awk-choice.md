---
type: regex
target: last_message
match: contains
flags: m
weight: 1
---

^### Decided without asking[ \t]*\n(?:[^#\n][^\n]*\n|\n)*?(?=[^#\n]*\bawk\b)(?=[^\n]*alternatives)(?=[^\n]*why)(?=[^\n]*reversible)
