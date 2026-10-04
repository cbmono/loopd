#!/usr/bin/env bash
#
# seed-size.test.sh — the per-turn instruction cost of `seed/CLAUDE.md`, finally pinned.
#
# The harness-native objective has carried this criterion since 2026-08-23: "the
# per-turn instruction cost stops growing and then falls … Tracked by: that command, at
# each re-audit — not yet by a test, which is the next thing to fix about this
# criterion." Unmeasured, the file grew 17,018 → 22,136 bytes in nine days. This is
# that test.
#
# THE CEILING IS A RATCHET, NOT AN ASPIRATION — the machinery-ceiling lesson applied at
# the size where it works: ONE constant in ONE file that no other PR re-measures, so it
# cannot collide across branches the way the retired 944-line ceiling test did.
# Lowering it is always free. Raising it is a deliberate act: change the number in the
# same commit as the growth and say why in the PR body. The objective's stated target
# is 8,000 bytes; the distance from this ceiling to that target is pinned rules the
# owner has so far chosen to keep always-loaded (pr-body-shape.test.sh and
# session-banner.test.sh name them), so closing it is the owner's call, not a diet's.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/plugin/seed/CLAUDE.md"
# 12800 -> 12816 (ai-bridge-v2/task-027). The ratchet's own protocol: raise it in the same
# commit as the growth and say why in the PR body. The growth is 26 bytes on the
# PR-sizing bullet, which now names `maxPrFiles` beside `maxPrLoc` — a second threshold an
# agent has to know before it opens a PR, and one it cannot infer from the first. Set to the
# measured size and not rounded up, so the next byte is the next deliberate act.
# 12816 -> 12980 (ai-bridge-next/task-007). +164 bytes on the "reading the KB" paragraph,
# which the task's criterion 5 replaces: it now carries the three-at-most cap and that a
# superseded row is history, neither of which the old wording said. Same protocol — flagged
# in the PR body, measured not rounded.
# 12980 -> 13452 (ai-bridge-next/task-022). +472 bytes for the one sentence that defines
# what a bare `scripts/<x>.sh` means, plus the shell that resolves it — 46 references in
# the seed pointed at a directory a data-only bundle does not have. Measured, not rounded.
# 13452 -> 13650 (ai-bridge-next/task-031). +198 bytes: the "no AI attribution" invariant
# is replaced by the rule that supersedes it — the trailer stays, the brief carries the
# resolved `commitAttribution`, `none` is the opt-out. Trimmed twice before raising, and
# an invariant an agent must hold before its first commit has to be always-loaded, exactly
# as the prohibition it replaces was. Measured, not rounded; flagged in the PR body.
# 13650 -> 13924 (ai-bridge-2x/task-004). +274 bytes: `/<plugin>:init` is now the one
# command to run after a plugin update — it stamps the seed AND runs the check-and-fix
# pass — and `/<plugin>:welcome` no longer fixes anything. Which command brings a bundle
# up to the installed plugin is something an agent must know before its first stamp, so
# it is always-loaded like the invariants around it. Measured, not rounded; flagged in
# the PR body.
# 13924 -> 13964 (ai-bridge-2x/task-011). +40 bytes: the answer instruction now shows the
# stamped form, `<ISO 8601> by <login> · <entry>`. The human reads this file when they type
# the ` --- ` reply, so the shape their answer lands in has to be here rather than one
# document away; written as the shortest form that still shows the `by`. Measured, not
# rounded; flagged in the PR body.
# 13964 -> 14622 (launcher-verification-contract/task-009). +658 bytes for two rules four
# stamped bundles had each written by hand: don't manufacture a decision out of a side
# effect that is not live yet (§ Ad-hoc requests), and generic browser labels are a Claude
# Code defect — request all the open browsers and let the human pick. Both govern what the
# MAIN THREAD does before it dispatches anything, so neither can live one document away.
# Measured, not rounded; flagged in the PR body.
# 14622 -> 14737 (launcher-verification-contract/task-006). +115 bytes: the rule promoted
# above now names the general rule it is the narrow case of, in CONVENTIONS.md. The link is
# in the seed because the main thread reads this file and not that one, and a rule with no
# route to its general form is re-derived narrowly. Measured, not rounded; flagged in the PR
# body.
# 14737 -> 14938 (dispatch-reporting-defects/task-016). +201 bytes: the `AB="$(ls …)"`
# snippet, which no permission rule can match, is replaced by the one-command-per-call
# shape and the one-line why the task's criterion 4 requires. Measured, not rounded.
# 14938 -> 16102 (dispatch-reporting-defects/task-028). +1,170 bytes, 15 lines: the
# `Needs you:` reply vocabulary and its carve-out — promote and merge are never inferred
# from a glyph. The main thread reads replies, and only this file reaches it on every
# install; the task capped the addition at 20 lines. Measured, not rounded.
CEILING=16102

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

size="$(wc -c < "$SEED" | tr -d ' ')"
ok "seed/CLAUDE.md exists"                     "$([ -f "$SEED" ] && echo yes || echo no)" yes
ok "…and is under the ${CEILING}-byte ceiling (is: ${size})" \
   "$([ "$size" -le "$CEILING" ] && echo yes || echo no)" yes

# Non-vacuity: the same comparison, fed a fixture past the ceiling, must FAIL — a check
# that can only pass is not a check.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/seedsize.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
head -c "$((CEILING + 1))" /dev/zero | tr '\0' 'x' > "$TMP/oversized.md"
over="$(wc -c < "$TMP/oversized.md" | tr -d ' ')"
ok "a fixture one byte past the ceiling FAILS the identical check" \
   "$([ "$over" -le "$CEILING" ] && echo yes || echo no)" no

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
