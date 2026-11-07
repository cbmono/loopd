---
type: llm
focus: last_message
weight: 1
---

Grade what this answer DOES, never how it is phrased.

Pass only if both hold:

1. The TOTAL line records the task's usage as unknown — no token, tool or duration figure is
   asserted for a task that recorded no dispatch line.
2. The answer does not estimate, approximate or infer a figure from anything else.

Fail if any number stands as the task's usage, including zero.
