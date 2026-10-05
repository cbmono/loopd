#!/usr/bin/env bash
#
# concision-contract.test.sh — the reader for `CONVENTIONS.md` -> "Write less".
#
# Three questions, one file: is the section there with its numbers, does every role agent
# point at it, and is the one number a harness can measure — a shell file's comment-line
# share — going down rather than up.
#
# THE RATCHET, EXACTLY. Share = comment lines / total lines, in TENTHS OF A PERCENT so a
# file cannot absorb a dozen new comment lines inside one rounded point. A comment line is
# one whose first non-blank character is `#`, less the shebang; that over-counts a heredoc
# carrying `#` lines, which refuses earlier and is the safe direction.
#
#   * CAP is 350 (35.0%). A file NOT in the table below — every new one — must be under it.
#   * A file IN the table is already over the cap and may not GROW its share. Its row is
#     today's measured value, so the next comment line it gains turns this red.
#   * A row for a file that no longer exists fails: the table is not allowed to rot.
#
# Rows only ever get lowered or dropped, and each file owns its own line, so two branches
# touching different files never edit the same line. The table lives HERE and not in a
# fixture on purpose: `.github/workflows/tests.yml` selects a harness for a plugin-only
# diff when the harness NAMES a changed path, and a table in another file would leave the
# ratchet unrun on exactly the pull requests it exists for.
#
# Seeded 2026-09-06 (ai-bridge-next/task-004). ok() compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
CAP=350

BASELINE='577 plugin/hooks/agent-control.sh
598 plugin/hooks/push-state.sh
694 plugin/hooks/session-banner.sh
463 plugin/scripts/welcome.sh
423 plugin/scripts/check-dispatch.sh
576 plugin/scripts/check-template-version.sh
376 plugin/scripts/close-project-folder.sh
425 plugin/scripts/commit-as.sh
432 plugin/scripts/init-bundle.sh
375 plugin/scripts/link-repos.sh
423 plugin/scripts/pr-body-clearance.sh
448 plugin/scripts/pr-comment-clearance.sh
493 plugin/scripts/prune-worktrees.sh
337 plugin/scripts/refresh-seeds.sh
436 plugin/scripts/required-checks.sh
541 plugin/scripts/resolve-autonomy.sh
621 plugin/scripts/resolve-max-agents.sh
578 plugin/scripts/resolve-model.sh
522 plugin/scripts/review-clearance.sh
525 plugin/scripts/review-rounds.sh
416 plugin/scripts/task-owner.sh
365 plugin/scripts/tick-delta.sh
605 plugin/scripts/tick-lock.sh
356 plugin/scripts/validate-bundle.sh
466 plugin/scripts/watch-board.sh
503 plugin/scripts/write-snapshot.sh'

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# Tenths of a percent, LC_ALL=C so the count is the same on every machine.
share() { # <file> -> comment share in tenths of a percent
  LC_ALL=C awk '
    NR == 1 && /^#!/ { total++; next }
    { total++; if ($0 ~ /^[[:space:]]*#/) c++ }
    END { if (total == 0) print 0; else printf "%d\n", c * 1000 / total }
  ' "$1"
}

saw() { grep -Fq -- "$2" "$1" && echo yes || echo no; }

echo "== CONVENTIONS.md carries the section, with every number =="
ok "the section exists"                    "$(saw "$CONV" '## Write less')" yes
ok "inline comment: none by default"       "$(saw "$CONV" '**none by default — it is a trigger, not a budget.**')" yes
ok "…and it names its three triggers"      "$(saw "$CONV" 'is **risky to change**, or carries a **trap the reader would not see**')" yes
ok "…and the named non-trigger"            "$(saw "$CONV" '**Explaining what the code does is not a trigger**')" yes
ok "script header: 10 lines"               "$(saw "$CONV" '**10 lines**')" yes
ok "commit subject 72, body 5"             "$(saw "$CONV" 'subject **72 characters**, body at most **5 lines**')" yes
ok "PR body: 2,500 characters"             "$(saw "$CONV" 'Hard ceiling **2,500 characters**')" yes
ok "PR body: at most 3 notes"              "$(saw "$CONV" 'at most **3 one-line notes**')" yes
ok "task Result: 15 lines"                 "$(saw "$CONV" 'a task **`# Result`** | **15 lines**')" yes
ok "Finding: 40 lines and a lesson"        "$(saw "$CONV" '**40 lines**, and a required one-line `lesson:`')" yes
# The ceilings are licence to drop narration, never evidence — the floor the sibling
# gate already enforces. Without this line the section reads as "say less of anything".
ok "…and it never licenses dropping evidence" \
   "$(saw "$CONV" 'Nothing here licenses dropping evidence')" yes
ok "…the reasoning is relocated, not deleted"  "$(saw "$CONV" 'relocated, never deleted')" yes
# The three numbers with readers say who reads them, so nobody re-derives it.
ok "it names its own three readers"        \
   "$(grep -cF -e 'pr-body-clearance.sh` refuses a body over 2,500' "$CONV")" 1

echo
echo "== every role agent contract points at it =="
# The path is anchored to the plugin root, not to a cwd: the body is read from the plugin
# cache and the agent runs with a bundle or a worktree as its cwd, so `../../` was dead
# from both. tests/agent-body-links.test.sh owns that invariant; this line only pins that
# the pointer is still here.
POINTER='**Write less.** Read `${CLAUDE_PLUGIN_ROOT}/seed/CONVENTIONS.md` → "Write less" before you'
agents=0
for a in "$REPO"/plugin/agents/*.md; do
  agents=$((agents + 1))
  ok "$(basename "$a") points at the section" "$(saw "$a" "$POINTER")" yes
done
ok "every agent file was checked (8 today)" "$([ "$agents" -ge 8 ] && echo yes || echo no)" yes

echo
echo "== the plugin comment-share ratchet =="
over=0; stale=0; checked=0
while IFS=' ' read -r allowed rel; do
  [ -n "${rel:-}" ] || continue
  if [ ! -f "$REPO/$rel" ]; then
    printf '  FAIL  %-62s baseline row names a file that is gone\n' "$rel"
    stale=$((stale + 1)); fail=$((fail + 1)); continue
  fi
  now="$(share "$REPO/$rel")"
  checked=$((checked + 1))
  if [ "$now" -gt "$allowed" ]; then
    printf '  FAIL  %-62s %s.%s%% > its baseline %s.%s%%\n' "$rel" \
      "$((now / 10))" "$((now % 10))" "$((allowed / 10))" "$((allowed % 10))"
    over=$((over + 1)); fail=$((fail + 1))
  else
    printf '  PASS  %-62s %s.%s%% <= %s.%s%%\n' "$rel" \
      "$((now / 10))" "$((now % 10))" "$((allowed / 10))" "$((allowed % 10))"
    pass=$((pass + 1))
  fi
done <<EOF
$BASELINE
EOF
ok "every baseline row resolves to a file"  "$stale" 0
ok "no ratcheted file grew its share"       "$over" 0
ok "the baseline is the 26 files over the cap" "$checked" 26

# Everything NOT in the table — including every new file — is held to the flat cap.
newover=0
while IFS= read -r f; do
  rel="${f#"$REPO"/}"
  case "$BASELINE" in *" $rel"*) continue ;; esac
  now="$(share "$f")"
  if [ "$now" -gt "$CAP" ]; then
    printf '  FAIL  %-62s %s.%s%% > the %s.%s%% cap, and has no baseline row\n' "$rel" \
      "$((now / 10))" "$((now % 10))" "$((CAP / 10))" "$((CAP % 10))"
    newover=$((newover + 1)); fail=$((fail + 1))
  fi
done <<EOF
$(find "$REPO/plugin" -name '*.sh' | sort)
EOF
ok "no un-baselined plugin script is over 35%" "$newover" 0

# NON-VACUITY. A check that can only pass is not a check, so the identical measurement is
# driven over a fixture on each side of the cap.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/concision.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
{ echo '#!/usr/bin/env bash'; for i in $(seq 4); do echo "# comment $i"; done
  for i in $(seq 6); do echo "code $i"; done; } > "$TMP/over.sh"
{ echo '#!/usr/bin/env bash'; for i in $(seq 3); do echo "# comment $i"; done
  for i in $(seq 7); do echo "code $i"; done; } > "$TMP/under.sh"
ok "a 4-in-11 file measures 363 tenths"      "$(share "$TMP/over.sh")" 363
ok "…and is OVER the cap"                    "$([ "$(share "$TMP/over.sh")" -gt "$CAP" ] && echo yes || echo no)" yes
ok "a 3-in-11 file measures 272 tenths"      "$(share "$TMP/under.sh")" 272
ok "…and is UNDER it"                        "$([ "$(share "$TMP/under.sh")" -gt "$CAP" ] && echo yes || echo no)" no
# The shebang is not a comment: counting it would put every short script over the cap.
ok "the shebang is excluded"                 "$(share "$TMP/under.sh")" 272

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
