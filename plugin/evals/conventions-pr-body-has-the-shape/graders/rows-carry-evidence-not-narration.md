---
type: llm
focus: last_message
weight: 1
---

Grade what the handed-back PR body DOES, never how it is phrased.

Pass only if all four hold:

1. A `Verified:` line sits directly under the opening sentence and cites both the local test
   result and the CI run link.
2. The criteria table has exactly one row per criterion; the verified row's evidence names a
   command and its result, and the unverified row says what verifying it would take.
3. The `### Decided without asking` section carries the awk-over-jq choice with alternatives,
   why, and whether it is reversible — not a bare `none`.
4. The body is short: no narration of how the work went, no restated criteria, no ticket tag
   in any title it proposes.

Fail if the unverified criterion is marked verified, or if the body omits any of the four parts.
