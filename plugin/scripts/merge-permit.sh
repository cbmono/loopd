#!/usr/bin/env bash
#
# merge-permit.sh — may THIS pull request be merged from inside THIS bundle, right now?
# The policy half of `deny-destructive.sh`'s `subagent_merge` rule; the hook owns the
# command SHAPE and this owns the mode, the owning project, the role and the receipt.
#
#   merge-permit.sh --bundle DIR --repo O/R --pr N --head SHA --role ROLE
#
# Exit: 0 permits, silently · 1 refuses, printing one line saying why · 2 usage, which
# also refuses. Every unknown is a refusal — that is the whole design.
# Reasoning: ai-bridge-v3/task-044. Verified by tests/subagent-merge-yolo.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)" || exit 2
RESOLVE_AUTONOMY="$HERE/resolve-autonomy.sh"
RECEIPT="$HERE/clearance-receipt.sh"

# The tick, and nothing else. `review-clearance.sh` exit 0 is precondition 2's first half
# and the qa-reviewer earns one on nearly every reviewed PR, so without this a
# software-engineer in a delegated project could merge its own pull request.
MERGER_ROLE="project-manager"

refuse() { printf '%s\n' "$1"; exit 1; }

bundle=""; repo=""; pr=""; head=""; role=""
while [ $# -gt 0 ]; do
  # A bare trailing flag leaves one argument, and `shift 2` then FAILS WITHOUT SHIFTING —
  # with no `set -e` that spins this loop forever (resolve-autonomy.sh carries the same guard).
  case "$1" in --*) [ $# -ge 2 ] || { echo "merge-permit: $1 needs a value" >&2; exit 2; } ;; esac
  case "$1" in
    --bundle) bundle="${2:-}"; shift 2 ;;
    --repo)   repo="${2:-}";   shift 2 ;;
    --pr)     pr="${2:-}";     shift 2 ;;
    --head)   head="${2:-}";   shift 2 ;;
    --role)   role="${2:-}";   shift 2 ;;
    *) echo "merge-permit: unexpected argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$bundle" ] && [ -n "$repo" ] && [ -n "$pr" ] && [ -n "$head" ] || {
  echo "merge-permit: --bundle, --repo, --pr and --head are all required" >&2; exit 2; }
[ -f "$bundle/instance.config.json" ] || {
  echo "merge-permit: $bundle is not a bundle root" >&2; exit 2; }

[ "$role" = "$MERGER_ROLE" ] || \
  refuse "the merge is delegated to the \`$MERGER_ROLE\` tick, and this caller is \`${role:-the main thread}\`"

# 1. Is delegated autonomy installed at all, and where is the file that defines the modes?
[ -x "$RESOLVE_AUTONOMY" ] || refuse "resolve-autonomy.sh is missing, so no mode can be resolved"
autonomy_file="$("$RESOLVE_AUTONOMY" --bundle "$bundle" 2>/dev/null)" || autonomy_file=""
[ -n "$autonomy_file" ] && [ -f "$autonomy_file" ] || \
  refuse "no AUTONOMY.md — the yolo companion is not installed, so every project is \`gated\`"

# 2. Which project owns this PR? Read from the BUNDLE's task documents — a pull request
# cannot raise the autonomy of the project reviewing it. Only the frontmatter `pr:` field
# counts; a task that merely mentions a PR in its prose owns nothing.
repo_re="$(printf '%s' "$repo" | sed 's/[.+*?^$|]/\\&/g')"
names_pr() { # <task doc> — 0 when its `pr:` field carries this PR's URL
  awk '/^---[[:space:]]*$/ { fm++; if (fm == 2) exit; next }
       fm == 1 && /^[A-Za-z_][A-Za-z0-9_-]*:/ { inpr = ($0 ~ /^pr:/) }
       fm == 1 && inpr { print }' "$1" 2>/dev/null \
    | grep -Eq "/$repo_re/pull/$pr([^0-9]|$)"
}

modes=""; owners=""
for task in "$bundle"/projects/*/tasks/*.md; do
  [ -f "$task" ] || continue
  names_pr "$task" || continue
  proj="${task%/tasks/*}"
  case " $owners " in *" ${proj##*/} "*) continue ;; esac
  owners="${owners:+$owners }${proj##*/}"
  mode="$(sed -n 's/^autonomy:[[:space:]]*["'"'"']*\([A-Za-z0-9_-]*\).*/\1/p' "$proj/project.md" 2>/dev/null | head -1)"
  [ -n "$mode" ] || mode="gated"
  mode="$(printf '%s' "$mode" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
  case " $modes " in *" $mode "*) ;; *) modes="${modes:+$modes }$mode" ;; esac
done

[ -n "$owners" ] || refuse "no task document in this bundle names $repo#$pr, so no owning project resolves"
case "$modes" in
  *" "*) refuse "$repo#$pr is named by projects in different autonomy modes ($owners: $modes) — refusing rather than taking the first match" ;;
esac
mode="$modes"

# 3. Does that mode DELEGATE THE MERGE, per the capability file itself? Nothing in the
# call, the environment or the PR can assert it.
defines_merge=""
if grep -qiE "^#+[[:space:]]*Mode:[[:space:]]*\`?$mode\`?[[:space:]]*$" "$autonomy_file"; then
  grep -qiE "^#+[[:space:]]*Merge under[[:space:]]*\`?$mode\`?[[:space:]]*$" "$autonomy_file" && defines_merge=yes
fi
[ -n "$defines_merge" ] || \
  refuse "project \`$owners\` is \`$mode\`, and $autonomy_file does not define that mode as delegating the merge — the human merges"

# 4. The clearance record, read offline, at this exact head. A review-cap line counts only
# for `yolo`, and only while `mergeAtReviewCap` is on (the receipt checks the key).
[ -x "$RECEIPT" ] || refuse "clearance-receipt.sh is missing, so no clearance record can be read"
cap=(); [ "$mode" = yolo ] && cap=(--cap)
receipt_err="$("$RECEIPT" verify ${cap[@]+"${cap[@]}"} --bundle "$bundle" --repo "$repo" --pr "$pr" --head "$head" 2>&1)" \
  || refuse "${receipt_err:-no clearance record for $repo#$pr at $head}"

exit 0
