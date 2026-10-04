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
by each dispatch tick that changed something. Delete this file to turn the queue off for good.
Last refreshed: <ISO>.

## 🔴 Awaiting you (5)
* 🧰 **grant** — [Has questions](/projects/demo/tasks/task-002-b.md) · Q2: install the foo CLI
* ⛔ **unblock** — [Stuck](/projects/demo/tasks/task-003-c.md) · waiting on a host account
* ❓ **answer** — [Has questions](/projects/demo/tasks/task-002-b.md) · Q1: which colour?
* ✅ **approve** — [Clean draft](/projects/demo/tasks/task-001-a.md) · refined & clean, promote `draft → ready`
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
echo "== the flow-list parser is NOT re-implemented here =="
# One parser, one place it can cut an entry in half. A second regex over these lists is
# the defect measured on 2026-09-12, so its absence is the assertion.
ok "it delegates to fold-answers.sh" "$(grep -c 'fold-answers.sh" --list' "$SH" | tr -d ' ')" 1
G="$TMP/hard"; inst "$G"; : > "$G/$AB_AWAITING"
task "$G" task-001-a "Hard" draft '"a `[x](y)` link, a comma, and a ] bracket"' '"Q1: is a ] fine, really?"'
bash "$SH" --instance "$G" >/dev/null 2>&1
ok "an entry with brackets and commas survives whole" \
   "$(grep -c '❓ \*\*answer\*\*.*Q1: is a \] fine, really?$' "$G/$AB_AWAITING" | tr -d ' ')" 1

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

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
