#!/usr/bin/env bash
#
# reclaim-worktree.sh — remove ONE task's worktree, named by the task itself.
#
#   reclaim-worktree.sh [--dry-run] <task-path>      run from a bundle root
#
# Exit: 0 removed (--dry-run: every guard passed, nothing touched) · 1 REFUSED, a guard
# said no · 2 cannot answer (usage, not a bundle, unreadable frontmatter) · 3 nothing to
# do (no `worktree:` recorded, or the path is already gone) — the idempotent re-run ·
# 4 REFUSED, and every live process in the tree is the task's OWN `session:` (its daemon
# roster worker or a descendant): a retry once that session is stopped, never a human item.
#
# It is record-driven: no scan, no candidate list, no "all finished worktrees" mode.
# `prune-worktrees.sh` stays report-only and this never calls it. Guards G1-G13, why
# each exists, and why forced removal is never passed: docs/conventions.md invariant 7.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

CONFIG="instance.config.json"
LOCAL_CONFIG="instance.config.local.json"
SELF="$(basename "$0")"

usage() {
  echo "Usage: $SELF [--dry-run] <task-path>" >&2
  exit 2
}

DRY=0
TARGET=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY=1; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$TARGET" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || usage

# `refuse:` is the only shape that means "a guard said no"; callers and the harness grep
# for the word, so keep it stable.
refuse() { printf 'refuse: %s\n' "$*" >&2; exit 1; }
noop()   { printf 'noop: %s\n' "$*"; exit 3; }
fatal()  { printf 'error: %s\n' "$*" >&2; exit 2; }

ab_is_bundle "." || fatal "run from a control-panel bundle root (no $CONFIG here)."

# --- readers -----------------------------------------------------------------

json_string() { # <file> <key> — no jq dependency, same parse as task-owner.sh
  [ -f "$1" ] || return 0
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
}

# Local file wins over the tracked one: an absolute path cannot be right on two machines.
config_path() { # <key>
  local v
  v="$(json_string "$LOCAL_CONFIG" "$1")"
  [ -n "$v" ] || v="$(json_string "$CONFIG" "$1")"
  printf '%s' "${v/#\~/$HOME}"
}

# `git worktree list --porcelain` prints RESOLVED paths; on macOS $TMPDIR alone
# (/var -> /private/var) makes an unresolved comparison match nothing.
canon() { ( cd "$1" 2>/dev/null && pwd -P ); }

# Exit 3 when the file does not open with `---`, 4 when it opens and never closes — an
# unterminated block would return the whole file and read a `branch:` line in the BODY
# as frontmatter.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# The FIRST occurrence only — a repeated key judged from the later value is the bug
# push-state.sh had. awk, not `sed | head`, so no stage can SIGPIPE under pipefail.
fm_scalar() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v k="$2" '
    !got && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[[:space:]]*/, "", v)
      sub(/[[:space:]]*#.*$/, "", v)
      sub(/^["'"'"']/, "", v); sub(/["'"'"']$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

# Every http(s) URL under a list key, inline (`pr: [ a, b ]`) or block (`pr:` then
# `  - a`). Shape-tolerant: the PM and the role agents both append here.
fm_list_urls() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v k="$2" '
      index($0, k ":") == 1 { grab = 1; print; next }
      grab && /^[[:space:]]/ { print; next }
      grab && /^-/ { print; next }
      grab { grab = 0 }
    ' | grep -oE 'https?://[^][:space:],"'"'"']+' || true
}

# --- G1: the task document, and it must be THIS bundle's ---------------------

tdir="$(dirname "$TARGET")"
[ -d "$tdir" ] || fatal "no such task document: $TARGET"
abs="$(cd "$tdir" && pwd -P)/$(basename "$TARGET")"
root="$(pwd -P)"

# A document from anywhere else is not evidence, however well-formed: it would carry its
# own `worktree:`, `branch:` and a merged PR URL and pass every later guard.
case "$abs" in
  "$root"/projects/*) ;;
  *) fatal "$TARGET is not a task document of this bundle.
       Expected a path under $root/projects/ — got $abs." ;;
esac

rel="${abs#"$root"/}"
[ -f "$rel" ] || fatal "no such task document: $TARGET"

fm=""; rc=0
fm="$(fm_block "$rel")" || rc=$?
[ "$rc" -eq 0 ] || fatal "$rel has no readable YAML frontmatter — refusing rather than
       reading a body line as a field."

STATUS="$(fm_scalar "$fm" status)"
WT_REC="$(fm_scalar "$fm" worktree)"
BR_REC="$(fm_scalar "$fm" branch)"
REPO_REC="$(fm_scalar "$fm" target_repo)"
SESSION_REC="$(fm_scalar "$fm" session)"

# --- G2: the task must be done -----------------------------------------------

[ "$STATUS" = "done" ] || refuse "$rel is '${STATUS:-<none>}', not 'done' — only a done task
        has had every PR checked as merged, which is the whole authority for
        removing anything here. A cancelled task's PR was closed UNMERGED, so its
        worktree may hold the only copy of that work: report it, never remove it."

# --- G3: what the task records -----------------------------------------------

[ -n "$WT_REC" ] || noop "$rel records no 'worktree:' — nothing to reclaim."

[ -n "$BR_REC" ] || refuse "$rel records worktree '$WT_REC' but no 'branch:'. The recorded
        branch is how a recycled path is told from the one this task created, so a
        missing branch is a missing guard, not a guard that passed."

# --- G4: the path is one of ours ---------------------------------------------

case "$WT_REC" in
  /*) ;;
  *) refuse "recorded worktree '$WT_REC' is not an absolute path." ;;
esac
case "$WT_REC" in
  *..*) refuse "recorded worktree '$WT_REC' contains '..' — refusing to resolve it." ;;
esac

[ -d "$WT_REC" ] || noop "recorded worktree '$WT_REC' does not exist — already reclaimed."

WT="$(canon "$WT_REC")"
[ -n "$WT" ] || refuse "cannot resolve recorded worktree '$WT_REC'."

REPOS_ROOT="$(config_path reposRoot)"
[ -n "$REPOS_ROOT" ] && [ -d "$REPOS_ROOT" ] \
  || fatal "reposRoot ('$REPOS_ROOT') not found — check $LOCAL_CONFIG / $CONFIG."
REPOS_ROOT="$(canon "$REPOS_ROOT")"

# `worktreeRoot`, plus the legacy `<reposRoot>/_wt` for a bundle whose config predates
# the key. Every doc naming the key states that fallback, and so does this.
ROOTS=""
WT_CONFIGURED="$(config_path worktreeRoot)"
if [ -n "$WT_CONFIGURED" ] && [ -d "$WT_CONFIGURED" ]; then
  ROOTS="$(canon "$WT_CONFIGURED")"
fi
if [ -d "$REPOS_ROOT/_wt" ]; then
  ROOTS="$ROOTS
$(canon "$REPOS_ROOT/_wt")"
fi

inside_a_root=1
while IFS= read -r r; do
  [ -n "$r" ] || continue
  case "$WT/" in "$r"/*/) inside_a_root=0 ;; esac
done <<EOF
$ROOTS
EOF
[ "$inside_a_root" -eq 0 ] || refuse "$WT is not inside this bundle's worktree roots
        (worktreeRoot from $CONFIG, or the legacy <reposRoot>/_wt when that key is
        absent). A path out of a text document is checked against config, never
        trusted."

# --- G5: the expected repo comes from the task -------------------------------

[ -n "$REPO_REC" ] || refuse "$rel records no 'target_repo:', so the repo this worktree
        should belong to cannot be established from the task."
REPO_DIR="$REPOS_ROOT/${REPO_REC##*/}"
[ -e "$REPO_DIR/.git" ] || refuse "expected repo '$REPO_REC' is not cloned at $REPO_DIR."
REPO_CANON="$(canon "$REPO_DIR")"

# --- G6/G7/G8: what git says about that exact path ---------------------------
# The porcelain reports `detached` explicitly, where `rev-parse --abbrev-ref HEAD`
# returns the literal "HEAD" and invites a branch comparison that can never match. One
# pass with an in-record flag, not blank-line boundaries: a here-doc drops the trailing
# newline, so a boundary parse has to special-case the LAST record.
found=1; is_main=1; detached=0; locked=0; prunable=0; branch=""; head=""
seen=0; in_rec=1
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      cur="${line#worktree }"; seen=$((seen + 1))
      if [ "$cur" = "$WT" ] || [ "$(canon "$cur" 2>/dev/null)" = "$WT" ]; then
        in_rec=0; found=0
        [ "$seen" -eq 1 ] && is_main=0
      else
        in_rec=1
      fi ;;
    "HEAD "*)   [ "$in_rec" -eq 0 ] && head="${line#HEAD }" ;;
    "branch "*) [ "$in_rec" -eq 0 ] && { branch="${line#branch }"; branch="${branch#refs/heads/}"; } ;;
    detached)              [ "$in_rec" -eq 0 ] && detached=1 ;;
    locked|"locked "*)     [ "$in_rec" -eq 0 ] && locked=1 ;;
    prunable|"prunable "*) [ "$in_rec" -eq 0 ] && prunable=1 ;;
  esac
done <<EOF
$(git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null)
EOF

[ "$found" -eq 0 ] || refuse "$WT is not a registered worktree of $REPO_REC ($REPO_DIR).
        An unregistered directory is somebody's — a rescued tree, a hand-made
        copy, a cache dir — and not ours to delete."
[ "$is_main" -eq 1 ] || refuse "$WT is the MAIN working tree of $REPO_REC, not a worktree
        of it."
[ "$WT" != "$REPO_CANON" ] || refuse "$WT is the repo itself."
[ "$prunable" -eq 0 ] || refuse "$WT is registered but git calls it prunable — a human
        should look before anything is removed."
[ "$locked" -eq 0 ] || refuse "$WT is LOCKED. 'git worktree lock' is an explicit 'do not
        touch' and it is honoured here."
[ "$detached" -eq 0 ] || refuse "$WT is at a DETACHED HEAD (${head:0:8}). Its commits are
        reachable only from that HEAD and the per-worktree reflog, both of which
        'git worktree remove' deletes — so this is refused unconditionally, with
        no flag to override it. Rescue it first:
          git -C $REPO_DIR branch <name> $head"
[ "$branch" = "$BR_REC" ] || refuse "$WT is on branch '${branch:-<none>}' but $rel recorded
        '$BR_REC'. A worktree PATH can be recycled for another task; the recorded
        branch is what tells that apart from the worktree this task created."

# --- G9: nothing uncommitted -------------------------------------------------

st="$(git -C "$WT" status --porcelain 2>/dev/null)" || refuse "cannot read the status of $WT."
[ -z "$st" ] || refuse "$WT has uncommitted changes. Unlike the pruner's REPORT, this
        path deletes, so there is no scaffolding allowance: any modification or
        untracked file refuses.
$(printf '%s\n' "$st" | sed 's/^/          /' | head -20)"

# --- G10: nothing unpushed ---------------------------------------------------

unpushed="$(git -C "$WT" rev-list --count HEAD --not --remotes 2>/dev/null)" \
  || refuse "cannot establish whether $WT has unpushed commits."
case "$unpushed" in
  ''|*[!0-9]*) refuse "cannot establish whether $WT has unpushed commits." ;;
esac
[ "$unpushed" -eq 0 ] || refuse "$WT has $unpushed commit(s) that no remote-tracking ref
        contains. Push them, or confirm by hand where they landed — a script must
        never decide that commits it cannot find anywhere are expendable."

# --- G11: every recorded PR is merged, by URL --------------------------------

PRS="$(fm_list_urls "$fm" pr)"
[ -n "$PRS" ] || refuse "$rel is done but records no PR URL in 'pr:'. Merged PRs are the
        evidence this removal rests on; an empty 'pr:' establishes nothing, so it
        is a refusal and never a vacuous pass."

command -v gh >/dev/null 2>&1 || refuse "gh is not available, so the recorded PR(s) cannot
        be checked. An unknown must never be what authorises a deletion."

pr_count=0; own_repo=1
while IFS= read -r url; do
  [ -n "$url" ] || continue
  pr_count=$((pr_count + 1))
  slug="$(printf '%s' "$url" | sed -n 's#^https\{0,1\}://[^/]*/\([^/]*\)/\([^/]*\)/pull/[0-9]*.*#\1/\2#p')"
  [ "$slug" = "$REPO_REC" ] && own_repo=0
  state="$( gh pr view "$url" --json state --jq '.state' 2>/dev/null )" \
    || refuse "gh could not read $url (auth, network, or a deleted PR). Refusing
        rather than assuming it merged."
  case "$state" in
    MERGED) ;;
    OPEN|CLOSED|DRAFT) refuse "$url is $state, not MERGED. CLOSED-UNMERGED is never
        removed by this path — that worktree is the one most likely to hold the only
        copy of abandoned work. Checked by URL, never by branch name, which is how a
        recycled name once carried an old merged PR onto a live worktree." ;;
    *) refuse "gh reported an unrecognised state '$state' for $url." ;;
  esac
done <<EOF
$PRS
EOF

[ "$own_repo" -eq 0 ] || refuse "none of the $pr_count recorded PR URL(s) belongs to
        $REPO_REC, so none of them is evidence about this repo's worktree."

# --- G12: no IGNORED content outside the cache allowlist ---------------------
# `git worktree remove` does NOT refuse a worktree whose only content is ignored:
# measured on git 2.50.1, a tree holding just a `.env` is removed with rc=0 and the file
# goes with it. G9 cannot see it either — `status --porcelain` skips ignored paths. So
# the check is explicit, and `--directory` collapses an ignored directory to one entry
# so a node_modules does not print 40,000 lines.
IGNORE_OK=" node_modules .pnpm-store .pnpm-store-task .bun-cache .venv venv __pycache__ \
.pytest_cache .mypy_cache .next .nuxt .turbo .cache .gradle tmp temp .DS_Store \
dist build out coverage "

# No python3 or no key leaves the list as above: absence only ever refuses more.
extra="$(bash "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve-config.sh" --json reclaimIgnoreOk 2>/dev/null)" || extra=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  case "$name" in
    .env*) echo "warning: reclaimIgnoreOk '$name' not added — a .env file is never a cache." >&2 ;;
    *[!A-Za-z0-9._+-]*) echo "warning: reclaimIgnoreOk '$name' not added — not a plain path component." >&2 ;;
    *) IGNORE_OK="$IGNORE_OK$name " ;;
  esac
done <<EOF
$(printf '%s' "$extra" | grep -oE '"[^"]*"' | tr -d '"')
EOF

ignored="" ; ignored_rc=0
ignored="$(git -C "$WT" ls-files -o -i --exclude-standard --directory 2>/dev/null)" || ignored_rc=$?
[ "$ignored_rc" -eq 0 ] || refuse "cannot list the ignored content of $WT, so whether
        anything of the human's is in there cannot be established."

# EXACT match on the first path component. A prefix or trailing glob would let `.envrc`
# ride in on `.env` and `tmp.secrets` ride in on `tmp`.
keepers=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  case "$IGNORE_OK" in *" ${entry%%/*} "*) continue ;; esac
  keepers="$keepers$entry
"
done <<EOF
$ignored
EOF
keepers="${keepers%$'\n'}"
[ -z "$keepers" ] || refuse "$WT holds IGNORED content that is not a known cache. git
        would delete it without complaint — 'git worktree remove' does not refuse an
        ignored file — so the last word on it stays the human's:
$(printf '%s\n' "$keepers" | sed 's/^/          /' | head -20)
        If none of it is yours, delete it and ask again:
git -C '$WT' clean -fdX --$(printf '%s\n' "$keepers" | while IFS= read -r k; do printf " '%s'" "$k"; done)"

# --- G13: nothing is running in it -------------------------------------------
# This replaces the pruner's PRUNE_ACTIVE_MINUTES veto rather than inheriting it: on this
# path the mtime window is dead on arrival, because the tick that reflects the merge runs
# inside it for every fast merge and no later tick revisits a `done` task.
ancestors_of() { # <pid> — it and every ancestor below pid 1, one per line
  local tree p=$1 n=0
  tree="$(ps -axo pid=,ppid= 2>/dev/null)" || tree=""
  while :; do
    printf '%s\n' "$p"
    p="$(printf '%s\n' "$tree" | awk -v p="$p" '$1 == p { print $2; exit }')"
    n=$((n + 1))
    case "$p" in ''|0|1) return 0 ;; esac
    [ "$n" -lt 64 ] || return 0
  done
}

# The caller chain is pre-seeded as seen: a `cd <wt> && …` or wrapper shell above this
# script names the path too, and is the one asking for the removal.
live_processes_in() { # <worktree> — PID<TAB>COMMAND per live process inside it
  local wt=$1 pid cmd dir seen line lsof_cwd ps_all
  seen=$'\n'"$(ancestors_of "$$")"$'\n'
  lsof_cwd=""
  command -v lsof >/dev/null 2>&1 && lsof_cwd="$(lsof -a -d cwd -n -P -Fpcn 2>/dev/null)"
  if [ -n "$lsof_cwd" ]; then
    pid=""; cmd=""
    while IFS= read -r line; do
      case "$line" in
        p*) pid=${line#p} ;;
        c*) cmd=${line#c} ;;
        n*)
          dir=${line#n}
          case "$dir" in
            "$wt"|"$wt"/*)
              case "$seen" in *$'\n'"$pid"$'\n'*) ;;
                *) seen="$seen$pid"$'\n'; printf '%s\t%s\n' "$pid" "$cmd" ;;
              esac ;;
          esac ;;
      esac
    done <<EOF
$lsof_cwd
EOF
  fi
  ps_all="$(ps -axo pid=,command= 2>/dev/null)" || ps_all=""
  if [ -n "$ps_all" ]; then
    while read -r pid cmd; do
      [ -n "$pid" ] || continue
      case "$cmd" in
        *"$wt"*)
          case "$seen" in *$'\n'"$pid"$'\n'*) ;;
            *) seen="$seen$pid"$'\n'; printf '%s\t%s\n' "$pid" "$cmd" ;;
          esac ;;
      esac
    done <<EOF
$ps_all
EOF
  fi
}

ps -axo pid= >/dev/null 2>&1 || refuse "cannot enumerate processes, so whether something
        is still running inside $WT cannot be established."

# Exit 0 when every live pid is the roster worker of the task's recorded session or a
# descendant of it. Any doubt (no session, no roster entry, no ps) is a 1: today's refusal.
own_session_only() { # <live> <worker-pid>
  local tree pid p n
  tree="$(ps -axo pid=,ppid= 2>/dev/null)" || return 1
  while IFS=$'\t' read -r pid _; do
    p=$pid; n=0
    while [ "$p" != "$2" ]; do
      p="$(printf '%s\n' "$tree" | awk -v p="$p" '$1 == p { print $2; exit }')"
      n=$((n + 1))
      case "$p" in ''|0|1) return 1 ;; esac
      [ "$n" -lt 64 ] || return 1
    done
  done <<EOF
$1
EOF
}

live="$(live_processes_in "$WT")"
if [ -n "$live" ] && [ -n "$SESSION_REC" ] \
   && worker="$(bash "$(dirname "${BASH_SOURCE[0]:-$0}")/agent-sessions.sh" worker "$SESSION_REC" 2>/dev/null)" \
   && own_session_only "$live" "${worker##* }"; then
  short="$(printf '%s' "$worker" | cut -d' ' -f2)"
  printf "refuse: own session %s (pid %s) is the only live process in %s — the task's
        own finished round. claude stop %s, then ask again: a retry, not a human item.\n" \
    "$short" "${worker##* }" "$WT" "$short" >&2
  exit 4
fi
[ -z "$live" ] || refuse "$WT has a live process inside it. A process whose cwd is in a
        worktree does NOT stop 'git worktree remove' — it is left with a dangling cwd —
        so this is checked here. Stop it, then ask again:
$(printf '%s\n' "$live" | sed 's/^/          /' | head -10)"

# --- remove ------------------------------------------------------------------

if [ "$DRY" -eq 1 ]; then
  printf 'would remove: %s  [%s]  (task %s, %d PR(s) merged)\n' "$WT" "$branch" "$rel" "$pr_count"
  exit 0
fi

if ! out="$(git -C "$REPO_DIR" worktree remove "$WT" 2>&1)"; then
  refuse "git declined to remove $WT:
$(printf '%s\n' "$out" | sed 's/^/          /')"
fi

# VERIFY THE WRITE. A report of "removed" for a directory still on disk sends the next
# tick past a worktree nobody will look at again — the bug migrate-bundle.sh once shipped.
still_registered=1
while IFS= read -r line; do
  case "$line" in
    "worktree "*) [ "${line#worktree }" = "$WT" ] && still_registered=0 ;;
  esac
done <<EOF
$(git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null)
EOF

if [ -d "$WT" ] || [ "$still_registered" -eq 0 ]; then
  printf 'FAILED: git exited 0 but %s is still %s.\n' "$WT" \
    "$([ -d "$WT" ] && printf 'on disk' || printf 'registered')" >&2
  exit 1
fi

printf 'removed: %s  [%s]  (task %s, %d PR(s) merged)\n' "$WT" "$branch" "$rel" "$pr_count"
printf 'note: branch %s still exists — removal deletes the working directory and the\n' "$branch"
printf '      admin entry, never the branch or any commit.\n'
exit 0
