#!/usr/bin/env bash
#
# design-diagram.test.sh — projects/<slug>/design.md: the refine step's instruction text,
# validate-bundle.sh's `type: Design` check, tick-delta.sh's redraw DELTA, build-awaiting.sh's
# one link per project, and the snapshot/board carrying its path and never its body. Every
# surface is asserted with design.md present AND absent. Refine itself (a model step) is
# not run: its text is pinned instead.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/plugin/scripts"
. "$S/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/design-diagram.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }
GIT() { git -C "$I" -c user.email=t@example.com -c user.name=T -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

echo "== the refine step's instruction text =="
STEP="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
for s in 'you write `projects/<slug>/design.md` yourself, once per' 'after its last draft is refined' \
         "The file's presence is the" 'once-only receipt' 'Never on a `kind: research` project' \
         'frontmatter `type: Design`' '`"<component or edge> → task-NNN"`' 'one fenced `mermaid` block' \
         'trust boundaries as `subgraph`s' 'one paragraph reading it' \
         'No internal hostnames, no secrets and no customer PII' '**Redraw rule:**' \
         '`tick-delta.sh check` reports that state as a `DELTA` naming the project'; do
  ok "step 2 says: $s" "$(has "$STEP" "$s")" yes
done
for s in '**Pre-mortem — in the same pass, write `pre_mortem:`**' \
         '`the most likely reason this project fails as designed is …`' \
         "from the
   diagram and the project's \`decisions:\`" 'naming a component or an edge the diagram draws' \
         'Any
   overturned `D<n>` of the project redraws it too' \
         '**Every redraw of design.md — the unmapped-task redraw or an overturned `D<n>` —
   rewrites `pre_mortem:`, and nothing else does.**'; do
  ok "step 2 says: ${s%%$'\n'*}…" "$(python3 -c 'import sys; print("yes" if sys.argv[2] in open(sys.argv[1]).read() else "no")' "$STEP" "$s")" yes
done
ok "SCHEMA.md's type: Design documents pre_mortem:" \
  "$(awk '/^## type: Design/,/^## type: Agent/' "$REPO/plugin/seed/SCHEMA.md" | grep -cE '^pre_mortem: "the most likely reason this project fails as designed is …" +# optional: one sentence naming a component or edge on the diagram$')" 1
ok "SCHEMA.md names design.md where a project's files live" \
  "$(awk '/^\*\*Where a project.s files live/,/^$/' "$REPO/plugin/seed/SCHEMA.md" | grep -cF '**`design.md`** — optional, written by the PM at refine')" 1

# ------------------------------------------------------------------- the fixture
I="$TMP/inst"; P="$I/projects/p1"
mkdir -p "$P/tasks" "$I/projects/p2/tasks" "$I/$AB_DIR"
printf '{ "org": "o" }\n' > "$I/instance.config.json"
printf '# SCHEMA\n' > "$I/$AB_SCHEMA"
printf '/%s\n' "$AB_STATE_DIR" > "$I/.gitignore"
proj() { printf -- '---\ntype: Project\ntitle: "%s"\nkind: build\nstatus: active\ntimestamp: 2026-10-28T00:00:00Z\n---\n' "$2" > "$I/projects/$1/project.md"; }
task() { # <slug> <id> <title> <criteria>
  printf -- '---\ntype: Task\ntitle: "%s"\nkind: build\nstatus: draft\nacceptance_criteria: [ %s ]\nopen_questions: [ ]\ntimestamp: 2026-10-28T00:00:00Z\n---\n' \
    "$3" "$4" > "$I/projects/$1/tasks/$2.md"; }
design() { # <mapping entries>
  printf -- '---\ntype: Design\ntitle: "P1 — design"\ntimestamp: 2026-10-28T00:00:00Z\ntasks: [ %s ]\n---\n\n```mermaid\nflowchart LR\n  subgraph public\n    ui[UI]\n  end\n  ui --> api[API]\n```\n\nBODY-SENTINEL the UI is new.\n' "$1" > "$P/design.md"; }
proj p1 "P1"; proj p2 "P2"
task p1 task-001-a "A" '"x"'; task p1 task-002-b "B" '"x"'; task p1 task-003-c "C" ''
task p2 task-001-z "Z" '"x"'
MAP2='"ui → task-001", "ui --> api → task-002"'
design "$MAP2"
GIT init -q; GIT add -A; GIT commit -qm fixture

echo; echo "== validate-bundle.sh =="
vb() { ( cd "$I" && bash "$S/validate-bundle.sh" ) > "$TMP/vb" 2>&1; echo $?; }
ok "a build project with design.md validates" "$(vb)" 0
ok "…and design.md is one of the checked documents" "$(grep -c 'checked 7,' "$TMP/vb")" 1
design '"ui → task-001", "queue → task-009"'
ok "a mapped id with no task file is an error" "$(vb)" 1
ok "…naming the id" "$(grep -c 'maps task-009, but no task-009 file' "$TMP/vb")" 1
rm "$P/design.md"
ok "no design.md stays green" "$(vb)" 0
design "$MAP2"

echo; echo "== tick-delta.sh: the redraw DELTA =="
TD() { bash "$S/tick-delta.sh" "$@" --instance "$I" 2>&1; }
settle() { GIT add -A; GIT commit -qm "$1" >/dev/null 2>&1; TD record >/dev/null; }
settle base
ok "every refined task mapped ⇒ IDLE" "$(TD check >/dev/null; echo $?)" 0
task p1 task-003-c "C" '"y"'; settle refine-c
out="$(TD check)"; rc=$?
ok "a refined task design.md lacks ⇒ DELTA, exit 1" "$rc" 1
ok "…naming the project" "$(printf '%s\n' "$out" | grep -c '^DELTA: projects/p1 has a refined task its projects/p1/design.md does not map')" 1
ok "…and the digest names step 2" "$(TD digest | grep '^steps:' | grep -c step-2-refine-drafts.md)" 1
design "$MAP2, \"api → task-003\""; settle redraw
ok "redrawn ⇒ IDLE again" "$(TD check >/dev/null; echo $?)" 0
cp "$P/design.md" "$TMP/design.keep"; rm "$P/design.md"; task p1 task-004-d "D" '"z"'; settle no-design
ok "no design.md ⇒ no redraw DELTA" "$(TD check >/dev/null; echo $?)" 0
rm "$P/tasks/task-004-d.md"; cp "$TMP/design.keep" "$P/design.md"; settle restore

echo; echo "== build-awaiting.sh: one link per project, on its first promote row =="
aw() { : > "$I/$AB_AWAITING"; bash "$S/build-awaiting.sh" --instance "$I" "$@" >/dev/null 2>&1; grep '^\* ' "$I/$AB_AWAITING"; }
DEF=' · refined & clean, promote `draft → ready`'
LINK=' · [design](/projects/p1/design.md)'
rows="$(aw)"
ok "DEF_APPROVE row: the first promote row carries the link" "$(printf '%s\n' "$rows" | sed -n 1p)" \
  "* ✅ **approve** — [A](/projects/p1/tasks/task-001-a.md)$DEF$LINK"
ok "…exactly once per project" "$(printf '%s\n' "$rows" | grep -c 'design.md')" 1
ok "…and a project with no design.md links nothing" "$(printf '%s\n' "$rows" | grep -F 'task-001-z' | grep -c design)" 0
rows="$(aw --trailer "$P/tasks/task-001-a.md=an agent sentence")"
ok "agent-trailer row: the link follows the trailer" "$(printf '%s\n' "$rows" | sed -n 1p)" \
  "* ✅ **approve** — [A](/projects/p1/tasks/task-001-a.md) · an agent sentence$LINK"
with="$(aw)"; rm "$P/design.md"; without="$(aw)"
ok "no design.md ⇒ every row byte-identical to the link-free render" "$without" "$(printf '%s\n' "$with" | while IFS= read -r l; do printf '%s\n' "${l%"$LINK"}"; done)"
ok "…and no row names design" "$(printf '%s\n' "$without" | grep -c design)" 0
cp "$TMP/design.keep" "$P/design.md"

echo; echo "== build-awaiting.sh: pre_mortem: after the link =="
pm() { cp "$TMP/design.keep" "$P/design.md"; printf '%s\n' "/^tasks:/a\\" "pre_mortem: $1" > "$TMP/pm.sed"; sed -i.bak -f "$TMP/pm.sed" "$P/design.md"; rm -f "$P/design.md.bak"; }
SENT='the most likely reason this project fails as designed is the edge from ui to api'
pm "\"$SENT\""
ok "present: the sentence follows the link, unquoted" "$(aw | sed -n 1p)" \
  "* ✅ **approve** — [A](/projects/p1/tasks/task-001-a.md)$DEF$LINK · $SENT"
pm "\"$SENT\"   # a YAML comment"
ok "a trailing YAML comment is not part of it" "$(aw | sed -n 1p)" \
  "* ✅ **approve** — [A](/projects/p1/tasks/task-001-a.md)$DEF$LINK · $SENT"
ok "…on the linked row only" "$(aw | grep -c 'fails as designed')" 1
ok "trailer: trailer, then link, then sentence" "$(aw --trailer "$P/tasks/task-001-a.md=an agent sentence" | sed -n 1p)" \
  "* ✅ **approve** — [A](/projects/p1/tasks/task-001-a.md) · an agent sentence$LINK · $SENT"
pm "'it''s the \`cache\` *edge* [x](https://example.com) <b>|#_~!'"
ok "markup and an apostrophe: single-quoted YAML unescaped, markup escaped" "$(aw | sed -n 1p)" \
  "* ✅ **approve** — [A](/projects/p1/tasks/task-001-a.md)$DEF$LINK · it's the \\\`cache\\\` \\*edge\\* \\[x\\]\\(https://example.com\\) \\<b\\>\\|\\#\\_\\~\\!"
pm "\"$(printf 'word%.0s ' $(seq 1 60))\""
tail_="$(aw | sed -n 1p)"; tail_="${tail_#*"$LINK · "}"
ok "cap: at most 200 characters, cut at a word" "$(python3 -c 'import sys; t=sys.argv[1]; print(len(t) <= 202 and t.endswith("word …"))' "$tail_")" True
cp "$TMP/design.keep" "$P/design.md"
ok "absent key: the linked row is unchanged" "$(aw | sed -n 1p)" "* ✅ **approve** — [A](/projects/p1/tasks/task-001-a.md)$DEF$LINK"
pm "\"$SENT\""; mv "$P/design.md" "$TMP/design.pm"
ok "absent file: no row carries the sentence" "$(aw | grep -c 'fails as designed')" 0
mv "$TMP/design.pm" "$P/design.md"

echo; echo "== write-snapshot.sh + build-board.sh: the path, never the body =="
GIT remote add origin https://github.com/example-user-007/example-bundle.git
render() { : > "$I/$AB_SNAPSHOT"
  ( cd "$I" && SNAPSHOT_NOW=2026-10-28T00:00:00Z bash "$S/write-snapshot.sh" --quiet ) >/dev/null 2>&1
  ( cd "$I" && bash "$S/build-board.sh" --standalone --out "$1" . ) >/dev/null 2>&1; }
URL='href="https://github.com/example-user-007/example-bundle/blob/HEAD/projects/p1/design.md"'
command -v python3 >/dev/null 2>&1 || { echo "  (python3 absent — board half skipped)"; }
render "$TMP/with.html"; cp "$I/$AB_SNAPSHOT" "$TMP/with.json"
ok "snapshot carries the design path" "$(has "$TMP/with.json" '"design": "projects/p1/design.md"')" yes
ok "…and the bundle's repo" "$(has "$TMP/with.json" '"repo": "example-user-007/example-bundle"')" yes
ok "…never the body" "$(grep -cE 'BODY-SENTINEL|mermaid|flowchart' "$TMP/with.json")" 0
ok "…nor pre_mortem:" "$(grep -cE 'pre_mortem|fails as designed' "$TMP/with.json")" 0
ok "…and only p1 carries a design key" "$(grep -c '"design"' "$TMP/with.json")" 1
if command -v python3 >/dev/null 2>&1; then
  ok "board links design.md on GitHub" "$(grep -c "$URL" "$TMP/with.html")" 1
  ok "…and renders no pre_mortem: text" "$(grep -c 'fails as designed' "$TMP/with.html")" 0
  ok "…renders no Mermaid" "$(grep -ciE 'mermaid|BODY-SENTINEL' "$TMP/with.html")" 0
fi
rm "$P/design.md"; render "$TMP/without.html"
ok "design.md adds exactly the keys design and repo" "$(python3 -c 'import json,sys
def k(v):
    if isinstance(v, dict):
        for x, c in v.items(): yield x; yield from k(c)
    elif isinstance(v, list):
        for c in v: yield from k(c)
w = set(k(json.load(open(sys.argv[1])))); o = set(k(json.load(open(sys.argv[2]))))
print(" ".join(sorted(w - o)))' "$TMP/with.json" "$I/$AB_SNAPSHOT" 2>/dev/null)" "design repo"
ok "no design.md ⇒ no design key" "$(grep -c '"design"' "$I/$AB_SNAPSHOT")" 0
ok "…and no repo key" "$(grep -c '"repo"' "$I/$AB_SNAPSHOT")" 0
if command -v python3 >/dev/null 2>&1; then
  ok "…and no link on the board" "$(grep -c 'class="design"' "$TMP/without.html")" 0
  ok "no new <script> with design.md present" "$(grep -c '<script' "$TMP/with.html")" "$(grep -c '<script' "$TMP/without.html")"
  sed 's#"design": "projects/p1/design.md"#"design": "projects/p1/../../x.md"#' "$TMP/with.json" > "$I/$AB_SNAPSHOT"
  ( cd "$I" && bash "$S/build-board.sh" --standalone --out "$TMP/hostile.html" . ) >/dev/null 2>&1
  ok "a design path off its own shape renders no link" "$(grep -c 'class="design"' "$TMP/hostile.html")" 0
fi

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
