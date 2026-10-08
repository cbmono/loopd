#!/usr/bin/env bash
#
# prune-wt.sh — remove what prune-worktrees.sh reports REMOVABLE, behind /loopd:prune-wt.
#
#   prune-wt.sh          preview: each REMOVABLE path and whether it would go; touches nothing
#   prune-wt.sh --yes    remove every one that still passes, then `git worktree prune` per repo
#
# Exit: 0 done (a skip is reported, not a failure) · 1 REFUSED (a tick holds the lock) or a
# removal failed · 2 cannot answer. Each path is re-checked here with reclaim-worktree.sh's
# guards; no forced removal, ever. Reasoning: docs/conventions.md invariant 7.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
PRUNER="${PRUNE_WT_PRUNER:-$HERE/prune-worktrees.sh}"
SELF="$(basename "$0")"

fatal()  { printf 'error: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'refuse: %s\n' "$*" >&2; exit 1; }

YES=0
case "${1:-}" in
  "") ;;
  --yes) YES=1 ;;
  -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
  *) fatal "usage: $SELF [--yes]" ;;
esac
[ "$#" -le 1 ] || fatal "usage: $SELF [--yes]"
ab_is_bundle "." || fatal "run from a control-panel bundle root (no instance.config.json here)."
ROOT="$(pwd -P)"

lock_free() {
  LOCK_MSG="$(bash "$HERE/tick-lock.sh" status --instance "$ROOT" 2>&1)"
}
lock_free || refuse "a tick holds the dispatch lock and may be dispatching into a worktree
        right now. Nothing was removed. Run this again once the tick ends.
        $LOCK_MSG"

report="$(bash "$PRUNER" 2>&1)" || fatal "prune-worktrees.sh failed:
$report"
[ "$YES" -eq 1 ] || printf '%s\n---\n' "$report"

json_string() { [ -f "$1" ] && sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1; }
config_path() {
  local v
  v="$(json_string instance.config.local.json "$1")"
  [ -n "$v" ] || v="$(json_string instance.config.json "$1")"
  printf '%s' "${v/#\~/$HOME}"
}
canon() { [ -n "$1" ] && ( cd "$1" 2>/dev/null && pwd -P ); }

REPOS_ROOT="$(canon "$(config_path reposRoot)")"
[ -n "$REPOS_ROOT" ] || fatal "reposRoot not found — check instance.config(.local).json."
ROOTS="$(canon "$(config_path worktreeRoot)")
$(canon "$REPOS_ROOT/_wt")"

paths_of() { printf '%s\n' "$report" | sed -n "s/^$1  *\(\/.*\)  \[.*\$/\1/p"; }
REMOVABLE="$(paths_of REMOVABLE)"
REPORTED_LIVE="$(paths_of 'LIVE PROCESS')"

# Must stay identical to reclaim-worktree.sh G12's list; tests/prune-wt.test.sh compares them.
IGNORE_OK=" node_modules .pnpm-store .pnpm-store-task .bun-cache .venv venv __pycache__ \
.pytest_cache .mypy_cache .next .nuxt .turbo .cache .gradle tmp temp .DS_Store "

live_processes_in() { # <worktree> — one line per live process whose cwd or argv is inside it
  local wt=$1 pid cmd line
  if command -v lsof >/dev/null 2>&1; then
    pid=""
    while IFS= read -r line; do
      case "$line" in
        p*) pid=${line#p} ;;
        n"$wt"|n"$wt"/*) [ "$pid" = "$$" ] || printf '%s\n' "$pid" ;;
      esac
    done <<EOF
$(lsof -a -d cwd -n -P -Fpn 2>/dev/null)
EOF
  fi
  while read -r pid cmd; do
    [ -n "$pid" ] && [ "$pid" != "$$" ] || continue
    case "$cmd" in *"$wt"*) printf '%s\n' "$pid" ;; esac
  done <<EOF
$(ps -axo pid=,command= 2>/dev/null)
EOF
}

# Sets REPO and BRANCH, or WHY and returns 1. Every refusal leaves the path alone.
check() { # <worktree>
  local wt=$1 r inside=1 common line cur found=1 is_main=1 seen=0 locked=0 prunable=0 detached=0
  REPO=""; BRANCH=""; WHY=""
  case "$wt" in *..*) WHY="the path contains '..'"; return 1 ;; esac
  [ -d "$wt" ] || { WHY="it is already gone"; return 1; }
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$wt/" in "$r"/*/) inside=0 ;; esac
  done <<EOF
$ROOTS
EOF
  [ "$inside" -eq 0 ] || { WHY="it is not inside worktreeRoot or <reposRoot>/_wt"; return 1; }
  case $'\n'"$REPORTED_LIVE"$'\n' in *$'\n'"$wt"$'\n'*)
    WHY="the report shows a live process in it"; return 1 ;; esac
  common="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || { WHY="git cannot read it"; return 1; }
  REPO="$(canon "$(dirname "$common")")"
  [ "$(dirname "$REPO")" = "$REPOS_ROOT" ] || { WHY="its repo $REPO is not under reposRoot"; return 1; }
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur="${line#worktree }"; seen=$((seen + 1))
                    if [ "$cur" = "$wt" ]; then found=0; [ "$seen" -gt 1 ] && is_main=0; fi ;;
      "branch "*)   [ "$cur" = "$wt" ] && { BRANCH="${line#branch }"; BRANCH="${BRANCH#refs/heads/}"; } ;;
      detached)              [ "$cur" = "$wt" ] && detached=1 ;;
      locked|"locked "*)     [ "$cur" = "$wt" ] && locked=1 ;;
      prunable|"prunable "*) [ "$cur" = "$wt" ] && prunable=1 ;;
    esac
  done <<EOF
$(git -C "$REPO" worktree list --porcelain 2>/dev/null)
EOF
  [ "$found" -eq 0 ] && [ "$is_main" -eq 0 ] || { WHY="it is not a linked worktree of $REPO"; return 1; }
  [ "$locked" -eq 0 ]   || { WHY="it is locked"; return 1; }
  [ "$prunable" -eq 0 ] || { WHY="git calls it prunable"; return 1; }
  [ "$detached" -eq 0 ] && [ -n "$BRANCH" ] || { WHY="it is at a detached HEAD"; return 1; }
  [ -z "$(git -C "$wt" status --porcelain 2>&1)" ] || { WHY="it has uncommitted or untracked files"; return 1; }
  [ "$(git -C "$wt" rev-list --count HEAD --not --remotes 2>/dev/null)" = 0 ] \
    || { WHY="it has commits no remote holds"; return 1; }
  local ignored entry keepers=""
  ignored="$(git -C "$wt" ls-files -o -i --exclude-standard --directory 2>/dev/null)" \
    || { WHY="its ignored content cannot be listed"; return 1; }
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$IGNORE_OK" in *" ${entry%%/*} "*) continue ;; esac
    keepers="$keepers $entry"
  done <<EOF
$ignored
EOF
  [ -z "$keepers" ] || { WHY="it holds ignored files git would delete without asking:$keepers"; return 1; }
  [ -z "$(live_processes_in "$wt")" ] || { WHY="a live process is running in it now"; return 1; }
}

removed=0; skipped=0; failed=0; PRUNE_REPOS=""
while IFS= read -r wt; do
  [ -n "$wt" ] || continue
  if ! check "$wt"; then
    printf 'skip: %s — %s\n' "$wt" "$WHY"; skipped=$((skipped + 1)); continue
  fi
  if [ "$YES" -eq 0 ]; then printf 'would remove: %s  [%s]\n' "$wt" "$BRANCH"; continue; fi
  lock_free || { printf 'refuse: a tick took the lock mid-run; stopping. %s\n' "$LOCK_MSG" >&2; failed=$((failed + 1)); break; }
  out="$(git -C "$REPO" worktree remove "$wt" 2>&1)"
  if [ -d "$wt" ] || git -C "$REPO" worktree list --porcelain | grep -qxF "worktree $wt"; then
    printf 'FAILED: %s is still there. %s\n' "$wt" "$out" >&2; failed=$((failed + 1)); continue
  fi
  printf 'removed: %s  [%s] — the branch is kept\n' "$wt" "$BRANCH"; removed=$((removed + 1))
  case $'\n'"$PRUNE_REPOS"$'\n' in *$'\n'"$REPO"$'\n'*) ;; *) PRUNE_REPOS="$PRUNE_REPOS
$REPO" ;; esac
done <<EOF
$REMOVABLE
EOF

while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  git -C "$repo" worktree prune && printf 'pruned: %s\n' "$repo"
done <<EOF
$PRUNE_REPOS
EOF

if [ "$YES" -eq 1 ]; then
  printf 'prune-wt: %d removed, %d skipped, %d failed.\n' "$removed" "$skipped" "$failed"
else
  printf 'prune-wt: preview — %d would go, %d skipped. Nothing was changed.\n' \
    "$(printf '%s\n' "$REMOVABLE" | grep -c .)" "$skipped"
fi
[ "$failed" -eq 0 ] || exit 1
exit 0
