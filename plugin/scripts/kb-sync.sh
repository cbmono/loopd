#!/usr/bin/env bash
# kb-sync.sh — mount, read and write a knowledge base held in another repository.
#
#   kb-sync.sh [--instance DIR] mount [--allow-empty] | pull | status
#   kb-sync.sh [--instance DIR] commit --message <m> [--role <r>] -- <path>...
#
# `commit` is ONE bounded transaction and the only writer: rebase, regenerate the
# index, commit, push, one retry, then stop and report. Every network call carries
# the bound named by --timeout, so no command here can hang a tick or a session.
# A mount into a repo with no commits is refused, naming it; --allow-empty is kb-migrate.sh's,
# which populates exactly that repo and whose first commit creates the branch.
# Exit: 0 done · 1 refused or failed (reported) · 2 usage · 3 no `knowledge` key.
# Reasoning, and why the mount is a nested clone: ai-bridge-v3/task-021.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# shellcheck source=bundle-paths.sh
. "$HERE/bundle-paths.sh" || exit 2
inst="."; cmd=""; message=""; role=""; paths=(); allow_empty=0; KB_EMPTY=0; TIMEOUT="${AI_BRIDGE_KB_TIMEOUT:-20}"
need2() { [ "$1" -ge 2 ] || { echo "kb-sync: $2 needs a value" >&2; exit 2; }; }
seen_dashdash=0
while [ $# -gt 0 ]; do
  if [ "$seen_dashdash" -eq 1 ]; then paths+=("$1"); shift; continue; fi
  case "$1" in
    --instance) need2 $# "$1"; inst="$2"; shift 2 ;;
    --message)  need2 $# "$1"; message="$2"; shift 2 ;;
    --role)     need2 $# "$1"; role="$2"; shift 2 ;;
    --timeout)  need2 $# "$1"; TIMEOUT="$2"; shift 2 ;;
    --)         seen_dashdash=1; shift ;;
    --allow-empty) allow_empty=1; shift ;;
    -h|--help)  sed -n '2,12p' "$0" >&2; exit 2 ;;
    -*) echo "kb-sync: unknown flag $1" >&2; exit 2 ;;
    *)  [ -z "$cmd" ] || { echo "kb-sync: unexpected argument '$1'" >&2; exit 2; }
        cmd="$1"; shift ;;
  esac
done
case "$TIMEOUT" in ""|*[!0-9]*) echo "kb-sync: --timeout wants seconds" >&2; exit 2 ;; esac
[ -d "$inst" ] || { echo "kb-sync: no such instance directory: $inst" >&2; exit 2; }
INST="$(cd "$inst" && pwd)"

say()   { printf 'kb-sync: %s\n' "$1"; }
warn()  { printf 'kb-sync: %s\n' "$1" >&2; }
die()   { printf 'kb-sync: %s\n' "$1" >&2; exit "${2:-1}"; }

cfg() { bash "$HERE/resolve-config.sh" --instance "$INST" "$@" 2>/dev/null; }

# Nothing here runs on a terminal — a tick, a SessionStart hook, an agent. Every way a
# child can block on input that will never arrive is closed, because each one spends the
# WHOLE bound and then reads as elapsed time: git's prompt, git's askpass, OpenSSH's own.
# GIT_ASKPASS is set EMPTY rather than unset on purpose — git consults core.askPass and
# SSH_ASKPASS only when GIT_ASKPASS is unset, so one empty value closes all three.
# Credential HELPERS run before any of this and are untouched: an HTTPS bundle with one
# still authenticates.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=""
export SSH_ASKPASS_REQUIRE=never

# The child's stderr has to transit a FILE, not a variable: half the bounded calls below run
# inside $( ) and a subshell's variables never come back. `mktemp` makes it 0600 in the
# caller's own TMPDIR, every call truncates it, why_failed truncates it again as soon as it
# has classified, and it is removed on the way out. It is only ever READ, never emitted.
# EXIT only, and no INT/TERM: a signal trap here would make this script ignore SIGINT and
# carry on mid-rebase, which is the opposite of what push_with_one_retry's trap is for.
ERRLOG="$(mktemp "${TMPDIR:-/tmp}/kb-sync-err.XXXXXX" 2>/dev/null)" || ERRLOG=""
cleanup() { [ -z "$ERRLOG" ] || rm -f "$ERRLOG"; }
trap cleanup EXIT

# A bound that holds without coreutils `timeout`, which stock macOS does not ship:
# the watchdog is a SIBLING, so it still fires if this shell is killed first.
bounded() {
  [ -z "$ERRLOG" ] || : > "$ERRLOG"
  local err="${ERRLOG:-/dev/null}"
  if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" "$@" 2>>"$err"; return $?; fi
  "$@" 2>>"$err" & local child=$! rc=0
  ( sleep "$TIMEOUT"; kill "$child" 2>/dev/null ) >/dev/null 2>&1 &
  local dog=$!
  # Both lines exist so that reaping a killed job does not print "Terminated" over the
  # report below — the child's OWN stderr is already safe in $err and is what gets read.
  disown "$dog" 2>/dev/null
  { wait "$child"; rc=$?; } 2>/dev/null
  kill "$dog" 2>/dev/null
  return $rc
}

# A URL is config we own, and it is printed. Userinfo and any query are REMOVED rather than
# masked — a display form needs neither, and removing cannot leave a tail behind.
safe_url() { printf '%s' "$1" | LC_ALL=C sed -e 's|\(://\)[^/]*@|\1|' -e 's|[?#].*$||'; }

# WHY THE LAST BOUNDED CALL FAILED, IN OUR OWN WORDS. The whole point is that a credential
# failure must not read as elapsed time — the 2026-10-03 mount spent 140s raising a bound
# against a username prompt. Git's stderr is how we KNOW which it was; it is never how we
# SAY so. Remote-influenced text in a line a human and an agent both read is a log- and
# prompt-injection surface, and redacting it is a blocklist against bytes we do not control.
# So the vocabulary here is fixed and ours: a signature decides the phrase, an unrecognised
# failure gets its exit code and the command that will show the real text, and nothing from
# the remote is printed, logged or stored. Adding a signature is how this gets more specific.
why_failed() { # <rc> -> one fixed phrase, never remote text
  local rc="$1" sig=""
  if [ -n "$ERRLOG" ] && [ -s "$ERRLOG" ]; then
    if   grep -qE 'could not read (Username|Password)|terminal prompts disabled' "$ERRLOG" 2>/dev/null; then
      sig='no credentials for this remote, and nothing could answer the prompt'
    elif grep -qE 'Authentication failed|Invalid username or password|HTTP 40[13]' "$ERRLOG" 2>/dev/null; then
      sig='the remote refused the credentials it was given'
    elif grep -qE 'Permission denied \(publickey|Permission denied, please try again|Host key verification failed' "$ERRLOG" 2>/dev/null; then
      sig='the remote refused this SSH key'
    elif grep -qE 'Repository not found|not appear to be a git repository|Could not read from remote repository' "$ERRLOG" 2>/dev/null; then
      sig='the remote could not be read — no such repository, or this identity cannot see it'
    elif grep -qE "find remote ref" "$ERRLOG" 2>/dev/null; then
      sig='no such branch on the remote'
    elif grep -qE 'Could not resolve host|Connection refused|Connection timed out|Network is unreachable|Operation timed out|Failed to connect' "$ERRLOG" 2>/dev/null; then
      sig='the remote host could not be reached'
    fi
    : > "$ERRLOG"
  fi
  if [ -n "$sig" ]; then printf '%s' "$sig"; return 0; fi
  case "$rc" in
    124|137|143) printf 'nothing was said within the %ss bound' "$TIMEOUT" ;;
    *) printf 'git exited %s; re-run the fetch by hand to see what it said' "$rc" ;;
  esac
}

# The transport and host the bundle's OWN origin uses. A shorthand `org/name` cloned over
# HTTPS from an SSH-remoted bundle cannot authenticate against a private KB at all, which
# is the whole defect; github.com over HTTPS stays the answer when there is no origin to
# read. Userinfo is stripped from an HTTPS authority so a token in the bundle's remote is
# never copied into the KB remote or into a message.
bundle_remote_prefix() {
  local url rest auth
  url="$(git -C "$INST" config --get remote.origin.url 2>/dev/null)"
  case "$url" in
    ssh://*)
      rest="${url#ssh://}"; auth="${rest%%/*}"
      auth="$(printf '%s' "$auth" | LC_ALL=C sed -e 's#:[^@]*@#@#')"   # keep the user, drop any password
      [ -z "$auth" ] || { printf 'ssh://%s/' "$auth"; return 0; } ;;
    http://*|https://*)
      # The HOST is inherited; the SCHEME is not. An http:// bundle would otherwise pull the
      # KB — and whatever a helper supplies for it — in clear, which `main`'s hardcoded
      # https:// never did. An operator who means http sets a full URL in `repo`.
      rest="${url#*://}"; auth="${rest%%/*}"; auth="${auth##*@}"
      [ -z "$auth" ] || { printf 'https://%s/' "$auth"; return 0; } ;;
    *@*:*)
      printf '%s:' "${url%%:*}"; return 0 ;;
  esac
  printf 'https://github.com/'
}

# `org/name` is the documented form and inherits the bundle's transport; anything carrying
# a scheme or a slash-prefix is taken verbatim, which is both the operator's explicit
# override and what lets the harness point a mount at a local bare repo.
remote_url() {
  case "$1" in
    *://*|/*|./*|../*|*@*:*) printf '%s' "$1" ;;
    */*) printf '%s%s.git' "$(bundle_remote_prefix)" "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

KBGIT="$INST/$AB_DIR/kb.git"
SRCROOT="$INST/$AB_DIR/kb-src"

# The mount is a real directory, never a symlink, so `find knowledge -type f` behaves
# exactly as it does over a bundle's own folder. Git cannot re-root a checkout, so the
# repo-relative folder decides where it lands: `/` is cloned straight into knowledge/,
# and a named folder is checked out sparsely against the bundle root.
mount_layout() { # <path> -> "<worktree>\t<sparse>\t<prefix>"
  case "$1" in
    /|""|.) printf '%s\t\t' "$INST/knowledge" ;;
    knowledge|knowledge/|/knowledge|/knowledge/) printf '%s\tknowledge\tknowledge/' "$INST" ;;
    *) return 1 ;;
  esac
}

kb_read() { # <key> -> value or empty
  cfg knowledge "$1"
}

kb_configured() { [ -n "$(kb_read repo)" ]; }

kb_vars() {
  KB_REPO="$(kb_read repo)"
  KB_PATH="$(kb_read path)"; [ -n "$KB_PATH" ] || KB_PATH="/"
  KB_REF="$(kb_read ref)"; [ -n "$KB_REF" ] || KB_REF="main"
  KB_URL="$(remote_url "$KB_REPO")"
  # From here KB_REPO is only ever DISPLAYED, so it is masked once rather than at each
  # of the seven messages that name it. KB_URL keeps whatever the operator configured.
  KB_REPO="$(safe_url "$KB_REPO")"
  local layout
  layout="$(mount_layout "$KB_PATH")" || die "knowledge.path is '$KB_PATH'. Only '/' (the repo
       root) and 'knowledge' (a top-level folder of that name) can be mounted at
       knowledge/ as a real directory — git cannot re-root a checkout, and a symlink
       mount regenerates an empty index. Move the folder or set path: /."
  KB_WT="${layout%%$'\t'*}"; layout="${layout#*$'\t'}"
  KB_SPARSE="${layout%%$'\t'*}"; KB_PREFIX="${layout#*$'\t'}"
  KB_MOUNT="$INST/knowledge"
}

# Always from the worktree: with `--git-dir` alone git resolves a pathspec against the
# current directory, which for this mount is usually somewhere else entirely.
kbg() { ( cd "$KB_WT" && git --git-dir="$KBGIT" "$@" ); }

# Under `path: knowledge` the worktree is the bundle root, so the bundle's `/knowledge/`
# ignore line hides every new file, and no excludes file can negate a parent directory.
# New files are listed through a view rooted at knowledge/ — the ignore rules a `path: /`
# mount gets — and force-added by name; a blanket -f would sweep in what the KB ignores.
kb_stage() { # <worktree-relative path>
  [ -n "$KB_SPARSE" ] || { kbg add -- "$1"; return; }
  local sub="${1#"$KB_SPARSE"}" list
  sub="${sub#/}"; [ -n "$sub" ] || sub=.
  list="$(mktemp "${TMPDIR:-/tmp}/kb-sync-new.XXXXXX")" || return 1
  ( cd "$KB_MOUNT" && git --git-dir="$KBGIT" --work-tree=. ls-files -o --exclude-standard -z -- "$sub" ) > "$list" \
    && { [ -s "$list" ] || kbg ls-files --error-unmatch -- "$1" >/dev/null 2>&1; } \
    && { [ ! -s "$list" ] || ( cd "$KB_MOUNT" && git --git-dir="$KBGIT" add -f --pathspec-from-file="$list" --pathspec-file-nul ); } \
    && kbg add -u -- "$1"
  local rc=$?; rm -f "$list"; return $rc
}

# `ref` names a BRANCH. A tag or a SHA checks out a detached HEAD, and the write path
# below has nothing to push it to — so it is refused here, by name, not at push time.
check_ref() { # <url> <ref>
  local url="$1" ref="$2"
  if [ "${#ref}" -eq 40 ] && printf '%s' "$ref" | grep -qE '^[0-9a-fA-F]{40}$'; then
    die "knowledge.ref '$ref' is a commit SHA. A detached HEAD cannot be pushed — name a BRANCH."
  fi
  local heads tags rc=0
  heads="$(bounded git ls-remote --heads "$url" "$ref" 2>/dev/null)"; rc=$?
  [ -z "$heads" ] || return 0
  [ "$rc" -eq 0 ] || return 0
  # A host reports a default branch for a repo with no refs at all — a setting, not a
  # branch — so emptiness is asked of the heads. Only --exit-code's 2 means "read, none";
  # any other failure is not evidence of anything and is left to the fetch to name.
  bounded git ls-remote --heads --exit-code "$url" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then
    [ "$allow_empty" -eq 1 ] || refuse_empty_remote "$url" "$ref"
    KB_EMPTY=1; return 0
  fi
  tags="$(bounded git ls-remote --tags "$url" "$ref" 2>/dev/null)"
  [ -z "$tags" ] || die "knowledge.ref '$ref' is a TAG. A detached HEAD cannot be pushed — name a BRANCH."
  return 0
}

refuse_empty_remote() { # <url> <ref>
  local to; to="$(printf '%q %q' "$(safe_url "$1")" "HEAD:refs/heads/$2")"
  warn "$KB_REPO exists but has no commits — not one branch — so knowledge.ref '$2' cannot
       resolve. Nothing was written. Create the first commit, then mount again:
         d=\"\$(mktemp -d)\" && git -C \"\$d\" init -q && git -C \"\$d\" commit -q --allow-empty -m 'chore: first commit' && git -C \"\$d\" push -q $to"
  ab_say_run "kb-sync:  " kb-sync.sh mount >&2
  exit 1
}

clone_mount() { # <gitdir> <worktree> <url> <ref> <sparse> [empty]
  local gd="$1" wt="$2" url="$3" ref="$4" sparse="$5" empty="${6:-0}" rc=0
  mkdir -p "$(dirname "$gd")" "$wt" || return 1
  git init --bare --quiet "$gd" || return 1
  git --git-dir="$gd" config core.bare false || return 1
  git --git-dir="$gd" config core.worktree "$wt" || return 1
  git --git-dir="$gd" config core.logAllRefUpdates true || return 1
  git --git-dir="$gd" remote add origin "$url" || return 1
  if [ -n "$sparse" ]; then
    git --git-dir="$gd" config core.sparseCheckout true || return 1
    printf '/%s/\n' "$sparse" > "$gd/info/sparse-checkout" || return 1
  fi
  if [ "$empty" -eq 1 ]; then
    git --git-dir="$gd" symbolic-ref HEAD "refs/heads/$ref" || return 1
    return 0
  fi
  bounded git --git-dir="$gd" fetch --quiet origin "$ref"; rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "fetching $ref from $(safe_url "$url") failed: $(why_failed "$rc")"
    git --git-dir="$gd" symbolic-ref HEAD "refs/heads/$ref"
    return 0
  fi
  ( cd "$wt" && git --git-dir="$gd" checkout --quiet -B "$ref" FETCH_HEAD )
}

# A leftover real knowledge/ is a bundle that has not been migrated. Cloning over it
# would bury ~200 tracked Findings under a half-copy, so the mount refuses instead.
refuse_stale_folder() {
  [ -d "$KB_MOUNT" ] || return 0
  [ -z "$(ls -A "$KB_MOUNT" 2>/dev/null)" ] && return 0
  die "knowledge/ is already a real folder of this bundle, with content in it.
       Move it into $KB_REPO first, in one recorded commit:
         $HERE/kb-migrate.sh --instance $inst
       then re-run 'kb-sync.sh mount'."
}

mount_writable() {
  kb_vars
  if [ -d "$KBGIT" ]; then return 0; fi
  refuse_stale_folder
  check_ref "$KB_URL" "$KB_REF"
  clone_mount "$KBGIT" "$KB_WT" "$KB_URL" "$KB_REF" "$KB_SPARSE" "$KB_EMPTY" \
    || { rm -rf "$KBGIT"; die "could not mount $KB_REPO at knowledge/ — nothing was written."; }
  if [ "$KB_EMPTY" -eq 1 ]; then
    say "mounted $KB_REPO EMPTY at knowledge/ — it has no commits; the first 'kb-sync.sh commit' creates $KB_REF."
  else
    say "mounted $KB_REPO ($KB_PATH @ $KB_REF) at knowledge/"
  fi
}

# Read-only mounts (`knowledgeSources[]`) use this same scheme and are never written,
# never pushed and never index-regenerated.
sources_json() { cfg --json knowledgeSources; }

each_source() { # -> "<index>\t<repo>\t<path>\t<ref>\t<name>"
  local js; js="$(sources_json)" || return 0
  [ -n "$js" ] || return 0
  printf '%s' "$js" | python3 -c '
import json,sys
try: v=json.load(sys.stdin)
except Exception: sys.exit(0)
if not isinstance(v,list): sys.exit(0)
for i,e in enumerate(v):
    if not isinstance(e,dict) or not e.get("repo"): continue
    repo=str(e["repo"]); name=repo.rstrip("/").split("/")[-1].replace(".git","")
    print("\t".join([str(i),repo,str(e.get("path") or "/"),str(e.get("ref") or "main"),name]))
' 2>/dev/null
}

# Two repos with one basename would share a destination, and the second would land as a
# silent no-op on the first one's clone — so the collision is named, never mounted over.
source_sparse() { # <path> -> the subtree to check out, or empty for the whole repo
  local s="$1"; s="${s#/}"; s="${s%/}"
  case "$s" in .|"") printf '' ;; *..*) return 1 ;; *) printf '%s' "$s" ;; esac
}

mount_sources() {
  local i repo path ref name gd wt sparse seen="" first
  while IFS=$'\t' read -r i repo path ref name; do
    [ -n "${repo:-}" ] || continue
    first="$(printf '%s' "$seen" | awk -F'\t' -v n="$name" '$1==n {print $2; exit}')"
    if [ -n "$first" ]; then
      warn "knowledgeSources[$i] '$(safe_url "$repo")' and '$(safe_url "$first")' both mount at knowledge-sources/$name — skipped. Rename one repo or drop one entry."
      continue
    fi
    seen="$seen$name	$repo
"
    if ! sparse="$(source_sparse "$path")"; then
      warn "knowledgeSources[$i] path '$path' escapes the repository — skipped, not fatal"
      continue
    fi
    gd="$SRCROOT/$name.git"; wt="$INST/knowledge-sources/$name"
    [ -d "$gd" ] && continue
    if clone_mount "$gd" "$wt" "$(remote_url "$repo")" "$ref" "$sparse"; then
      say "mounted read-only $(safe_url "$repo") at knowledge-sources/$name${sparse:+/$sparse}"
    else
      rm -rf "$gd"; warn "could not mount read-only source $(safe_url "$repo") — skipped, not fatal"
    fi
  done <<EOF
$(each_source)
EOF
}

pull_one() { # <gitdir> <ref> <label>
  local gd="$1" ref="$2" label="$3" wt rc=0
  [ -d "$gd" ] || return 0
  bounded git --git-dir="$gd" fetch --quiet origin "$ref"; rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "could not fetch $label: $(why_failed "$rc") — using the local copy (not fatal)"
    return 0
  fi
  wt="$(git --git-dir="$gd" config core.worktree 2>/dev/null)"
  [ -n "$wt" ] && [ -d "$wt" ] || { warn "$label is fetched but not checked out — run 'kb-sync.sh mount'"; return 0; }
  ( cd "$wt" && git --git-dir="$gd" merge --ff-only --quiet FETCH_HEAD ) 2>/dev/null \
    || warn "$label is not fast-forwardable — left untouched (not fatal)"
}

# --- the write transaction ---------------------------------------------------
rebase_in_progress() { [ -d "$KBGIT/rebase-merge" ] || [ -d "$KBGIT/rebase-apply" ]; }
abort_rebase() { rebase_in_progress && kbg rebase --abort >/dev/null 2>&1; return 0; }

regenerate_index() {
  bash "$HERE/build-kb-index.sh" >/dev/null 2>&1 || return 1
  kb_stage "${KB_PREFIX}index.md" >/dev/null 2>&1
}

conflicted() { kbg diff --name-only --diff-filter=U 2>/dev/null; }

# index.md is DERIVED, so a conflict in it is resolved by taking neither side and
# rerunning the generator. Any other conflicted path — a same-slug Finding from two
# clones — is a real collision and stops here for a human.
resolve_conflicts() {
  local files; files="$(conflicted)"
  [ -n "$files" ] || return 0
  if [ "$files" != "${KB_PREFIX}index.md" ]; then
    warn "the KB rebase conflicts outside the derived index:"
    while IFS= read -r f; do [ -n "$f" ] && printf '         %s\n' "$f" >&2; done <<EOF
$files
EOF
    warn "that is a real collision (two clones, one slug) — resolve it by hand in $KB_MOUNT."
    return 1
  fi
  ( cd "$INST" && regenerate_index ) || return 1
  GIT_EDITOR=true kbg rebase --continue >/dev/null 2>&1
}

# No tracking ref means the branch has never been pushed, so EVERY local commit is
# unpushed — the case that read as "clean" while holding a day of Findings.
unpushed_count() {
  local n
  n="$(kbg rev-list --count "origin/$KB_REF..HEAD" 2>/dev/null)" || n=""
  [ -n "$n" ] || n="$(kbg rev-list --count HEAD 2>/dev/null)" || n=""
  printf '%s' "${n:-0}"
}

kb_author() { # -> "<name>\t<email>"
  local pair where val who email
  pair="$(cfg --source authorEmail)"; where="${pair%%$'\t'*}"; val="${pair#*$'\t'}"
  who="$(cfg ownerGithubUser)"
  if [ "$where" = local ] && [ -n "$val" ]; then email="$val"
  else
    email="$(cfg people "$who")"
    [ -n "$email" ] || email="$val"
  fi
  [ -n "$email" ] || email="$(git -C "$INST" config user.email 2>/dev/null)"
  [ -n "$who" ] || who="$(git -C "$INST" config user.name 2>/dev/null)"
  printf '%s\t%s' "$who" "$email"
}

do_commit() {
  kb_configured || exit 3
  kb_vars
  [ -d "$KBGIT" ] || die "no knowledge mount here — run 'kb-sync.sh mount' first."
  [ -n "$message" ] || die "commit wants --message" 2
  [ "${#paths[@]}" -gt 0 ] || die "commit wants '-- <path>...' (bundle-relative, under knowledge/)" 2

  local rel p
  for p in "${paths[@]}"; do
    p="${p#./}"; p="${p#"$INST"/}"
    case "$p" in
      knowledge|knowledge/*) ;;
      knowledge-sources/*) die "'$p' is a READ-ONLY mount (knowledgeSources[]). It is never
       written, never pushed and never index-regenerated — file the change upstream." ;;
      *) die "'$p' is outside knowledge/ — kb-sync commits the mounted KB and nothing else." ;;
    esac
    case "$KB_SPARSE" in "") rel="${p#knowledge/}"; [ "$rel" = knowledge ] && rel="." ;; *) rel="$p" ;; esac
    kb_stage "$rel" || die "could not stage '$p' in the KB mount."
  done

  local who name email
  who="$(kb_author)"; name="${who%%$'\t'*}"; email="${who#*$'\t'}"
  [ -n "$email" ] || die "no author email for the KB commit — add this clone's login to
       \"people\" in instance.config.json and \"ownerGithubUser\" to instance.config.local.json."
  [ -n "$name" ] || name="$email"

  ( cd "$INST" && regenerate_index ) || die "could not regenerate knowledge/index.md — refusing to commit."

  if kbg diff --cached --quiet 2>/dev/null; then
    # Re-running this command is what a failed push tells you to do, so an already-made
    # local commit is pushed here rather than reported as "nothing to do" forever.
    if [ "$(unpushed_count)" -gt 0 ]; then
      say "nothing new to commit — pushing the KB commit(s) already made here."
      push_with_one_retry
      return $?
    fi
    say "nothing to commit in the KB mount."
    return 0
  fi

  local trailer body
  trailer="Co-Authored-By: ai-bridge ${role:-agent} (Claude) <noreply@anthropic.com>"
  body="$message

$trailer"
  kbg -c "user.name=$name" -c "user.email=$email" \
      commit --quiet --author="$name <$email>" -m "$body" \
    || die "the KB commit failed — nothing was pushed."

  push_with_one_retry
}

push_with_one_retry() {
  local attempt=0 rc=0
  trap 'abort_rebase; cleanup' EXIT
  while [ "$attempt" -lt 2 ]; do
    attempt=$((attempt+1))
    bounded git --git-dir="$KBGIT" fetch --quiet origin "$KB_REF"; rc=$?
    if [ "$rc" -ne 0 ]; then
      warn "could not fetch $KB_REPO on attempt $attempt: $(why_failed "$rc")"
    elif ! kbg rebase --quiet FETCH_HEAD >/dev/null 2>&1; then
      if ! resolve_conflicts; then
        abort_rebase
        die "the KB transaction stopped on attempt $attempt and left no rebase behind.
       Your commit is local in $KB_MOUNT; resolve and re-run 'kb-sync.sh commit'."
      fi
    fi
    bounded git --git-dir="$KBGIT" push --quiet origin "HEAD:refs/heads/$KB_REF"; rc=$?
    if [ "$rc" -eq 0 ]; then
      trap cleanup EXIT
      say "pushed $(kbg rev-parse --short HEAD) to $KB_REPO ($KB_REF)."
      return 0
    fi
    warn "push rejected on attempt $attempt of 2: $(why_failed "$rc")"
  done
  abort_rebase; trap cleanup EXIT
  die "the KB push failed twice — stopping rather than forcing.
       The commit is local in $KB_MOUNT and unpushed; re-run 'kb-sync.sh commit' once
       the remote settles. Nothing was force-pushed and no rebase was left behind."
}

# --- commands ----------------------------------------------------------------
case "$cmd" in
  mount)
    kb_configured || { say "no 'knowledge' key in instance.config.json — knowledge/ is this bundle's own folder."; exit 3; }
    mount_writable
    mount_sources
    ;;
  pull)
    kb_configured || exit 3
    kb_vars
    pull_one "$KBGIT" "$KB_REF" "$KB_REPO"
    while IFS=$'\t' read -r i repo path ref name; do
      [ -n "${repo:-}" ] || continue
      pull_one "$SRCROOT/$name.git" "$ref" "$(safe_url "$repo")"
    done <<EOF
$(each_source)
EOF
    exit 0
    ;;
  status)
    kb_configured || exit 3
    kb_vars
    [ -d "$KBGIT" ] || { warn "knowledge is configured but not mounted. Mount it with:"
      ab_say_run "kb-sync:  " kb-sync.sh mount >&2
      exit 1; }
    ahead="$(unpushed_count)"
    if [ "$ahead" -gt 0 ]; then
      warn "$ahead KB commit(s) are local and UNPUSHED in $KB_MOUNT. Push by hand, or run:"
      ab_say_run "kb-sync:  " kb-sync.sh commit --message '"<message>"' -- '<path>...' >&2
      exit 1
    fi
    say "KB mount is clean and pushed."
    ;;
  commit) do_commit ;;
  "") echo "kb-sync: no command. One of: mount, pull, status, commit." >&2; exit 2 ;;
  *) echo "kb-sync: unknown command '$cmd'" >&2; exit 2 ;;
esac
