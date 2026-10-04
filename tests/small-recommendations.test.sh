#!/usr/bin/env bash
#
# small-recommendations.test.sh — four one-line rules, each pinned where it was put:
# `non_goals:` on a Project and NOT on a Task (plugin/seed/SCHEMA.md), the advisory
# unapproved-decision note (plugin/agents/qa-reviewer.md), docs-in-the-same-PR
# (plugin/agents/software-engineer.md) and the proposed eval case
# (plugin/agents/failure-analyst.md). Text only: no fixture, no git.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
QA="$REPO/plugin/agents/qa-reviewer.md"
SE="$REPO/plugin/agents/software-engineer.md"
FA="$REPO/plugin/agents/failure-analyst.md"
pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }
section() { # <heading prefix> — that `## type:` section of SCHEMA.md, up to the next one
  awk -v h="$1" 'index($0, h) == 1 { f = 1; print; next } f && /^## type: / { exit } f' "$SCHEMA"; }

PROJECT="$(section '## type: Project')"; TASK="$(section '## type: Task')"
ok "the section extractor finds a Project block"  "$(printf '%s\n' "$PROJECT" | grep -c '^type: Project$')" 1
ok "the section extractor finds a Task block"     "$(printf '%s\n' "$TASK" | grep -c '^type: Task$')" 1
ok "non_goals is a Project key"                   "$(printf '%s\n' "$PROJECT" | grep -c '^non_goals: ')" 1
ok "non_goals appears nowhere in the Task block"  "$(printf '%s\n' "$TASK" | grep -c 'non_goals')" 0
NG="$(printf '%s\n' "$PROJECT" | grep '^non_goals: ')"
ok "non_goals is optional"                        "$(printf '%s' "$NG" | grep -c '# optional')" 1
ok "a recurring decision is routed to a Finding"  "$(printf '%s' "$NG" | grep -c "belongs in a \`Finding\`")" 1
ok "validate-bundle.sh does not read non_goals"   "$(grep -c 'non_goals' "$REPO/plugin/scripts/validate-bundle.sh")" 0
ok "/new-project does not ask for non_goals"      "$(grep -c 'non_goals' "$REPO/plugin/skills/new-project/SKILL.md")" 0

ok "qa-reviewer: the unapproved-decision note"    "$(has "$QA" '"Unapproved decision:"')" yes
ok "qa-reviewer: it is not a trailer caveat"      "$(has "$QA" 'never a trailer `caveats:` entry')" yes
ok "qa-reviewer: taste never qualifies"           "$(has "$QA" 'grade against the criteria, not against your own taste')" yes
ok "CONVENTIONS.md still carries the cited rule"  "$(has "$REPO/plugin/seed/CONVENTIONS.md" 'grade against the criteria, not against your own taste')" yes
ok "SCHEMA.md clause 6 still refuses a caveat"    "$(has "$SCHEMA" '6. **`caveats: none`**')" yes

ok "software-engineer: docs move with behaviour"  "$(has "$SE" 'If the change alters behaviour that a document in the repo describes, update that document in the same PR.')" yes

ok "failure-analyst: an eval case is proposed"    "$(has "$FA" '**Eval case (optional)**')" yes
ok "failure-analyst: in the evals vocabulary"     "$(has "$FA" 'evals/README.md')" yes
ok "failure-analyst: it writes no file"           "$(has "$FA" 'Propose only — you write no file.')" yes
ok "plugin/evals/README.md documents grader types" "$(has "$REPO/plugin/evals/README.md" '## The grader types')" yes

printf '\nsmall-recommendations: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
