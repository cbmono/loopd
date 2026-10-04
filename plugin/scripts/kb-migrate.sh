#!/usr/bin/env bash
# kb-migrate.sh — move this bundle's own knowledge/ into the repo `knowledge.repo` names.
#
#   kb-migrate.sh [--instance DIR] [--dry-run]
#
# One recorded commit pair: the KB repo gains the files, and the bundle loses them from
# its index and gains the `/knowledge/` ignore line in the SAME commit — so a clone that
# pulls it before syncing sees no knowledge/ at all and is told which command makes one.
# Refuses a dirty tree, refuses to run twice, and prints every path it moved.
# Exit: 0 migrated · 1 refused (reported) · 2 usage · 3 no `knowledge` key.
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
KB_PATH="$(cfg knowledge path)"; [ -n "$KB_PATH" ] || KB_PATH="/"
KB_REF="$(cfg knowledge ref)"; [ -n "$KB_REF" ] || KB_REF="main"
case "$KB_PATH" in /|.|knowledge|knowledge/|/knowledge|/knowledge/) ;; *)
  die "knowledge.path '$KB_PATH' cannot be mounted at knowledge/ — see kb-sync.sh." ;;
esac
case "$KB_PATH" in /|.) PREFIX="" ;; *) PREFIX="knowledge/" ;; esac

git -C "$INST" rev-parse --git-dir >/dev/null 2>&1 || die "$INST is not a git repository."
[ -d "$INST/knowledge" ] || die "$INST/knowledge does not exist — nothing to move."
[ -z "$(git -C "$INST" status --porcelain 2>/dev/null)" ] \
  || die "the bundle's working tree is dirty. Commit or stash first: a migration that
       moves ~200 files must be the only thing in its commit."

TRACKED="$(git -C "$INST" ls-files -- knowledge 2>/dev/null)"
[ -n "$TRACKED" ] || die "git tracks no file under knowledge/ here — this bundle is already migrated."

MOUNT="$INST/$AB_DIR/kb.git"
[ -d "$MOUNT" ] && die "a KB mount already exists at $AB_DIR/kb.git. Remove it, or this
       bundle is already migrated."

count="$(printf '%s\n' "$TRACKED" | grep -c .)"
say "$count tracked file(s) under knowledge/ -> $REPO ($KB_PATH @ $KB_REF)"
printf '%s\n' "$TRACKED" | sed 's/^/  /'

if [ "$dry" -eq 1 ]; then say "--dry-run: nothing was written."; exit 0; fi

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

# Inside the MOUNTED folder, never at the KB repo's root: with `path: knowledge` that
# root is a shared repo whose own README is somebody else's front page.
README="$INST/knowledge/README.md"
if [ ! -e "$README" ]; then
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
       removed from the bundle's index. Fix the remote and re-run kb-sync.sh commit."
fi

# Step 2 — the bundle. Un-track the same paths and ignore the mount, in ONE commit.
GI="$INST/.gitignore"
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

git -C "$INST" rm -r --cached --quiet -- knowledge || die "could not un-track knowledge/ in the bundle."
git -C "$INST" add -- .gitignore || die "could not stage .gitignore."
git -C "$INST" commit --quiet -m "chore: knowledge/ moves to $REPO

$count files are now tracked in $REPO ($KB_PATH @ $KB_REF) and ignored here.
A clone with no knowledge/ yet makes one with: scripts/kb-sync.sh mount" \
  || die "the bundle commit failed — .gitignore and the index are staged, commit by hand."

say "migrated $count file(s). The bundle no longer tracks knowledge/; the mount does."
