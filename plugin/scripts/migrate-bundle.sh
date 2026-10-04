#!/usr/bin/env bash
#
# migrate-bundle.sh — repair the mechanical schema violations `validate-bundle.sh`
# reports, in this instance's bundle.
#
#   Usage: migrate-bundle.sh            # report what it WOULD change (default)
#          migrate-bundle.sh --apply    # write the changes
#
# REPORT-ONLY BY DEFAULT, for the same reason `prune-worktrees.sh` is: a script that
# edits many files should not be one keystroke away from doing it. Read the report,
# then re-run with --apply.
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
#     "provenance:"): `machine` only when a role created it and no one else touched it.
#   · THE 3.0 LAYOUT. Plugin-owned files still sitting at the bundle root move under
#     `.ai-bridge/`, and the links pointing at them are rewritten. See that step.
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

APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--apply]" >&2; exit 2 ;;
  esac
  shift
done

ab_is_bundle . || {
  echo "migrate-bundle: run from a control-panel instance root (instance.config.json)." >&2
  exit 2
}

fixed=0; skipped=0; human=0; failed=0

# =========================================================================================
# THE 3.0 LAYOUT STEP — plugin-owned files move from the bundle root under `.ai-bridge/`.
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

layout_pending() { # prints "<old>\t<new>" per plugin-owned file still at the root
  local pair old
  for pair in $AB_MOVES; do
    old="${pair%%:*}"
    [[ -e "$old" ]] && printf '%s\t%s\n' "$old" "${pair#*:}"
  done
  return 0
}

layout_refusal() { # prints the reason, or nothing
  [[ -e "$AB_LOCK" || -e ".tick-lock" ]] && { printf 'a dispatch tick holds the lock'; return 0; }
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
# (`.board-live` -> `.ai-bridge/.board-live/.board-live`), and a per-path guard would only
# catch the collision after the earlier paths had already moved. This is not one of the two
# refusals — it says the bundle is HALF-MIGRATED, which a human resolves pair by pair.
layout_conflicts() { # <pending> — prints "<old> -> <new>" per occupied destination
  local old new
  while IFS=$'\t' read -r old new; do
    [[ -n "$new" && -e "$new" ]] && printf '%s -> %s\n' "$old" "$new"
  done <<< "$1"
  return 0
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
  m="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null || echo 644)"
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

prov_machine=0; prov_mixed=0; prov_human=0; prov_unresolved=0
# <file> -> machine | mixed | human, and the reason. `git -C` the file's own directory, so a
# mounted knowledge/ is read from its own repository.
provenance_from_git() {
  local d b authors creator a
  d="$(dirname "$1")"; b="$(basename "$1")"
  # --follow also pairs a new file with a SIMILAR one (status C) and hands it that file's
  # creator — a person's document read as machine. So history stops at a copy.
  authors="$(git -C "$d" log --follow --format='@%an' --name-status -- "$b" 2>/dev/null \
    | awk '/^@/ { print substr($0, 2); next } /^C[0-9]*\t/ { exit }' || true)"
  creator="$(printf '%s\n' "$authors" | sed '/^$/d' | tail -1)"
  if [[ -z "$creator" ]]; then
    printf 'human\tunresolved: git has no commit for it'; return 0
  fi
  # AMBIGUITY BIASES TO HUMAN: anything but a role name as the creator is a person.
  if ! is_machine "$creator"; then
    printf 'human\tcreated by %s' "$creator"; return 0
  fi
  while IFS= read -r a; do
    [[ -z "$a" ]] || is_machine "$a" || {
      printf 'mixed\tcreated by %s, later edited by %s' "$creator" "$a"; return 0
    }
  done <<< "$authors"
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

PENDING="$(layout_pending)"
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
    echo "  REFUSED  $refusal"
    echo "           Run these by hand once it clears, from $(pwd):"
    echo "             mkdir -p $AB_DIR $(dirname "$AB_ROSTER")"
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
    if [[ -d "$AB_DIR/kb.git" ]]; then
      echo "           knowledge/ is MOUNTED: its relinked files are uncommitted in that"
      ab_say_run "           repository. Review and push them with:" kb-sync.sh commit --message '"chore: relink knowledge/"' -- '<path>...'
    fi
    echo "           Now run /${PLUGIN_NAME}:init to re-seed the ignore lines at their new paths."
  fi
  echo "---"
fi

FILE_LIST="$(collect_files | grep -vE '/(index|log)\.md$' | sort -u || true)"

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
          derived="$(provenance_from_git "$file")"
          case "$derived" in
            machine*) prov_machine=$((prov_machine+1)) ;;
            mixed*)   prov_mixed=$((prov_mixed+1)) ;;
            *)        prov_human=$((prov_human+1)) ;;
          esac
          if [[ "$derived" == *$'\tunresolved:'* ]]; then prov_unresolved=$((prov_unresolved+1)); fi
          fix_field "$file" "$rel" "provenance missing -> ${derived%%$'\t'*} (${derived#*$'\t'})" \
            provenance "${derived%%$'\t'*}" add ;;
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
if [[ $((prov_machine+prov_mixed+prov_human)) -gt 0 ]]; then
  printf 'provenance: %d machine, %d mixed, %d human (%d of them unresolved in git).\n' \
    "$prov_machine" "$prov_mixed" "$prov_human" "$prov_unresolved"
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
