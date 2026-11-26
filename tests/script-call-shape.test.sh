#!/usr/bin/env bash
#
# script-call-shape.test.sh — no shipped prompt teaches a plugin-script call that a
# permission rule cannot match. Measured on Claude Code 2.1.284 (task-016): the rule
# `Bash(<cache>/<mk>/loopd/*/scripts/*)` matches `<abs>/x.sh args`, and never a call
# whose path is a variable (plugin/seed/CLAUDE.md's old `AB="$(ls -d …)"; "$AB/x.sh"`),
# a `~` path, or one chained to `$?`. On 2.1.332 no rule matched a path holding a space;
# `Bash(<space-free abs path>/<version>/scripts/<name>.sh *)` did, the form a spaced root
# gets per read-only script. `${CLAUDE_PLUGIN_ROOT}` is the one placeholder allowed. Scans plugin/{skills,tick-steps,agents,seed}/**/*.md and plugin/hooks/hooks.json;
# there is no plugin/commands/.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

cd "$REPO" || exit 2
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find plugin/skills plugin/tick-steps plugin/agents plugin/seed -type f -name '*.md' | sort
  echo plugin/hooks/hooks.json)
ok "prompt files found" "$([ "${#FILES[@]}" -gt 20 ] && echo yes || echo no)" yes

SCRIPT='[A-Za-z0-9_-]+\.sh'
shape() { # <name> <ERE> [allowed fixed string]
  local hits
  hits="$(grep -nE "$2" "${FILES[@]}")"
  [ -z "${3:-}" ] || hits="$(printf '%s\n' "$hits" | grep -vF "$3")"
  [ -z "$hits" ] || printf '%s\n' "$hits" | sed 's/^/        /'
  ok "$1" "$(printf '%s' "$hits" | grep -c .)" 0
}
shape 'no script reached through a shell variable'  "\\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?/(scripts/)?$SCRIPT" \
  'CLAUDE_PLUGIN_ROOT}/'
shape 'no script reached through a ~ path'          "~/[^[:space:]]*/scripts/$SCRIPT"
shape 'no script call chained to $?'                "scripts/$SCRIPT.*\\\$\\?"

# The seed is the surface that taught the idiom, so it must teach the replacement.
ok "plugin/seed/CLAUDE.md names the matchable shape" \
  "$(grep -c 'one command per call' plugin/seed/CLAUDE.md)" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
