#!/usr/bin/env bash
#
# kb-compare.test.sh — plugin/scripts/kb-compare.sh, the reflector's comparator, alone and as
# kb-propose.sh's proposer.
#
# THE FALSE MERGE IS THE WHOLE RISK, so its fixtures are SYNTHETIC pairs built to the
# dangerous shape — every word shared but the interpreter, the calling context or the
# harness — and each must also be the NEAREST item at a high score, or refusing it would
# prove nothing. Byte-identity is asserted on runs that FOUND a duplicate, ignored files and
# a mounted KB's own gitdir included. ok() compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
CMP="$REPO/plugin/scripts/kb-compare.sh"
PROPOSE="$REPO/plugin/scripts/kb-propose.sh"
APPLY="$REPO/plugin/scripts/kb-apply.sh"
SYNC="$REPO/plugin/scripts/kb-sync.sh"
SEED="$REPO/plugin/seed"
[ -x "$CMP" ] || { echo "kb-compare.test: $CMP is missing or not executable" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kbcompare.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null AI_BRIDGE_KB_TIMEOUT=3
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

pass=0; fail=0
ok() {
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }
kbsum() { ( cd "$1" && find knowledge "$AB_DIR" -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort ); }
code() { grep -vE '^[[:space:]]*#' "$1"; }

doc() { # <file> <type> <provenance> <title> <description> <lesson-line(s)> [extra frontmatter]
  mkdir -p "$(dirname "$1")"
  printf -- '---\ntype: %s\ntitle: %s\ndescription: %s\n%s\ncategory: learning\ntags: [kb]\nstatus: current\nprovenance: %s\n%stimestamp: 2026-10-01T00:00:00Z\n---\n\n# Finding\n\nBody.\n' \
    "$2" "$4" "$5" "$6" "$3" "${7:-}" >"$1"
}
F() { doc "$K/findings/$1.md" Finding "${2}" "$3" "$4" "lesson: $5" "${6:-}"; }
C() { doc "$CD/$1.md" Finding machine "$2" "$3" "lesson: $4" "${5:-}"; }

D="$TMP/bundle"; K="$D/knowledge"; CD="$TMP/cands"
mkdir -p "$K/findings" "$K/services" "$D/$AB_DIR" "$CD"
cp "$SEED/SCHEMA.md" "$D/$AB_SCHEMA"; cp "$SEED/knowledge/vocab.md" "$K/vocab.md"
printf '{ "org": "example-org" }\n' >"$D/instance.config.json"
printf 'knowledge/*.log\n' >"$D/.gitignore"

# --- the corpus --------------------------------------------------------------
F worktree-remove-drops-ignored-files machine "git worktree remove drops ignored files" \
  "a worktree whose only content is ignored files is removed without force" \
  "check for ignored files before git worktree remove, because status cannot show them"
F index-is-derived-from-frontmatter machine "The KB index is derived from frontmatter" \
  "index.md rows come from the lesson field of each document" \
  "Never hand-edit index.md; regenerate it from the frontmatter of the documents."
F ledger-is-append-only machine "The ledger is append-only" "no verb edits or removes a ledger entry" \
  "append a new ledger entry instead of editing an old one"
F read-t-hangs-on-a-pipe machine "read -t hangs on a pipe under bash 3.2" \
  "a read with a timeout never returns when stdin is a pipe under bash 3.2" \
  "wrap every read -t on a pipe in an external timeout under bash 3.2"
F old-claim machine "The tick lock expires after ten minutes" "a stale lock is released by age" \
  "trust the tick lock age to release a stale lock" "superseded_by: new-claim
"
sed -i.bak 's/^status: current/status: superseded/' "$K/findings/old-claim.md" && rm -f "$K/findings/old-claim.md.bak"
F new-claim machine "A long tick is not a dead one" "tick-lock release is the human override" \
  "never release the tick lock on age alone; the human releases it" "supersedes: [ old-claim ]
"
F human-claim human "Pause a project by flipping its status" "pausing never demotes tasks" \
  "pause by flipping project status alone, never by demoting tasks to draft"
doc "$K/findings/folded-lesson.md" Finding machine "A board number is never truncated" \
  "the terminal board prints every digit" "lesson: >-
  never clip a number on the board,
  print every digit"
F blank-lesson machine "Prune worktrees is report only" "the pruner never deletes a worktree" ""
F multi-a machine "Scratch is task unique" "two agents share one scratchpad" "key every scratch path by task"
F multi-b machine "Scratch is task unique" "two agents share one scratchpad" "key every scratch path by task"
doc "$K/services/svc-twin.md" Service machine "The renderer escapes per medium" \
  "a terminal and a page escape differently" "lesson: escape for the medium the renderer writes"
sed -i.bak "s/^provenance: machine/provenance: 'machine'/" "$K/findings/folded-lesson.md" && rm -f "$K/findings/folded-lesson.md.bak"
printf 'ignored\n' >"$K/scratch.log"
cd "$D" || exit 2
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && git commit -qm init

# --- the candidates ----------------------------------------------------------
C cand-merge-wording "Ignored files: git worktree remove drops them" \
  "Without force, a worktree is removed whose only content is ignored files." \
  "Because status cannot show ignored files, check for them before git worktree remove."
C cand-merge-case "THE KB INDEX IS DERIVED FROM FRONTMATTER" \
  "Index.md rows come from each document lesson field." \
  "Regenerate index.md from documents frontmatter — never hand-edit it."
doc "$CD/cand-patch.md" Finding machine "Ledgers are append-only" "No verb edits or removes ledger entries." \
  "lesson: Instead of editing an old ledger entry, append a new one."
sed -i.bak 's/^tags: \[kb\]/tags: [kb, ledger]/' "$CD/cand-patch.md" && rm -f "$CD/cand-patch.md.bak"
C cand-new "Concurrent agents need task-unique artifact names" \
  "a shared pr-body.md is overwritten by a sibling" "name every artifact after the task that owns it"
C cand-hang-zsh "read -t hangs on a pipe under zsh 5.9" \
  "a read with a timeout never returns when stdin is a pipe under zsh 5.9" \
  "wrap every read -t on a pipe in an external timeout under zsh 5.9"
C cand-hang-cron "read -t hangs on a pipe under bash 3.2" \
  "a read with a timeout never returns when stdin is a pipe under bash 3.2" \
  "wrap every read -t on a pipe in an external timeout under bash 3.2 when called from cron"
C cand-hang-bats "read -t hangs on a pipe under bash 3.2 in the bats harness" \
  "a read with a timeout never returns when stdin is a pipe under bash 3.2" \
  "wrap every read -t on a pipe in an external timeout under bash 3.2"
C cand-sup "The tick lock expires after ten minutes" "A stale lock is released by age." \
  "Trust the tick lock age to release a stale lock."
C cand-human "Pause a project by flipping its status" "Pausing never demotes tasks." \
  "Pause by flipping project status alone, never by demoting tasks to draft."
C cand-folded "A board number is never truncated" "The terminal board prints every digit." \
  "Print every digit; never clip a number on the board."
doc "$CD/cand-block.md" Finding machine "The KB index is derived from frontmatter" \
  "index.md rows come from the lesson field of each document" "lesson: >-
  Never hand-edit index.md;
  regenerate it from the frontmatter of the documents."
C cand-empty "Something" "something else" ""
doc "$CD/cand-block-empty.md" Finding machine "Something" "something else" "lesson: >-"
C cand-near-blank "Prune worktrees is report only" "The pruner never deletes a worktree." "never add a delete flag"
C cand-svc "The renderer escapes per medium" "a terminal and a page escape differently" \
  "escape for the medium the renderer writes"
C cand-multi "Scratch is task unique" "Two agents share one scratchpad." "Key every scratch path by task."
doc "$CD/cand-runbook.md" Runbook machine "x" "y" "lesson: z"

run() { # <candidate> -> OUT, ERR, RC
  OUT="$("$CMP" "$CD/$1.md" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
}
f() { awk -F' · ' -v n="$1" '{ print $n }' <<<"$OUT"; }
HEAD12="$(git rev-parse --short=12 HEAD)"

echo "== criterion 5: an always-append reflector fails — merge, merge, patch, append =="
run cand-merge-wording
ok "near-duplicate 1 (reworded, reordered) is a merge"     "$(f 1)" merge
ok "…naming the existing slug"                             "$(f 2)" worktree-remove-drops-ignored-files
ok "…and the candidate's"                                  "$(f 4)" cand-merge-wording
ok "…with the specific change"                             "$(f 3)" timestamp=2026-10-01T00:00:00Z
ok "…and the proposal names its outcome"                   "$(has "$(f 5)" 'merge: cand-merge-wording restates')" yes
ok "…and exits 0"                                          "$RC" 0
run cand-merge-case
ok "near-duplicate 2 (case, punctuation, plurals) is a merge" "$(f 1)/$(f 2)/$(f 4)" merge/index-is-derived-from-frontmatter/cand-merge-case
run cand-patch
ok "the same key plus a tag the item lacks is a patch"     "$(f 1)/$(f 2)/$(f 4)" edit/ledger-is-append-only/cand-patch
ok "…whose change is the tag union"                        "$(f 3)" "tags=[kb, ledger]"
ok "…and which says it is a patch"                         "$(has "$(f 5)" 'patch: cand-patch adds tags ledger')" yes
run cand-new
ok "a clearly new Finding proposes nothing"                "$OUT" ""
ok "…and says append as new"                               "$(has "$ERR" 'kb-compare: append as new · cand-new')" yes
ok "…exit 0"                                               "$RC" 0

echo "== criterion 4: the false merge is refused on synthetic pairs =="
for c in cand-hang-zsh cand-hang-cron cand-hang-bats; do
  run "$c"
  ok "$c: no proposal"                                     "$OUT" ""
  ok "…append as new, nearest read-t-hangs-on-a-pipe"      "$(has "$ERR" "append as new · $c · read-t-hangs-on-a-pipe · nearest")" yes
  sc="$(sed -n 's/.*nearest read-t-hangs-on-a-pipe (\([0-9.]*\)).*/\1/p' <<<"$ERR")"
  ok "…which it IS near (score ≥ 0.70), so the refusal is not vacuous" \
    "$(awk -v s="${sc:-0}" 'BEGIN { print (s >= 0.70) ? "yes" : "no" }')" yes
done
run cand-hang-zsh
ok "the verdict names the words that differ"               "$(has "$ERR" 'only here: zsh,5.9; only there: bash,3.2')" yes

echo "== criterion 3: the key is title + description + lesson:, folded blocks read =="
run cand-folded
ok "a candidate matching a 'lesson: >-', provenance: 'machine' item is a merge"   "$(f 1)/$(f 2)" merge/folded-lesson
run cand-block
ok "a candidate whose OWN lesson is '>-' is read folded"   "$(f 1)/$(f 2)" merge/index-is-derived-from-frontmatter
for c in cand-empty cand-block-empty; do
  run "$c"
  ok "$c: no proposal: unreadable, never append"           "$(has "$ERR" "no proposal: unreadable · $c")/$RC/$OUT" yes/1/
done
run cand-near-blank
ok "a NEAR item with an empty lesson: is unreadable too"   "$(has "$ERR" 'no proposal: unreadable · cand-near-blank · blank-lesson')/$RC" yes/1
ok "no new frontmatter field is read"                      "$(code "$CMP" | grep -oE 'V\[[a-z0-9]+, "[a-z_]+"\]' | sed 's/.*"\(.*\)".*/\1/' | sort -u | tr '\n' ' ')" \
  "description lesson provenance superseded_by tags timestamp title type "

E="$TMP/empty"; mkdir -p "$E/knowledge/findings"
ok "an empty KB is append as new, not an error" "$(cd "$E" && "$CMP" "$CD/cand-new.md" 2>&1 >/dev/null | grep -c 'append as new')" 1
echo "== criterion 6: superseded and human-authored targets =="
run cand-sup
ok "a match on a superseded item follows the edge"         "$(f 1)/$(f 2)/$(f 4)" merge/new-claim/cand-sup
ok "…and names both slugs"                                 "$(has "$(f 5)" 'matched old-claim → new-claim via superseded_by')" yes
run cand-human
ok "a match on a human-authored item is no proposal"       "$OUT/$RC" /0
ok "…reported human-authored, review only"                 "$(has "$ERR" 'human-authored, review only · cand-human · human-claim')" yes

echo "== criterion 7: one candidate, against type: Finding only =="
run cand-svc
ok "a Service with the same words is not compared"         "$OUT/$(has "$ERR" 'append as new · cand-svc · - ·')" /yes
run cand-multi
ok "several matches: the best is the target"               "$(f 2)" multi-a
ok "…the merge leads to the candidate alone"               "$(f 4)" cand-multi
ok "…and the rest are listed"                              "$(has "$(f 5)" 'also near: multi-b 1.00')" yes
ok "a candidate that is not a Finding is refused"          "$("$CMP" "$CD/cand-runbook.md" >/dev/null 2>&1; echo $?)" 2

echo "== criterion 8: a script, not a prompt or the index renderer =="
ok "build-kb-index.sh does not carry it"  "$(grep -c 'kb-compare' "$REPO/plugin/scripts/build-kb-index.sh")" 0
ok "the cataloguer prompt does not carry it" "$(grep -c 'kb-compare' "$REPO/plugin/agents/cataloguer.md")" 0
ok "no write verb in its code"            "$(code "$CMP" | grep -cE 'git (add|commit|mv|rm|checkout|pull|fetch)|mkdir|mktemp| > *"|>>|tee |sed -i|\bmv |\brm ')" 0

echo "== criteria 1, 2, 9: the productive run through kb-propose.sh writes nothing =="
cp "$CD/cand-merge-wording.md" "$TMP/keep.md"
BEFORE="$(kbsum "$D")"
ok "the fingerprint covers the ignored file"  "$(grep -c 'knowledge/scratch.log' <<<"$BEFORE")" 1
ok "…which git status cannot see"             "$(git status --porcelain --ignored=no knowledge/ | wc -l | tr -d ' ')" 0
out="$("$PROPOSE" --proposer "$CMP $CD/cand-merge-wording.md" 2>/dev/null)"; rc=$?
ok "kb-propose.sh runs it as the proposer and writes a report" "$rc" 0
R="$(sed -n 's/.* in \(projects[^ ]*\.md\) .*/\1/p' <<<"$out")"
ok "…the report is a draft task document outside knowledge/" "$(sed -n 's/^type: //p' "$R")/${R%%/*}" Task/projects
ok "…carrying the merge"   "$(grep -c '^P1 · merge · worktree-remove-drops-ignored-files · timestamp=.* · cand-merge-wording · [0-9]*-[0-9]* · merge: ' "$R")" 1
ok "…and the KB HEAD it read" "$(grep -c "kb bundle@$HEAD12" "$R")" 1
ok "EVERY file under knowledge/ is byte-identical, ignored ones too" "$([ "$BEFORE" = "$(kbsum "$D")" ] && echo yes || echo no)" yes
ok "…and so is the candidate"  "$(cmp -s "$TMP/keep.md" "$CD/cand-merge-wording.md" && echo yes || echo no)" yes
out="$("$PROPOSE" --project kb-patch --proposer "$CMP $CD/cand-patch.md" 2>/dev/null)"
RP="$(sed -n 's/.* in \(projects[^ ]*\.md\) .*/\1/p' <<<"$out")"
ok "the patch reaches a report too"  "$(grep -c '^P1 · edit · ledger-is-append-only · tags=\[kb, ledger\] · cand-patch · ' "$RP")" 1
ok "…still byte-identical"           "$([ "$BEFORE" = "$(kbsum "$D")" ] && echo yes || echo no)" yes
git add -A projects && git commit -qm reports
for r in "$R" "$RP"; do
  A="$TMP/apply-$(basename "$r" .md)"; cp -R "$D" "$A"
  ok "kb-apply.sh pre-flights and applies $(basename "$r")" \
    "$(cd "$A" && "$APPLY" --by example-user-007 "$r" >/dev/null 2>&1; echo $?)" 0
done
ok "…the merge lands its ledger entry" "$(grep -c '^ledger:.*merge.*items worktree-remove-drops-ignored-files,cand-merge-wording' \
  "$TMP/apply-$(basename "$R" .md)/knowledge/findings/worktree-remove-drops-ignored-files.md")" 1
ok "…the patch lands its tags"         "$(sed -n 's/^tags: //p' "$TMP/apply-$(basename "$RP" .md)/knowledge/findings/ledger-is-append-only.md")" "[kb, ledger]"

echo "== criteria 1, 9: a mounted KB is read as it stands, never pulled =="
BARE="$TMP/kb.git"; SC="$TMP/seedclone"; M="$TMP/mounted"
git init --bare -q "$BARE"; git init -q -b main "$SC"
cp -R "$K/findings" "$SC/findings"; cp "$K/vocab.md" "$SC/vocab.md"
( cd "$SC" && git add -A && git commit -qm seed && git remote add origin "$BARE" && git push -q origin main )
mkdir -p "$M/projects" "$M/$AB_DIR" && cp "$SEED/SCHEMA.md" "$M/$AB_SCHEMA"
printf '{ "org": "example-org", "knowledge": { "repo": "%s", "path": "/", "ref": "main" } }\n' "$BARE" >"$M/instance.config.json"
ok "the mount is made" "$(bash "$SYNC" --instance "$M" mount >/dev/null 2>&1; echo $?)" 0
MHEAD="$(git --git-dir="$M/$AB_DIR/kb.git" rev-parse --short=12 HEAD)"
printf 'ignored\n' >"$M/knowledge/scratch.log"
cp "$CD/cand-new.md" "$SC/findings/remote-only.md"
( cd "$SC" && git add -A && git commit -qm ahead && git push -q origin main )
MB="$(kbsum "$M")"
ok "the fingerprint descends the mount's own gitdir" "$(grep -c "$AB_DIR/kb.git/HEAD" <<<"$MB")" 1
out="$(cd "$M" && "$PROPOSE" --proposer "$CMP $CD/cand-merge-wording.md" 2>/dev/null)"; rc=$?
RM="$M/$(sed -n 's/.* in \(projects[^ ]*\.md\) .*/\1/p' <<<"$out")"
ok "the run over the mount finds the duplicate" "$rc/$(grep -c '^P1 · merge · worktree-remove-drops-ignored-files' "$RM")" 0/1
ok "…and names the mount HEAD it read"          "$(grep -c "kb mount@$MHEAD" "$RM")" 1
ok "every file in the mount and its gitdir is byte-identical" "$([ "$MB" = "$(kbsum "$M")" ] && echo yes || echo no)" yes
ok "…so it did not pull the newer remote item"  "$([ -e "$M/knowledge/findings/remote-only.md" ] && echo yes || echo no)" no

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
