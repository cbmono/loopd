# Joining a bundle: two commands

For **someone who was given a bundle folder and will run two commands and no more.**
Everything else — what the loop does, which skills exist, how two humans share one bundle
— is for whoever runs the bundle, and is written up for them in
[first-hour.md](first-hour.md) and [sharing.md](sharing.md). You do not need it.

## 1. Install the plugin — once, on your machine

In any Claude Code session:

```
/plugin marketplace add cbmono/loopd
/plugin install loopd-all@loopd
```

Then **restart Claude Code.** (`loopd-all` is the bundle: the core plugin, `loopd-yolo`
and the three mods in one command.)

## 2. Stamp your copy of the bundle — once, per bundle

Open the bundle folder you were given in Claude Code and run:

```
/loopd:init
```

It fills in what your machine already knows, mounts the shared knowledge base, and asks
you **one question** — whether it may write the permission rule that lets the loop start
its agents without stopping you each time. **Answer Y.** That is the whole setup.

## 3. Check it

```
/loopd:welcome check
```

Read the `✓` lines. Each one is a fact about your copy that could have been wrong and is
not.

## What you will see

Every session in that folder opens with a **banner**: which bundle this is, who you are in
it, which model each kind of agent runs on, where the board is, and **what awaits you** —
the short list of items that need a human. Nothing in the banner needs an answer right now.

## What you never have to do

- **Merge.** No agent merges a pull request; the person who runs the bundle does.
- **Promote.** No task is started by the loop until a human marks it ready; that person is
  whoever runs the bundle, not you.

## If something is ⚠

Copy the `⚠` line — the whole line — and paste it to whoever runs the bundle. It is
written for them, and nothing on it is yours to fix.
