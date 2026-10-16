#!/usr/bin/env bash
#
# round-report-convention.test.sh — the three `--bg` roles end a round with a report and
# put every ask in `open_questions`; nothing in the plugin predicts the CLI's verdict.
# Why: plugin/seed/CONVENTIONS.md → "A round's final message is a report, not an ask".
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$TPL/plugin/seed/CONVENTIONS.md"
pass=0 fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 — got [$2], want [$3]"; fi; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

ok "CONVENTIONS states the rule" "$(has "$CONV" "**A round's final message is a report, not an ask**")" yes
for r in software-engineer devops-engineer qa-reviewer; do
  ok "CONVENTIONS scopes it to $r" "$(sed -n "/final message is a report, not an ask/,/^- /p" "$CONV" | grep -c "\`$r\`")" 1
done
ok "CONVENTIONS routes the escalation block to open_questions" \
  "$(has "$CONV" "the task's \`open_questions\`, not the final message.")" yes

for r in software-engineer devops-engineer; do
  f="$TPL/plugin/agents/$r.md"
  ok "$r: final message ends with one status line" "$(has "$f" "and ends with one status line; anything the human must decide or provide goes in the")" yes
  ok "$r: the TWO ROUNDS block goes to open_questions" "$(has "$f" "defines into the task's \`open_questions\`")" yes
  ok "$r: no ask routed to the final message" "$(grep -c "and report\$\|Your final message summarizes" "$f")" 0
done
ok "qa-reviewer: final message ends with one status line" \
  "$(has "$TPL/plugin/agents/qa-reviewer.md" "Your final message reports the verdict and ends with one status line")" yes

ok "no classifier: only agent-sessions.sh reads suggestedReply" \
  "$(grep -rl "suggestedReply" "$TPL/plugin" --include='*.sh' | sed "s|$TPL/||")" "plugin/scripts/agent-sessions.sh"

echo "round-report-convention: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
