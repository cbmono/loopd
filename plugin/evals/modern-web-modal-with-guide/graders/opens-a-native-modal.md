---
type: regex
target: last_message
match: contains
flags: m
weight: 1
---

^```[\w-]+[ \t]*\n(?:(?!^```)[\s\S])*?(?:showModal\(\)|command="show-modal")
