#!/usr/bin/env bash
#
# clearance-receipt.sh — the merge gate's preconditions, recorded on disk at the head they
# were checked against, so the PreToolUse hook can read them OFFLINE.
#
#   clearance-receipt.sh record <script> [--kind internal|external] [--fail] --repo O/R --pr N --head SHA [--bundle DIR]
#   clearance-receipt.sh record review-next.sh --unreviewed last-round|qa-zero|zero-zero --repo O/R --pr N --head SHA [--bundle DIR]
#   clearance-receipt.sh verify [--unreviewed] --repo O/R --pr N --head SHA [--bundle DIR]
#   clearance-receipt.sh path   --repo O/R --pr N --head SHA [--bundle DIR]
#
# Exit: 0 recorded / complete / printed · 1 absent or incomplete · 2 usage, or no bundle.
# `record` never fails a caller: outside a bundle it exits 0 having written nothing.
# An `--unreviewed` line is read only by `verify --unreviewed` (merge-permit.sh, `yolo` only).
# Reasoning: ai-bridge-v3/task-044, loopd-papercuts/task-010, loopd-papercuts/task-005.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

# What a delegated merge needs, all at the SAME head. A `review-clearance.sh` receipt alone
# is precondition 2's first half and the qa-reviewer earns one on nearly every PR. The
# checker table (CHECKER) is required only where no EXTERNAL reviewer cleared the head —
# a REVIEWERS vendor by route A or C; a line with no kind predates the kinds and is internal.
REQUIRED="review-clearance.sh required-checks.sh pr-body-clearance.sh"
CHECKER="pr-verdict-clearance.sh"
KEEP_DAYS=14

usage() {
  sed -n '5,10p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

mode="${1:-}"; [ $# -gt 0 ] && shift
script=""; kind=""; result=pass; unrev=""
case "$mode" in
  record) script="${1:-}"; [ -n "$script" ] || usage; shift ;;
  verify|path) ;;
  *) usage ;;
esac

bundle=""; repo=""; pr=""; head=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) bundle="${2:-}"; [ -n "$bundle" ] || usage; shift 2 ;;
    --repo)   repo="${2:-}";   [ -n "$repo" ] || usage; shift 2 ;;
    --pr)     pr="${2:-}";     [ -n "$pr" ] || usage; shift 2 ;;
    --head)   head="${2:-}";   [ -n "$head" ] || usage; shift 2 ;;
    --kind)   [ "$mode" = record ] || usage
              case "${2:-}" in internal|external) kind="$2" ;; *) usage ;; esac; shift 2 ;;
    --fail)   [ "$mode" = record ] || usage; result=fail; shift ;;
    --unreviewed)
      case "$mode" in
        record) [ "$script" = review-next.sh ] || usage
                case "${2:-}" in last-round|qa-zero|zero-zero) result="$2" ;; *) usage ;; esac; shift 2 ;;
        verify) unrev=yes; shift ;;
        *) usage ;;
      esac ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

case "$repo" in */*) ;; *) usage ;; esac
case "$pr" in ''|*[!0-9]*) usage ;; esac
case "$head" in [0-9a-fA-F][0-9a-fA-F]*) ;; *) usage ;; esac

# The bundle root, in the order a caller can be sure of: the flag, then the session's own
# project dir, then the first ancestor carrying the marker.
if [ -z "$bundle" ]; then
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/instance.config.json" ]; then
    bundle="$CLAUDE_PROJECT_DIR"
  else
    d="$PWD"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
      [ -f "$d/instance.config.json" ] && { bundle="$d"; break; }
      d="$(dirname "$d")"
    done
  fi
fi
if [ -z "$bundle" ] || [ ! -f "$bundle/instance.config.json" ]; then
  [ "$mode" = record ] && exit 0
  echo "clearance-receipt: no bundle root — refusing (fail closed)" >&2
  exit 2
fi

safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
dir="$bundle/$AB_RECEIPTS"
file="$dir/$(safe "$repo")__pr$(safe "$pr")__$(safe "$head")"

case "$mode" in
  path)
    printf '%s\n' "$file"
    [ -f "$file" ]
    exit $?
    ;;

  verify)
    [ -f "$file" ] || { echo "clearance-receipt: no receipt for $repo#$pr at $head" >&2; exit 1; }
    # The head is in the file NAME and again in the file, and both must say this SHA: a
    # receipt earned at an earlier head must not authorise a later one under any spelling.
    grep -qx "head $head" "$file" || {
      echo "clearance-receipt: the receipt for $repo#$pr does not name head $head — refusing" >&2
      exit 1
    }
    # A merge with no review at this head (review-next.sh --clear) stands in for the review
    # pass and the checker table; after the last round, its FAIL rows count as addressed.
    path=""
    [ -n "$unrev" ] && path="$(awk '$2 == "review-next.sh" && ($1 == "last-round" || $1 == "qa-zero" || $1 == "zero-zero") { print $1 }' \
      "$file" 2>/dev/null | tail -n 1)"
    failed="$(awk -v p="$path" '$1 == "fail" && !(p == "last-round" && $2 == "pr-verdict-clearance.sh") { print $2 }' \
      "$file" 2>/dev/null | tr '\n' ' ')"
    [ -z "$failed" ] || {
      echo "clearance-receipt: $repo#$pr at $head failed: ${failed% } — refusing" >&2
      exit 1
    }
    got="$(awk '$1 == "pass" { print $2 }' "$file" 2>/dev/null)"
    need="$REQUIRED"
    if [ -n "$path" ]; then
      need="required-checks.sh pr-body-clearance.sh"
    else
      awk '$1 == "pass" && $2 == "review-clearance.sh" && $4 == "external" { f = 1 } END { exit !f }' \
        "$file" 2>/dev/null || need="$need $CHECKER"
    fi
    missing=""
    for r in $need; do
      printf '%s\n' "$got" | grep -qx "$r" || missing="${missing:+$missing }$r"
    done
    [ -z "$missing" ] || {
      echo "clearance-receipt: $repo#$pr at $head has not passed: $missing" >&2
      exit 1
    }
    exit 0
    ;;

  record)
    mkdir -p "$dir" 2>/dev/null || exit 0
    tmp="$file.$$"
    {
      printf 'repo %s\npr %s\nhead %s\n' "$repo" "$pr" "$head"
      # One line per script AND kind: an internal run at this head cannot erase an external one.
      [ -f "$file" ] && awk '$1 ~ /^(pass|fail|last-round|qa-zero|zero-zero)$/ &&
        !($2 == s && ($4 == "external" ? "external" : "internal") == k)' \
        s="$script" k="${kind:-internal}" "$file"
      printf '%s %s %s%s\n' "$result" "$script" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${kind:+ $kind}"
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
    find "$dir" -type f -mtime "+$KEEP_DAYS" -delete 2>/dev/null
    exit 0
    ;;
esac
