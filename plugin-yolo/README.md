# loopd-yolo — the delegated-autonomy companion

`loopd` core is **gated-only**: the human promotes `draft → ready`, and the human
merges. This companion is the *only* thing that makes any other mode exist.

```
/plugin marketplace add cbmono/loopd     # already added? skip
/plugin install loopd-yolo@loopd
```

Uninstall it and every project is `gated` again, with **no other edits** anywhere. That
is the whole design — a capability some deployments must not have is one deletable
thing, and its absence is the safe behaviour rather than an error.

## What it ships

| Path | What core does with it |
|---|---|
| `companion/AUTONOMY.md` | The capability file. `resolve-autonomy.sh` finds it here when the bundle root has none; it defines `yolo`, its preflight, and the four things `yolo` never delegates. |

Nothing else. No skills, no agents, no hooks, no scripts — a companion that shipped a
second copy of an enforcement hook would fire it twice in every session on the machine.

## Two things to know before you install it

1. **It arms every bundle on this machine**, because a plugin is installed per user
   while `AUTONOMY.md` at a bundle root is per bundle. The per-bundle opt-out is
   unchanged and still the human's: set that project's `autonomy: gated`.
2. **A bundle root beats it.** A bundle that carries its own real `AUTONOMY.md` — a v1
   instance, or one deliberately pinned — keeps using that file, installed or not.

`yolo` is all-out: it delegates both gates, browser writes, and the fallback reviewer's
spend. Read [`companion/AUTONOMY.md`](companion/AUTONOMY.md) before you install it, and
pair it with `/audit`, the slow counter-metric that watches an autonomous loop for drift.

The contract this plugin is an instance of — how a companion registers, where core looks,
and the rule that a companion may ADD behaviour but never remove a core gate — is in
[`../plugin/README.md`](../plugin/README.md) → "Companion plugins".
