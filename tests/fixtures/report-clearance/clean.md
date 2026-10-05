Tick 41 dispatched two tasks and merged [demo#12](https://example.com/pr/12).

Blocking: [demo#14](https://example.com/pr/14) waits on a review that has not started.

Needs you:
1. Grant trust to `~/work/_wt/task-007` — the agent cannot write there without it.
2. Re-dispatch `projects/demo/tasks/task-007.md` once trust is granted — it stalled on the prompt.
3. Merge [demo#13](https://example.com/pr/13) after CI is green — the review is clean.

BOARD: rendered /tmp/board.html
