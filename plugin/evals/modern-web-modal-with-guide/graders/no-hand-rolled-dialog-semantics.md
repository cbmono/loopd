---
type: regex
target: last_message
match: not_contains
flags: m
weight: 1
---

^```[\w-]*[ \t]*\n(?:(?!^```)[\s\S])*?(?:aria-modal|role="dialog")
