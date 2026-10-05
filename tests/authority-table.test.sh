#!/usr/bin/env bash
#
# authority-table.test.sh — SCHEMA.md's "Which document wins" table stays truthful.
#
# WHY. loopd has several instruction documents and, until this table, no statement of
# which one wins when two disagree. The live case: /loopd:answer's precondition probed a
# `.claude/agents` directory that no 3.0 bundle has, while /loopd:dispatch said the check
# must not look for one — two documents, one bundle, opposite instructions, and no rule
# for which to fix. A hand-maintained table drifts the same way unless something reads it,
# so this harness asserts three things on every run:
#   (a) the section exists in plugin/seed/SCHEMA.md;
#   (b) every path or glob the table names resolves to at least one file in this repo
#       — a row that points at nothing is a row nobody can follow;
#   (c) every plugin/agents/*.md, plugin/tick-steps/*.md and plugin/skills/*/SKILL.md is
#       matched by some row's glob, so a new instruction document cannot land without an
#       owner.
# Non-vacuity: the same parser runs over a planted fixture carrying one dangling glob and
# one unowned document, and must report exactly those.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
HEADING='# Which document wins'

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# section <schema> — the lines from the heading to the next top-level heading.
section() { awk -v h="$HEADING" '$0==h{p=1;next} p&&/^# /{exit} p' "$1"; }

# globs <schema> — every backticked token in the section that names a repo path: rooted
# at plugin/, docs/, tests/ or .claude/, or the repo's own CLAUDE.md. Prose in backticks
# (`SCHEMA.md`, a config key) is not a path and is not parsed.
globs() {
  section "$1" | grep -o '`[^`]*`' | tr -d '`' \
    | grep -E '^(plugin/|docs/|tests/|\.claude/|CLAUDE\.md$)' | sort -u
}

# expand <root> <glob> — the files the glob names under root, one per line; nothing when
# it names none. nullglob is scoped to the subshell.
expand() { ( cd "$1" || exit 1; shopt -s nullglob; for f in $2; do [ -f "$f" ] && echo "$f"; done ); }

# dangling <root> <schema> — the globs that resolve to no file.
dangling() {
  local g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    [ -n "$(expand "$1" "$g")" ] || echo "$g"
  done <<<"$(globs "$2")"
}

# unowned <root> <schema> <set-glob>... — the files in the sets no table glob names.
unowned() {
  local root="$1" schema="$2" g owned f; shift 2
  owned="$(while IFS= read -r g; do [ -n "$g" ] && expand "$root" "$g"; done <<<"$(globs "$schema")")"
  for set in "$@"; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      printf '%s\n' "$owned" | grep -qxF "$f" || echo "$f"
    done <<<"$(expand "$root" "$set")"
  done
}

SETS=('plugin/agents/*.md' 'plugin/tick-steps/*.md' 'plugin/skills/*/SKILL.md')

echo "== (a) the section exists =="
ok "SCHEMA.md is readable"                 "$([ -f "$SCHEMA" ] && echo yes || echo no)" yes
ok "heading '$HEADING' present once"       "$(grep -cxF "$HEADING" "$SCHEMA" | tr -d ' ')" 1
rows="$(section "$SCHEMA" | grep -c '^| `\|^| [^-|]')"
ok "the section carries a table (>= 8 rows incl. header)" "$([ "$rows" -ge 8 ] && echo yes || echo "no ($rows)")" yes
ok "it says what to do on a contradiction" \
   "$(section "$SCHEMA" | grep -ciE 'fix the non-authoritative' | tr -d ' ')" 1
ok "…and that nobody asks"                 "$(section "$SCHEMA" | grep -ciE 'never ask' | tr -d ' ')" 1

echo "== (b) every path the table names resolves =="
n="$(globs "$SCHEMA" | grep -c .)"
ok "the table names paths (>= 8 distinct)" "$([ "$n" -ge 8 ] && echo yes || echo "no ($n)")" yes
d="$(dangling "$REPO" "$SCHEMA")"
[ -z "$d" ] || printf '%s\n' "$d" | sed 's/^/        DANGLING /'
ok "no path or glob resolves to nothing"   "$(printf '%s' "$d" | grep -c .)" 0

echo "== (c) every agent, tick step and skill is under some row =="
for set in "${SETS[@]}"; do
  ok "the set '$set' is non-empty here" "$([ -n "$(expand "$REPO" "$set")" ] && echo yes || echo no)" yes
done
u="$(unowned "$REPO" "$SCHEMA" "${SETS[@]}")"
[ -z "$u" ] || printf '%s\n' "$u" | sed 's/^/        UNOWNED /'
ok "no instruction document is outside every row" "$(printf '%s' "$u" | grep -c .)" 0

echo "== non-vacuity: the parser flags a planted dangling glob and a planted unowned doc =="
TMP="$(mktemp -d "${TMPDIR:-/tmp}/authority-table.XXXXXX")" || {
  echo "authority-table.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugin/agents" "$TMP/plugin/tick-steps" "$TMP/plugin/skills/one" "$TMP/plugin/seed"
: > "$TMP/plugin/agents/owned.md"; : > "$TMP/plugin/tick-steps/step-9.md"; : > "$TMP/plugin/skills/one/SKILL.md"
printf '%s\n' '# Before' 'prose' "$HEADING" 'intro `SCHEMA.md` is prose, not a path' \
  '| Concern | Authoritative | Others |' '|---|---|---|' \
  '| agents | `plugin/agents/*.md` | — |' \
  '| skills | `plugin/skills/*/SKILL.md` | — |' \
  '| gone | `plugin/retired/*.md` | — |' \
  'Fix the non-authoritative document; never ask.' '# After' '| `plugin/tick-steps/*.md` is past the section |' \
  > "$TMP/plugin/seed/SCHEMA.md"
ok "fixture: three globs parsed, prose ignored, next section excluded" \
   "$(globs "$TMP/plugin/seed/SCHEMA.md" | tr '\n' ' ')" "plugin/agents/*.md plugin/retired/*.md plugin/skills/*/SKILL.md "
ok "fixture: exactly the retired glob is dangling" "$(dangling "$TMP" "$TMP/plugin/seed/SCHEMA.md" | tr '\n' ' ')" "plugin/retired/*.md "
ok "fixture: exactly the tick step is unowned" \
   "$(unowned "$TMP" "$TMP/plugin/seed/SCHEMA.md" "${SETS[@]}" | tr '\n' ' ')" "plugin/tick-steps/step-9.md "

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
