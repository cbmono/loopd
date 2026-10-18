#!/usr/bin/env bash
#
# lease-form-braced.test.sh — no file under plugin/ writes an expected-sha lease as
# `lease=…$name:…`: zsh reads `$B:h1` as the :h modifier and the colon vanishes.
# Why: plugin/tick-steps/step-4-advance.md, the exit-3 rebase round.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
pass=0 fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 — got [$2], want [$3]"; fi; }
UNBRACED='lease=["'"'"']?[^"'"'"' ]*\$[A-Za-z_][A-Za-z0-9_]*:'
hits() { grep -rnE -- "$UNBRACED" "$@"; }

FX="$(mktemp -d)"; trap 'rm -rf "$FX"' EXIT
printf '%s\n' 'git push "--force-with-lease=$B:h1"' >"$FX/bare"
printf '%s\n' 'git push --force-with-lease="refs/heads/$head:$lease"' >"$FX/quoted"
printf '%s\n' 'git push --force-with-lease="refs/heads/${BRANCH}:${SHA}"' >"$FX/braced"
ok "catches the bare form" "$(hits "$FX/bare" | wc -l | tr -d ' ')" 1
ok "catches the quoted refspec form" "$(hits "$FX/quoted" | wc -l | tr -d ' ')" 1
ok "passes the braced form" "$(hits "$FX/braced" | wc -l | tr -d ' ')" 0

ok "no unbraced lease under plugin/" "$(hits "$TPL/plugin" | sed "s|$TPL/||")" ""

FORM='--force-with-lease="refs/heads/${BRANCH}:${SHA}"'
ok "step 4 gives the braced form" "$(grep -cF -- "$FORM" "$TPL/plugin/tick-steps/step-4-advance.md")" 1
ok "step 4 names the zsh reason" "$(grep -c "zsh reads .*as a modifier" "$TPL/plugin/tick-steps/step-4-advance.md")" 1
ok "software-engineer gives the braced form" "$(grep -cF -- "$FORM" "$TPL/plugin/agents/software-engineer.md")" 1
ok "software-engineer states the rule" \
  "$(grep -cF 'An expected-sha lease is written braced, never `$branch:$sha`' "$TPL/plugin/agents/software-engineer.md")" 1

echo "lease-form-braced: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
