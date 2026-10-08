#!/usr/bin/env bash
#
# migrate-bundle.sh — repair the mechanical schema violations `validate-bundle.sh`
# reports, in this instance's bundle.
#
#   Usage: migrate-bundle.sh                          # report what it WOULD change (default)
#          migrate-bundle.sh --apply                  # write the changes
#          migrate-bundle.sh --layout-only [--apply]  # ONLY the two directory steps; no content
#
# REPORT-ONLY BY DEFAULT, for the same reason `prune-worktrees.sh` is: a script that
# edits many files should not be one keystroke away from doing it. Read the report,
# then re-run with --apply.
#
# --layout-only exists because the 3.3 rename was required on three bundles (2026-10-05)
# and the content repairs rode along as 865 and 341 uncommitted edits in a mounted
# knowledge/ — another repository's working tree — reverted by hand. A document under a
# MOUNTED knowledge/ (kb.git) is now SKIPPED and named in every mode, never repaired here.
#
# WHAT IT FIXES (mechanical — one right answer, no judgement):
#   · Finding `status` of exactly `open` or `active` — both mean "still applies" ⇒
#     `current`. A Finding with NO status ⇒ `current`.
#   · Service `status` of exactly `current` — the Finding enum applied to a Service
#     ⇒ `active`. A Service with NO status ⇒ `active`.
#   The mapping list is CLOSED. Any other unrecognised value — a typo, or a lifecycle
#   state this script has never seen — is reported for a human, never normalised: the
#   original carries a meaning the script cannot read, and overwriting it would
#   destroy that meaning while looking like a repair. Same rule as the timestamp.
#   · A missing `timestamp`. Filled from **git**: the author date of the commit that
#     added the file. That is real provenance, not a guess. A file git does not know
#     is reported and skipped — inventing a date would be worse than leaving the
#     error, because a wrong timestamp is indistinguishable from a right one.
#   · A missing knowledge-document `provenance`, from the file's git history (SCHEMA.md,
#     "provenance:"): `machine` only when a role created it and no one else touched it. A
#     delete, a pure rename and a BULK commit by a person are not touches, and a file whose
#     author git cannot name is SKIPPED, like the timestamp — never labelled `human` here.
#   · THE 3.0 LAYOUT. Plugin-owned files still sitting at the bundle root move under
#     `.loopd/`, and the links pointing at them are rewritten. See that step.
#   · THE .loopd RENAME. `.ai-bridge/` moves to `.loopd/` in one `git mv`, with its ignore
#     lines, the statusline pin and any KB mount's `core.worktree`, then commits. See that step.
#
# WHAT IT REFUSES TO FIX (needs a human):
#   · Dangling structural references. Whether to drop a `depends_on:` depends on
#     whether the task it pointed at finished, and once its project folder is gone
#     that state is unknowable from the bundle. `/close-project` step 6 is where this
#     is decided, with the source task still readable. Reported, never touched.
#   · A missing or unknown `type`, and absent frontmatter. These say the document is
#     not what its location claims, which is a content decision.
#
# Idempotent: a second run finds nothing. Safe to run before `validate-bundle.sh` and
# again after.
#
# Run from a control-panel instance root. Bash + awk + git only.
# Verified by tests/migrate-bundle.test.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

APPLY=0; LAYOUT_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --layout-only) LAYOUT_ONLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--layout-only] [--apply]" >&2; exit 2 ;;
  esac
  shift
done

ab_is_bundle . || {
  echo "migrate-bundle: run from a control-panel instance root (instance.config.json)." >&2
  exit 2
}

fixed=0; skipped=0; human=0; failed=0

# =========================================================================================
# THE 3.0 LAYOUT STEP — plugin-owned files move from the bundle root under `.loopd/`.
# =========================================================================================
#
# HARD CUTOVER, NO COMPATIBILITY SYMLINKS. A `mv` once left 185 dangling symlinks across
# three instances that all looked healthy (docs/operations.md:326-368), so nothing here
# creates one.
#
# TWO REFUSALS AND NO OTHERS: a live `.tick-lock`, or a dirty TRACKED tree. Untracked dirt
# is deliberately NOT a refusal — a bundle carries untracked derived files on any day a
# tick has run, and refusing those would refuse every real bundle. An occupied destination
# is not a third refusal: it says the bundle is already HALF-MIGRATED, and the step stops
# before the first move rather than declining a migration it could otherwise do.
#
# `git mv` for what git tracks, plain `mv` for the five derived files it does not. It is
# allowed to stop short: a refusal prints the commands instead, which is a finished answer
# for the one colleague migrating three installations today.

layout_pending() { # [<old:new ...>] — prints "<old>\t<new>" per source still present
  local pair old
  for pair in ${1:-$AB_MOVES}; do
    old="${pair%%:*}"
    [[ -e "$old" ]] && printf '%s\t%s\n' "$old" "${pair#*:}"
  done
  return 0
}

layout_refusal() { # prints the reason, or nothing
  [[ -e "$AB_LOCK" || -e ".tick-lock" || -e "$RENAME_FROM/.tick-lock" ]] && { printf 'a dispatch tick holds the lock'; return 0; }
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]] \
    && printf 'the tracked tree is dirty — commit or stash first'
  return 0
}

layout_cmd() { # <old> — the command that can move it: git mv only for what git tracks
  git ls-files --error-unmatch -- "$1" >/dev/null 2>&1 && printf 'git mv' || printf 'mv'
}

layout_move() { # <old> <new> — git mv when tracked, plain mv when not
  local old="$1" new="$2"
  mkdir -p "$(dirname "$new")"
  if [[ "$(layout_cmd "$old")" == "git mv" ]]; then
    git mv -- "$old" "$new"
  else
    mv -- "$old" "$new"
  fi
}

# Every destination is checked BEFORE the first move, not inside layout_move: a plain `mv`
# onto an occupied path overwrites a file or buries the source inside an existing directory
# (`.board-live` -> `.loopd/.board-live/.board-live`), and a per-path guard would only
# catch the collision after the earlier paths had already moved. This is not one of the two
# refusals — it says the bundle is HALF-MIGRATED, which a human resolves pair by pair.
layout_conflicts() { # <pending> — prints "<old> -> <new>" per occupied destination
  local old new
  while IFS=$'\t' read -r old new; do
    [[ -n "$new" && -e "$new" ]] && printf '%s -> %s\n' "$old" "$new"
  done <<< "$1"
  return 0
}

# THE .loopd RENAME. Both ends are spelled here: AB_DIR names only the new directory, and the
# old one has to be recognised to be moved.
RENAME_FROM=".ai-bridge"; RENAME_TO=".loopd"; SETTINGS=".claude/settings.json"

# Comments are prose and take the new name; a pattern line only has its directory segment
# renamed, so an ignore line never starts or stops matching anything but the moved path.
ignore_rewrite() { # stdin -> stdout
  sed -E -e '/^[[:space:]]*#/{s/ai-bridge/loopd/g;b' -e '}' \
         -e 's#(^|[/!])\.ai-bridge(/|$)#\1.loopd\2#g'
}

pin_target() { # <root> — the command the statusline pin should carry; nothing if not ours
  local cur shim
  cur="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
  [[ "$cur" =~ ^bash\ .*/\.claude/(ai-bridge|loopd)-statusline\.sh$ ]] || return 0
  for shim in loopd-statusline.sh "${cur##*/}"; do
    [[ -f ".claude/$shim" ]] && { printf 'bash %s/.claude/%s' "$1" "$shim"; return 0; }
  done
  echo "  HUMAN    the statusline pin names a shim .claude/ does not have — repin it by hand" >&2
}

kb_gitdirs() { # <dir> — the KB mount and every read-only source under it
  local g
  for g in "$1/kb.git" "$1"/kb-src/*.git; do [[ -d "$g" ]] && printf '%s\n' "$g"; done
  return 0
}

kb_worktree_for() { # <root> <gitdir> — the core.worktree kb-sync.sh's clone_mount writes
  local n="${2##*/}"
  case "$2" in
    */kb-src/*) printf '%s/knowledge-sources/%s' "$1" "${n%.git}" ;;
    *) [[ "$(git config --file "$2/config" --bool core.sparseCheckout 2>/dev/null)" == true ]] \
         && printf '%s' "$1" || printf '%s/knowledge' "$1" ;;
  esac
}

rename_refusal() { # prints the reason, or nothing
  local g n
  if [[ -f "$SETTINGS" ]]; then
    command -v jq >/dev/null 2>&1 || { printf '%s needs jq to be rewritten safely, and jq is not installed' "$SETTINGS"; return 0; }
    jq empty "$SETTINGS" >/dev/null 2>&1 || { printf '%s does not parse — fix it first; a broken one drops permissions.deny' "$SETTINGS"; return 0; }
  fi
  if [[ -f .gitignore ]] && ignore_rewrite < .gitignore | grep -q ai-bridge; then
    printf '.gitignore has a pattern naming ai-bridge outside the directory — rewrite it by hand'; return 0
  fi
  # --work-tree: a core.worktree naming a vanished directory makes every git call fatal,
  # which must not read as "nothing unpushed".
  while IFS= read -r g; do
    n=0
    if git --git-dir="$g" --work-tree=. rev-parse -q --verify HEAD >/dev/null 2>&1; then
      n="$(git --git-dir="$g" --work-tree=. rev-list --count HEAD --not --remotes 2>/dev/null)" || n="an uncountable number of"
    fi
    [[ "$n" == 0 ]] || { printf '%s has %s unpushed commit(s) — push first (kb-sync.sh status)' "$g" "$n"; return 0; }
  done < <(kb_gitdirs "$RENAME_FROM")
}

# THE DESTRUCTIVE EDGE: kb.git is a nested clone and gitignored, so `git status` cannot see it.
# The directory moves in ONE rename and is never deleted; the ignore file is rewritten FIRST,
# and put back if the move fails, so no window leaves either directory's derived files trackable.
rename_step() { # <pending>
  local root conflicts refusal pin cur g wt new gi_tmp gi_bak st_tmp st_bak tracked=""
  root="$(pwd)"
  echo "rename: this bundle keeps its state in $RENAME_FROM/, which moves to $RENAME_TO/."
  conflicts="$(layout_conflicts "$1")"
  refusal="$(layout_refusal)"; [[ -n "$refusal" ]] || refusal="$(rename_refusal)"
  if [[ -n "$conflicts" ]]; then
    echo "  STOPPED  $RENAME_TO/ already exists, so nothing was moved. Resolve it by hand, then re-run:"
    echo "             $conflicts"
    human=$((human+1)); return 0
  elif [[ -n "$refusal" ]]; then
    echo "  REFUSED  $refusal"; human=$((human+1)); return 0
  fi
  pin=""; [[ -f "$SETTINGS" ]] && pin="$(pin_target "$root")"
  cur=""; [[ -n "$pin" ]] && cur="$(jq -r .statusLine.command "$SETTINGS")"
  [[ "$pin" != "$cur" ]] || pin=""
  if [[ $APPLY -eq 0 ]]; then
    [[ -f .gitignore ]] && paste -d $'\037' .gitignore <(ignore_rewrite < .gitignore) \
      | awk -F $'\037' '$1 != $2 { printf "  WOULD REWRITE .gitignore:%d  %s  ->  %s\n", NR, $1, $2 }'
    [[ -z "$pin" ]] || echo "  WOULD REPIN  $SETTINGS: $cur -> $pin"
    echo "  WOULD MOVE $RENAME_FROM -> $RENAME_TO"
    while IFS= read -r g; do
      echo "  WOULD KEEP  $g — it moves inside the directory, never copied or deleted"
      wt="$(git config --file "$g/config" core.worktree 2>/dev/null || true)"
      new="$(kb_worktree_for "$root" "$g")"
      [[ "$wt" == "$new" ]] || echo "  WOULD SET   $RENAME_TO/${g#"$RENAME_FROM"/} core.worktree $wt -> $new"
    done < <(kb_gitdirs "$RENAME_FROM")
    echo "  WOULD COMMIT the move"
    return 0
  fi
  if [[ -f .gitignore ]]; then
    gi_tmp="$(temp_beside .gitignore)" && gi_bak="$(temp_beside .gitignore)" \
      && ignore_rewrite < .gitignore > "$gi_tmp" && ! grep -q ai-bridge "$gi_tmp" && cp -p .gitignore "$gi_bak" \
      || { echo "  FAILED   could not prepare the .gitignore rewrite — nothing was moved" >&2; failed=$((failed+1)); rm -f "${gi_tmp:-}" "${gi_bak:-}"; return 0; }
  fi
  if [[ -n "$pin" ]]; then
    st_tmp="$(temp_beside "$SETTINGS")" && st_bak="$(temp_beside "$SETTINGS")" \
      && jq --arg c "$pin" '.statusLine.command = $c' "$SETTINGS" > "$st_tmp" \
      && [[ "$(jq -r .statusLine.command "$st_tmp")" == "$pin" ]] \
      && [[ "$(jq -S 'del(.statusLine.command)' "$st_tmp")" == "$(jq -S 'del(.statusLine.command)' "$SETTINGS")" ]] \
      && cp -p "$SETTINGS" "$st_bak" \
      || { echo "  FAILED   the $SETTINGS rewrite did not parse back — nothing was moved" >&2; failed=$((failed+1))
           rm -f "${gi_tmp:-}" "${gi_bak:-}" "${st_tmp:-}" "${st_bak:-}"; return 0; }
  fi
  [[ -z "${gi_tmp:-}" ]] || { mv "$gi_tmp" .gitignore; echo "  REWROTE  .gitignore — $(grep -c ai-bridge "$gi_bak" || true) line(s) naming ai-bridge, 0 left"; }
  [[ -z "$pin" ]] || { mv "$st_tmp" "$SETTINGS"; echo "  REPINNED $SETTINGS: $pin"; }
  if ! layout_move "$RENAME_FROM" "$RENAME_TO" || [[ -e "$RENAME_FROM" || ! -d "$RENAME_TO" ]]; then
    if [[ -e "$RENAME_FROM" && ! -e "$RENAME_TO" ]]; then   # nothing moved: put both files back
      [[ -z "${gi_bak:-}" ]] || mv "$gi_bak" .gitignore
      [[ -z "${st_bak:-}" ]] || mv "$st_bak" "$SETTINGS"
    fi
    echo "  FAILED   the move of $RENAME_FROM/ did not land — check both directories by hand" >&2
    failed=$((failed+1)); return 0
  fi
  rm -f "${gi_bak:-}" "${st_bak:-}"
  echo "  MOVED    $RENAME_FROM -> $RENAME_TO"
  while IFS= read -r g; do
    new="$(kb_worktree_for "$root" "$g")"
    [[ "$(git config --file "$g/config" core.worktree 2>/dev/null || true)" == "$new" ]] && { echo "  KEPT     $g"; continue; }
    git config --file "$g/config" core.worktree "$new" 2>/dev/null || true
    if [[ "$(git config --file "$g/config" core.worktree 2>/dev/null || true)" == "$new" ]]; then
      echo "  SET      $g core.worktree $new"
    else
      echo "  FAILED   $g core.worktree — set it by hand to $new" >&2; failed=$((failed+1))
    fi
  done < <(kb_gitdirs "$RENAME_TO")
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  for g in .gitignore "$SETTINGS"; do git ls-files --error-unmatch -- "$g" >/dev/null 2>&1 && tracked="$tracked $g"; done
  # shellcheck disable=SC2086
  if { [[ -z "$tracked" ]] || git add -- $tracked; } && git commit -q -m "chore: move $RENAME_FROM/ to $RENAME_TO/ (migrate-bundle.sh)"; then
    echo "  COMMITTED the move — push it when you are ready"
  else
    echo "  FAILED   the move is staged but not committed — run: git commit" >&2; failed=$((failed+1))
  fi
}

# Links INSIDE the bundle are rewritten in the same step, or they rot: a task document or
# a Finding pointing at `/SCHEMA.md` names a path that no longer exists.
#
# `-type f` is load-bearing: `find` emits SYMLINKS that match `*.md` too, and the rename
# below replaces one with a regular file whether or not the content changed.
layout_relink() {
  local f tmp
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    tmp="$(temp_beside "$f")" || continue
    sed -e 's|(/SCHEMA\.md|(/'"$AB_SCHEMA"'|g' \
        -e 's|(/CONVENTIONS\.md|(/'"$AB_CONVENTIONS"'|g' \
        -e 's|^\([[:space:]-]*\)/agents/index\.md|\1/'"$AB_ROSTER"'|' \
        -e 's|(/agents/index\.md|(/'"$AB_ROSTER"'|g' "$f" > "$tmp" && mv "$tmp" "$f"
  done < <(find ./projects ./knowledge -type f -name '*.md' 2>/dev/null || true)
}


# One write path, and the label comes AFTER the verification.
#
# The first attempt at this fix printed FIXED before writing and corrected the count
# afterwards — so a caller reading stdout still saw a false success, which is the very
# bug being fixed. In apply mode nothing is announced until the field has been read
# back and matches.
fix_field() { # <file> <rel> <what> <key> <value> <add|set>
  local f="$1" rel="$2" what="$3" k="$4" v="$5" mode="$6" got rc=0
  if [[ $APPLY -eq 0 ]]; then
    printf '  WOULD FIX %s\n           %s\n' "$rel" "$what"
    fixed=$((fixed+1)); return 0
  fi
  case "$mode" in
    add) add_field "$f" "$k" "$v" || rc=$? ;;
    set) set_field "$f" "$k" "$v" || rc=$? ;;
  esac
  got="$(field "$f" "$k")"
  if [[ $rc -eq 0 && "$got" == "$v" ]]; then
    printf '  FIXED    %s\n           %s\n' "$rel" "$what"
    fixed=$((fixed+1))
  else
    printf '  FAILED   %s\n           %s — the write did not land (found %s)\n' \
      "$rel" "$what" "${got:-nothing}" >&2
    failed=$((failed+1))
  fi
}

hold() { printf '  HUMAN    %s\n           %s\n' "$1" "$2"; human=$((human+1)); }
skip() { printf '  SKIPPED  %s\n           %s\n' "$1" "$2"; skipped=$((skipped+1)); }

# A temporary file BESIDE the target, carrying the target's mode.
#
# Two reasons it cannot live in $TMPDIR: `mktemp` creates mode 0600, and renaming
# that over a document would silently make every repaired file 0600; and if $TMPDIR
# is on another filesystem, `mv` degrades to copy-and-remove, so an interruption can
# leave a half-written document. Same-directory rename is atomic and keeps the mode.
temp_beside() { # <file> — prints a temp path, or returns 1 if it cannot make one
  local f="$1" d t m
  d="$(dirname "$f")"
  t="$(mktemp "$d/.migrate-bundle.XXXXXX" 2>/dev/null)" || return 1
  # GNU first, BSD second, and the answer VALIDATED. GNU `stat -f` means --file-system:
  # with `%Lp` read as a file it printed a filesystem block for "$f" to stdout and exited
  # 1, so the BSD-first spelling fell through to `-c` and `m` became that block plus the
  # mode — `chmod` refused it and every repaired file on Linux came out 0600 (mktemp's
  # mode). BSD `stat -c` fails on stderr with nothing on stdout, so probing it first is
  # safe on macOS, and only an octal mode is accepted either way.
  m="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null || true)"
  case "$m" in [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;; *) m=644 ;; esac
  chmod "$m" "$t" 2>/dev/null || true
  printf '%s\n' "$t"
}

# Replace a frontmatter scalar in place, only inside the frontmatter block.
set_field() { # <file> <key> <value> — returns non-zero if the write cannot be made
  local f="$1" k="$2" v="$3" tmp
  tmp="$(temp_beside "$f")" || return 1
  awk -v key="$k" -v val="$v" '
    BEGIN { n=0; done=0 }
    /^---$/ { n++; print; next }
    n==1 && !done && $0 ~ "^" key ":" { print key ": " val; done=1; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Insert a frontmatter scalar just before the closing delimiter.
add_field() { # <file> <key> <value> — returns non-zero if the write cannot be made
  local f="$1" k="$2" v="$3" tmp
  tmp="$(temp_beside "$f")" || return 1
  awk -v key="$k" -v val="$v" '
    BEGIN { n=0 }
    /^---$/ { n++; if (n==2) print key ": " val; print; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

field() { # <file> <key>
  awk -v key="$2" '
    NR==1 && $0!="---" { exit }
    /^---$/ { n++; if (n==2) exit; next }
    n==1 && $0 ~ "^" key ":" { sub("^" key ":[[:space:]]*", ""); sub(/[[:space:]]*#.*/, ""); print; exit }
  ' "$1"
}

git_added_date() { # <file> -> ISO 8601, or empty
  git log --diff-filter=A --format=%aI -1 -- "$1" 2>/dev/null | head -1
}

# The author names commit-as.sh stamps for an agent. Read from it so there is one list; a
# missing file yields none, and every document then falls to human.
MACHINE_AUTHORS="$(awk -F'[()]' '/^VALID_ROLES=\(/ { print $2; exit }' \
  "$(dirname "${BASH_SOURCE[0]:-$0}")/commit-as.sh" 2>/dev/null | tr ' ' '\n' | grep -vx -e human -e '' || true)"
# No pipe: under pipefail, `grep -q` quitting early SIGPIPEs printf and reads as "not a role".
is_machine() { [[ -n "$1" && $'\n'"$MACHINE_AUTHORS"$'\n' == *$'\n'"$1"$'\n'* ]]; }

# THE BULK RULE: a commit by a NON-ROLE author touching more than BULK_DOCS Markdown documents
# is a move, an import or a sweep — evidence about none of them (docs/conventions.md §9).
BULK_DOCS=50
bulk_docs() { # <dir> <sha> -> how many .md files the commit touches; cached per sha (bash 3.2: no maps)
  local v="bulk_$2" n
  eval "n=\${$v:-}"
  if [[ -z "$n" ]]; then
    n="$(git -C "$1" show --format= --name-only "$2" 2>/dev/null | grep -c '\.md$' || true)"
    eval "$v=\$n"
  fi
  printf '%s' "${n:-0}"
}
is_bulk() { [[ "$(bulk_docs "$1" "$2")" -gt $BULK_DOCS ]]; }

prov_machine=0; prov_mixed=0; prov_human=0; prov_unknowable=0
# <file> -> machine | mixed | human | unknowable, a TAB, and the reason. The caller writes the
# first three and SKIPS the fourth. `git -C` the file's own directory, so a mounted knowledge/
# is read from its own repository.
provenance_from_git() {
  local d b entries oldest st who sha creator csha n
  d="$(dirname "$1")"; b="$(basename "$1")"
  # --follow also pairs a new file with a SIMILAR one (status C) and hands it that file's
  # creator — a person's document read as machine. So the copying commit IS the creation and
  # history stops there. A delete (D) and a pure rename (R100) leave the content alone, so
  # neither is a touch by its author: the one commit that moved knowledge/ out of a bundle
  # made 291 of 334 role documents `mixed`.
  entries="$(git -C "$d" log --follow --format='@%H %an' --name-status -- "$b" 2>/dev/null \
    | awk -F'\t' '/^@/ { sha=substr($1,2,40); who=substr($1,43); next }
                  $1 ~ /^C/ { print $1 "\t" who "\t" sha; exit }
                  NF>=2 && $1 != "D" && $1 != "R100" { print $1 "\t" who "\t" sha }' || true)"
  oldest="$(printf '%s\n' "$entries" | sed '/^$/d' | tail -1)"
  if [[ -z "$oldest" ]]; then
    printf 'unknowable\tgit has no commit that wrote it'; return 0
  fi
  IFS=$'\t' read -r st creator csha <<< "$oldest"
  # AMBIGUITY BIASES TO HUMAN: anything but a role name as the creator is a person — unless the
  # creating commit is bulk (a squashed import), which says nothing about who wrote THIS file.
  if ! is_machine "$creator"; then
    if is_bulk "$d" "$csha"; then
      printf 'unknowable\tits only history is a bulk commit by %s (%s documents)' "$creator" "$(bulk_docs "$d" "$csha")"
      return 0
    fi
    printf 'human\tcreated by %s' "$creator"; return 0
  fi
  while IFS=$'\t' read -r st who sha; do
    [[ -n "$who" && "$sha" != "$csha" ]] || continue
    is_machine "$who" && continue
    is_bulk "$d" "$sha" && continue
    printf 'mixed\tcreated by %s, later edited by %s' "$creator" "$who"; return 0
  done <<< "$entries"
  if ! git -C "$d" diff --quiet HEAD -- "$b" 2>/dev/null; then
    printf 'mixed\tcreated by %s, with an uncommitted edit' "$creator"; return 0
  fi
  printf 'machine\tcreated by %s, no other author' "$creator"
}

collect_files() {
  find ./objectives -maxdepth 1 -name '*.md' 2>/dev/null || true
  find ./projects -maxdepth 2 -name 'project.md' 2>/dev/null || true
  find ./projects -path '*/phases/*.md' 2>/dev/null || true
  find ./projects -path '*/tasks/*.md' 2>/dev/null || true
  find ./knowledge -mindepth 2 -maxdepth 2 -type f -name '*.md' 2>/dev/null || true
}

# A bundle still holding $RENAME_FROM/ takes its root files INTO it, so the rename carries them
# over whole; moving them to $AB_DIR would leave the rename an occupied destination.
LAYOUT_DIR="$AB_DIR"; [[ -d "$RENAME_FROM" ]] && LAYOUT_DIR="$RENAME_FROM"
LAYOUT_MOVES="${AB_MOVES//$AB_DIR\//$LAYOUT_DIR/}"
PENDING="$(layout_pending "$LAYOUT_MOVES")"
if [[ -n "$PENDING" ]]; then
  echo "layout: this bundle is on the pre-3.0 layout."
  refusal="$(layout_refusal)"
  conflicts="$(layout_conflicts "$PENDING")"
  if [[ -n "$conflicts" ]]; then
    echo "  STOPPED  this bundle is half-migrated — a destination is already occupied, so"
    echo "           nothing was moved. Resolve each pair by hand, then re-run:"
    while IFS= read -r pair; do echo "             $pair"; done <<< "$conflicts"
    human=$((human+1))
  elif [[ -n "$refusal" ]]; then
    echo "  REFUSED  $refusal"; human=$((human+1))
    echo "           Run these by hand once it clears, from $(pwd):"
    echo "             mkdir -p $LAYOUT_DIR $LAYOUT_DIR/$(basename "$(dirname "$AB_ROSTER")")"
    while IFS=$'\t' read -r old new; do echo "             $(layout_cmd "$old") $old $new"; done <<< "$PENDING"
    echo "           …then re-run this script. docs/operations.md carries the full list."
  elif [[ $APPLY -eq 0 ]]; then
    while IFS=$'\t' read -r old new; do echo "  WOULD MOVE $old -> $new"; done <<< "$PENDING"
  else
    while IFS=$'\t' read -r old new; do
      layout_move "$old" "$new" && echo "  MOVED    $old -> $new"
    done <<< "$PENDING"
    # The five gitignored paths need their ignore lines moved with them; /<plugin>:init
    # appends the new ones, so this only has to drop the stale root spellings.
    if [[ -f .gitignore ]]; then
      tmp="$(temp_beside .gitignore)" \
        && grep -vxE '/?(AWAITING\.md|SNAPSHOT\.json|\.tick-state|\.board-live/?|\.board-others\.json|\.tick-lock|\.tick-lock\.claim)' .gitignore > "$tmp" \
        && mv "$tmp" .gitignore \
        && echo "  REWROTE  .gitignore (the root spellings of the derived files are gone)"
    fi
    layout_relink
    echo "  RELINKED projects/ and knowledge/ links to $AB_SCHEMA and $AB_CONVENTIONS"
    # A MOUNTED knowledge base is another repository's worktree, so the relink leaves it
    # dirty and this script must not commit it — kb-sync.sh is the only KB writer.
    if [[ -d "$LAYOUT_DIR/kb.git" ]]; then
      echo "           knowledge/ is MOUNTED: its relinked files are uncommitted in that"
      ab_say_run "           repository. Review and push them with:" kb-sync.sh commit --message '"chore: relink knowledge/"' -- '<path>...'
    fi
    echo "           Now run /${PLUGIN_NAME}:init to re-seed the ignore lines at their new paths."
  fi
  echo "---"
fi

RENAMING="$(layout_pending "$RENAME_FROM:$RENAME_TO")"
if [[ -n "$PENDING" && -n "$RENAMING" ]]; then
  echo "rename: $RENAME_FROM/ -> $RENAME_TO/ waits until the layout move above is committed. Re-run then."
  echo "---"
elif [[ -n "$RENAMING" ]]; then
  rename_step "$RENAMING"; echo "---"
elif [[ -z "$PENDING" && -d "$RENAME_TO" ]]; then
  echo "rename: already migrated — $RENAME_TO/ is in place and there is no $RENAME_FROM/. Nothing to do."
  echo "---"
fi

if [[ $LAYOUT_ONLY -eq 1 ]]; then
  echo "content: NOT CHECKED (--layout-only) — no status, timestamp or provenance repair was run or reported."
  echo "---"
  if [[ $APPLY -eq 1 ]]; then
    printf 'migrate-bundle --layout-only: directory steps done, %d left for a human, %d FAILED; content NOT checked.\n' "$human" "$failed"
    ab_say_run "Report the content repairs with:" migrate-bundle.sh
    [[ $failed -eq 0 ]] || exit 1
  else
    printf 'migrate-bundle --layout-only: directory steps reported, %d need a human; content NOT checked. (report only — nothing changed)\n' "$human"
    ab_say_run "Move the directory with:" migrate-bundle.sh --layout-only --apply
  fi
  exit 0
fi

FILE_LIST="$(collect_files | grep -vE '/(index|log)\.md$' | sort -u || true)"

# A MOUNTED knowledge/ is another repository's working tree, and `git log` from inside it
# reaches THIS bundle's history, which ignores it — so 326 documents read as "unresolved"
# and were labelled human (2026-10-05). This script repairs only this bundle's own files.
if [[ -d "$AB_DIR/kb.git" || -d "$RENAME_FROM/kb.git" ]]; then
  mounted="$(grep -c '^\./knowledge/' <<<"$FILE_LIST" || true)"
  if [[ "$mounted" -gt 0 ]]; then
    FILE_LIST="$(grep -v '^\./knowledge/' <<<"$FILE_LIST" || true)"
    printf '  SKIPPED  knowledge/ (%d document(s))\n           lives in a knowledge mount; repair it from that repository, not here\n' "$mounted"
    skipped=$((skipped+mounted))
  fi
fi

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  rel="${file#./}"
  head -1 "$file" | grep -q '^---$' || { skip "$rel" "no frontmatter — a content decision, not a migration"; continue; }
  # An unterminated frontmatter block has no closing delimiter to insert before, so
  # add_field would silently no-op while this script reported a fix. Skip it: the
  # document is malformed, which is a content decision, and validate-bundle.sh names
  # it precisely. This guard exists because the script DID once report FIXED for a
  # write it never made — a false success is worse than the error it claimed to fix.
  [[ "$(grep -c '^---$' "$file")" -ge 2 ]] || {
    skip "$rel" "frontmatter opens but never closes — add the missing '---' by hand, then re-run"
    continue
  }

  type="$(field "$file" type)"
  [[ -n "$type" ]] || { skip "$rel" "no type — a content decision, not a migration"; continue; }
  status="$(field "$file" status)"

  case "$type" in
    Finding)
      case "$status" in
        current|superseded) : ;;
        "")            fix_field "$file" "$rel" "Finding has no status -> current" status current add ;;
        open|active)   fix_field "$file" "$rel" "Finding status '$status' -> current" status current set ;;
        *)             hold "$rel" "Finding status '$status' is not a mapping this script knows — decide it by hand" ;;
      esac ;;
    Service)
      case "$status" in
        active|deprecated) : ;;
        "")        fix_field "$file" "$rel" "Service has no status -> active" status active add ;;
        current)   fix_field "$file" "$rel" "Service status 'current' -> active" status active set ;;
        *)         hold "$rel" "Service status '$status' is not a mapping this script knows — decide it by hand" ;;
      esac ;;
  esac

  case "$type" in
    Service|Finding|Team|Runbook|Reference)
      prov="$(field "$file" provenance)"
      case "$prov" in
        machine|mixed|human) : ;;
        "")
          derived="$(provenance_from_git "$file")"; value="${derived%%$'\t'*}"; why="${derived#*$'\t'}"
          case "$value" in
            machine) prov_machine=$((prov_machine+1)) ;;
            mixed)   prov_mixed=$((prov_mixed+1)) ;;
            human)   prov_human=$((prov_human+1)) ;;
            *)       value="" ;;   # unknowable, or anything unexpected: never a value on disk
          esac
          if [[ -n "$value" ]]; then
            fix_field "$file" "$rel" "provenance missing -> $value ($why)" provenance "$value" add
          else
            # Same posture as the timestamp: a label that reads as a fact is worse than the error.
            prov_unknowable=$((prov_unknowable+1))
            skip "$rel" "provenance unknowable from git — $why; refusing to invent a value, a person decides"
          fi ;;
        *) hold "$rel" "provenance '$prov' is not machine|mixed|human — decide it by hand" ;;
      esac ;;
  esac

  if [[ -z "$(field "$file" timestamp)" ]]; then
    added="$(git_added_date "$file")"
    if [[ -n "$added" ]]; then
      fix_field "$file" "$rel" "timestamp missing -> $added (author date of the commit that added it)" \
        timestamp "$added" add
    else
      skip "$rel" "timestamp missing and git does not know this file — refusing to invent a date"
    fi
  fi

  # Structural refs: reported for a human, never rewritten here.
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || hold "$rel" "dangling reference $ref — decide it in /close-project step 6, not here"
  done < <(awk '
      NR==1 && $0!="---" { exit }
      /^---$/ { n++; if (n==2) exit; next }
      n==1 && /^(objective|project|phase|depends_on):/ { inblock=1; print; next }
      n==1 && inblock && /^[[:space:]]+-[[:space:]]*/ { print; next }
      n==1 && /^[^[:space:]]/ { inblock=0 }
    ' "$file" | grep -oE '/(objectives|projects|knowledge|agents)/[A-Za-z0-9._/-]+[.]md' | sort -u || true)
done <<< "$FILE_LIST"

echo "---"
if [[ $((prov_machine+prov_mixed+prov_human+prov_unknowable)) -gt 0 ]]; then
  printf 'provenance: %d machine, %d mixed, %d human; %d unknowable, skipped with no value written.\n' \
    "$prov_machine" "$prov_mixed" "$prov_human" "$prov_unknowable"
fi
if [[ $APPLY -eq 1 ]]; then
  printf 'migrate-bundle: %d fixed, %d left for a human, %d skipped, %d FAILED.\n' \
    "$fixed" "$human" "$skipped" "$failed"
  ab_say_run "Now run:" validate-bundle.sh
  [[ $failed -eq 0 ]] || exit 1
else
  printf 'migrate-bundle: %d would be fixed, %d need a human, %d skipped. (report only — nothing changed)\n' \
    "$fixed" "$human" "$skipped"
  ab_say_run "Write these changes with:" migrate-bundle.sh --apply
fi
