#!/usr/bin/env bash
#
# kb-sync-write.test.sh — the KB write transaction, against a fixture KB repo: one bare
# repo and two bundles that both write to it.
#
# WHAT THE TWO CLONES ARE FOR. Every interesting property of this path only exists with a
# second writer — the derived index conflicting on every commit, the non-fast-forward
# retry, and a same-slug `Finding` arriving from two people. So the fixture is the shape
# the real thing has, and every case below is a race the harness constructs deliberately.
#
# THE DISTINCTION THE SUITE EXISTS TO PIN: `index.md` is DERIVED and its conflict is
# resolved by REGENERATION; anything else is a real collision and stops for a human.
# A script that resolved both would silently pick a winner between two people's Findings.
#
# OFFLINE. The remote is a local bare repo. Nothing here reaches the network.
# ok() compares actual to expected, in that order. Seeded ai-bridge-v3/task-021.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"
SYNC="$REPO/plugin/scripts/kb-sync.sh"
MIGRATE="$REPO/plugin/scripts/kb-migrate.sh"
COMMIT_AS="$REPO/plugin/scripts/commit-as.sh"
SEED="$REPO/plugin/seed"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kb-sync-write.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() {
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export AI_BRIDGE_KB_TIMEOUT=5

# `gh` is never called on this path; the stub is here so a regression that starts calling
# it fails loudly instead of reaching a real host (tests/check-dispatch.test.sh:83).
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "gh: refused in a test" >&2\nexit 90\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"; PATH="$TMP/bin:$PATH"; export PATH

finding() { # <file> <slug> <lesson>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
---
type: Finding
title: $2
description: $2
lesson: $3
category: learning
status: current
author: example-user-007
timestamp: 2026-09-13T00:00:00Z
---

# Finding

$3
EOF
}

BARE="$TMP/kb.git"; git init --bare --quiet "$BARE"
SEEDC="$TMP/seedclone"; git init --quiet -b main "$SEEDC"
finding "$SEEDC/findings/alpha.md" alpha "the first finding"
cp "$SEED/knowledge/vocab.md" "$SEEDC/vocab.md" 2>/dev/null || true
: > "$SEEDC/log.md"
( cd "$SEEDC" && git add -A >/dev/null && git commit -qm seed && git remote add origin "$BARE" && git push -q origin main )

bundle() { # <dir> — a bundle whose knowledge/ is mounted from $BARE
  local d="$1"
  mkdir -p "$d/projects"
  mkdir -p "$d/$AB_DIR" && cp "$SEED/SCHEMA.md" "$d/$AB_SCHEMA"
  cat > "$d/instance.config.json" <<EOF
{ "org": "acme", "ownerGithubUser": "example-user-007",
  "people": { "example-user-007": "seven@example.com" },
  "knowledge": { "repo": "$BARE", "path": "/", "ref": "main" } }
EOF
  git init --quiet -b main "$d" && ( cd "$d" && git add -A >/dev/null && git commit -qm bundle )
  bash "$SYNC" --instance "$d" mount >/dev/null 2>&1
}

A="$TMP/a"; B="$TMP/b"; bundle "$A"; bundle "$B"

echo "== one commit, pushed =="

finding "$A/knowledge/findings/beta.md" beta "a commit is pushed straight away"
out="$(bash "$SYNC" --instance "$A" commit --role cataloguer --message "docs: beta" -- knowledge/findings/beta.md 2>&1)"; rc=$?
ok "a KB commit succeeds" "$rc" 0
ok "…and says it pushed" "$(has "$out" 'pushed')" yes
ok "…leaving nothing local and unpushed" \
  "$(bash "$SYNC" --instance "$A" status >/dev/null 2>&1; echo $?)" 0
ok "…and the derived index was regenerated and carries the new row" \
  "$(grep -c 'a commit is pushed straight away' "$A/knowledge/index.md" | tr -d ' ')" 1
ok "…and the bare repo now has it" \
  "$(git --git-dir="$BARE" show main:findings/beta.md >/dev/null 2>&1; echo $?)" 0

echo "== authorship: the human authors, the tool co-authors =="

msg="$(git --git-dir="$BARE" log -1 --format='%an%x09%ae%x09%B' main)"
ok "the KB commit's author is the human login" "${msg%%$'\t'*}" example-user-007
rest="${msg#*$'\t'}"
ok "…with the human's email from people[]" "${rest%%$'\t'*}" seven@example.com
ok "…and the AI as Co-Authored-By, naming the role and the tool" \
  "$(has "$msg" 'Co-Authored-By: ai-bridge cataloguer (Claude)')" yes
ok "…never the reverse (the tool is not the author)" \
  "$(has "${msg%%$'\t'*}" 'Claude')" no

echo "== index.md conflicts are regenerated, never merged =="

# Both bundles add a Finding and both regenerate the index: the only textual conflict on
# the rebase is index.md, and taking neither side is the whole rule.
finding "$B/knowledge/findings/gamma.md" gamma "the second writer"
out="$(bash "$SYNC" --instance "$B" commit --role cataloguer --message "docs: gamma" -- knowledge/findings/gamma.md 2>&1)"; rc=$?
ok "the second writer's commit lands too" "$rc" 0
ok "…after rebasing over the first" "$(has "$out" 'pushed')" yes
ok "…and the pushed index carries BOTH rows, not one side of a merge" \
  "$(git --git-dir="$BARE" show main:index.md | grep -cE 'the second writer|a commit is pushed straight away' | tr -d ' ')" 2
ok "…and no conflict marker reached the index" \
  "$(git --git-dir="$BARE" show main:index.md | grep -c '<<<<<<<' | tr -d ' ')" 0
ok "…and no rebase was left behind" \
  "$([ -d "$B/$AB_DIR/kb.git/rebase-merge" ] || [ -d "$B/$AB_DIR/kb.git/rebase-apply" ] && echo yes || echo no)" no

echo "== a same-slug Finding from two clones is a REAL conflict a human resolves =="

bash "$SYNC" --instance "$A" pull >/dev/null 2>&1
finding "$A/knowledge/findings/delta.md" delta "A's version of delta"
finding "$B/knowledge/findings/delta.md" delta "B's version of delta"
bash "$SYNC" --instance "$A" commit --role cataloguer --message "docs: delta (A)" -- knowledge/findings/delta.md >/dev/null 2>&1
out="$(bash "$SYNC" --instance "$B" commit --role cataloguer --message "docs: delta (B)" -- knowledge/findings/delta.md 2>&1)"; rc=$?
ok "the same slug from two clones STOPS" "$rc" 1
ok "…naming it a collision rather than resolving it" "$(has "$out" 'real collision')" yes
ok "…naming the conflicted file" "$(has "$out" 'findings/delta.md')" yes
ok "…and aborting its own rebase, so the next reader is not blocked" \
  "$([ -d "$B/$AB_DIR/kb.git/rebase-merge" ] || [ -d "$B/$AB_DIR/kb.git/rebase-apply" ] && echo yes || echo no)" no
ok "…and never force-pushing A's work away" \
  "$(git --git-dir="$BARE" show main:findings/delta.md | grep -c "B's version" | tr -d ' ')" 0
ok "…leaving B's own commit local and reported as unpushed" \
  "$(bash "$SYNC" --instance "$B" status >/dev/null 2>&1; echo $?)" 1

echo "== a rejected push is retried exactly once, then stops =="

# A pre-receive hook that refuses the first push of each run and accepts the next is the
# only deterministic way to reach the retry: a real race cannot be scheduled.
retry_bare() { # <dir> <refusals> — seeded FIRST, so the hook only ever sees our push
  git init --bare --quiet "$1"
  ( cd "$SEEDC" && git push -q "$1" main )
  cat > "$1/hooks/pre-receive" <<EOF
#!/bin/sh
n=\$(cat "\$GIT_DIR/refused" 2>/dev/null || echo 0)
if [ "\$n" -lt $2 ]; then echo \$((n+1)) > "\$GIT_DIR/refused"; echo "refused \$n" >&2; exit 1; fi
exit 0
EOF
  chmod +x "$1/hooks/pre-receive"
}

for spec in "1 0 pushed" "2 1 failed twice"; do
  set -- $spec; refusals=$1; want_rc=$2
  RB="$TMP/retry$refusals.git"; retry_bare "$RB" "$refusals"
  R="$TMP/r$refusals"; mkdir -p "$R/projects"; mkdir -p "$R/$AB_DIR" && cp "$SEED/SCHEMA.md" "$R/$AB_SCHEMA"
  printf '{ "ownerGithubUser": "example-user-007", "people": { "example-user-007": "seven@example.com" }, "knowledge": { "repo": "%s", "path": "/", "ref": "main" } }\n' "$RB" > "$R/instance.config.json"
  bash "$SYNC" --instance "$R" mount >/dev/null 2>&1
  finding "$R/knowledge/findings/eta.md" eta "a rejected push is retried once"
  out="$(bash "$SYNC" --instance "$R" commit --role cataloguer --message "docs: eta" -- knowledge/findings/eta.md 2>&1)"; rc=$?
  ok "$refusals rejection(s): exit $want_rc" "$rc" "$want_rc"
  ok "…and the transaction is reported, not silent" "$(has "$out" 'attempt')" yes
  if [ "$refusals" -eq 1 ]; then
    ok "…and the accepted retry actually pushed eta" \
      "$(git --git-dir="$RB" show main:findings/eta.md >/dev/null 2>&1; echo $?)" 0
    ok "…leaving no unpushed KB commit behind" \
      "$(bash "$SYNC" --instance "$R" status >/dev/null 2>&1; echo $?)" 0
  fi
  ok "…and no rebase is left behind" \
    "$([ -d "$R/$AB_DIR/kb.git/rebase-merge" ] && echo yes || echo no)" no
done
ok "two rejections stop rather than force" \
  "$(bash "$SYNC" --instance "$TMP/r2" status 2>&1 | grep -c 'UNPUSHED' | tr -d ' ')" 1

echo "== the documented recovery command pushes a commit an earlier run left local =="
out="$(bash "$SYNC" --instance "$TMP/r2" commit --role cataloguer --message "docs: eta" -- knowledge/findings/eta.md 2>&1)"; rc=$?
ok "re-running commit with nothing new staged still pushes" "$rc" 0
ok "…rather than reporting 'nothing to commit' forever" "$(has "$out" 'already made')" yes
ok "…and the KB repo now carries eta" \
  "$(git --git-dir="$TMP/retry2.git" show main:findings/eta.md >/dev/null 2>&1; echo $?)" 0
ok "…and the mount reports clean" \
  "$(bash "$SYNC" --instance "$TMP/r2" status >/dev/null 2>&1; echo $?)" 0

echo "== there are no per-user folders anywhere in the KB =="
ok "the KB carries exactly one findings/ folder" \
  "$(git --git-dir="$BARE" ls-tree -d --name-only main | grep -c '^findings$' | tr -d ' ')" 1
ok "…and SCHEMA.md says so" \
  "$(grep -c 'no per-user folders' "$SEED/SCHEMA.md" | tr -d ' ')" 1

echo "== commit-as.sh refuses a path under the mount, by name =="

out="$(cd "$A" && bash "$COMMIT_AS" cataloguer "docs: x" -- knowledge/findings/beta.md 2>&1)"; rc=$?
ok "commit-as.sh refuses a mounted KB path" "$rc" 5
ok "…instead of silently committing nothing" "$(has "$out" 'MOUNTED knowledge base')" yes
ok "…and points at the script that CAN write it" "$(has "$out" 'kb-sync.sh commit')" yes

echo "== unmounted, commit-as.sh regenerates and stages the index instead =="

LOCAL="$TMP/local"
mkdir -p "$LOCAL/knowledge/findings" "$LOCAL/projects"
mkdir -p "$LOCAL/$AB_DIR" && cp "$SEED/SCHEMA.md" "$LOCAL/$AB_SCHEMA"
cp "$SEED/knowledge/vocab.md" "$LOCAL/knowledge/vocab.md" 2>/dev/null || true
: > "$LOCAL/knowledge/log.md"
printf '{ "org": "acme", "authorEmail": "e@example.com" }\n' > "$LOCAL/instance.config.json"
finding "$LOCAL/knowledge/findings/alpha.md" alpha "a local KB"
( cd "$LOCAL" && bash "$REPO/plugin/scripts/build-kb-index.sh" >/dev/null 2>&1 \
  && git init --quiet -b main . && git add -A >/dev/null && git commit -qm seed )
finding "$LOCAL/knowledge/findings/epsilon.md" epsilon "staged without its index row"
( cd "$LOCAL" && git add -- knowledge/findings/epsilon.md )
( cd "$LOCAL" && bash "$COMMIT_AS" cataloguer "docs: epsilon" -- knowledge/findings/epsilon.md ) >/dev/null 2>&1
rc=$?
ok "commit-as.sh still commits a LOCAL knowledge/ path" "$rc" 0
ok "…and regenerated the index into that same commit" \
  "$(cd "$LOCAL" && git show --name-only --format= HEAD | grep -c 'knowledge/index.md' | tr -d ' ')" 1
ok "…with the new row in it" \
  "$(cd "$LOCAL" && git show HEAD:knowledge/index.md | grep -c 'staged without its index row' | tr -d ' ')" 1

echo "== the migration is one recorded commit pair =="

BARE3="$TMP/kb3.git"; git init --bare --quiet "$BARE3"
MIG="$TMP/mig"
mkdir -p "$MIG/knowledge/findings" "$MIG/projects"
mkdir -p "$MIG/$AB_DIR" && cp "$SEED/SCHEMA.md" "$MIG/$AB_SCHEMA"
cp "$SEED/knowledge/vocab.md" "$MIG/knowledge/vocab.md" 2>/dev/null || true
: > "$MIG/knowledge/log.md"
printf '{ "org": "acme", "ownerGithubUser": "example-user-007", "people": { "example-user-007": "seven@example.com" }, "knowledge": { "repo": "%s", "path": "/", "ref": "main" } }\n' "$BARE3" > "$MIG/instance.config.json"
finding "$MIG/knowledge/findings/zeta.md" zeta "a finding that must survive the move"
( cd "$MIG" && bash "$REPO/plugin/scripts/build-kb-index.sh" >/dev/null 2>&1 \
  && git init --quiet -b main . && git add -A >/dev/null && git commit -qm seed )

finding "$MIG/knowledge/findings/dirty.md" dirty "an uncommitted file makes the tree dirty"
out="$(bash "$MIGRATE" --instance "$MIG" 2>&1)"; rc=$?
ok "a dirty tree REFUSES the migration" "$rc" 1
ok "…saying why" "$(has "$out" 'dirty')" yes
rm -f "$MIG/knowledge/findings/dirty.md"

out="$(bash "$MIGRATE" --instance "$MIG" --dry-run 2>&1)"
ok "--dry-run prints every path it would move" "$(has "$out" 'knowledge/findings/zeta.md')" yes
ok "…and writes nothing" "$(cd "$MIG" && git ls-files -- knowledge | grep -c zeta | tr -d ' ')" 1

out="$(bash "$MIGRATE" --instance "$MIG" 2>&1)"; rc=$?
ok "the migration runs" "$rc" 0
ok "…and the KB repo now holds the files" \
  "$(git --git-dir="$BARE3" show main:findings/zeta.md >/dev/null 2>&1; echo $?)" 0
ok "…and the bundle tracks none of them any more" \
  "$(cd "$MIG" && git ls-files -- knowledge | grep -c . | tr -d ' ')" 0
ok "…via ONE bundle commit carrying the ignore line too" \
  "$(cd "$MIG" && git show --name-only --format= HEAD | grep -c '^\.gitignore$' | tr -d ' ')" 1
ok "…which ignores the mount" \
  "$(cd "$MIG" && git check-ignore -q knowledge && echo yes || echo no)" yes
ok "…and knowledge/ is still populated here, from the mount" \
  "$([ -f "$MIG/knowledge/findings/zeta.md" ] && echo yes || echo no)" yes
ok "…and the KB repo carries the harness-neutral reading rule" \
  "$(git --git-dir="$BARE3" show main:README.md | grep -c 'at most three' | tr -d ' ')" 1
ok "…including the Superseded clause" \
  "$(git --git-dir="$BARE3" show main:README.md | grep -ci 'superseded' | tr -d ' ')" 1
ok "…and the index-first clause" \
  "$(git --git-dir="$BARE3" show main:README.md | grep -c 'index.md' | tr -d ' ')" 1

echo "== a clone that pulls that commit before syncing sees NO knowledge/ =="

FRESH="$TMP/fresh"
git clone --quiet "$MIG" "$FRESH" 2>/dev/null
ok "a fresh clone has no knowledge/ at all" \
  "$([ -e "$FRESH/knowledge" ] && echo yes || echo no)" no
ok "…and no dangling link either" \
  "$([ -L "$FRESH/knowledge" ] && echo yes || echo no)" no
ok "…and the ignore line names the one command that makes one" \
  "$(grep -c 'kb-sync.sh mount' "$FRESH/.gitignore" | tr -d ' ')" 1
cp "$MIG/instance.config.json" "$FRESH/instance.config.json"
bash "$SYNC" --instance "$FRESH" mount >/dev/null 2>&1
ok "…and that one command populates it" \
  "$([ -f "$FRESH/knowledge/findings/zeta.md" ] && echo yes || echo no)" yes

echo "== a migration that stopped half-way is finished by running it again (task-008) =="
# 2026-10-03: the push failed after the mount, and every later run refused the tree its own
# first run had dirtied. Each stop below is a real one, and the same command resumes it.
BARE4="$TMP/kb4.git"; git init --bare --quiet "$BARE4"
RES="$TMP/res"
mkdir -p "$RES/knowledge/findings" "$RES/projects" "$RES/$AB_DIR"
cp "$SEED/SCHEMA.md" "$RES/$AB_SCHEMA"; cp "$SEED/.gitignore" "$RES/.gitignore"
: > "$RES/knowledge/log.md"
printf '{ "org": "acme", "ownerGithubUser": "example-user-007", "people": { "example-user-007": "seven@example.com" }, "knowledge": { "repo": "%s", "path": "/", "ref": "main" } }\n' "$BARE4" > "$RES/instance.config.json"
finding "$RES/knowledge/findings/eta.md"   eta   "a finding that must survive a stopped move"
finding "$RES/knowledge/findings/theta.md" theta "a second one"
( cd "$RES" && bash "$REPO/plugin/scripts/build-kb-index.sh" >/dev/null 2>&1 \
  && git init --quiet -b main . && git add -A >/dev/null && git commit -qm seed )
tracked() { (cd "$RES" && git ls-files -- knowledge | grep -c . | tr -d ' '); }
want="$(tracked)"
printf '#!/bin/sh\nexit 1\n' > "$BARE4/hooks/pre-receive"; chmod +x "$BARE4/hooks/pre-receive"

out="$(bash "$MIGRATE" --instance "$RES" 2>&1)"; rc=$?
ok "a rejected push stops the first run" "$rc" 1
ok "…after the mount was made" "$([ -d "$RES/$AB_DIR/kb.git" ] && echo yes || echo no)" yes
ok "…removing nothing from the bundle's index" "$(tracked)" "$want"
ok "…and leaving the bundle's tree clean, mount and README included" \
  "$(cd "$RES" && git status --porcelain | grep -c . | tr -d ' ')" 0

out="$(bash "$MIGRATE" --instance "$RES" 2>&1)"; rc=$?
ok "the re-run is not refused as dirty" "$(has "$out" 'dirty')" no
ok "…it resumes, and stops on the same push" "$rc" 1

rm -f "$BARE4/hooks/pre-receive"
printf '#!/bin/sh\nexit 1\n' > "$RES/.git/hooks/pre-commit"; chmod +x "$RES/.git/hooks/pre-commit"
out="$(bash "$MIGRATE" --instance "$RES" 2>&1)"; rc=$?
ok "a refused bundle commit stops the run" "$rc" 1
ok "…after the KB push landed" "$(git --git-dir="$BARE4" show main:findings/eta.md >/dev/null 2>&1; echo $?)" 0
ok "…rolled back to a clean tree" "$(cd "$RES" && git status --porcelain | grep -c . | tr -d ' ')" 0
ok "…still tracking every file" "$(tracked)" "$want"

DEL="$TMP/res-del"; git clone --quiet -b main "$BARE4" "$DEL"
( cd "$DEL" && git rm -q findings/eta.md && git commit -qm "remove eta" && git push -q origin main )
out="$(bash "$MIGRATE" --instance "$RES" 2>&1)"; rc=$?
ok "a file absent from the remote refuses the index removal" "$rc" 1
ok "…naming the count" "$(has "$out" "1 of $want tracked file(s) are NOT on")" yes
ok "…and the file, in the absent list" "$(has "$out" '         knowledge/findings/eta.md')" yes
ok "…removing nothing" "$(tracked)" "$want"

( cd "$DEL" && git revert --no-edit HEAD >/dev/null && git push -q origin main )
rm -f "$RES/.git/hooks/pre-commit"
out="$(bash "$MIGRATE" --instance "$RES" 2>&1)"; rc=$?
ok "the same command then finishes the migration" "$rc" 0
ok "…after verifying every file on the remote" "$(has "$out" "verified $want of $want file(s)")" yes
ok "…and the bundle tracks none of them" "$(tracked)" 0
ok "…in one commit with the ignore line" \
  "$(cd "$RES" && git show --name-only --format= HEAD | grep -c '^\.gitignore$' | tr -d ' ')" 1
ok "…leaving the tree clean" "$(cd "$RES" && git status --porcelain | grep -c . | tr -d ' ')" 0

out="$(bash "$MIGRATE" --instance "$RES" 2>&1)"; rc=$?
ok "a run after the migration is a no-op" "$rc" 0
ok "…saying so" "$(has "$out" 'already migrated')" yes

# The README is hidden from the bundle in its own exclude, not its .gitignore: with
# `path: knowledge` the KB worktree IS the bundle root and reads that file.
BARE5="$TMP/kb5.git"; git init --bare --quiet "$BARE5"
RK="$TMP/res-k"; mkdir -p "$RK/knowledge/findings" "$RK/$AB_DIR"
cp "$SEED/SCHEMA.md" "$RK/$AB_SCHEMA"; cp "$SEED/.gitignore" "$RK/.gitignore"; : > "$RK/knowledge/log.md"
printf '{ "ownerGithubUser": "example-user-007", "people": { "example-user-007": "seven@example.com" }, "knowledge": { "repo": "%s", "path": "knowledge", "ref": "main" } }\n' "$BARE5" > "$RK/instance.config.json"
finding "$RK/knowledge/findings/iota.md" iota "a shared-repo migration"
( cd "$RK" && bash "$REPO/plugin/scripts/build-kb-index.sh" >/dev/null 2>&1 \
  && git init --quiet -b main . && git add -A >/dev/null && git commit -qm seed )
bash "$MIGRATE" --instance "$RK" >/dev/null 2>&1; rc=$?
ok "a path: knowledge migration runs" "$rc" 0
ok "…and its KB commit carries the README" \
  "$(git --git-dir="$BARE5" show main:knowledge/README.md >/dev/null 2>&1; echo $?)" 0

TOK="$TMP/res-tok"; mkdir -p "$TOK/knowledge"; : > "$TOK/knowledge/log.md"
printf '{ "knowledge": { "repo": "https://u:s3cr3tt0ken@example.com/kb.git", "path": "/" } }\n' > "$TOK/instance.config.json"
( cd "$TOK" && git init --quiet -b main . && git add -A >/dev/null && git commit -qm seed )
out="$(bash "$MIGRATE" --instance "$TOK" --dry-run 2>&1)"
ok "a tokened knowledge.repo is named without its token" \
  "$(has "$out" 'example.com/kb.git')$(has "$out" 's3cr3tt0ken')" yesno

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
