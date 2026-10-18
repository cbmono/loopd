#!/usr/bin/env bash
#
# push-commit.sh — push the commit just made in <dir>'s work tree: fetch, rebase only when
# the upstream moved, push. Never forces; never aborts a rebase it did not start.
#
#   Usage: push-commit.sh <dir>
#
# Exit: 0 pushed · 2 usage, or not a work tree · 3 no upstream, nothing pushed, silent
#       4 committed locally, not pushed — one line on stderr says why
# Reasoning: simple-board/task-007.
set -uo pipefail

[ $# -eq 1 ] || { sed -n '6p' "$0" >&2; exit 2; }
root="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" && cd "$root" || { echo "push-commit: not a git work tree: $1" >&2; exit 2; }
local_only() { echo "committed locally; $*" >&2; exit 4; }
in_rebase() { [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; }
# Before @{u}: a rebase detaches HEAD, and a detached HEAD has no upstream to report.
in_rebase && local_only "a rebase is already in progress, so nothing pulled or pushed"
git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || exit 3
git fetch --quiet >/dev/null 2>&1 || local_only "the fetch failed, so nothing was pushed — push by hand, never force"
# A dirty tree refuses pull --rebase, so pull only when there is something to rebase onto.
if ! git merge-base --is-ancestor '@{u}' HEAD 2>/dev/null; then
  # The nonce-tagged reflog `(start)` line says whose rebase it is; a pre-check cannot.
  nonce="push-commit.sh $$.$RANDOM.$(date +%s)"
  if ! GIT_REFLOG_ACTION="$nonce" git pull --rebase --quiet >/dev/null 2>&1; then
    if in_rebase; then
      case "$(git log -g --format=%gs HEAD 2>/dev/null | grep -m1 ' (start): ')" in
        "$nonce (start): "*) git rebase --abort >/dev/null 2>&1 ;;
        *) local_only "a rebase this command did not start is in progress — left alone, nothing pushed" ;;
      esac
    fi
    local_only "pull --rebase failed, so nothing was pushed — rebase and push by hand, never force"
  fi
fi
branch="$(git symbolic-ref --short HEAD)"
# An explicit refspec bypasses push.default and any configured `+` push refspec.
git push --quiet "$(git config "branch.$branch.remote")" "HEAD:$(git config "branch.$branch.merge")" >/dev/null 2>&1 ||
  local_only "the push was rejected — pull and push by hand, never force"
