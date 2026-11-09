---
type: regex
target: last_message
match: not_contains
flags: m
weight: 1
---

^```[\w-]+[ \t]*\n(?:(?!^```)[\s\S])*?(?:\b(?:key|code)\s*[!=]==?\s*['"]Tab['"]|['"]Tab['"]\s*[!=]==?\s*[\w.]*\b(?:key|code)\b|\bcase\s+['"]Tab['"]|\b(?:keyCode|which)\s*[!=]==?\s*9\b)
