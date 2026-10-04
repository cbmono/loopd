#!/usr/bin/env bash
# dispatch-brief.sh — the five fixed sections the PM pastes into a dispatch brief
# verbatim: `## Grounding (<repo>)`, the Service-doc entry points capped at 15 lines (or
# one line telling the agent to draft the missing doc); `## Effort`, the files/LOC/turns
# budget; `## Commit attribution` and `## PR title`, the resolved `commitAttribution` and
# `ticketPrefix` — answered here so no agent reads either key itself; and `## Scratch`, a
# directory this task alone owns.
# Usage: dispatch-brief.sh <task-doc> [--instance <bundle>]. Exit: 0 printed, 2 cannot
# answer (no task doc, unreadable frontmatter). Never fails a dispatch — an absent config
# key falls back to the documented default. Reasoning: ai-bridge-next/task-017 (bands),
# task-031 (attribution), ai-bridge-v3/task-053 (scratch),
# dispatch-reporting-defects/task-030 (ticket prefix).
set -uo pipefail

GROUNDING_MAX_LINES=15
# THE ONE COPY OF EACH HEADING. project-manager.md quotes them and
# tests/dispatch-brief.test.sh pins them against this file, so a rename cannot land in one
# place only.
GROUNDING_HEADING='## Grounding'
EFFORT_HEADING='## Effort'
ATTRIBUTION_HEADING='## Commit attribution'
TITLE_HEADING='## PR title'
SCRATCH_HEADING='## Scratch'

usage() { sed -n '2,10p' "$0" >&2; exit 2; }

fm_block() { # <file> — the frontmatter, or exit 3/4 for a shape we will not read
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

field() { # <key> <frontmatter> — only the FIRST occurrence counts
  printf '%s\n' "$2" | awk -v key="$1" '
    !got && index($0, key ":") == 1 {
      v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

list_region() { # <key> <frontmatter> — the key line's value plus its block-sequence lines
  printf '%s\n' "$2" | awk -v key="$1" '
    !got && index($0, key ":") == 1 {
      v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); print v; got = 1; inblk = 1; next
    }
    inblk && /^[[:space:]]+-/ { print; next }
    inblk && /^[[:space:]]*$/ { next }
    { inblk = 0 }'
}

count_entries() { # <list region, flow or block> — always a number, so an absent field bands as 0
  printf '%s\n' "$1" | awk '
    { n = split($0, a, "\""); c += (n > 1) ? int(n / 2) : 0 }
    END { print c + 0 }'
}

worktree_path() { # <slug> — the task's recorded worktree, else where it will be created
  local w r
  w="$(field worktree "$FM")"
  [ -n "$w" ] && { printf '%s' "$w"; return; }
  w="$(cfg worktreeRoot "")"
  [ -n "$w" ] || { r="$(cfg reposRoot "")"; [ -n "$r" ] && w="$r/_wt"; }
  printf '%s' "${w:+$w/$1}"
}

cfg() { # <key> <default>
  local v=""
  [ -n "$INSTANCE" ] && [ -x "$(command -v python3 || true)" ] &&
    v="$(bash "$BIN/resolve-config.sh" --instance "$INSTANCE" "$1" 2>/dev/null)"
  printf '%s' "${v:-$2}"
}

TASK=""; INSTANCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; INSTANCE="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "dispatch-brief: unexpected option '$1'" >&2; usage ;;
    *) [ -z "$TASK" ] || { echo "dispatch-brief: one task document, not two" >&2; usage; }
       TASK="$1"; shift ;;
  esac
done
[ -n "$TASK" ] || usage
[ -f "$TASK" ] || { echo "dispatch-brief: no such task document: $TASK" >&2; exit 2; }
BIN="$(cd "$(dirname "$0")" && pwd)"

# The bundle is the nearest ancestor of the task document holding instance.config.json —
# the same anchor `/<plugin>:init` writes, so nothing has to be passed in.
if [ -z "$INSTANCE" ]; then
  d="$(cd "$(dirname "$TASK")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -f "$d/instance.config.json" ] && { INSTANCE="$d"; break; }
    d="$(dirname "$d")"
  done
fi

FM=""; fm_rc=0
FM="$(fm_block "$TASK")" || fm_rc=$?
[ "$fm_rc" -eq 0 ] || {
  echo "dispatch-brief: $TASK has no readable YAML frontmatter — refusing rather than" >&2
  echo "                printing a brief whose target repo is a guess." >&2
  exit 2
}

REPO="$(field target_repo "$FM")"
CRITERIA="$(count_entries "$(list_region acceptance_criteria "$FM")")"
SERVICE=""
[ -n "$REPO" ] && [ -n "$INSTANCE" ] && SERVICE="$INSTANCE/knowledge/services/${REPO##*/}.md"
TARGET_REPO="$REPO"
[ -n "$REPO" ] || REPO="(no target_repo on the task)"

printf '%s (%s)\n\n' "$GROUNDING_HEADING" "$REPO"

if [ -n "$SERVICE" ] && [ -f "$SERVICE" ]; then
  {
    printf 'Service doc: %s — read it before you read code.\n' "$SERVICE"
    # An explicit `# Entry points` section wins; absent one, the doc's identity plus its
    # section list is what a cold agent needs to know where to start.
    entry="$(awk '/^#+ *Entry points/{f=1;next} f&&/^#+ /{exit} f' "$SERVICE" | sed '/^$/d')"
    if [ -n "$entry" ]; then
      printf '%s\n' "$entry"
    else
      SFM="$(fm_block "$SERVICE" 2>/dev/null)" || SFM=""
      for k in path stack runtime; do
        v="$(field "$k" "$SFM")"; [ -n "$v" ] && printf '%s: %s\n' "$k" "$v"
      done
      # `paste -d` takes a single BYTE, so the separator is joined as ASCII and widened after.
      printf 'Sections: %s\n' "$(grep '^##* ' "$SERVICE" | sed 's/^#* *//' | paste -sd '|' - | sed 's/|/ · /g')"
    fi
  } | awk -v max="$GROUNDING_MAX_LINES" '
      NR < max { print; next }
      NR == max { print "… truncated at " max " lines — open the Service doc for the rest"; exit }'
else
  # shellcheck disable=SC2016  # backticks are markdown, not a subshell
  printf 'No Service doc for %s. Draft `knowledge/services/%s.md` in the bundle alongside this task, for the `cataloguer` to review.\n' \
    "$REPO" "${REPO##*/}"
fi

# Bands measured over 47 merged cbmono/loopd PRs paired with their task's criteria
# count (2026-09-06): 0-3 → 6 files/142 lines, 4-6 → 14/306, 7+ → 20/597.
if   [ "$CRITERIA" -le 3 ]; then BAND=small;    FILES=6;  TURNS=3
elif [ "$CRITERIA" -le 6 ]; then BAND=standard; FILES=14; TURNS=5
else                             BAND=large;    FILES=20; TURNS=8
fi

printf '\n%s\n\n' "$EFFORT_HEADING"
printf 'Files expected: ~%s (band %s — %s acceptance criteria). A wildly different number is a signal, not a rule.\n' \
  "$FILES" "$BAND" "$CRITERIA"
printf 'LOC ceiling: %s (maxPrLoc), %s files (maxPrFiles) — past either, propose a split in the PR body.\n' \
  "$(cfg maxPrLoc 500)" "$(cfg maxPrFiles 100)"
printf 'Turns: be making your first edit by turn ~%s. Still only reading past ~%s ⇒ say so in your report.\n' \
  "$TURNS" "$((TURNS * 2))"

# Only the exact string `none` switches attribution off; every other answer, including a
# typo and an absent key, is the documented `claude` default (seed instance.config.json).
printf '\n%s\n\n' "$ATTRIBUTION_HEADING"
if [ "$(cfg commitAttribution claude)" = none ]; then
  printf 'commitAttribution: none — write NO attribution trailer and NO session URL on a target-repo commit. This installation opted out.\n'
else
  printf 'commitAttribution: claude — end every target-repo commit with the `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer the harness provides.\n'
fi

# Only a Jira-shaped key is a prefix; anything else is absent, so the default is no tag.
printf '\n%s\n\n' "$TITLE_HEADING"
PREFIX="$(cfg ticketPrefix "")"
if [[ "$PREFIX" =~ ^[A-Z][A-Z0-9_]+$ ]]; then
  printf 'ticketPrefix: %s — title is `<type>: <subject> [%s-<n>]`, with the id your task or this brief names, and `[%s-0]` when neither names one.\n' \
    "$PREFIX" "$PREFIX" "$PREFIX"
else
  printf 'ticketPrefix: none — title is `<type>: <subject>` and NOTHING after it: no bracketed tag. This installation names no ticket system.\n'
fi

# The task slug is what makes this path unique: a tick spawns several agents into ONE
# session, so every per-session path they are handed is the same path (ai-bridge-v3/task-053).
SLUG="$(basename "$TASK" .md)"
WT="$(worktree_path "$SLUG")"; [ -n "$WT" ] || WT='<worktree>'
CLONE=""; REPOS_ROOT="$(cfg reposRoot "")"
[ -n "$TARGET_REPO" ] && [ -n "$REPOS_ROOT" ] && CLONE="$REPOS_ROOT/${TARGET_REPO##*/}"

IGNORED=unknown
if [ -n "$CLONE" ] && git -C "$CLONE" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$CLONE" check-ignore -q "tmp/$SLUG/draft"; then IGNORED=yes; else IGNORED=no; fi
fi

case "$IGNORED" in
  yes) SCRATCH="$WT/tmp/$SLUG"
       NOTE="$(printf '`%s` ignores `tmp/` (`git check-ignore` in %s), so nothing you write here can reach a commit.' "$TARGET_REPO" "$CLONE")" ;;
  no)  SCRATCH="${TMPDIR:-/tmp}"; SCRATCH="${SCRATCH%/}/ai-bridge-scratch/$SLUG"
       NOTE="$(printf '`%s` does NOT ignore `tmp/` (`git check-ignore` in %s), so this path is outside the repo instead.' "$TARGET_REPO" "$CLONE")" ;;
  *)   SCRATCH="$WT/tmp/$SLUG"
       NOTE="$(printf 'No clone to check, so whether the repo ignores `tmp/` is UNKNOWN — run `git check-ignore -q tmp/%s` in your worktree before you write, and use a path outside the repo if it says no.' "$SLUG")" ;;
esac

printf '\n%s\n\n' "$SCRATCH_HEADING"
printf 'Scratch directory — this task alone owns it. Create it, and keep every draft, probe and throwaway config inside it:\n%s\n' "$SCRATCH"
printf 'Never the session scratchpad and never a path from another task: one tick spawns several agents into one session, and a shared `pr-body.md` is one a sibling overwrites.\n'
printf '%s\n' "$NOTE"
