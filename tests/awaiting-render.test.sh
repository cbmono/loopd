#!/usr/bin/env bash
# build-awaiting.sh — the queue's STRUCTURE is the script's, the trailing sentence is the
# model's (ai-bridge-v3/task-024).
#
# THE BYTE-IDENTITY CASE IS THE POINT. session-banner.sh greps `## 🔴 Awaiting you` and a
# `* ` marker literally, so a reshape empties the startup nudge instead of failing — the
# rendered page for a fixture bundle is therefore compared byte for byte against the layout
# the project-manager used to write by hand, `Last refreshed:` excepted (it moves by
# design). What is NOT byte-asserted is the trailer text: that is per-tick prose.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/build-awaiting.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/awaiting-render.XXXXXX")" || {
  echo "awaiting-render.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

ok "the renderer exists" "$([ -f "$SH" ] && echo yes || echo no)" yes

inst() { # <dir> — a minimal instance signature
  mkdir -p "$1/projects/demo/tasks" "$1/$AB_DIR"
  printf '{ "org": "demo" }\n' > "$1/instance.config.json"
  printf '# SCHEMA\n' > "$1/$AB_SCHEMA"
  printf -- '---\ntype: Project\ntitle: "Demo"\nstatus: active\n---\n' > "$1/projects/demo/project.md"
}
task() { # <dir> <id> <title> <status> <criteria> <questions>
  printf -- '---\ntype: Task\ntitle: "%s"\nstatus: %s\nacceptance_criteria: [ %s ]\nopen_questions: [ %s ]\n---\n' \
    "$3" "$4" "$5" "$6" > "$1/projects/demo/tasks/$2.md"
}

echo "== the off switch is ABSENCE, and it is the script's rule, not the caller's =="
A="$TMP/off"; inst "$A"; task "$A" task-001-a "Clean draft" draft '"x"' ''
bash "$SH" --instance "$A" >/dev/null 2>&1
ok "no AWAITING.md ⇒ it is not created" "$([ -e "$A/$AB_AWAITING" ] && echo yes || echo no)" no
ok "…and that is exit 0, not an error"  "$(bash "$SH" --instance "$A" >/dev/null 2>&1; echo $?)" 0

echo
echo "== BYTE-IDENTICAL to the page the project-manager wrote by hand =="
B="$TMP/bytes"; inst "$B"; : > "$B/$AB_AWAITING"
task "$B" task-001-a "Clean draft"   draft    '"x"' ''
task "$B" task-002-b "Has questions" draft    '"x"' '"Q1: which colour?", "Q2: install the foo CLI"'
task "$B" task-003-c "Stuck"         blocked  '"x"' ''
task "$B" task-004-d "Green"         in-review '"x"' ''
bash "$SH" --instance "$B" \
  --merge "$B/projects/demo/tasks/task-004-d.md=[ai-bridge#7](https://github.com/cbmono/ai-bridge/pull/7)" \
  --trailer "$B/projects/demo/tasks/task-003-c.md=waiting on a host account" >/dev/null 2>&1

# Rows are in severity order, not glob order (tests/awaiting-queue.test.sh pins the sort);
# each row's bytes are unchanged.
cat > "$TMP/want" <<'WANT'
# Awaiting you

Derived and gitignored — **do not hand-edit**. Rewritten from `projects/*/tasks/*.md`
by each dispatch tick that changed something. Set "awaiting": false in instance.config.json to turn the queue off.
Last refreshed: <ISO>.

## 🔴 Awaiting you (5)
* 🧰 **grant** — [Has questions](/projects/demo/tasks/task-002-b.md) · Q2: install the foo CLI (no recommendation)
* ⛔ **unblock** — [Stuck](/projects/demo/tasks/task-003-c.md) · waiting on a host account
* ❓ **answer** — [Has questions](/projects/demo/tasks/task-002-b.md) · Q1: which colour? (no recommendation)
* ✅ **approve** — [Clean draft](/projects/demo/tasks/task-001-a.md) · unverified · no design yet · refined & clean, promote `draft → ready`
* 🔀 **merge** — [Green](/projects/demo/tasks/task-004-d.md) · [ai-bridge#7](https://github.com/cbmono/ai-bridge/pull/7)
WANT
sed -E 's/^Last refreshed: .*$/Last refreshed: <ISO>./' "$B/$AB_AWAITING" > "$TMP/got"
ok "the rendered page is byte-identical" "$(cmp -s "$TMP/got" "$TMP/want" && echo yes || echo no)" yes
[ -s "$TMP/got" ] && head -20 <<<"$(diff -u "$TMP/want" "$TMP/got")"

echo
echo "== the consumer's two literals, asserted against the render itself =="
ok "the heading session-banner.sh greps"  "$(grep -c '^## 🔴 Awaiting you (' "$B/$AB_AWAITING" | tr -d ' ')" 1
ok "every row uses the '* ' marker"       "$(grep -c '^\* ' "$B/$AB_AWAITING" | tr -d ' ')" 5
ok "…and the heading's count matches"     "$(sed -n 's/^## 🔴 Awaiting you (\([0-9]*\)).*/\1/p' "$B/$AB_AWAITING")" 5
ok "the timestamp line is present"        "$(grep -cE '^Last refreshed: [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$B/$AB_AWAITING" | tr -d ' ')" 1

echo
echo "== the GLYPH is the script's: grant vs answer is classified, never handed in =="
ok "an install request is a grant"  "$(grep -c '🧰 \*\*grant\*\*.*install the foo CLI' "$B/$AB_AWAITING" | tr -d ' ')" 1
ok "…and a plain question is not"   "$(grep -c '🧰 \*\*grant\*\*.*which colour' "$B/$AB_AWAITING" | tr -d ' ')" 0
ok "the plain question is an answer" "$(grep -c '❓ \*\*answer\*\*.*which colour' "$B/$AB_AWAITING" | tr -d ' ')" 1
# The classifier is the only place the choice is made — no flag lets a caller pick one.
ok "no caller-supplied glyph flag"  "$(grep -cE '^\s+--glyph\)' "$SH" | tr -d ' ')" 0

echo
echo "== an ANSWERED question is step 2's fold, never the human's queue =="
C="$TMP/answered"; inst "$C"; : > "$C/$AB_AWAITING"
task "$C" task-001-a "Answered" draft '"x"' '"Q1: which colour? --- blue"'
bash "$SH" --instance "$C" >/dev/null 2>&1
ok "an answered entry queues nothing"  "$(grep -c '❓ \*\*answer\*\*' "$C/$AB_AWAITING" | tr -d ' ')" 0
ok "…and the clean draft is an approve" "$(grep -c '✅ \*\*approve\*\*' "$C/$AB_AWAITING" | tr -d ' ')" 1

echo
echo "== an empty queue renders _None._ under the heading, never an empty page =="
D="$TMP/empty"; inst "$D"; : > "$D/$AB_AWAITING"
task "$D" task-001-a "Running" in-progress '"x"' ''
bash "$SH" --instance "$D" >/dev/null 2>&1
ok "the heading still renders, at zero" "$(grep -c '^## 🔴 Awaiting you (0)$' "$D/$AB_AWAITING" | tr -d ' ')" 1
ok "…with _None._ under it"             "$(grep -c '^_None\._$' "$D/$AB_AWAITING" | tr -d ' ')" 1
ok "…and no row at all"                 "$(grep -c '^\* ' "$D/$AB_AWAITING" | tr -d ' ')" 0

echo
echo "== a done project is skipped, and a finished one is a close row =="
E="$TMP/close"; inst "$E"; : > "$E/$AB_AWAITING"
task "$E" task-001-a "Shipped" done '"x"' ''
bash "$SH" --instance "$E" >/dev/null 2>&1
ok "all-terminal proposes a close"  "$(grep -c '🏁 \*\*close\*\*' "$E/$AB_AWAITING" | tr -d ' ')" 1
printf -- '---\ntype: Project\ntitle: "Demo"\nstatus: done\n---\n' > "$E/projects/demo/project.md"
bash "$SH" --instance "$E" >/dev/null 2>&1
ok "…and a done project proposes none" "$(grep -c '🏁 \*\*close\*\*' "$E/$AB_AWAITING" | tr -d ' ')" 0

echo
echo "== the shared-instance narrowing is the SCRIPT's, not the model's =="
ok "it asks task-owner.sh itself"   "$(grep -c 'task-owner.sh' "$SH" | tr -d ' ' | awk '{print ($1>0)?"yes":"no"}')" yes
ok "…from the instance root"        "$(grep -c 'cd "$inst" && bash "$HERE/task-owner.sh"' "$SH" | tr -d ' ')" 1
F="$TMP/shared"; inst "$F"; : > "$F/$AB_AWAITING"
printf '{ "org": "demo", "defaultOwner": "someone-else" }\n' > "$F/instance.config.json"
printf '{ "ownerGithubUser": "me" }\n' > "$F/instance.config.local.json"
task "$F" task-001-a "Theirs" draft '"x"' ''
bash "$SH" --instance "$F" >/dev/null 2>&1
ok "the other human's task is not queued" "$(grep -c '✅ \*\*approve\*\*' "$F/$AB_AWAITING" | tr -d ' ')" 0

echo
echo "== a close row is narrowed by the project's owner, and fails closed =="
proj() { # <dir> <slug> <title> <owner-line>
  mkdir -p "$1/projects/$2/tasks"
  printf -- '---\ntype: Project\ntitle: "%s"\nstatus: active\n%s---\n' "$3" "$4" > "$1/projects/$2/project.md"
  printf -- '---\ntype: Task\ntitle: "t"\nstatus: done\n---\n' > "$1/projects/$2/tasks/task-001-a.md"
}
closes() { grep '🏁 \*\*close\*\*' "$1/$AB_AWAITING" | sed 's/.*— \[\([^]]*\)\].*/\1/' | sort | paste -sd, -; }
O="$TMP/close-owner"; inst "$O"; : > "$O/$AB_AWAITING"; rm -rf "$O/projects/demo"
proj "$O" mine-p "Mine" $'owner: me\n'
proj "$O" theirs-p "Theirs" $'owner: someone-else\n'
proj "$O" nobody-p "Nobody" ''
printf '{ "ownerGithubUser": "me" }\n' > "$O/instance.config.local.json"
bash "$SH" --instance "$O" >/dev/null 2>&1
ok "only this clone's and the unowned close rows" "$(closes "$O")" "Mine,Nobody"
rm "$O/instance.config.local.json"
bash "$SH" --instance "$O" >/dev/null 2>&1
ok "no ownerGithubUser ⇒ an owned project has none" "$(closes "$O")" "Nobody"
proj "$O" mine-p "Mine" $'owner: not a login!\n'
printf '{ "ownerGithubUser": "me" }\n' > "$O/instance.config.local.json"
bash "$SH" --instance "$O" >/dev/null 2>&1
ok "a malformed owner ⇒ no close row" "$(closes "$O")" "Nobody"

echo
echo "== a done task's do: deploy entry is one 👉 do row until it is answered =="
D="$TMP/deploy"; inst "$D"; : > "$D/$AB_AWAITING"
DQ='Q1: do: deploy demo/web — https://github.com/demo/web/pull/9 merged, not deployed; answer done once it is live'
task "$D" task-001-a "Shipped by hand" done '"x"' "\"$DQ\""
bash "$SH" --instance "$D" >/dev/null 2>&1
ok "unanswered: one do row on the done task" "$(grep -c '^\* 👉 \*\*do\*\* — \[Shipped by hand\](/projects/demo/tasks/task-001-a.md) · Q1: do: deploy demo/web' "$D/$AB_AWAITING" | tr -d ' ')" 1
ok "…and no second do row"                   "$(grep -c '^\* 👉' "$D/$AB_AWAITING" | tr -d ' ')" 1
ok "…and no close row while it is open"     "$(grep -c '^\* 🏁' "$D/$AB_AWAITING" | tr -d ' ')" 0
task "$D" task-001-a "Shipped by hand" done '"x"' "\"$DQ --- done\""
bash "$SH" --instance "$D" >/dev/null 2>&1
ok "answered: the row is gone"               "$(grep -c '^\* 👉' "$D/$AB_AWAITING" | tr -d ' ')" 0
ok "…and the close row is back"              "$(grep -c '^\* 🏁' "$D/$AB_AWAITING" | tr -d ' ')" 1
printf -- '---\ntype: Task\ntitle: "Shipped by hand"\nstatus: done\nopen_questions: [ ]\nanswered_questions: [ "%s --- done" ]\n---\n' "$DQ" \
  > "$D/projects/demo/tasks/task-001-a.md"
bash "$SH" --instance "$D" >/dev/null 2>&1
ok "…and stays gone once folded"             "$(grep -c '^\* 👉' "$D/$AB_AWAITING" | tr -d ' ')" 0

echo
echo "== the flow-list parser is NOT re-implemented here =="
# One parser, one place it can cut an entry in half. A second regex over these lists is
# the defect measured on 2026-09-12, so its absence is the assertion.
ok "it delegates to fold-answers.sh" "$(grep -c 'fold-answers.sh" --list' "$SH" | tr -d ' ')" 1
G="$TMP/hard"; inst "$G"; : > "$G/$AB_AWAITING"
task "$G" task-001-a "Hard" draft '"a `[x](y)` link, a comma, and a ] bracket"' '"Q1: is a ] fine, really?"'
bash "$SH" --instance "$G" >/dev/null 2>&1
ok "an entry with brackets and commas survives whole" \
   "$(grep -c '❓ \*\*answer\*\*.*Q1: is a \] fine, really? (no recommendation)$' "$G/$AB_AWAITING" | tr -d ' ')" 1

echo
echo "== every question's recommendation renders beside it, from its ### Q<n> block =="
R="$TMP/rec"; inst "$R"; : > "$R/$AB_AWAITING"
printf -- '---\ntype: Project\ntitle: "Demo"\nstatus: active\ndecisions: [ "D1: no cache — alternatives: redis; why: low load; reversible: yes" ]\n---\n' \
  > "$R/projects/demo/project.md"
block() { printf '\n### %s\nRecommendation: %s\nOptions:\n1. %s\n' "$1" "$2" "$2"; }
qs='"Q1: which colour?", "Q2: install the foo CLI", "Q3: which font?", "Q4: advisor: is the cache bounded?", "advisor: is it sound?"'
task "$R" task-001-a "Recs" draft '"x"' "$qs"
{ printf '\n## Question details\n'; block Q1 'Blue, the `brand` colour'; block Q2 'yes, with brew'; } >> "$R/projects/demo/tasks/task-001-a.md"
DQ='Q1: do: deploy demo/web — merged, not deployed'
task "$R" task-002-b "Deploy" done '"x"' "\"$DQ\""
{ printf '\n## Question details\n'; block Q1 done; } >> "$R/projects/demo/tasks/task-002-b.md"
task "$R" task-003-c "Clean" draft '"x"' ''
{ printf '\n## Question details\n'; block Q1 'an answered one'; } >> "$R/projects/demo/tasks/task-003-c.md"
bash "$SH" --instance "$R" >/dev/null 2>&1
L1='* ❓ **answer** — [Recs](/projects/demo/tasks/task-001-a.md) · Q1: which colour? (recommended: Blue, the \`brand\` colour); Q3: which font? (no recommendation); Q4: advisor: is the cache bounded?; advisor: is it sound?'
L2='* 🧰 **grant** — [Recs](/projects/demo/tasks/task-001-a.md) · Q2: install the foo CLI (recommended: yes, with brew)'
row_is() { grep -cxF -- "$1" "$R/$AB_AWAITING" | tr -d ' '; }
ok "answer: the whole row, each question with its own, escaped" "$(row_is "$L1")" 1
ok "grant: the whole row"        "$(row_is "$L2")" 1
ok "do: the whole row"           "$(row_is "* 👉 **do** — [Deploy](/projects/demo/tasks/task-002-b.md) · $DQ (recommended: done)")" 1
ok "review: the decision is the recommendation" \
   "$(row_is '* 👀 **review** — [Demo](/projects/demo/project.md) · D1: no cache — alternatives: redis; why: low load; reversible: yes (recommended: ok)')" 1
ok "approve: one row, display-only, nothing added" \
   "$(row_is '* ✅ **approve** — [Clean](/projects/demo/tasks/task-003-c.md) · unverified · no design yet · refined & clean, promote `draft → ready`')" 1
bash "$SH" --instance "$R" --trailer "$R/projects/demo/tasks/task-001-a.md=pick a colour and a font" >/dev/null 2>&1
ok "a trailer replaces the questions, once, never their recommendations" \
   "$(row_is '* ❓ **answer** — [Recs](/projects/demo/tasks/task-001-a.md) · pick a colour and a font (Q1 recommended: Blue, the \`brand\` colour; Q3 no recommendation)')" 1
ok "…and on a grant row"         "$(row_is '* 🧰 **grant** — [Recs](/projects/demo/tasks/task-001-a.md) · pick a colour and a font (Q2 recommended: yes, with brew)')" 1
ok "…and the trailer is never printed twice" "$(grep -c 'font.*pick a colour' "$R/$AB_AWAITING" | tr -d ' ')" 0
ok "one reader of the block: fold-answers.sh --block" "$(grep -c 'fold-answers.sh" --block' "$SH" | tr -d ' ')" 1
long="$(printf 'word%.0s ' $(seq 1 60))"
task "$R" task-001-a "Recs" draft '"x"' '"Q1: which colour?"'
{ printf '\n## Question details\n'; block Q1 "$long"; } >> "$R/projects/demo/tasks/task-001-a.md"
bash "$SH" --instance "$R" >/dev/null 2>&1
ok "a long recommendation is capped at a word" "$(grep -cE 'which colour\? \(recommended: (word ){30,32}…\)$' "$R/$AB_AWAITING" | tr -d ' ')" 1

# A LIST IT CANNOT PARSE IS NOT AN EMPTY LIST. Swallowing the parser's exit renders the
# draft as a clean `approve` row with its unresolved questions still on the page, which is
# the one row a human acts on without reading further.
H="$TMP/unparsable"; inst "$H"; : > "$H/$AB_AWAITING"
task "$H" task-001-a "Broken" draft '"x"' '"Q1: unterminated'
cp "$H/$AB_AWAITING" "$TMP/unparsable.before"
ok "an unreadable open_questions list is exit 3" \
   "$(bash "$SH" --instance "$H" >/dev/null 2>&1; echo $?)" 3
ok "…and never an approve row"  "$(grep -c 'approve' "$H/$AB_AWAITING" | tr -d ' ')" 0
ok "…leaving the page as it was" \
   "$(cmp -s "$H/$AB_AWAITING" "$TMP/unparsable.before" && echo yes || echo no)" yes

# =====================================================================================
# A MERGE ROW WITH A TRAILER KEEPS ITS PR LINK. The row used to be "trailer, else the
# link", so a tick that added "7/7 checks green" REPLACED the only thing the human needed
# to act — measured 2026-10-28 on a live bundle: a merge row naming a commit and no PR.
# The link is the row; the trailer is appended after it.
# =====================================================================================
echo "== a merge row carries its PR link AND its trailer =="
M="$TMP/mergetrail"; inst "$M"; : > "$M/$AB_AWAITING"
task "$M" task-004-d "Green" in-review '"x"' ''
bash "$SH" --instance "$M" \
  --merge "$M/projects/demo/tasks/task-004-d.md=[ai-bridge#7](https://github.com/cbmono/ai-bridge/pull/7)" \
  --trailer "$M/projects/demo/tasks/task-004-d.md=7/7 checks green at a069721" >/dev/null 2>&1
mrow="$(grep '^\* 🔀' "$M/$AB_AWAITING")"
saw() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
ok "the merge row still links the PR"   "$(saw "$mrow" '[ai-bridge#7](https://github.com/cbmono/ai-bridge/pull/7)')" yes
ok "…and carries the trailer after it"  "$(saw "$mrow" '/pull/7) · 7/7 checks green at a069721')" yes
ok "…as one row"                        "$(grep -c '^\* 🔀' "$M/$AB_AWAITING" | tr -d ' ')" 1

# =====================================================================================
# A QA DISAGREEMENT IS A Q<n> ENTRY ON DISK (qa-disagreement.sh), so the render needs no
# flag and no host: a `gh` that records every call must see none.
# =====================================================================================
echo
echo "== a QA disagreement renders from the task doc and clears when the head moves =="
QD="$REPO/plugin/scripts/qa-disagreement.sh"
D="$TMP/disagree"; inst "$D"; : > "$D/$AB_AWAITING"
task "$D" task-005-e "Disputed" in-review '"x"' ''
DT="$D/projects/demo/tasks/task-005-e.md"
H1=0123456789abcdef0123456789abcdef01234567; H2=89abcdef0123456789abcdef0123456789abcdef
U=https://github.com/octo/demo/pull/7
mkdir -p "$TMP/ghbin"; printf '#!/bin/sh\necho "$*" >> "%s/gh.calls"\nexit 1\n' "$TMP" > "$TMP/ghbin/gh"
chmod +x "$TMP/ghbin/gh"
opens() { bash "$REPO/plugin/scripts/fold-answers.sh" --list "$DT" open_questions | grep -c 'QA disagreement on' | tr -d ' '; }
ok "a checker table older than the head writes nothing (exit 1)" \
   "$(bash "$QD" open "$DT" --pr "$U" --head "$H1" --checker "$H2" --criteria 2 >/dev/null; echo "$?/$(opens)")" 1/0
ok "exit 1 at the head writes ONE Q<n> entry" \
   "$(bash "$QD" open "$DT" --pr "$U" --head "$H1" --checker "$H1" --criteria 2,3)" "written: Q1"
ok "…a second exit 1 at the same head writes nothing twice" \
   "$(bash "$QD" open "$DT" --pr "$U" --head "$H1" --checker "$H1" --criteria 2,3)/$(opens)" "exists: Q1/1"
PATH="$TMP/ghbin:$PATH" bash "$SH" --instance "$D" >/dev/null 2>&1
drow="$(grep '^\* ❓' "$D/$AB_AWAITING")"
ok "build-awaiting.sh renders it as one answer row" "$(grep -c '^\* ' "$D/$AB_AWAITING" | tr -d ' ')" 1
ok "…naming the PR and the disputed criteria" "$(saw "$drow" "QA disagreement on $U at ${H1:0:12}: criteria 2, 3")" yes
ok "…with the recommendation" "$(saw "$drow" '(recommended: send it back for a fix round)')" yes
ok "…and it called no gh" "$([ -e "$TMP/gh.calls" ] && echo yes || echo no)" no
ok "clear at the same head keeps it" "$(bash "$QD" clear "$DT" --pr "$U" --head "$H1")/$(opens)" "cleared: 0/1"
ok "clear once the head moved moves it" "$(bash "$QD" clear "$DT" --pr "$U" --head "$H2")/$(opens)" "cleared: 1/0"
ans="$(bash "$REPO/plugin/scripts/fold-answers.sh" --list "$DT" answered_questions)"
ok "…to answered_questions, cleared: head moved past <sha>" \
   "$(saw "$ans" "Q1: QA disagreement on $U at ${H1:0:12}: criteria 2, 3 — the PR body marks ✓, QA's table FAILs. What next? --- cleared: head moved past ${H1:0:12}")" yes
ok "…with no by" "$(saw "$ans" ' by ')" no
bash "$SH" --instance "$D" >/dev/null 2>&1
ok "…and the row is gone" "$(grep -c '^\* ' "$D/$AB_AWAITING" | tr -d ' ')" 0
ok "a cleared entry does not stop a new one at a new head" \
   "$(bash "$QD" open "$DT" --pr "$U" --head "$H2" --checker "$H2" --criteria 1)" "written: Q2"
bash "$REPO/plugin/scripts/fold-answers.sh" --answer "$(bash "$REPO/plugin/scripts/fold-answers.sh" --list "$DT" open_questions | grep 'QA disagreement on')" 3 "$DT" >/dev/null
ok "an answered entry at the same head writes nothing again" \
   "$(bash "$QD" open "$DT" --pr "$U" --head "$H2" --checker "$H2" --criteria 1)/$(opens)" "answered: Q2/0"
bash "$SH" --instance "$D" >/dev/null 2>&1
ok "…and renders no row" "$(grep -c '^\* ' "$D/$AB_AWAITING" | tr -d ' ')" 0
bash "$QD" open "$DT" --pr "$U" --head "$H1" --checker "$H1" --criteria 1 >/dev/null
sed -i.bak 's/^status: in-review$/status: done/' "$DT"
ok "a task that left in-review clears it too" "$(bash "$QD" clear "$DT")/$(opens)" "cleared: 1/0"
ok "…and open refuses there (exit 1)" \
   "$(bash "$QD" open "$DT" --pr "$U" --head "$H2" --checker "$H2" --criteria 1 >/dev/null; echo $?)" 1

echo
echo "== a recorded grant trails its task's row, display-only =="
G="$TMP/grant"; inst "$G"; : > "$G/$AB_AWAITING"
task "$G" task-001-a "Clean draft" draft '"x"' ''
GT="$G/projects/demo/tasks/task-001-a.md"
bash "$REPO/plugin/scripts/answer.sh" --instance "$G" --grant "$GT" wait for CI >/dev/null 2>&1
bash "$REPO/plugin/scripts/answer.sh" --instance "$G" --grant "$GT" 'then *promote*' >/dev/null 2>&1
bash "$SH" --instance "$G" >/dev/null 2>&1
grow="$(grep '^\* ' "$G/$AB_AWAITING")"
ok "the newest grant trails the row, escaped" "$([[ "$grow" == *' · grant: then \*promote\*' ]] && echo yes || echo "$grow")" yes
ok "…the older one is not shown" "$(grep -c 'wait for CI' "$G/$AB_AWAITING" | tr -d ' ')" 0
ok "…it is still the one approve row" "$(grep -c '^\* ✅ \*\*approve\*\*' "$G/$AB_AWAITING" | tr -d ' ')/$(grep -c '^\* ' "$G/$AB_AWAITING" | tr -d ' ')" 1/1
ok "…and the draft stays draft" "$(sed -n 's/^status: //p' "$GT")" draft
sed -i.bak 's/: grant — /: granted — /' "$GT"
bash "$SH" --instance "$G" >/dev/null 2>&1
ok "mutant: no grant line -> no grant text" "$(grep -c ' · grant: ' "$G/$AB_AWAITING" | tr -d ' ')" 0

# =====================================================================================
# THE --merge VALUE IS A SCRIPT'S, NOT THE TICK'S: review-next.sh --merge-row prints it only
# on merge-path, and merge-path needs a live read showing 0 unresolved non-author threads.
# =====================================================================================
echo
echo "== the merge row comes from review-next.sh --merge-row, and open threads leave none =="
MR="$TMP/mergerow"; inst "$MR"; : > "$MR/$AB_AWAITING"
printf '{ "org": "demo", "coderabbitRounds": 0, "qaRounds": 0 }\n' > "$MR/instance.config.json"
task "$MR" task-004-d "Green" in-review '"x"' ''
MRT="$MR/projects/demo/tasks/task-004-d.md"; RF="$TMP/rnfix"; mkdir -p "$RF" "$TMP/rnbin"
RH=8f40f2ed565a31e141f5ae54a6935ad0810314c4
jq -n --arg h "$RH" '{url:"https://github.com/octo/demo/pull/7", number:7, headRefOid:$h, headRefName:"b",
  baseRefName:"main", headRepository:{name:"demo"}, headRepositoryOwner:{login:"octo"}, isCrossRepository:false,
  author:{login:"dev"}, mergeable:"MERGEABLE", mergeStateStatus:"CLEAN", commits:[]}' > "$RF/pr"
printf '[]\n' > "$RF/empty"; printf '[{"sha":"%s"}]\n' "$RH" > "$RF/commits"
printf '[{"name":"CI","bucket":"pass"}]\n' > "$RF/checks"
printf '{"delete_branch_on_merge":true}\n' > "$RF/repo"; printf '[]\n' > "$RF/deps"
{ printf '#!/usr/bin/env bash\nRF=%q\n' "$RF"; cat <<'STUB'
f=""; p=""; for a in "$@"; do [ "$p" = --jq ] && f="$a"; p="$a"; done
out() { if [ -n "$f" ]; then jq -r "$f" "$1"; else cat "$1"; fi; }
printf '%s\n' "$*" >> "$RF/calls"
case " $* " in
  " pr view "*) out "$RF/pr" ;;
  " api repos/"*"/demo --jq "*) [ -f "$RF/repofail" ] && exit 1; out "$RF/repo" ;;
  *"/pulls?state=open&"*) [ -f "$RF/depsfail" ] && exit 1; out "$RF/deps" ;;
  " pr checks "*) out "$RF/checks" ;;
  *" graphql "*) [ -f "$RF/fail" ] && exit 1; cat "$RF/threads" ;;
  *"/actions/workflows "*) ;;
  *"/branches/"*) echo '{}' ;;
  *"/pulls/7/commits"*) out "$RF/commits" ;;
  *"/pulls/7/reviews"*|*"/issues/7/comments"*) out "$RF/empty" ;;
  *) echo "stub: unhandled gh $*" >&2; exit 99 ;;
esac
STUB
} > "$TMP/rnbin/gh"; chmod +x "$TMP/rnbin/gh"
rthreads() { # <login>... — one unresolved thread per login, read at the head
  jq -n --arg h "$RH" '{data:{repository:{pullRequest:{headRefOid:$h, reviewThreads:{pageInfo:{hasNextPage:false},
    nodes:[$ARGS.positional[] | {isResolved:false, path:"a.sh", line:1,
           comments:{nodes:[{author:{login:.}, url:"https://example.invalid/t", body:"look"}]}}]}}}}}' \
    --args "$@" > "$RF/threads"
}
render_from_rn() { # -> "<review-next exit> <merge rows>"; each printed line is one build-awaiting.sh argument
  local v rc a=() l
  v="$(PATH="$TMP/rnbin:$PATH" CLAUDE_PROJECT_DIR="$MR" bash "$REPO/plugin/scripts/review-next.sh" 7 \
       --repo octo/demo --instance "$MR" --merge-row "$MRT" 2>/dev/null)"; rc=$?
  while IFS= read -r l; do [ -n "$l" ] && a+=("$l"); done <<<"$v"
  bash "$SH" --instance "$MR" ${a[@]+"${a[@]}"} >/dev/null 2>&1
  echo "$rc $(grep -c '^\* 🔀' "$MR/$AB_AWAITING" | tr -d ' ')"
}
rthreads
ok "guard: green, 0 unresolved threads -> exit 0 and one merge row" "$(render_from_rn)" "0 1"
ok "…linking the PR" "$(grep -c '^\* 🔀 .*\[demo#7\](https://github.com/octo/demo/pull/7)' "$MR/$AB_AWAITING" | tr -d ' ')" 1
"$(dirname "$0")/../plugin/scripts/review-clearance.sh" --match-reviewer example-user-007 >/dev/null 2>&1
ok "the other account is in no REVIEWERS row (a second reviewer)" "$?" 1
rthreads example-user-007 example-user-007
ok "green, 0 CodeRabbit threads, 2 open from another account -> no merge row" "$(render_from_rn)" "1 0"
rthreads dev
ok "the PR author's own open thread -> merge row" "$(render_from_rn)" "0 1"
rthreads; printf '[{"name":"CI","bucket":"fail"}]\n' > "$RF/checks"
ok "0 threads but a required check red -> no merge row" "$(render_from_rn)" "1 0"
printf '[{"name":"CI","bucket":"pass"}]\n' > "$RF/checks"
: > "$RF/fail"
ok "the thread read fails -> unknown (exit 2), no merge row" "$(render_from_rn)" "2 0"
rm -f "$RF/fail"

echo
echo "== a criteria ✗ prints its count on the merge row, and an unreadable tally prints unknown =="
rbody() { # <heading tally> <second mark> — the PR body pr-body-clearance.sh --tally reads
  jq --arg b "$(printf '### Criteria (%s)\n\n| C | ✓ | By |\n|---|---|---|\n| a | ✓ | `a.test.sh` 3/0 |\n| b | %s | `b.test.sh` 3/0 |\n' "$1" "$2")" \
    '.body = $b' "$RF/pr" > "$RF/pr.v" && mv "$RF/pr.v" "$RF/pr"
}
notes() { grep '^  > ' "$MR/$AB_AWAITING"; }
rbody '2 ✓ / 0 ✗' ✓
ok "guard: an all-✓ tally -> the merge row exactly as before, no note" "$(render_from_rn)/$(notes | grep -c .)" "0 1/0"
rbody '1 ✓ / 1 ✗ — b is a later slice' ✗
ok "1 ✗ with a reason (gated) -> still the merge row, one count line under it" "$(render_from_rn)/$(notes)" "0 1/  > 1 ✗ criteria: b is a later slice"
rbody '1 ✓ / 1 ✗' ✗
ok "an unexplained ✗ -> the count, and no reason" "$(render_from_rn)/$(notes)" "0 1/  > 1 ✗ criteria: no reason on the heading"
rbody '2 ✓ / 0 ✗' ✗
ok "a tally the table contradicts -> criteria: unknown" "$(render_from_rn)/$(notes)" "0 1/  > criteria: unknown (the heading claims 0 ✗, the table carries 1 ✗)"
rbody 'pending' ✗
ok "a heading with no tally -> criteria: unknown" "$(render_from_rn)/$(notes)" "0 1/  > criteria: unknown (no N ✓ / M ✗ tally on the criteria heading)"
rbody "1 ✓ / 1 ✗ — ##mq1 main x $(printf 'y%.0s' $(seq 1 80))" ✗
ok "author text cannot read as a token, and is capped" "$(render_from_rn)/$(notes | grep -c '^  > 1 ✗ criteria: mq1 main x y*\.\.\.$')/$(notes | grep -c warning)/$(notes | awk '{ print (length($0) <= 90) }')" "0 1/1/0/1"
jq 'del(.body)' "$RF/pr" > "$RF/pr.v" && mv "$RF/pr.v" "$RF/pr"
ok "the body unreadable -> criteria: unknown, never nothing" "$(render_from_rn)/$(notes)" "0 1/  > criteria: unknown (the PR body is unreadable)"
rbody '2 ✓ / 0 ✗' ✓

echo
echo "== an open PR based on the head branch, where merging auto-deletes it, prints on the merge row =="
deps() { # <base ref> <base repo> <number>... — the open PRs the REST list answers
  local r="$1" b="$2"; shift 2
  jq -n --arg r "$r" --arg b "$b" '[$ARGS.positional[] | {number: (. | tonumber),
    html_url: ("https://github.com/" + $b + "/pull/" + .), base: {ref: $r, repo: {full_name: $b}}}]' --args "$@" > "$RF/deps"
}
setref() { jq --arg r "$1" --argjson c "${2:-false}" '.headRefName = $r | .isCrossRepository = $c' "$RF/pr" > "$RF/pr.v" && mv "$RF/pr.v" "$RF/pr"; }
dbm() { printf '{"delete_branch_on_merge":%s}\n' "$1" > "$RF/repo"; }
DN='  > dependent PR [demo#12](https://github.com/octo/demo/pull/12) will be retargeted on merge'
rm -f "$RF/calls"
ok "guard: auto-delete on, no PR based on the head -> the merge row exactly as before" "$(render_from_rn)/$(notes | grep -c .)" "0 1/0"
ok "…reading the setting and the list once each" \
   "$(grep -c 'delete_branch_on_merge' "$RF/calls")/$(grep -c 'pulls?state=open&base=b&' "$RF/calls")" 1/1
deps b octo/demo 12; dbm false
ok "guard: auto-delete off, a PR based on the head -> the merge row exactly as before" "$(render_from_rn)/$(notes | grep -c .)" "0 1/0"
dbm true
ok "auto-delete on, one PR based on the head -> the merge row, naming it" "$(render_from_rn)/$(notes)" "0 1/$DN"
deps b octo/demo 12 13
ok "several -> one line each, in order" "$(render_from_rn)/$(notes | sed -n 2p)" "0 1/  > dependent PR [demo#13](https://github.com/octo/demo/pull/13) will be retargeted on merge"
deps b octo/fork 12
ok "a same-named base in another repository is not this head" "$(render_from_rn)/$(notes | grep -c .)" "0 1/0"
deps b Octo/Demo 12
ok "the repository's name in another case is the same repository" "$(PATH="$TMP/rnbin:$PATH" bash "$REPO/plugin/scripts/dependent-prs.sh" check 7 --repo OCTO/demo --head "$RH"; echo "rc=$?")" \
   "dependent PR [demo#12](https://github.com/Octo/Demo/pull/12) will be retargeted on merge
rc=1"
deps B octo/demo 12
ok "…but a branch in another case is another branch" "$(render_from_rn)/$(notes | grep -c .)" "0 1/0"
deps b octo/demo 7
ok "the PR itself is never its own dependent" "$(render_from_rn)/$(notes | grep -c .)" "0 1/0"
deps b octo/demo 12; setref b true
ok "a fork's head branch: no PR here is based on it -> nothing" "$(render_from_rn)/$(notes | grep -c .)" "0 1/0"
deps -x octo/demo 12; setref -x; rm -f "$RF/calls"
ok "a head branch named like an option is a query value, never a flag" \
   "$(render_from_rn)/$(notes)/$(grep -c 'pulls?state=open&base=-x&per_page=100' "$RF/calls")" "0 1/$DN/1"
deps feat/a octo/demo 12; setref feat/a; rm -f "$RF/calls"
ok "…and a slash in it is encoded" "$(render_from_rn)/$(grep -c 'base=feat%2Fa&' "$RF/calls")" "0 1/1"
setref b; deps b octo/demo 12
: > "$RF/repofail"
ok "the setting unreadable -> dependent PRs: unknown on the row, never silence" \
   "$(render_from_rn)/$(notes)" "0 1/  > dependent PRs: unknown (delete_branch_on_merge is unreadable)"
ok "…and nothing counts toward merge-queue.sh's bound" "$(ls -A "$MR/$AB_MERGE_HOLDS" 2>/dev/null | grep -c .)" 0
rm -f "$RF/repofail"; printf '{}\n' > "$RF/repo"
ok "the setting absent from the answer -> unknown, never false" \
   "$(render_from_rn)/$(notes)" "0 1/  > dependent PRs: unknown (delete_branch_on_merge is unreadable)"
dbm true; : > "$RF/depsfail"
ok "the list unreadable -> dependent PRs: unknown on the row" \
   "$(render_from_rn)/$(notes)" "0 1/  > dependent PRs: unknown (the open PRs based on its head branch are unreadable)"
ok "…and nothing counts toward merge-queue.sh's bound" "$(ls -A "$MR/$AB_MERGE_HOLDS" 2>/dev/null | grep -c .)" 0
rm -f "$RF/depsfail"
mkdir -p "$TMP/nogh"; printf '#!/usr/bin/env bash\n: > %q\nexit 1\n' "$TMP/nogh/called" > "$TMP/nogh/gh"; chmod +x "$TMP/nogh/gh"
PATH="$TMP/nogh:$PATH" bash "$SH" --instance "$MR" --merge "$MRT=[demo#7](https://github.com/octo/demo/pull/7)" \
  --note "$MRT=${DN#  > }" --note "$MRT=dependent PRs: unknown (x)" >/dev/null 2>&1
ok "build-awaiting.sh renders the dependent lines and calls no gh" \
   "$(notes | grep -c dependent)/$([ -e "$TMP/nogh/called" ] && echo called || echo none)" "2/none"
printf '[]\n' > "$RF/deps"
# =====================================================================================
# A LIVE ROLE SESSION OR A HAND-OFF OPEN AT THE HEAD HOLDS THE ROW, AND SAYS SO. The session
# is read from the listing step 4 saves (agent-sessions.sh save), never from the CLI here.
# =====================================================================================
echo
echo "== a live session or an open hand-off at the head holds the merge row, never silently =="
SID=11111111-2222-3333-4444-555555555555; LST="$MR/$AB_SESSIONS_SAVED"; mkdir -p "$(dirname "$LST")"
sleep 0 & DEADPID=$!; wait "$DEADPID"
listing() { # <state> [<pid>] — the listing and the round marks, as agent-sessions.sh save writes them
  printf '[{"sessionId":"%s","state":"%s","pid":%s}]\n' "$SID" "$1" "${2:-$$}" > "$LST"
  bash "$REPO/plugin/scripts/merge-hold.sh" marks "$MR" > "$(dirname "$LST")/marks"; }
with_session() { sed -i.bak "s/^status: in-review$/status: in-review\nsession: $SID/" "$MRT"; }
held_row() { grep '^\* ⏸ \*\*held\*\*' "$MR/$AB_AWAITING"; }
says_held() { # <why> -> "<held rows>/<why shown>"
  echo "$(held_row | grep -c . | tr -d ' ')/$(held_row | grep -cF "[demo#7](https://github.com/octo/demo/pull/7) merge held: $1" | tr -d ' ')"; }
task "$MR" task-004-d "Green" in-review '"x"' ''; with_session
for st in working blocked; do
  listing "$st"
  ok "session $st -> no merge row (exit 1)" "$(render_from_rn)" "1 0"
  ok "…the held row says role session live" "$(says_held 'role session live')" 1/1
done
for st in done gone stopped; do
  listing "$st"
  ok "guard: session $st -> merge row" "$(render_from_rn)" "0 1"
  ok "…and no held row" "$(held_row | grep -c . | tr -d ' ')" 0
done
listing working "$DEADPID"
ok "session working with no live pid (dead) -> no merge row (exit 2)" "$(render_from_rn)" "2 0"
ok "…held as session unknown" "$(says_held 'session unknown')" 1/1
listing paused
ok "an unrecognised state -> session unknown" "$(render_from_rn)/$(says_held 'session unknown')" "2 0/1/1"
printf 'not json\n' > "$LST"
ok "the listing unreadable (states exit 2) -> session unknown" "$(render_from_rn)/$(says_held 'session unknown')" "2 0/1/1"
rm -f "$LST"
ok "no saved listing -> session unknown" "$(render_from_rn)/$(says_held 'session unknown')" "2 0/1/1"
listing done; touch -t 202001010000 "$LST"
ok "a stale listing (past one tick gap) -> session unknown" "$(render_from_rn)/$(says_held 'session unknown')" "2 0/1/1"
listing done; printf '\n* woke %s\n' "$SID" >> "$MRT"
ok "a resume after the listing was saved -> session unknown" "$(render_from_rn)/$(says_held 'session unknown')" "2 0/1/1"
listing done
ok "…until the next save reads it" "$(render_from_rn)" "0 1"
listing done
task "$MR" task-004-d "Green" in-review '"x"' ''
ok "guard: no recorded session, no hand-off -> merge row" "$(render_from_rn)" "0 1"
rm -f "$LST"
ok "…even with no saved listing" "$(render_from_rn)" "0 1"
printf '\n# Notes\n\n* spawned; session id unresolved: abc12345\n' >> "$MRT"
ok "an empty session after an unresolved spawn -> session unknown" "$(render_from_rn)/$(says_held 'session unknown')" "2 0/1/1"
OH=0123456789abcdef0123456789abcdef01234567
handoff() { # <entry> <heads field> — one hand-off entry and its note
  task "$MR" task-004-d "Green" in-review '"x"' "\"$1\""
  printf '\n# Notes\n\n* 2026-11-20T10:00:00Z needs handed off %s · hand-off 11111111-aaaabbbb · Q1 · session stopped by the tick%s\n' \
    "$SID" "${2:+ · heads $2}" >> "$MRT"
}
HQ="Q1: do: finish the agent's hand-off 11111111-aaaabbbb — its jobs are in AWAITING.md; answer done, or with what its next round should know"
handoff "$HQ" "$RH"
ok "a hand-off opened at the current head -> no merge row (exit 1)" "$(render_from_rn)" "1 0"
ok "…the held row says hand-off open" "$(says_held 'hand-off open')" 1/1
ok "…beside the hand-off's own do row" "$(grep -c '^\* 👉 \*\*do\*\*' "$MR/$AB_AWAITING" | tr -d ' ')" 1
handoff "$HQ" unknown
ok "a hand-off whose head was unread -> held" "$(render_from_rn)/$(says_held 'hand-off open')" "1 0/1/1"
handoff "$HQ" "$OH"
ok "a hand-off from an earlier head -> merge row" "$(render_from_rn)" "0 1"
handoff "$HQ" merged
ok "a post-merge hand-off -> merge row" "$(render_from_rn)" "0 1"
handoff "$HQ" "merged $OH"
ok "…merged beside an earlier head -> merge row" "$(render_from_rn)" "0 1"
handoff "$HQ" "merged $RH"
ok "a sibling PR merged, this PR open at its head -> held" "$(render_from_rn)/$(says_held 'hand-off open')" "1 0/1/1"
handoff "$HQ"
ok "a hand-off with no heads field (before this change) -> merge row" "$(render_from_rn)" "0 1"
handoff "$HQ --- done" "$RH"
ok "an answered hand-off at the head -> merge row" "$(render_from_rn)" "0 1"
handoff "Q1: do: deploy the release once merged" "$RH"
ok "a do: deploy entry -> merge row" "$(render_from_rn)" "0 1"
task "$MR" task-004-d "Green" in-review '"x"' ''
S4="$REPO/plugin/tick-steps/step-4-advance.md"; S8="$REPO/plugin/tick-steps/step-8-render.md"
first() { grep -nF -- "$2" "$1" | cut -d: -f1 | sed -n 1p; }
ok "step 4 saves the listing after its stop and resume sweep" \
   "$([ "$(first "$S4" 'agent-sessions.sh save')" -gt "$(first "$S4" 'session-handoff.sh --owed <task-path>')" ] \
      && [ "$(first "$S4" 'agent-sessions.sh save')" -gt "$(first "$S4" 'agent-sessions.sh recorded <the task')" ] && echo after || echo before)" after
ok "step 8 passes every printed --merge-row line, in order, as one argument" \
   "$(tr -s '[:space:]' ' ' < "$S8" | grep -cF -- '--merge-row <task-path>` printed this tick, unchanged and in order, one argument per line')" 1

echo
echo "== --note is repeatable per row, and carries merge-queue.sh's tokens =="
N="$TMP/notes"; inst "$N"; : > "$N/$AB_AWAITING"
task "$N" task-004-d "Green" in-review '"x"' ''; NT="$N/projects/demo/tasks/task-004-d.md"
NL='[demo#7](https://github.com/octo/demo/pull/7)'
bash "$SH" --instance "$N" --merge "$NT=$NL" --note "$NT=##mq1 main tests-Tests-refs/heads/main" \
  --note "$NT=##mq2 gh could not list the workflows" --note "$NT=a third line" >/dev/null 2>&1
ok "##mq1 still renders its warning under the merge row" \
   "$(grep -cxF '  > warning: a tests-Tests-refs/heads/main run is in progress on main; merging now cancels it' "$N/$AB_AWAITING" | tr -d ' ')" 1
ok "…##mq2 too" "$(grep -cxF '  > warning: concurrency unknown: gh could not list the workflows' "$N/$AB_AWAITING" | tr -d ' ')" 1
ok "…and any other note as itself, in the order given" "$(grep '^  > ' "$N/$AB_AWAITING" | tail -n 1)" "  > a third line"
ok "…under the one merge row, which keeps its link" "$(grep -c '^\* ' "$N/$AB_AWAITING" | tr -d ' ')/$(grep -cF "· $NL" "$N/$AB_AWAITING" | tr -d ' ')" 1/1
bash "$SH" --instance "$N" --merge "$NT=$NL ##mq2 x" >/dev/null 2>&1
ok "a token on the --merge value is no longer parsed" "$(grep -c '^  > ' "$N/$AB_AWAITING" | tr -d ' ')" 0
ok "--held with an unknown reason is a usage error" \
   "$(bash "$SH" --instance "$N" --held "$NT=busy $NL" >/dev/null 2>&1; echo $?)" 2

ok "step 8 passes the value through: the tick judges no eligibility" \
   "$(grep -c 'merge-eligibility is this tick.s judgement' "$REPO/plugin/tick-steps/step-8-render.md" | tr -d ' ')/$(grep -c 'review-next.sh <pr> --repo <org>/<repo> --head <sha> --merge-row <task-path>' "$REPO/plugin/tick-steps/step-8-render.md" | tr -d ' ')" 0/1

echo
echo "== closeAfterDays holds the close row; the day comes from git, in UTC =="
g() { git -C "$1" -c user.name=t -c user.email=t@example.com -c core.excludesFile=/dev/null "${@:2}"; }
at() { # <dir> <committer date> <status> [<extra body line>] — commit task-001-a at that status
  printf -- '---\ntype: Task\ntitle: "Shipped"\nstatus: %s\n---\n%s\n' "$3" "${4:-}" > "$1/projects/demo/tasks/task-001-a.md"
  g "$1" add -A >/dev/null && GIT_COMMITTER_DATE="$2" g "$1" commit -qm "$3" >/dev/null
}
closed_on() { # <dir> <pinned today> -> 1 with a close row, 0 without
  CHECKPOINT_TODAY="$2" bash "$SH" --instance "$1" >/dev/null 2>&1
  grep -c '^\* 🏁' "$1/$AB_AWAITING" | tr -d ' '
}
H="$TMP/held"; inst "$H"; g "$H" init -q
at "$H" '2026-11-01T12:00:00Z' in-review
# 01:00 at +05:00 is 20:00 UTC the day before: the day is 2026-11-09, never the local 11-10.
at "$H" '2026-11-10T01:00:00+05:00' done
: > "$H/$AB_AWAITING"
ok "inside the delay (3 of 5 days): no close row"  "$(closed_on "$H" 2026-11-12)" 0
ok "on the day it ends (5 of 5, UTC): the row"      "$(closed_on "$H" 2026-11-14)" 1
printf '{ "org": "demo", "closeAfterDays": 0 }\n' > "$H/instance.config.json"
ok "closeAfterDays: 0 ⇒ the row at once"            "$(closed_on "$H" 2026-11-09)" 1
printf '{ "org": "demo", "closeAfterDays": null }\n' > "$H/instance.config.json"
ok "…null counts as absent, so 5"                   "$(closed_on "$H" 2026-11-12)" 0
printf '{ "org": "demo" }\n' > "$H/instance.config.json"
at "$H" '2026-11-20T12:00:00Z' done 'a later note'
ok "a later non-status edit keeps the day"          "$(closed_on "$H" 2026-11-14)" 1
at "$H" '2026-11-21T12:00:00Z' in-progress
at "$H" '2026-11-22T12:00:00Z' done
ok "reverted then re-set: day of the re-set"        "$(closed_on "$H" 2026-11-26)" 0
ok "…and the row 5 days after it"                   "$(closed_on "$H" 2026-11-27)" 1
mkdir -p "$TMP/broken"; cp -R "$REPO/plugin/scripts/." "$TMP/broken/"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/broken/close-delay.sh"
CHECKPOINT_TODAY=2026-11-23 bash "$TMP/broken/build-awaiting.sh" --instance "$H" >/dev/null 2>&1
ok "a failing helper shows the row"                 "$(grep -c '^\* 🏁' "$H/$AB_AWAITING" | tr -d ' ')" 1
printf -- '---\ntype: Task\ntitle: "Later"\nstatus: done\n---\n' > "$H/projects/demo/tasks/task-002-b.md"
ok "an untracked terminal task: day is today"       "$(closed_on "$H" 2026-12-31)" 0
g "$H" add -A >/dev/null; GIT_COMMITTER_DATE='2026-11-23T12:00:00Z' g "$H" commit -qm b >/dev/null
printf -- '---\ntype: Task\ntitle: "Later"\nstatus: draft\n---\n' > "$H/projects/demo/tasks/task-002-b.md"
GIT_COMMITTER_DATE='2026-11-23T12:00:00Z' g "$H" commit -qam c >/dev/null
printf -- '---\ntype: Task\ntitle: "Later"\nstatus: done\n---\n' > "$H/projects/demo/tasks/task-002-b.md"
ok "an uncommitted terminal status: today"          "$(closed_on "$H" 2026-12-31)" 0
Z="$TMP/zero"; inst "$Z"; g "$Z" init -q; task "$Z" task-001-a "Shipped" done '"x"' ''; : > "$Z/$AB_AWAITING"
ok "zero commits ⇒ the row at once"                 "$(closed_on "$Z" 2026-11-01)" 1
at "$Z" '2026-11-01T12:00:00Z' in-review; at "$Z" '2026-11-02T12:00:00Z' done
git clone -q --depth 1 "file://$Z" "$TMP/shallow" 2>/dev/null; : > "$TMP/shallow/$AB_AWAITING"
ok "a shallow clone ⇒ the row at once"              "$(closed_on "$TMP/shallow" 2026-11-01)" 1
ok "…while Z itself, inside the delay, holds it"    "$(closed_on "$Z" 2026-11-03)" 0
blob="$(g "$Z" rev-parse HEAD:projects/demo/tasks/task-001-a.md)"; rm -f "$Z/.git/objects/${blob:0:2}/${blob:2}"
ok "an unreadable blob at HEAD fails open: the row" "$(closed_on "$Z" 2026-11-03)" 1

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
