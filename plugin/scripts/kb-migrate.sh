#!/usr/bin/env bash
# kb-migrate.sh — move this bundle's own knowledge/ into the repo `knowledge.repo` names.
#
#   kb-migrate.sh [--instance DIR] [--dry-run]
#
# One recorded commit pair: the KB repo gains the files, and the bundle loses them from
# its index and gains the `/knowledge/` ignore line in the SAME commit — so a clone that
# pulls it before syncing sees no knowledge/ at all and is told which command makes one.
# Refuses a dirty tree and prints every path it moved. A run that stopped part-way is
# finished by running it again; nothing leaves the index until every file is on the remote.
# Exit: 0 migrated or already migrated · 1 refused (reported) · 2 usage · 3 no `knowledge` key.
# Reasoning: ai-bridge-v3/task-021, criteria 19-20.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# shellcheck source=bundle-paths.sh
. "$HERE/bundle-paths.sh" || exit 2
inst="."; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || { echo "kb-migrate: --instance needs a directory" >&2; exit 2; }
                inst="$2"; shift 2 ;;
    --dry-run)  dry=1; shift ;;
    -h|--help)  sed -n '2,11p' "$0" >&2; exit 2 ;;
    *) echo "kb-migrate: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$inst" ] || { echo "kb-migrate: no such instance directory: $inst" >&2; exit 2; }
INST="$(cd "$inst" && pwd)"

say() { printf 'kb-migrate: %s\n' "$1"; }
die() { printf 'kb-migrate: %s\n' "$1" >&2; exit "${2:-1}"; }
cfg() { bash "$HERE/resolve-config.sh" --instance "$INST" "$@" 2>/dev/null; }

REPO="$(cfg knowledge repo)"
[ -n "$REPO" ] || { say "no 'knowledge' key in instance.config.json — nothing to migrate."; exit 3; }
# Display-only from here (kb-sync.sh reads the URL itself), so userinfo and query go once.
REPO="$(printf '%s' "$REPO" | LC_ALL=C sed -e 's|\(://\)[^/]*@|\1|' -e 's|[?#].*$||')"
KB_PATH="$(cfg knowledge path)"; [ -n "$KB_PATH" ] || KB_PATH="/"
KB_REF="$(cfg knowledge ref)"; [ -n "$KB_REF" ] || KB_REF="main"
case "$KB_PATH" in /|.|knowledge|knowledge/|/knowledge|/knowledge/) ;; *)
  die "knowledge.path '$KB_PATH' cannot be mounted at knowledge/ — see kb-sync.sh." ;;
esac
case "$KB_PATH" in /|.) PREFIX="" ;; *) PREFIX="knowledge/" ;; esac

git -C "$INST" rev-parse --git-dir >/dev/null 2>&1 || die "$INST is not a git repository."
MOUNT="$INST/$AB_DIR/kb.git"
TRACKED="$(git -C "$INST" ls-files -- knowledge 2>/dev/null)"
if [ -z "$TRACKED" ]; then
  [ -z "$(git -C "$INST" ls-tree -r --name-only HEAD -- knowledge 2>/dev/null)" ] || die "the index no
       longer tracks knowledge/ but HEAD still does — a run stopped between the two. Check
       that .gitignore carries /knowledge/, then commit both by hand:
         git -C $INST commit -m 'chore: knowledge/ moves to $REPO'"
  say "git tracks no file under knowledge/ here — this bundle is already migrated."
  exit 0
fi
[ -d "$INST/knowledge" ] || die "$INST/knowledge does not exist — nothing to move."

# A mount from an earlier run means that run stopped part-way. knowledge/ and the mount's
# gitdirs are then its own state, so the clean-tree rule applies to everything else.
resume=0; [ -d "$MOUNT" ] && resume=1
scope=(. ":(exclude)$AB_DIR/kb.git" ":(exclude)$AB_DIR/kb-src")
[ "$resume" -eq 0 ] || scope+=(":(exclude)knowledge" ":(exclude)knowledge-sources")
[ -z "$(git -C "$INST" status --porcelain -- "${scope[@]}" 2>/dev/null)" ] \
  || die "the bundle's working tree is dirty. Commit or stash first: a migration that
       moves ~200 files must be the only thing in its commit."

count="$(printf '%s\n' "$TRACKED" | grep -c .)"
say "$count tracked file(s) under knowledge/ -> $REPO ($KB_PATH @ $KB_REF)"
printf '%s\n' "$TRACKED" | sed 's/^/  /'
[ "$resume" -eq 0 ] || say "resuming: an earlier run mounted $AB_DIR/kb.git and stopped before the bundle commit."

if [ "$dry" -eq 1 ]; then say "--dry-run: nothing was written."; exit 0; fi

if [ "$resume" -eq 1 ]; then
  # The bundle's index is still the authority, so a file the mount lost comes back from it.
  git -C "$INST" ls-files -z --deleted -- knowledge | git -C "$INST" checkout-index -z --stdin \
    || die "could not restore the tracked files the mount is missing."
else
  # Step 1 — the KB repo. Mount it empty, copy the files in, commit and push.
  STAGE="$(mktemp -d "${TMPDIR:-/tmp}/kb-migrate.XXXXXX")" || die "could not create a staging directory."
  trap 'rm -rf "$STAGE"' EXIT
  mv "$INST/knowledge" "$STAGE/knowledge" || die "could not set knowledge/ aside."

  if ! bash "$HERE/kb-sync.sh" --instance "$INST" mount --allow-empty; then
    mv "$STAGE/knowledge" "$INST/knowledge"
    die "could not mount $REPO — knowledge/ was put back untouched."
  fi

  # `cp -R <dir>/.` copies the CONTENTS, so the mount keeps its own root and a repo that
  # already carries a knowledge/ folder is merged into rather than nested inside.
  mkdir -p "$INST/knowledge"
  if ! cp -R "$STAGE/knowledge/." "$INST/knowledge/"; then
    # A partial copy leaves the only complete set in STAGE, so the cleanup trap goes first.
    trap - EXIT
    die "could not copy knowledge/ into the mount — the originals are kept in $STAGE."
  fi
fi

# Inside the MOUNTED folder, never at the KB repo's root: with `path: knowledge` that
# root is a shared repo whose own README is somebody else's front page.
README="$INST/knowledge/README.md"
if [ ! -e "$README" ]; then
  # Hidden from the bundle in its OWN exclude file, never its .gitignore: with
  # `path: knowledge` the KB repo's worktree is the bundle root, reads that .gitignore,
  # and would leave the README out of its commit.
  EXCL="$(git -C "$INST" rev-parse --git-path info/exclude)"
  case "$EXCL" in /*) ;; *) EXCL="$INST/$EXCL" ;; esac
  mkdir -p "$(dirname "$EXCL")"
  grep -qxF '/knowledge/README.md' "$EXCL" 2>/dev/null || printf '/knowledge/README.md\n' >> "$EXCL"
  cat > "$README" <<'MD'
# Knowledge base

Plain-markdown OKF documents. Any harness can read this repository; nothing here
depends on a plugin.

**How to read it — the rule, whatever tool you are on:**

- Read `index.md` **first**. It is the lookup surface and it is derived from document
  frontmatter — never hand-edit it.
- Open **at most three** matching documents. Never bulk-read this repository.
- A **Superseded** row is **history**: read it to understand a decision, never cite it
  as current guidance.

`Finding`s live in one folder with unique slugs — two people filing the same slug is a
real conflict for a human, not a merge accident. Provenance is the `author:` field, never
the path.
MD
  say "wrote the harness-neutral reading rule to ${PREFIX}README.md"
fi

if ! bash "$HERE/kb-sync.sh" --instance "$INST" commit \
     --role human --message "feat: import the bundle's knowledge base ($count files)" \
     -- knowledge; then
  die "the KB commit failed. knowledge/ is mounted and holds the files; nothing was
       removed from the bundle's index. Fix the remote and re-run this same command."
fi

# The gate on Step 2: every tracked file, read back from the remote rather than from the
# push's own report. Absent ones are named and nothing leaves the index.
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="" SSH_ASKPASS_REQUIRE=never
git --git-dir="$MOUNT" fetch --quiet origin "+refs/heads/$KB_REF:refs/remotes/origin/$KB_REF" \
  || die "could not read $REPO back to verify the push — nothing was removed from the
       bundle's index. Re-run this same command once it is reachable."
ON_REMOTE="$(git --git-dir="$MOUNT" ls-tree -r --name-only "refs/remotes/origin/$KB_REF")"
absent="$(printf '%s\n' "$TRACKED" | awk -v p="$PREFIX" '
  NR == FNR { on[$0] = 1; next }
  { f = $0; sub(/^knowledge\//, "", f); if (!((p f) in on)) print }' <(printf '%s\n' "$ON_REMOTE") -)"
if [ -n "$absent" ]; then
  printf 'kb-migrate: %s of %s tracked file(s) are NOT on %s (%s) — nothing was removed from\n' \
    "$(printf '%s\n' "$absent" | grep -c .)" "$count" "$REPO" "$KB_REF" >&2
  printf '       the bundle'"'"'s index:\n' >&2
  printf '%s\n' "$absent" | sed 's/^/         /' >&2
  die "restore them on the remote, or git rm them from the bundle in their own commit,
       then re-run this same command."
fi
say "verified $count of $count file(s) on $REPO ($KB_REF) — 0 absent."

# Step 2 — the bundle. Un-track the same paths and ignore the mount, in ONE commit.
# A failure puts the index and .gitignore back, so the re-run starts from the state above.
GI="$INST/.gitignore"
undo() {
  git -C "$INST" reset -q -- knowledge .gitignore 2>/dev/null
  if git -C "$INST" cat-file -e HEAD:.gitignore 2>/dev/null; then
    git -C "$INST" checkout -q HEAD -- .gitignore
  else rm -f "$GI"; fi
  die "$1 — the bundle is back as it was; re-run this same command."
}
if ! grep -qxF '/knowledge/' "$GI" 2>/dev/null; then
  [ -s "$GI" ] && [ -n "$(tail -c 1 "$GI")" ] && printf '\n' >> "$GI"
  cat >> "$GI" <<'GIEOF'

# The knowledge base is MOUNTED from another repository (`knowledge` in
# instance.config.json) — a nested clone, per bundle, never shared between two bundles
# on one machine. A clone that has not synced yet has no knowledge/ at all; make one
# with: scripts/kb-sync.sh mount
/knowledge/
/knowledge-sources/
GIEOF
fi

git -C "$INST" rm -r --cached --quiet -- knowledge || undo "could not un-track knowledge/ in the bundle"
git -C "$INST" add -- .gitignore || undo "could not stage .gitignore"
git -C "$INST" commit --quiet -m "chore: knowledge/ moves to $REPO

$count files are now tracked in $REPO ($KB_PATH @ $KB_REF) and ignored here.
A clone with no knowledge/ yet makes one with: scripts/kb-sync.sh mount" \
  || undo "the bundle commit failed"

say "migrated $count file(s). The bundle no longer tracks knowledge/; the mount does."
