#!/usr/bin/env bash
#
# refused-dispatch.test.sh — a spawn the host refused is reported as a refusal, never as a
# full cap. Pins step 3's two literal templates (the `open_questions` entry and the report
# line), feeds every entry variant through the UNMODIFIED build-awaiting.sh, and reads the
# queue back off status-line.sh. Offline; fixtures under mktemp.
#
# Reasoning: dispatch-reporting-defects/task-003.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S3="$REPO/plugin/tick-steps/step-3-dispatch.md"
SKILL="$REPO/plugin/skills/dispatch/SKILL.md"
AW="$REPO/plugin/scripts/build-awaiting.sh"
SL="$REPO/plugin/scripts/status-line.sh"
for f in "$S3" "$SKILL" "$AW" "$SL"; do
  [ -f "$f" ] || { echo "refused-dispatch.test: $f not found" >&2; exit 2; }
done
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/refused-dispatch.XXXXXX")" || {
  echo "refused-dispatch.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }
yn() { "$@" && echo yes || echo no; }

entry_tpl="$(head -n1 <<<"$(sed -n 's/^[[:space:]]*\(Q<n>: dispatch refused: .*\)$/\1/p' "$S3")")"
line_tpl="$(head -n1 <<<"$(sed -n 's/^[[:space:]]*\(dispatch refused: <which>\. <task> .*\)$/\1/p' "$S3")")"
# The three `| <carries> | <which> | <remedy> |` rows under the table's header.
table_of() { awk '/\| The text carries \|/ { t = 1; next } t && /^[[:space:]]*\|---/ { next } t && /^[[:space:]]*\|/ { print; next } t { exit }' "$1"; }
table="$(table_of "$S3")"

echo "== the step carries the two templates and the three refusal kinds =="
ok "the open_questions entry template"  "$([ -n "$entry_tpl" ] && echo yes || echo no)" yes
ok "the one-line report template"       "$([ -n "$line_tpl" ] && echo yes || echo no)" yes
ok "three refusal kinds in the table"   "$(printf '%s\n' "$table" | grep -c '|' | tr -d ' ')" 3
ok "the classifier is named by its reason" "$(yn grep -qF 'Reason: [Create Unsafe Agents]' <<<"$table")" yes
ok "workspace trust is named by its text"  "$(yn grep -qF 'Workspace not trusted' <<<"$table")" yes
ok "neither ⇒ the refusal quoted verbatim" "$(yn grep -qF 'verbatim: <the refusal text, sanitised>' <<<"$table")" yes

cell() { # <row> <n> — the nth cell, backticks stripped
  printf '%s' "$1" | awk -F' [|] ' -v n="$2" '{ gsub(/^[[:space:]]*[|] | [|][[:space:]]*$/, ""); print $n }' \
    | sed 's/^`//; s/`$//'
}
fill() { # <template> <which> <remedy>
  local s="$1"
  s="${s//<n>/2}"; s="${s//<which>/$2}"; s="${s//<remedy>/$3}"
  s="${s//<the refusal text, sanitised>/Bash command blocked by [Some Future Rule]}"
  s="${s//<task>/task-001-a}"; s="${s//<k>/3}"
  printf '%s' "$s"
}
plain_yaml() { case "$1" in *'"'* | *\\*) return 1 ;; esac; }
inst() { # <dir> <open_questions list body>
  mkdir -p "$1/projects/demo/tasks" "$1/$AB_DIR"
  printf '{ "org": "demo" }\n' > "$1/instance.config.json"
  printf '# SCHEMA\n' > "$1/$AB_SCHEMA"
  printf -- '---\ntype: Project\ntitle: "Demo"\nstatus: active\n---\n' > "$1/projects/demo/project.md"
  printf -- '---\ntype: Task\ntitle: "Refused"\nkind: build\nstatus: ready\nacceptance_criteria: [ "x" ]\nopen_questions: [ %s ]\n---\n' \
    "$2" > "$1/projects/demo/tasks/task-001-a.md"
  : > "$1/$AB_AWAITING"
}

echo
echo "== every variant renders ONE grant row through the unmodified renderer, never a cap =="
i=0
while IFS= read -r r; do
  [ -n "$r" ] || continue
  i=$((i + 1)); which="$(cell "$r" 2)"; remedy="$(cell "$r" 3)"
  entry="$(fill "$entry_tpl" "$which" "$remedy")"; line="$(fill "$line_tpl" "$which" "$remedy")"
  ok "kind $i: the entry needs no YAML escaping" "$(yn plain_yaml "$entry")" yes
  D="$TMP/k$i"; inst "$D" "\"Q1: which colour? --- blue\", \"$entry\""
  bash "$AW" --instance "$D" >/dev/null 2>&1
  ok "kind $i: exactly one 🧰 grant row"  "$(grep -c '^\* 🧰 \*\*grant\*\* — \[Refused\]' "$D/$AB_AWAITING" | tr -d ' ')" 1
  ok "kind $i: …and no ❓ answer row"     "$(grep -c '^\* ❓' "$D/$AB_AWAITING" | tr -d ' ')" 0
  ok "kind $i: the report line says which" "$(yn grep -qF -- "$(fill "$which" "" "")" <<<"$line")" yes
  ok "kind $i: the report line never says cap"  "$(yn grep -qiwE 'cap' <<<"$line")" no
  ok "kind $i: …nor in-flight"                  "$(yn grep -qiE 'in[- ]flight' <<<"$line")" no
done <<EOF
$table
EOF

echo
echo "== a verbatim refusal is sanitised before it enters the flow list =="
sanitise() { # the step's rule: ONE line, `"` -> `'`, backslashes dropped, ` --- ` -> ` - `
  local s="$1" sq="'"; s="${s//\"/$sq}"; s="${s//\\/}"; s="${s// --- / - }"; printf '%s' "$s"
}
raw='Bash blocked: policy said "no" \ retry --- x'
which4="unrecognised, verbatim: $(sanitise "$raw")"
entry4="${entry_tpl//<n>/2}"; entry4="${entry4//<which>/$which4}"
entry4="${entry4//<remedy>/unknown, read the refusal text}"
ok "kind 4: the sanitised entry needs no YAML escaping" "$(yn plain_yaml "$entry4")" yes
D="$TMP/k4"; inst "$D" "\"Q1: which colour? --- blue\", \"$entry4\""
bash "$AW" --instance "$D" >/dev/null 2>&1
ok "kind 4: exactly one 🧰 grant row" "$(grep -c '^\* 🧰 \*\*grant\*\* — \[Refused\]' "$D/$AB_AWAITING" | tr -d ' ')" 1
T4="$D/projects/demo/tasks/task-001-a.md"
bash "$REPO/plugin/scripts/fold-answers.sh" --instance "$D" "$T4" >/dev/null 2>&1
ok "kind 4: a fold leaves the blocker OPEN" \
   "$(bash "$REPO/plugin/scripts/fold-answers.sh" --list "$T4" open_questions | grep -cF -- "$which4" | tr -d ' ')" 1

echo
echo "== the status line shows a refused wave apart from an idle machine =="
sgr_of() { head -n1 <<<"$(printf '%s' "$1" | tr '\033' '\n' | grep -F "$2" | sed -n 's/^\[\([0-9;]*\)m.*/\1/p')"; }
IDLE="$TMP/idle"; inst "$IDLE" ''; bash "$AW" --instance "$IDLE" >/dev/null 2>&1
R="$(bash "$SL" --instance "$TMP/k1" --color always </dev/null)"; I="$(bash "$SL" --instance "$IDLE" --color always </dev/null)"
ok "refused: the queue carries the grant, in the human's pink" "$(sgr_of "$R" '1 need you')" 95
ok "idle: an empty queue, dim"                                  "$(sgr_of "$I" '0 need you')" 2
ok "…so the two are different lines"                           "$([ "$R" != "$I" ] && echo yes || echo no)" yes

echo
echo "== the wave, the stall counter and the remedy are settled in the shipped step =="
ok "the wave stops at the first refusal"             "$(has "$S3" 'then **stop dispatching this tick.**')" yes
ok "…and the rest are not touched"                   "$(has "$S3" 'no status write, no worktree, no')" yes
ok "no stall round, on this task or any other"       "$(has "$S3" 'Do not run `stall-counter.sh` for it, on this task or any other.')" yes
ok "the SKILL guardrail carves the refusal out"      "$(has "$SKILL" 'refused is not a round and is never recorded')" yes
ok "one condition, one row"                          "$(has "$S3" 'already sits')" yes
ok "…keyed on <which>, so a new cause REPLACES"      "$(has "$S3" '⇒ **replace that entry in place** with the new one rather than skipping.')" yes
ok "the verbatim text is sanitised first"            "$(has "$S3" 'is copied onto ONE line, with every `"` replaced by')" yes
ok "…because a separator would fold the blocker away" "$(has "$S3" '` --- ` makes `fold-answers.sh` read the entry as ANSWERED')" yes
ok "a later successful spawn clears it"              "$(has "$S3" 'cleared: a spawn succeeded')" yes
ok "…said where the spawn succeeds, too"             "$(has "$S3" 'A spawn that succeeds also clears every open `dispatch refused:` entry')" yes
# The remedy used to be "exit auto mode for the whole tick". The owner never leaves auto
# mode, and the cause was the spawn asking for a bypass agent — so the remedy now points at
# the spawn's own mode, and leaving auto mode is named as NOT a remedy.
ok "the remedy: check the spawn asked for auto mode" "$(has "$S3" 'check the spawn asked for --permission-mode auto')" yes
ok "…and never leaving auto mode for it"             "$(has "$S3" 'Never leave auto mode for it')" yes
ok "…the old remedy is gone"                         "$(has "$S3" 'exit auto mode for the WHOLE tick')" no
ok "…the classifier is the tick session's, judging the child" "$(has "$S3" 'The classifier that refuses is the one of the session RUNNING THE TICK')" yes
ok "…and leaving auto mode is not printed as a remedy" "$(has "$S3" 'leaving auto mode, or running anything under `bypassPermissions`, as a remedy')" yes
ok "an allow rule for claude --bg is NOT the remedy" "$(has "$S3" 'Never print an allow rule for `claude --bg`')" yes
ok "…nor bypassPermissions: the grant is the operator's" "$(has "$S3" 'A grant is the')" yes

echo
echo "refused-dispatch.test: $pass passed, $fail failed"
[ "$fail" = 0 ]
