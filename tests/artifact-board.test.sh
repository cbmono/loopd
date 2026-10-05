#!/usr/bin/env bash
# iced — the board is on hold (owner's decision, 2026-10-05). `run.sh --iced`, the nightly
# workflow and any PR whose diff names this file's subject still run it. Thaw: delete these lines.
#
# artifact-board.test.sh — `scripts/build-board.sh` renders an Artifact page BODY, from
# the snapshot only, and leaks nothing the snapshot does not carry.
#
# WHY THIS EXISTS SEPARATELY from board-renderers.test.sh: this renderer targets a
# different medium. The other renderers write a terminal table or a standalone HTML
# file; this one writes a fragment the artifact host wraps in
# <!doctype>/<html>/<head>/<body>. So the assertion that matters most here is the one no
# other harness makes — that the output carries NONE of those tags. A page that ships
# them gets double-nested.
#
# It was its own SCRIPT (`build-artifact-board.sh`) until the two HTML renderers were
# consolidated behind `--layout`, and became the only one when the kanban `columns`
# layout was deleted; every assertion below is the one it made as a separate script, run
# against the surviving entry point. Nothing was dropped in either move, which is the
# whole point of keeping this file rather than folding it into another one.
#
# THE FLAG IS GONE, AND ITS ABSENCE IS ASSERTED HERE. `--layout` chose between this page
# and a kanban `columns` one; the owner rejected `columns` as unreadable, so it was
# deleted rather than defaulted away. Two consequences are pinned below: the script
# refuses `--layout` BY NAME (a stale caller must fail loudly, never render silently),
# and NO tracked file in this repo invokes build-board.sh with it — checked over every
# tracked file rather than just symlink/, because README.md and docs/ were the half that
# rotted last time (see the retired-renderer block at the bottom of this file).
#
# The escaping assertions are not duplicated effort either. Escaping is per MEDIUM: the
# terminal renderer guards ESC and newline, this one guards `<`, `&` and `"` in an
# attribute, because every button carries untrusted title text in a data- attribute.
#
# Fixtures are hand-written SNAPSHOT.json files rather than write-snapshot.sh output:
# this harness is about the RENDERER, and building the input by hand is what lets it
# assert on forms the live instance does not currently contain.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# No render below passes a layout flag: there is one page, and `--layout` now exits 2
# rather than selecting anything.
GEN="$REPO/plugin/scripts/build-board.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/artboard.XXXXXX")" || {
  echo "artifact-board.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
fhas()   { grep -qF -- "$1" "$2" && echo 0 || echo 1; }
fhasnt() { grep -qF -- "$1" "$2" && echo 1 || echo 0; }
eq()     { [[ "$1" == "$2" ]] && echo 0 || echo 1; }

# Planted strings. Each must never appear in the page: the snapshot does not carry the
# fields they would come from, so their presence would mean the renderer invented a path
# back to the bundle.
HOSTILE='Rename <script>alert(1)</script> & "quote" it'

mk() { # <dir> <group> <json-projects>
  mkdir -p "$1/$AB_DIR"
  cat > "$1/$AB_SNAPSHOT" <<JSON
{"_schema":"ai-bridge board snapshot v1","group":"$2",
 "generated_at":"2026-08-23T12:00:00Z","counts":{"projects":1,"tasks":1,"awaiting":0},
 "projects":$3}
JSON
}

# ---- a live project, a finished one, and every affordance ------------------
mk "$TMP/alpha" "alpha" '[
 {"slug":"live-one","title":"Live work","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":1,"total":3},
  "tasks":[
    {"id":"task-001","title":"First","status":"in-progress","assignee":"software-engineer",
     "awaiting":"","open_questions":0,"advisor_notes":0,"depends_on":[],"in_flight":true,
     "prs":[{"repo":"o/r","number":41,"url":"https://github.com/o/r/pull/41"}]},
    {"id":"task-002","title":"HOSTILE_TITLE","status":"draft","assignee":"",
     "awaiting":"approve","open_questions":0,"advisor_notes":2,
     "depends_on":["task-001"],"in_flight":false,"prs":[]},
    {"id":"task-003","title":"Third","status":"ready","assignee":"qa-reviewer",
     "awaiting":"","open_questions":2,"advisor_notes":0,
     "depends_on":["task-001","task-002"],"in_flight":false,"prs":[],
     "open_question_ids":["Q1",""]}]},
 {"slug":"all-done","title":"Finished work","kind":"build","status":"active",
  "awaiting_close":true,"phase_progress":{"done":2,"total":2},
  "tasks":[{"id":"task-001","title":"Done","status":"done","assignee":"","awaiting":"",
            "open_questions":0,"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]}]}]'
# substitute the hostile title without fighting JSON quoting in the heredoc
python3 - "$TMP/alpha/$AB_SNAPSHOT" "$HOSTILE" <<'PYS'
import json, sys
p, hostile = sys.argv[1], sys.argv[2]
d = json.load(open(p))
for pr in d["projects"]:
    for t in pr["tasks"]:
        if t["title"] == "HOSTILE_TITLE":
            t["title"] = hostile
json.dump(d, open(p, "w"))
PYS

OUT="$TMP/page.html"
rc=0; bash "$GEN" --out "$OUT" "$TMP/alpha" >/dev/null 2>&1 || rc=$?
assert "it renders and exits 0"                      "$(eq "$rc" 0)"
assert "…and wrote the page"                         "$(yes_if test -s "$OUT")"

echo "== it is a page BODY, not a document =="
for tag in '<!doctype' '<!DOCTYPE' '<html' '<head>' '<body' '</body' '</html'; do
  assert "no $tag"                                   "$(fhasnt "$tag" "$OUT")"
done

echo "== the title names the workspace =="
assert "group becomes the title"                     "$(fhas '<title>Alpha Bridge Board</title>' "$OUT")"

echo "== projects are collapsed, and finished ones sink =="
assert "three <details>, none open"                  "$(fhasnt '<details class="proj" open' "$OUT")"
# The ✓ is the CARET on a finished row now (`.proj.fin .phead::before`), so the marker
# is the card's own class rather than a chip repeating what the divider already says.
assert "a finished project is marked"                "$(fhas 'class="proj fin' "$OUT")"
assert "…under a Finished divider"                   "$(fhas 'class="sep fin"' "$OUT")"
assert "…and it sorts AFTER the live one"            "$(yes_if python3 -c "
import sys; h=open('$OUT').read()
sys.exit(0 if h.index('Live work') < h.index('Finished work') else 1)")"

# ---------------------------------------------------------------------------
# THE COLLAPSED VIEW HAS TO ANSWER "WHICH PROJECTS NEED ME?" ON ITS OWN.
#
# The pooled queue that used to sit above every project moved INSIDE each project on
# 2026-08-30. That move is only safe if the summary line carries the weight the pooled
# list used to carry, and this is the block that says so: sixteen closed rows with the
# queues hidden inside them and no marking is strictly worse than the clutter it
# replaced. Three channels are asserted separately, because each covers a reader the
# others do not — the COUNT (a number, for anyone), the MARKED CARD (a shape, for a
# reader skimming rather than reading) and the ORDER (colour-free, for a reader who
# cannot see the chip at all, or a phone showing four rows at a time). A test on only
# the chip would pass a page whose entire signal is one colour nobody can see.
#
# The fixture lists the quiet project FIRST in the snapshot, so the order assertion
# fails if the sort is dropped rather than passing on the input's own order.
#
# ONE BOUNDARY RULE for every "inside this project's card" assertion below, and it is
# not `t.index('</details>', i)`. A card can now contain NESTED <details> — every rail
# item is one — so that slice stops at the first ASK rather than at the end of the
# project, and an assertion cut that way reads a few hundred bytes and reports green on
# a page that is wrong immediately after them. A card ends where the NEXT card begins.
card() { # <file> <project title> -> just that project's card, on stdout
  python3 - "$1" "$2" <<'PYC'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
i = t.index(sys.argv[2])
j = t.find('<details class="proj', i)
sys.stdout.write(t[i:] if j < 0 else t[i:j])
PYC
}
# THE RAIL, NOT THE WHOLE CARD. A card holds the rail AND the task table, and every
# task title appears in that table whether or not the task is waiting on you — so
# "this task is not in the queue" asserted over the card is asserting something else
# entirely, and would be red for a reason that has nothing to do with the queue. Empty
# output when the project has no rail at all, which is itself the answer to "is anything
# waiting here?".
rail_of() { # <file> <project title> -> just that project's rail section, on stdout
  card "$1" "$2" | python3 -c "
import sys
t = sys.stdin.read()
i = t.find('<section class=\"rail\"')
if i < 0:
    sys.exit(0)
j = t.find('</section>', i)
sys.stdout.write(t[i:j if j > 0 else len(t)])"
}
# The renderer joins its parts with newlines, so two spans that render side by side sit
# on two LINES in the file. Adjacency is a real property for some of what follows — "the
# date sits with the title" is exactly that, and a before/after check would also pass a
# date six chips away — so this joins tag boundaries back up rather than settling for the
# weaker claim. Only whitespace BETWEEN tags is collapsed; nothing inside a tag or a text
# node moves.
flat() { python3 -c "
import re, sys
sys.stdout.write(re.sub(r'>\s*\n\s*<', '><', sys.stdin.read()))"
}
fhas_in()   { grep -qF -- "$1" && echo 0 || echo 1; }
fhasnt_in() { grep -qF -- "$1" && echo 1 || echo 0; }
before_in() { # <a> <b> — 0 when a appears before b on stdin
  python3 -c "
import sys
t = sys.stdin.read()
try:
    sys.exit(0 if t.index(sys.argv[1]) < t.index(sys.argv[2]) else 1)
except ValueError:
    sys.exit(1)" "$1" "$2" && echo 0 || echo 1
}
mkdir -p "$TMP/board15/projects/quiet" "$TMP/board15/projects/wants-me" \
         "$TMP/board15/projects/nostamp"
mk "$TMP/board15" "board15" '[
 {"slug":"quiet","title":"Nothing waiting","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Just working","status":"in-progress",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "advisor_notes":3,"depends_on":[],"in_flight":true,"prs":[]}]},
 {"slug":"wants-me","title":"Two decisions","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Promote me","status":"draft","assignee":"",
            "awaiting":"approve","open_questions":0,"advisor_notes":0,"depends_on":[],
            "in_flight":false,"prs":[]},
           {"id":"task-002","title":"Merge me","status":"in-review","assignee":"",
            "awaiting":"merge","open_questions":0,"advisor_notes":0,"depends_on":[],
            "in_flight":false,"prs":[]}]},
 {"slug":"nostamp","title":"No timestamp","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},"tasks":[]},
 {"slug":"nofile","title":"No project md","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},"tasks":[]},
 {"slug":"..","title":"Hostile slug here","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},"tasks":[]}]'
printf -- '---\ntype: Project\ntitle: Nothing waiting\nstatus: active\ntimestamp: 2026-03-04T10:11:12Z   # notes at %s\n---\n' \
  "/Users/attacker/board15-secret.md" > "$TMP/board15/projects/quiet/project.md"
printf -- '---\ntype: Project\ntitle: Two decisions\nstatus: active\ntimestamp: 2026-07-21T08:00:00Z\n---\n' \
  > "$TMP/board15/projects/wants-me/project.md"
printf -- '---\ntype: Project\ntitle: No timestamp\nstatus: active\n---\n' \
  > "$TMP/board15/projects/nostamp/project.md"
# The file a `..` slug reaches if the slug is joined to a path untested. It sits one
# level ABOVE projects/, which is the whole point: nothing here may read it.
printf -- '---\ntype: Project\ntitle: Outside projects\nstatus: active\ntimestamp: 1999-12-31T00:00:00Z\n---\n' \
  > "$TMP/board15/project.md"
BOUT="$TMP/board15.html"
brc=0; bash "$GEN" --out "$BOUT" "$TMP/board15" >/dev/null 2>&1 || brc=$?

echo "== the collapsed line answers 'which projects need me?' =="
assert "the fixture renders and exits 0"             "$(eq "$brc" 0)"
# (1) THE COUNT. Two awaiting items on that project, so the chip says two — the same
# number the pooled list used to contribute for it.
assert "a project with items carries a weighted count" \
  "$(fhas '<span class="c you"><b>2</b> need you</span>' "$BOUT")"
assert "…and only the project that has items carries one" \
  "$(eq "$(grep -oF 'class="c you"' "$BOUT" | wc -l | tr -d ' ')" 1)"
# (2) THE MARKED CARD. Not the same fact as the chip: the chip is one pill among six in
# a row; this is the whole card, readable at a glance from any scroll position.
assert "…and the card itself is marked"              "$(fhas '<details class="proj wants">' "$BOUT")"
assert "a project with none is NOT marked"           "$(fhas '<details class="proj"><summary' "$BOUT")"
assert "…and carries no count chip inside it"        "$(card "$BOUT" 'Nothing waiting' | fhasnt_in 'class="c you"')"
# (3) THE ORDER — the colour-free channel. The snapshot lists `quiet` first; a project
# that wants you must still come out on top, or a reader who cannot see the chip has
# nothing left.
assert "…and it sorts ABOVE a project that wants nothing" "$(yes_if python3 -c "
import sys; t=open('$BOUT').read()
sys.exit(0 if t.index('Two decisions') < t.index('Nothing waiting') else 1)")"
# NON-VACUITY for that ordering: the snapshot really does list them the other way, so
# the assertion above measures the sort rather than the input's own order.
assert "…and the snapshot really lists them the other way round" "$(yes_if python3 -c "
import json, sys
s = json.load(open('$TMP/board15/$AB_SNAPSHOT'))
slugs = [p['slug'] for p in s['projects']]
sys.exit(0 if slugs.index('quiet') < slugs.index('wants-me') else 1)")"

echo "== each project's queue is INSIDE it, and the pooled one is gone =="
assert "the rail moved into the project"             "$(card "$BOUT" 'Two decisions' | fhas_in 'class="rail"')"
assert "…holding only THAT project's items"          \
  "$(eq "$(card "$BOUT" 'Two decisions' | grep -oF 'class="ask"' | grep -c . || true)" 2)"
assert "…above its task table, not below it"         "$(card "$BOUT" 'Two decisions' | before_in 'class="rail"' '<table>')"
# THE POOLED LIST IS GONE, and this is how that is stated without banning `.rail`
# outright: no rail may appear before the first project card. One that survived above
# them all would sit before that index.
assert "no pooled queue above the first project"     "$(yes_if python3 -c "
import sys
t = open('$BOUT').read()
sys.exit(0 if t.index('<details class=\"proj') < t.index('class=\"rail\"') else 1)")"
assert "…replaced by one line saying where to look" \
  "$(fhas '<span class="sig">2 items need you</span> across 1 project' "$BOUT")"

echo "== the creation date comes from project.md, and ONLY a date does =="
assert "the date renders on the collapsed line" \
  "$(fhas '<span class="pdate" title="Project created 2026-07-21">2026-07-21</span>' "$BOUT")"
assert "…for the other project too"                  "$(fhas '>2026-03-04</span>' "$BOUT")"
# ONLY A DATE. frontmatter() does not strip a trailing YAML comment off `timestamp:`,
# so the raw value still carries whatever follows it — rendering the VALUE rather than
# the matched date would put an absolute path on a page that may be published.
assert "…never the time of day"                      "$(fhasnt '10:11:12' "$BOUT")"
assert "…and never a path hidden in that line's comment" "$(fhasnt 'attacker' "$BOUT")"
assert "a project.md with no timestamp renders no date" "$(card "$BOUT" 'No timestamp' | fhasnt_in 'class="pdate"')"
assert "…and so does a project with no project.md at all" "$(card "$BOUT" 'No project md' | fhasnt_in 'class="pdate"')"
# THE SLUG IS SHAPE-CHECKED BEFORE IT IS JOINED TO A PATH, exactly as it is for a
# deliverable path. `projects/../project.md` is a read OUTSIDE projects/, and the
# fixture plants a readable file there so this fails loudly rather than vacuously.
assert "a \`..\` slug reads nothing outside projects/" "$(fhasnt '1999-12-31' "$BOUT")"
assert "…and the file it would have read really is there" \
  "$(yes_if test -s "$TMP/board15/project.md")"
# …AND IT SITS WITH THE TITLE. The date qualifies the title — "this project, started
# then" — and reading it used to mean crossing six count chips to the far end of the
# line. ORDER is the whole assertion, so it is made on the order and not on presence.
assert "the date follows the title immediately"      \
  "$(card "$BOUT" 'Two decisions' | flat | fhas_in 'Two decisions</span><span class="pdate"')"
assert "…with its treatment unchanged"               "$(fhas 'class="pdate" title="Project created' "$BOUT")"
# THE CHIPS KEEP THEIR PLACE. They are still after the date and still before the ✕, and
# `.counts` now takes the free space itself instead of being pushed right by `.ptitle`.
assert "…and the chips still follow it"              \
  "$(card "$BOUT" 'Two decisions' | before_in '<span class="pdate"' 'class="c you"')"
assert "…still ahead of the ✕"                       \
  "$(card "$BOUT" 'Two decisions' | before_in 'class="c you"' 'class="pclose"')"
assert "…and .counts holds its own end of the line"  "$(fhas '.counts{display:flex;gap:6px;flex-wrap:wrap;margin-left:auto;align-items:center;' "$BOUT")"
assert "…which needs .ptitle to stop growing"        "$(fhas '.ptitle{font-weight:600;letter-spacing:-.01em;flex:0 1 auto' "$BOUT")"

echo "== the ✕ copies a command and can never close anything =="
assert "it copies /close-project <slug>"             "$(fhas 'data-copy="/close-project wants-me"' "$BOUT")"
assert "…one per well-formed project"                "$(eq "$(grep -oF 'class="pclose"' "$BOUT" | wc -l | tr -d ' ')" 4)"
assert "…and none for a slug that is not one segment" "$(card "$BOUT" 'Hostile slug here' | fhasnt_in 'class="pclose"')"
# The tooltip is a promise to the reader, and the wrong wording IS the failure: a
# control labelled "close this project" that only copies is a lie, and one that really
# closed would be a rendered page performing /close-project's consolidation, log entry
# and folder removal. Both directions are asserted.
assert "the tooltip says it COPIES"                  "$(fhas 'title="Copy the command to close this project' "$BOUT")"
assert "…and no pclose tooltip starts any other way" "$(yes_if python3 -c "
import re, sys
t = open('$BOUT').read()
btns = re.findall(r'<button class=\"pclose\"[^>]*>', t)
bad = [b for b in btns if 'title=\"Copy the command to close this project' not in b]
sys.exit(0 if btns and not bad else 1)")"
# It is a BUTTON with no href, no form and no target: there is nothing for it to
# navigate to and nothing to submit, whatever any handler does or does not do.
assert "…and it is inert markup: no href, form or target" "$(yes_if python3 -c "
import re, sys
t = open('$BOUT').read()
btns = re.findall(r'<button class=\"pclose\"[^>]*>', t)
sys.exit(0 if btns and not any(a in b for b in btns
                               for a in ('href=', 'formaction=', 'target=')) else 1)")"

echo "== …reusing the ONE clipboard helper: no second script, no second link =="
assert "still exactly one <script>"                  "$(eq "$(grep -oF '<script' "$BOUT" | wc -l | tr -d ' ')" 1)"
assert "…and still exactly two <link> elements"      "$(eq "$(grep -cF '<link' "$BOUT")" 2)"
assert "…the ✕ using the same [data-copy] convention" "$(fhas 'data-what="Close command"' "$BOUT")"
# A FAILED COPY MUST DEGRADE VISIBLY. This page is opened over file://, where a
# clipboard write can be refused, and a control that appears to copy and does not is
# worse than no control. The live behaviour was measured in a browser on that origin
# (see the PR body); what is pinned HERE is that the shipped page still carries a
# failure state that is distinct, selectable and does not fade — a three-second
# unselectable notice is the regression this guards against.
# Asserted on the RULE, not on the page: `fhas 'pointer-events:auto'` is green on any
# page that happens to carry that declaration anywhere, including on a rule that has
# nothing to do with the toast. The property has to be in `.toast.fail`'s own block, or
# the failure notice is still the unclickable, unselectable one.
toast_fail_rule() { # <file> -> the body of the `.toast.fail{...}` rule
  python3 - "$1" <<'PYT'
import re, sys
m = re.search(r"\.toast\.fail\{([^}]*)\}", open(sys.argv[1], encoding="utf-8").read())
sys.stdout.write(m.group(1) if m else "")
PYT
}
assert "the failure state is its own toast rule"     "$(toast_fail_rule "$BOUT" | fhas_in 'background:var(--stop)')"
assert "…that accepts the pointer"                   "$(toast_fail_rule "$BOUT" | fhas_in 'pointer-events:auto')"
assert "…and whose text can be selected"             "$(toast_fail_rule "$BOUT" | fhas_in 'user-select:text')"
assert "…carrying the exact text in a selectable <code>" \
  "$(fhas '.toast.fail code{' "$BOUT")"
assert "…entering a state the success path never sets" "$(fhas "el.classList.add('on','fail');" "$BOUT")"
assert "…with a dismiss control, since it never fades" "$(fhas "dismiss.className='x'" "$BOUT")"

echo "== untrusted title text is escaped for THIS medium =="
assert "no raw <script> survives"                    "$(fhasnt '<script>alert(1)</script>' "$OUT")"
assert "…the tag is entity-escaped"                  "$(fhas '&lt;script&gt;' "$OUT")"
assert "…and a quote inside an attribute is escaped" "$(fhasnt 'data-copy="Rename <' "$OUT")"

echo "== references are short, and never a real path =="
assert "a task ref drops projects/"                  "$(fhasnt 'data-copy="projects/' "$OUT")"
assert "…and drops .md"                              "$(fhasnt '.md"' "$OUT")"
# ONE NOTATION, AND `tasks/` IS NOT IN IT. The ref used to be the FILENAME minus
# `projects/` and `.md` — `live-one/tasks/task-001-…` — which names a document and reads
# as a path; five controls then each wrapped it in a different sentence. It is now
# `<project>/task-<n>`, the same string every control on the page copies.
assert "…and the handle is <project>/task-<n>"      "$(fhas 'data-copy="live-one/task-001' "$OUT")"
# THE ABSENCE IS ASSERTED OVER WHAT IS COPIED, not over the page: the footer legend
# spells out where the document lives (`projects/<p>/tasks/task-<n>*.md`), which is the
# resolution rule and not a second notation. A COPIED value carrying `/tasks/` would be.
assert "…and no copied value carries a tasks/ segment" "$(yes_if python3 -c "
import re, sys
vals = re.findall(r'data-copy=\"([^\"]*)\"', open('$OUT', encoding='utf-8').read())
sys.exit(0 if vals and not [v for v in vals if '/tasks/' in v] else 1)")"

echo "== depends_on shows the NUMBER only =="
assert "a single dependency renders 001"             "$(fhas '>001</button>' "$OUT")"
assert "…two render as a pair"                       "$(fhas '>002</button>' "$OUT")"
assert "…never the full slug"                        "$(fhasnt '>task-001-<' "$OUT")"

echo "== questions =="
# The fixture's two ids are `Q1` and `""` (a question naming no number), so this one task
# exercises both branches. The first is Q1 because ITS LABEL SAYS Q1, not because it is first.
assert "a numbered handle is labelled from its id"   "$(fhas 'answer Q1</button>' "$OUT")"
# THE SECOND QUESTION IS NOT `Q2`. It carries no number, it is merely SECOND, and
# calling that Q2 is the entire defect this file now guards. Scoped to the card, so the
# fixture's other project cannot make it pass or fail.
assert "…and an unnumbered question is never named by its position" \
  "$(card "$OUT" 'Live work' | fhasnt_in 'Q2')"
assert "a question on a READY task reaches the rail" "$(fhas 'class="verb">question' "$OUT")"

# ---------------------------------------------------------------------------
# A QUESTION IS NAMED BY THE `Q<n>` IT CARRIES, NEVER BY ITS POSITION.
#
# THE DEFECT THIS BLOCK EXISTS FOR, from the live bundle on 2026-08-30:
# `ai-bridge-v5/task-012` had Q1 in `answered_questions` and Q2 in `open_questions`, so
# the count was 1 and the board rendered a button reading `answer Q1`. Every number on
# it was internally consistent and it pointed at the wrong question. A human who clicks
# it, opens the document and finds Q1 answered either answers the wrong one or stops
# believing the board — and there is no way to tell from the page which happened.
#
# So the assertions come in PAIRS: the number that must appear, and the positional
# number that must NOT. Asserting only the first is green on a renderer that guesses and
# happens to guess right on a Q1-first fixture, which is exactly what the old test did.
mkdir -p "$TMP/qnum"
mk "$TMP/qnum" "qnum" '[
 {"slug":"twelve","title":"The task-012 shape","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-012-claim-identity","title":"Claim identity","status":"ready",
            "assignee":"software-engineer","awaiting":"","open_questions":1,
            "advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[],
            "open_question_ids":["Q2"]}]},
 {"slug":"sparse","title":"Non contiguous numbers","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Gaps","status":"ready","assignee":"","awaiting":"",
            "open_questions":3,"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[],
            "open_question_ids":["Q7","Q9","Q4"]}]},
 {"slug":"noprefix","title":"No number in the text","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Unnumbered","status":"ready","assignee":"","awaiting":"",
            "open_questions":1,"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[],
            "open_question_ids":[""]}]},
 {"slug":"notext","title":"Count only","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Two questions, no text","status":"ready","assignee":"",
            "awaiting":"","open_questions":2,"advisor_notes":0,"depends_on":[],
            "in_flight":false,"prs":[]}]},
 {"slug":"prose","title":"Numbers in prose","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Prose","status":"ready","assignee":"","awaiting":"",
            "open_questions":2,"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[],
            "open_question_ids":["Q01",""]}]},
 {"slug":"runon","title":"A run that does not end","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Run on","status":"ready","assignee":"","awaiting":"",
            "open_questions":2,"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[],
            "open_question_ids":["Q1234","Q2x"]}]}]'
QN="$TMP/qnum.html"
qnrc=0; bash "$GEN" --out "$QN" "$TMP/qnum" >/dev/null 2>&1 || qnrc=$?

echo "== THE BUG: a waiting row names the question the question names =="
assert "the fixture renders and exits 0"             "$(eq "$qnrc" 0)"
# THE SHIP-BLOCKER, on the real shape: one open question, and it is Q2.
assert "the rail button reads 'answer Q2'"           "$(card "$QN" 'The task-012 shape' | fhas_in 'answer Q2</button>')"
assert "…and never 'answer Q1'"                      "$(card "$QN" 'The task-012 shape' | fhasnt_in 'answer Q1')"
assert "…the table handle is Q2 too"                 "$(card "$QN" 'The task-012 shape' | fhas_in '>Q2</button>')"
assert "…and the copied handle is the right one"     "$(card "$QN" 'The task-012 shape' | fhas_in 'twelve/task-012/q2: ')"
assert "…with no Q1 anywhere in that card"           "$(card "$QN" 'The task-012 shape' | fhasnt_in 'Q1')"
# NON-VACUITY: the count really is 1, so a positional renderer really would say Q1 here.
assert "…and the fixture's count really is 1"        "$(yes_if python3 -c "
import json, sys
s = json.load(open('$TMP/qnum/$AB_SNAPSHOT'))
t = s['projects'][0]['tasks'][0]
sys.exit(0 if t['open_questions'] == 1 and t['open_question_ids'] == ['Q2'] else 1)")"

echo "== …for numbers that are neither contiguous nor in order =="
for n in 7 9 4; do
  assert "Q$n is labelled Q$n"                       "$(card "$QN" 'Non contiguous numbers' | fhas_in ">Q$n</button>")"
done
for n in 1 2 3; do
  assert "…and no Q$n is invented for position $n"   "$(card "$QN" 'Non contiguous numbers' | fhasnt_in ">Q$n</button>")"
done
# ORDER IS PRESERVED, and it is the document's order — not sorted, which would be a
# second way of deciding what a question is called.
assert "…in the order the document lists them"       "$(card "$QN" 'Non contiguous numbers' | before_in '>Q7</button>' '>Q9</button>')"

echo "== …and says so honestly when there is no number to read =="
assert "an unprefixed question gets an unnumbered handle" \
  "$(card "$QN" 'No number in the text' | fhas_in 'answer question</button>')"
assert "…drawn as the handle that admits it"         "$(card "$QN" 'No number in the text' | fhas_in 'class="qbtn nonum"')"
assert "…and it invents no digit at all"             "$(yes_if python3 -c "
import re, sys
t = open('$TMP/qnum.html').read()
i = t.index('No number in the text'); j = t.find('<details class=\"proj', i)
sys.exit(0 if not re.search(r'Q\d', t[i:j if j > 0 else len(t)]) else 1)")"
assert "…saying it will not invent one"              "$(card "$QN" 'No number in the text' | fhas_in 'will not invent one')"
assert "…and naming which absence this is"           "$(card "$QN" 'No number in the text' | fhas_in 'carries no Qn prefix')"

echo "== …and when the snapshot carries a count and no text at all =="
assert "the count yields ONE honest handle, not N"   \
  "$(eq "$(card "$QN" 'Count only' | grep -oF 'class="qbtn nonum"' | wc -l | tr -d ' ')" 2)"
assert "…numbered neither Q1 nor Q2"                 "$(yes_if python3 -c "
import re, sys
t = open('$TMP/qnum.html').read()
i = t.index('Count only'); j = t.find('<details class=\"proj', i)
sys.exit(0 if not re.search(r'Q\d', t[i:j if j > 0 else len(t)]) else 1)")"
assert "…and saying it is a count, not a name"       "$(card "$QN" 'Count only' | fhas_in 'carries a COUNT of open questions')"
assert "…the copy value is the bare task handle"    "$(card "$QN" 'Count only' | fhas_in 'data-copy="notext/task-001: "')"
# …AND CARRIES NO `/q<n>`. The board cannot name this question, so a handle claiming to
# scope one would be the same fabrication as a positional number, one segment along.
assert "…and no /q segment is invented for it"      "$(card "$QN" 'Count only' | fhasnt_in 'task-001/q')"

echo "== …a padded label normalises, an empty one stays unnumbered =="
assert "Q01 normalises to Q1"                        "$(card "$QN" 'Numbers in prose' | fhas_in '>Q1</button>')"
assert "…and that question gets the unnumbered handle" "$(card "$QN" 'Numbers in prose' | fhas_in 'class="qbtn nonum"')"

# THE FALLBACK IS NOT MERELY UNUSED — IT IS ABSENT. A renderer that still contains the
# positional path is one edit away from taking it again, and no page-level assertion can
# tell "never reached" from "not reached by this fixture". So the source is read too.
echo "== …and a number must END where it is read, or it is not read at all =="
# THE TRUNCATION THIS PREVENTS IS THE SHIP-BLOCKER'S OWN FAILURE MODE, arriving by a
# different route. `Q(\d{1,3})` with no boundary after it reads `Q1234` as `Q123` — a
# number that is not in the text, on a control that claims to have read the text, and
# indistinguishable on the page from a correct one. `Q2x` is the same defect one character
# smaller. Both must fall through to the handle that admits it cannot name the question.
assert "a four-digit run is not truncated to three"  "$(card "$QN" 'A run that does not end' | fhasnt_in '>answer Q123<')"
assert "…and no number is invented from it at all"   "$(card "$QN" 'A run that does not end' | fhasnt_in '>answer Q1<')"
assert "…it gets the handle that admits it"          "$(card "$QN" 'A run that does not end' | fhas_in 'class="qbtn nonum"')"
assert "a letter straight after the digits is not Q2" "$(card "$QN" 'A run that does not end' | fhasnt_in '>answer Q2<')"
# BOTH questions fall through, so both handles in the RAIL are unnumbered. Counted on the
# rail and not the card: a numbered handle is rendered in two places — the waiting row and
# the task table's Q column — so a card-wide count is 2 per question and reads like a bug.
assert "…so both questions render unnumbered"        \
  "$(eq "$(rail_of "$QN" 'A run that does not end' | grep -oF 'class="qbtn nonum"' | wc -l | tr -d ' ')" 2)"
assert "…and the card carries no numbered handle"    "$(card "$QN" 'A run that does not end' | fhasnt_in 'class="qbtn">answer Q')"
# NON-VACUITY: a number that DOES end where it is read still reads, in the same fixture
# set — otherwise the four assertions above are satisfied by a renderer that numbers
# nothing at all.
assert "…while a bounded number still reads"         "$(card "$QN" 'The task-012 shape' | fhas_in '>answer Q2<')"

echo "== positional numbering is unreachable, because it is not there =="
assert "q_range() is gone from the renderer"         "$(fhasnt 'def q_range' "$GEN")"
assert "…and nothing calls it"                       "$(fhasnt 'q_range(' "$GEN")"
assert "…no question label is enumerated"            "$(fhasnt 'enumerate(qs, 1)' "$GEN")"
assert "…and no label is built from a range"         "$(yes_if python3 -c "
import re, sys
src = open('$GEN', encoding='utf-8').read()
# Every 'Q%d'/'Q%s' format in the file must be fed q_split()'s number. Guard the shape
# that produced the bug: a range/enumerate counter reaching a question label.
bad = re.findall(r'for\s+\w+\s+in\s+(?:range|enumerate)\([^)]*\)[^\n]*', src)
sys.exit(0 if not any('q' in b.lower() and 'Q%' not in b for b in bad if 'question' in b.lower()) else 1)")"
assert "…and the header records why it may not come back" \
  "$(fhas 'NEVER BY ITS POSITION' "$GEN")"

# ---------------------------------------------------------------------------
# ONE HANDLE SHAPE, AND IT IS ASSERTED ONCE.
#
# Every control that refers to a task used to spell the reference its own way: the ghost
# button copied `<slug>/tasks/<full-filename>`, the Q buttons copied that plus ` Q2: `,
# and Approve/Discuss/Reject copied a SENTENCE describing the item — `APPROVED — go
# ahead. Re the "merge" item on <task title> in <project title>.` An agent receiving the
# last one has to parse prose to find out which document is meant, which is the failure
# class this page exists to delete.
#
# So there is one notation, `<slug>/task-<n>[/q<n>]: `, and this block asserts the
# COMMON PREFIX ONCE over every control in a waiting row rather than five times in five
# shapes. Five separate literal assertions would each go green on a change that split
# the notation again, as long as each shape kept its own spelling.
mkdir -p "$TMP/handle/projects/gdg/tasks"
mk "$TMP/handle" "handle" '[
 {"slug":"gdg","title":"One handle","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-044-the-dwd-calendar-grant-lives-in-a-workspace","title":"DWD grant",
            "status":"draft","assignee":"software-engineer","awaiting":"answer",
            "open_questions":3,"open_question_ids":["Q1","Q2",""],"advisor_notes":0,
            "depends_on":[],"in_flight":false,"prs":[]},
           {"id":"task-058-ship-it","title":"Ship it","status":"in-review",
            "assignee":"devops-engineer","awaiting":"merge","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,
            "depends_on":["task-044-the-dwd-calendar-grant-lives-in-a-workspace"],
            "in_flight":false,
            "prs":[{"repo":"o/r","number":79,"url":"https://github.com/o/r/pull/79"}]}]},
 {"slug":"twins","title":"Two tasks one number","kind":"build","status":"active",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-007-first","title":"First seven","status":"draft",
            "assignee":"software-engineer","awaiting":"approve","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]},
           {"id":"task-007-second","title":"Second seven","status":"ready",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]},
           {"id":"task-008-only","title":"Eight","status":"ready",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]},
           {"id":"task-009-unassigned","title":"Nobody yet","status":"ready",
            "assignee":"","awaiting":"","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]}]},
 {"slug":"/Users/SECRET-HOME/notes","title":"Slug is a path","kind":"build",
  "status":"active","autonomy":"gated","awaiting_close":false,
  "phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Hostile slug with a task","status":"draft",
            "assignee":"software-engineer","awaiting":"approve","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]}]},
 {"slug":"quiet","title":"Nothing waiting here","kind":"build","status":"active",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Just working","status":"in-progress",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,"depends_on":[],"in_flight":true,"prs":[]}]}]'
# THE DOCUMENTS THE HANDLES MUST RESOLVE TO, on disk. The renderer never reads them —
# it is the assertion below that does, standing in for the session a human pastes into.
: > "$TMP/handle/projects/gdg/tasks/task-044-the-dwd-calendar-grant-lives-in-a-workspace.md"
: > "$TMP/handle/projects/gdg/tasks/task-058-ship-it.md"
HB="$TMP/handle.html"
hrc=0; bash "$GEN" --out "$HB" "$TMP/handle" >/dev/null 2>&1 || hrc=$?
# Every data-copy value inside ONE waiting row's action block, unescaped, one per line.
# Scoped to the <li class="ask"> naming that task: a page-wide sweep would mix rows and
# could not tell "all five agree" from "each row is internally consistent".
acts_of() { # <file> <id fragment>
  python3 - "$1" "$2" <<'PYA'
import html, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
for li in re.findall(r'<li class="ask">.*?</li>', page, re.S):
    if sys.argv[2] in li and '<div class="acts">' in li:
        acts = li[li.index('<div class="acts">'):]
        for v in re.findall(r'data-copy="([^"]*)"', acts):
            print(html.unescape(v))
        break
PYA
}
acts_of "$HB" '044-the-dwd' > "$TMP/acts044.txt"
acts_of "$HB" '058-ship-it' > "$TMP/acts058.txt"

echo "== all five controls emit ONE handle shape =="
assert "the fixture renders and exits 0"             "$(eq "$hrc" 0)"
# THE ONE ASSERTION. Seven controls in this row — copy task ref, three question handles,
# and the three verdicts — and every one of them opens with the same handle. The count is
# part of it: `all()` over an empty list is True, so a helper that returned nothing would
# otherwise certify the property it failed to look at.
assert "every control in the row opens with the same handle" "$(yes_if python3 -c "
import sys
vals = [v for v in open('$TMP/acts044.txt', encoding='utf-8').read().split(chr(10)) if v]
sys.exit(0 if len(vals) == 7 and all(v.startswith('gdg/task-044') for v in vals) else 1)")"
# …AND NO SECOND NOTATION SURVIVES. The prose form is named literally, because that is
# the string being deleted and a renderer that kept it for one button would still pass
# the prefix check above (the sentence used to FOLLOW the verdict, not precede it).
assert "…and the prose form is gone from the page"   "$(fhasnt 'Re the "' "$HB")"
assert "…from every other rendered page too"         "$(fhasnt 'Re the "' "$BOUT")"

echo "== the /q<n> segment appears ONLY on a question =="
# Two of the three questions carry a number; the third carries none. So exactly two
# values are question-scoped, and every other control in the row — including all three
# verdicts, which are given on the ITEM — stops at the task id. Inventing a `q1` for a
# verdict is the fabrication #79 removed, one segment along.
assert "exactly the numbered questions carry /q<n>"  "$(yes_if python3 -c "
import re, sys
vals = [v for v in open('$TMP/acts044.txt', encoding='utf-8').read().split(chr(10)) if v]
scoped = [v for v in vals if re.match(r'gdg/task-044/q[0-9]+: $', v)]
plain  = [v for v in vals if '/q' not in v]
sys.exit(0 if len(scoped) == 2 and len(scoped) + len(plain) == len(vals) == 7 else 1)")"
assert "…and they are q1 and q2, from the labels"    "$(fhas 'data-copy="gdg/task-044/q2: "' "$HB")"
# A MERGE ITEM HAS NO QUESTION AT ALL, so none of its four controls may carry one. This
# is the case a `q1` would be invented for out of nothing.
assert "a merge item's controls carry no /q at all"  "$(yes_if python3 -c "
import sys
vals = [v for v in open('$TMP/acts058.txt', encoding='utf-8').read().split(chr(10)) if v]
sys.exit(0 if len(vals) == 4 and not [v for v in vals if '/q' in v] else 1)")"

echo "== the verdict wording after the colon says what the verdict does =="
# APPROVE and DISCUSS are unchanged on this item (a merge). REJECT is not: it used to read
# `REJECTED — do not proceed. Record why on the task and move on.`, which is the wording of
# a CANCELLATION — "this one is over" — and an agent receiving it could reasonably close a
# task the owner had only declined an action on. Nothing on this page changes a status; a
# rejected draft stays `draft`; cancelling is `status: cancelled`, a different act with no
# control here. So the payload now declines the action and names the status it leaves alone.
for v in 'APPROVED — go ahead.' 'I want to discuss this before you proceed.' 'REJECTED — do not do this.'; do
  assert "…$v follows the handle"                    "$(fhas "data-copy=\"gdg/task-058: $v" "$HB")"
done
assert "…and Reject says to leave the status alone"  \
  "$(fhas 'data-copy="gdg/task-058: REJECTED — do not do this. Record why on the task; leave its status as it is."' "$HB")"
# BOTH HALVES OF THE OLD READING ARE GONE, named literally, because either one alone still
# reads as a cancellation.
assert "…so nothing tells the reader to move on"     "$(fhasnt 'and move on.' "$HB")"
assert "…and nothing reads as do-not-proceed"        "$(fhasnt 'REJECTED — do not proceed' "$HB")"
# AND NO CONTROL PROPOSES CANCELLING. This round deliberately added none: a cancel button
# would be a fourth verdict with a state change behind it (`status: cancelled`), which is
# not a wording change. Asserted over what is COPIED, since the word could legitimately
# appear on the page as a task's own state.
assert "…and no copied value proposes cancelling"    "$(yes_if python3 -c "
import re, sys
vals = re.findall(r'data-copy=\"([^\"]*)\"', open('$HB', encoding='utf-8').read())
sys.exit(0 if vals and not [v for v in vals if 'cancel' in v.lower()] else 1)")"

echo "== the handle resolves to exactly one document =="
# THE POINT OF THE SHORT FORM IS THAT IT STILL RESOLVES. `gdg/task-044` is not a path;
# it is resolved by one glob, `projects/<slug>/tasks/task-044*.md`, which is what a
# session pasting it does. Asserted against real files on disk rather than argued for.
assert "each handle globs to one task document"      "$(yes_if python3 -c "
import pathlib, re, sys
root = pathlib.Path('$TMP/handle')
vals = [v for v in (open('$TMP/acts044.txt', encoding='utf-8').read()
                    + open('$TMP/acts058.txt', encoding='utf-8').read()).split(chr(10)) if v]
hits = set()
for v in vals:
    m = re.match(r'([^/]+)/(task-[0-9]+)', v)
    if not m:
        sys.exit(1)
    found = list((root / 'projects' / m.group(1) / 'tasks').glob(m.group(2) + '*.md'))
    if len(found) != 1:
        sys.exit(1)
    hits.add(found[0].name)
sys.exit(0 if len(hits) == 2 else 1)")"
# NON-VACUITY: the documents really are there and really are two, so the check above is
# measuring a glob rather than an empty directory.
assert "…and both documents really exist"            "$(eq "$(ls "$TMP/handle/projects/gdg/tasks" | wc -l | tr -d ' ')" 2)"

echo "== …and falls back to the full id when a number is not unique =="
# Nothing enforces that two tasks in a project cannot share a number, so the short form
# is used only where it resolves. Both colliding tasks fall back — not just the second —
# because either one alone would still be ambiguous to a reader.
assert "colliding ids keep their full form"          "$(card "$HB" 'Two tasks one number' | fhas_in 'data-copy="twins/task-007-first"')"
assert "…both of them, not just the second"          "$(card "$HB" 'Two tasks one number' | fhas_in 'data-copy="twins/task-007-second"')"
assert "…and no bare twins/task-007 is emitted"      "$(card "$HB" 'Two tasks one number' | fhasnt_in 'data-copy="twins/task-007"')"
# NON-VACUITY: the same project's non-colliding task still gets the short form, so the
# fallback is scoped to the collision and not a renderer that gave up on short handles.
assert "…while an unambiguous number stays short"    "$(card "$HB" 'Two tasks one number' | fhas_in 'data-copy="twins/task-008"')"

echo "== a slug that is a PATH never reaches a copied handle =="
# The handle now travels on the VERDICT buttons and on a project-level close item, and
# neither carried a slug before this round — so a `"slug": "/Users/…"` in a snapshot
# this renderer reads back without knowing who wrote it would put an absolute path in a
# data-copy value. Same shape check the ✕ applies, same reason: a slug that is not one
# well-formed segment resolves to nothing anyway, so the handle names the task alone.
assert "no copied value carries the hostile slug"    "$(yes_if python3 -c "
import re, sys
vals = re.findall(r'data-copy=\"([^\"]*)\"', open('$HB', encoding='utf-8').read())
sys.exit(0 if vals and not [v for v in vals if 'SECRET-HOME' in v] else 1)")"
assert "…and the page carries it nowhere else either" "$(fhasnt 'SECRET-HOME' "$HB")"
# NON-VACUITY: that project really is on the page, with a task and a waiting row, so
# the absence above is the shape check firing rather than the project being skipped.
assert "…though the project and its task do render"  "$(card "$HB" 'Slug is a path' | fhas_in 'Hostile slug with a task')"
assert "…and its handle names the task alone"        "$(card "$HB" 'Slug is a path' | fhas_in 'data-copy="task-001: promote to ready"')"

echo "== there is NO Role column, on any project =="
# IT WENT THROUGH BOTH WEAKER FORMS FIRST, and this block asserts the third: unconditional
# absence. It was unconditional; then conditional on `len(roles) > 1` (a column with one
# value is not a column, but a rare `devops-engineer` row is real information); then that
# AND not phased. Every version cost the task name width on every project to serve one
# project out of twelve, so the owner removed it outright on 2026-08-31.
#
# WHAT WAS ASSERTED BEFORE IS RE-EXPRESSED, NOT DELETED. `a project with two roles keeps
# Role` and its `shows both values` companion pinned the KEPT direction; they now pin that
# a two-role project has no column either, which is the same claim inverted and is the one
# a reintroduction would break. The header/body column-count check is kept and widened to
# a second page: the predicate it guarded is gone, so it can no longer fail that way, but a
# <thead> and <tbody> that disagree is a defect independent of what caused it.
assert "no page renders a Role header"               "$(yes_if python3 -c "
import sys
bad = [f for f in ['$OUT', '$BOUT', '$HB'] if '<th>Role</th>' in open(f, encoding='utf-8').read()]
sys.exit(0 if not bad else 1)")"
assert "…not even on a project naming two roles"     "$(card "$HB" 'One handle' | fhasnt_in '<th>Role</th>')"
assert "…and no role value is rendered as a cell"    "$(card "$HB" 'One handle' | fhasnt_in '>devops-engineer</td>')"
assert "…nor on a phased two-role project"           "$(card "$OUT" 'Live work' | fhasnt_in '<th>Role</th>')"
assert "…and its roles reach no cell either"         "$(card "$OUT" 'Live work' | fhasnt_in '>qa-reviewer</td>')"
# NON-VACUITY, AND IT IS THE WHOLE POINT HERE: an absence assertion over a page with no
# multi-role project is satisfied by the fixture, not by the renderer. Both projects named
# above really do name two roles — one phased, one not — so between them they cover every
# case each earlier form of the predicate kept the column for.
assert "…though 'One handle' really names two roles" "$(yes_if python3 -c "
import json, sys
s = json.load(open('$TMP/handle/$AB_SNAPSHOT'))
pr = [x for x in s['projects'] if x['slug'] == 'gdg'][0]
sys.exit(0 if sorted({t['assignee'] for t in pr['tasks']} - {''})
         == ['devops-engineer', 'software-engineer'] else 1)")"
assert "…and 'Live work' names two AND is phased"    "$(yes_if python3 -c "
import json, sys
s = json.load(open('$TMP/alpha/$AB_SNAPSHOT'))
pr = [x for x in s['projects'] if x['slug'] == 'live-one'][0]
sys.exit(0 if sorted({t['assignee'] for t in pr['tasks']} - {''})
         == ['qa-reviewer', 'software-engineer'] and pr['phase_progress']['total'] else 1)")"
# THE ASSIGNEE IS NOT LOST — it was never this page's only home. It stays in the task
# document and in AWAITING.md; only the column is gone. Asserted as the rows still being
# there, since "the column went" and "the rows went" are different bugs.
assert "…and every task row still renders"           "$(card "$HB" 'One handle' | fhas_in 'DWD grant')"
assert "…including an unassigned one"                "$(card "$HB" 'Two tasks one number' | fhas_in 'Nobody yet')"
# NOTHING COMPUTES THE COLUMN ANY MORE. A predicate left in place with no consumer is the
# state this deletion is one edit away from, and it is the state the next reader restores
# the column from.
assert "no role-count predicate survives"            "$(fhasnt 'show_role' "$GEN")"
# …AND THE FIELD IS NOT READ AT ALL. write-snapshot.sh still carries `assignee` — this
# deletion is the board's, not the contract's — so the renderer simply never asks for it.
assert "…and the renderer never reads assignee"      "$(fhasnt 't.get(\"assignee\")' "$GEN")"
# THE COLUMN COUNT FOLLOWS THE HEADER. A <thead> and <tbody> that disagree shift every
# value one column left, which renders as a table nobody can read. Run over two pages.
for pg in "$HB" "$OUT"; do
assert "header and body agree on the column count"   "$(yes_if python3 -c "
import re, sys
page = open('$pg', encoding='utf-8').read()
seen = 0
for tbl in re.findall(r'<table>.*?</table>', page, re.S):
    head = len(re.findall(r'<th[ >]', tbl[:tbl.index('</thead>')]))
    body = tbl[tbl.index('<tbody>'):]
    rows = [len(re.findall(r'<td[ >]', r)) for r in re.split(r'<tr[^>]*>', body)[1:]]
    if not rows or any(n != head for n in rows):
        sys.exit(1)
    seen += 1
sys.exit(0 if seen >= 2 else 1)")"
done
assert "…and that count is five, the columns that are left" "$(yes_if python3 -c "
import re, sys
page = open('$HB', encoding='utf-8').read()
heads = [len(re.findall(r'<th[ >]', t[:t.index('</thead>')]))
         for t in re.findall(r'<table>.*?</table>', page, re.S)]
sys.exit(0 if heads and set(heads) == set([5]) else 1)")"

echo "== the collapsed line carries ONE pill, and it is the awaiting one =="
# TWO PILLS MEASURED OVERLAPPING THINGS: a filled `N awaiting you` at the front of the
# row and an outlined `N questions` at the end. The questions counter is gone and the
# surviving pill took its slot and its treatment.
assert "the awaiting pill is there, with the awaiting count" \
  "$(card "$HB" 'One handle' | fhas_in '<span class="c you"><b>2</b> need you</span>')"
assert "…and no questions counter survives anywhere" "$(fhasnt 'question</span>' "$HB")"
assert "…nor its plural"                             "$(fhasnt 'questions</span>' "$HB")"
assert "…nor the class it was drawn with"            "$(fhasnt 'class="c q"' "$HB")"
assert "…nor the CSS rule behind that class"         "$(fhasnt '.c.q{' "$HB")"
# THE SLOT IS THE QUESTIONS PILL'S: last of the count chips, after `pending`, where the
# questions counter used to sit — not first in the row, where it used to sit itself.
assert "…and it sits where the questions pill sat"   "$(card "$HB" 'One handle' | before_in 'pending</span>' 'need you</span>')"
assert "…after the done chip too"                    "$(card "$HB" 'One handle' | before_in 'class="c ok"' 'class="c you"')"
# THE FILL IS BACK, and the outline is what went. The soft-slate redesign makes every
# other count a plain run of text, so the amber pill is now the ONLY box on the line —
# a stronger channel than the outlined chip it replaces, not a weaker one. Both
# directions, so a rule that only filled the pill would not pass.
assert "…drawn as the one filled pill on the line"   "$(fhas '.c.you{background:var(--signal);color:var(--signal-ink);font-weight:700;' "$HB")"
assert "…and every other count carries no box at all" "$(fhas '.c,.tag{font-size:13px;color:var(--muted);border:0;background:none;padding:0;' "$HB")"
# #74'S QUESTION STILL HAS TO HOLD: from the collapsed view alone, which projects need
# me? The pill lost its fill, so the two channels that never depended on it are what
# carry it — and they are asserted here rather than assumed.
# ASSERTED ON THE CARD'S OWN OPENING TAG, WHICH `card()` CANNOT SEE. That helper slices
# from the project TITLE to the next card, and `<details class="proj …">` sits BEFORE the
# title — so `card … | fhasnt_in 'proj wants'` is structurally incapable of failing, and
# an earlier version of this pair said exactly that and read green on a fixture with no
# quiet project in it at all (CodeRabbit, PR #83). This pairs each title with the class
# on the tag that introduces it, and asserts both directions at once.
# THE COMPARISON IS A LIST, NOT A SET OR DICT LITERAL: a `{a, b}` inside a `$( )` in a
# command ARGUMENT is brace-expanded by bash, which runs the check twice and hands
# `assert` the second answer (knowledge/findings/brace-expansion-mangles-a-regex-inside-
# a-command-substitution.md). Brackets are not braces.
assert "the marked cards are exactly the ones with items" "$(yes_if python3 -c "
import re, sys
page = open('$HB', encoding='utf-8').read().replace(chr(10), '')
pairs = re.findall(r'<details class=.proj([^\"]*).><summary class=.phead.><span class=.ptitle.>([^<]*)', page)
got = sorted('%s=%s' % (t, 'wants' in c) for c, t in pairs)
sys.exit(0 if got == ['Nothing waiting here=False', 'One handle=True',
                      'Slug is a path=True', 'Two tasks one number=True'] else 1)")"

echo "== open_question_ids is what the handles are built from =="
# THE FIELD THIS ROUND EXISTS FOR. Before it the snapshot carried a COUNT, so #79's
# `answer Q<n>` control had nothing to read and degraded to the unnumbered one on every
# instance. Three questions, two of them numbered: three handles, named from the labels.
assert "one handle per question, numbered from its label" \
  "$(rail_of "$HB" 'One handle' | fhas_in 'answer Q1</button>')"
assert "…including the second"                       "$(rail_of "$HB" 'One handle' | fhas_in 'answer Q2</button>')"
assert "…three handles for three questions"          \
  "$(eq "$(rail_of "$HB" 'One handle' | grep -oF 'class="qbtn' | wc -l | tr -d ' ')" 3)"
# THE HONEST PATH SURVIVES, as its own case: the third label is empty, and an empty
# label is a question that names no number — not a question to number by position.
assert "…and the unlabelled one stays unnumbered"    "$(rail_of "$HB" 'One handle' | fhas_in 'answer question</button>')"
assert "…never invented as Q3"                       "$(rail_of "$HB" 'One handle' | fhasnt_in 'answer Q3')"
assert "…and its tooltip names the right absence"    "$(rail_of "$HB" 'One handle' | fhas_in 'carries no Qn prefix')"

# ---------------------------------------------------------------------------
# THE SECOND DEFECT IN THE SAME ROW, DECIDED SEPARATELY.
#
# task-012 was `status: done` and still sat under "Waiting for you". That is not the
# Q-number fault and must not be resolved by it. Decision (a): the board omits waiting
# items for a TERMINAL task. Its rationale is on the guard in build-board.sh; what is
# pinned here is that the two fixes are independent — the guard removes a terminal
# task's item, and the Q fix leaves a LIVE task's item exactly where it was.
mkdir -p "$TMP/term"
mk "$TMP/term" "term" '[
 {"slug":"mixed","title":"Terminal and live","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-012-claim-identity","title":"Shipped already","status":"done",
            "assignee":"","awaiting":"","open_questions":1,"advisor_notes":0,
            "depends_on":[],"in_flight":false,"prs":[],
            "open_question_ids":["Q2"]},
           {"id":"task-013-cancelled-one","title":"Cancelled already","status":"cancelled",
            "assignee":"","awaiting":"","open_questions":1,"advisor_notes":0,
            "depends_on":[],"in_flight":false,"prs":[],
            "open_question_ids":["Q3"]},
           {"id":"task-014-still-live","title":"Still live","status":"ready","assignee":"",
            "awaiting":"","open_questions":1,"advisor_notes":0,"depends_on":[],
            "in_flight":false,"prs":[],"open_question_ids":["Q5"]},
           {"id":"task-015-drifted","title":"Drifted done with a verb","status":"done",
            "assignee":"","awaiting":"merge","open_questions":0,"advisor_notes":0,
            "depends_on":[],"in_flight":false,"prs":[]}]},
 {"slug":"finished","title":"Finished and proposing its close","kind":"build","status":"active",
  "awaiting_close":true,"phase_progress":{"done":1,"total":1},
  "tasks":[{"id":"task-001","title":"All done","status":"done","assignee":"","awaiting":"",
            "open_questions":0,"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]}]}]'
TM="$TMP/term.html"
tmrc=0; bash "$GEN" --out "$TM" "$TMP/term" >/dev/null 2>&1 || tmrc=$?

echo "== a terminal task is not waiting on you (defect 2, decided as (a)) =="
assert "the fixture renders and exits 0"             "$(eq "$tmrc" 0)"
assert "a done task contributes no rail item"        "$(rail_of "$TM" 'Terminal and live' | fhasnt_in 'Shipped already')"
assert "…nor does a cancelled one"                   "$(rail_of "$TM" 'Terminal and live' | fhasnt_in 'Cancelled already')"
assert "…and neither leaves a stale Q handle in the queue" \
  "$(rail_of "$TM" 'Terminal and live' | fhasnt_in 'answer Q2')"
# …and the guard is on the whole contribution, so a hand-edited snapshot claiming a
# done task is awaiting a merge is caught too. write-snapshot.sh cannot emit that shape;
# a human editing SNAPSHOT.json can.
assert "…nor a done task carrying a drifted awaiting verb" \
  "$(rail_of "$TM" 'Terminal and live' | fhasnt_in 'class="verb">merge')"
# THE INDEPENDENCE, in both directions. The Q fix must not delete rows, and the guard
# must not be what makes Q numbers right.
assert "a LIVE task's question still reaches the rail" \
  "$(rail_of "$TM" 'Terminal and live' | fhas_in 'class="verb">question')"
assert "…still labelled from its own text"           "$(rail_of "$TM" 'Terminal and live' | fhas_in 'answer Q5</button>')"
assert "…exactly one item in the rail"               \
  "$(eq "$(rail_of "$TM" 'Terminal and live' | grep -oF 'class="ask"' | wc -l | tr -d ' ')" 1)"
# NON-VACUITY for rail_of() itself: it must be capable of returning something, or every
# `fhasnt_in` above is green because the helper hands back an empty string.
assert "…and rail_of really returns that project's rail" \
  "$(rail_of "$TM" 'Terminal and live' | fhas_in '<section class="rail"')"
assert "…and the collapsed count agrees"             "$(card "$TM" 'Terminal and live' | fhas_in '<b>1</b> needs you')"
# THE TASK TABLE IS UNTOUCHED: the question is still visible where the task lives. The
# guard removes it from the queue of things blocking you, not from the record.
assert "the terminal task still renders in the table" "$(card "$TM" 'Terminal and live' | fhas_in 'Shipped already')"
assert "…keeping its own Q handle"                   "$(card "$TM" 'Terminal and live' | fhas_in '>Q2</button>')"
# A PROJECT'S OWN awaiting_close IS NOT A TASK, and a finished project proposing its
# close is exactly the case `.proj.fin.wants` exists for. The guard must not reach it.
assert "a finished project still proposes its close" "$(card "$TM" 'Finished and proposing' | fhas_in 'class="verb">close')"
assert "…and is still marked as wanting you"         "$(fhas '<details class="proj fin wants">' "$TM")"

# ---------------------------------------------------------------------------
# APPROVE IS GENERIC OVER THE AWAITING KINDS, SO ITS PAYLOAD IS NOT.
#
# One button serves a promotion, a merge, a project close and a deliverable, and copied
# one verdict sentence for all four. Only the FIRST is the same decision as the task
# table's `promote → ready`, so only the first copies that payload — `promote to ready` on
# a merge or a close names an act nobody asked for.
#
# ONE ASSERTION FOR THE WHOLE RULE, AS AN IFF, over every waiting row on every page this
# harness renders. Two literals ("a promotion copies X", "a merge copies Y") both go green
# on a renderer that copies the promote payload for every kind, as long as one promotion is
# somewhere on the page — which is exactly the blanket edit of WORDING["approve"] this
# criterion exists to forbid.
echo "== Approve's payload follows the awaiting KIND =="
assert "the promote payload appears exactly on promotion rows" "$(yes_if python3 -c "
import html, re, sys
rows = []
for path in ['$OUT', '$BOUT', '$HB', '$TM']:
    page = open(path, encoding='utf-8').read()
    for li in re.findall(r'<li class=\"ask\">.*?</li>', page, re.S):
        v = re.search(r'<span class=\"verb\">([^<]*)</span>', li)
        b = re.search(r'<button class=\"go\" data-copy=\"([^\"]*)\"', li)
        if v and b:
            rows.append((v.group(1), html.unescape(b.group(1))))
promo = [r for r in rows if r[1].endswith(': promote to ready')]
other = [r for r in rows if not r[1].endswith(': promote to ready')]
# NO SET LITERAL AND NO SET COMPREHENSION WITH A COMMA IN IT. bash brace-expands
# a {a, b} inside a command substitution in an argument, runs the substitution
# twice and hands assert the second answer — see the Finding
# brace-expansion-mangles-a-regex-inside-a-command-substitution. Written with
# set(...) so the python source survives the shell.
kinds = set(v for v, _ in other)
sys.exit(0 if (len(rows) >= 6 and len(promo) >= 2 and len(other) >= 2
               and all(v == 'approve' for v, _ in promo)
               and all(v != 'approve' for v, _ in other)
               and all(': APPROVED — go ahead.' in m for _, m in other)
               and 'merge' in kinds and 'close' in kinds) else 1)")"
# The literals too, both directions, so a failure above says which side broke.
assert "…a promotion item copies handle + promote to ready" \
  "$(fhas 'data-copy="twins/task-007-first: promote to ready"' "$HB")"
assert "…a merge item keeps the verdict sentence"     "$(fhas 'data-copy="gdg/task-058: APPROVED — go ahead."' "$HB")"
assert "…and a close item keeps it WITH its run hint" "$(rail_of "$TM" 'Finished and proposing' | fhas_in ': APPROVED — go ahead. Run /close-project')"
# THE TWO CONTROLS FOR THE SAME DECISION COPY THE SAME BYTES. `promote → ready` in the
# task table and `Approve` on that task's promotion row are one act; two spellings of it
# is the defect, and comparing the values is the only way to pin "the same", since each
# is independently correct-looking.
assert "…and the rail value equals the button's, byte for byte" "$(yes_if python3 -c "
import html, re, sys
page = open('$HB', encoding='utf-8').read()
btn = set(html.unescape(v) for v in
          re.findall(r'<button class=\"promote\" data-copy=\"([^\"]*)\"', page))
rail = set()
for li in re.findall(r'<li class=\"ask\">.*?</li>', page, re.S):
    if '<span class=\"verb\">approve</span>' in li:
        m = re.search(r'<button class=\"go\" data-copy=\"([^\"]*)\"', li)
        if m:
            rail.add(html.unescape(m.group(1)))
sys.exit(0 if btn and rail and rail <= btn else 1)")"

# ---------------------------------------------------------------------------
# THE TASK ROW: THE JITTER IS THE DEFECT, NOT THE LINE COUNT.
#
# `014-banner-reaches-the-human Some title` and `001-local-board Some title` were two
# inline runs in one cell, so every title started at a different x and the column read
# as ragged; and the row reflowed between one and two lines as the window moved, so some
# rows were one line and their neighbours two. Both are the same thing — nothing about
# the row is fixed — and both are fixed by giving the filename a column of its own.
#
# A RENDERED PAGE CANNOT BE MEASURED HERE. There is no layout engine in this harness, so
# what is asserted is the two things that DECIDE the layout and that a regression would
# have to break: the markup that makes two columns possible at all (a flex wrapper
# INSIDE the <td> — `display:flex` on the cell itself would take it out of the table's
# column sizing), and the rules that switch between them. Anything past that is a claim
# about pixels this file must not pretend to make; the PR body says what was looked at.
mkdir -p "$TMP/rows"
mk "$TMP/rows" "rows" '[
 {"slug":"jitter","title":"Ragged titles","kind":"build","status":"active",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001-local-board","title":"Short name, long title that will wrap",
            "status":"draft","assignee":"software-engineer","awaiting":"","open_questions":0,
            "advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]},
           {"id":"task-017-write-for-a-human-who-will-not-read","title":"Longest filename present",
            "status":"done","assignee":"qa-reviewer","awaiting":"","open_questions":0,
            "advisor_notes":0,"depends_on":[],"in_flight":false,
            "prs":[{"repo":"o/r","number":75,"url":"https://github.com/o/r/pull/75"}]}]}]'
RW="$TMP/rows.html"
rwrc=0; bash "$GEN" --out "$RW" "$TMP/rows" >/dev/null 2>&1 || rwrc=$?

echo "== a task row has a filename column, not two inline runs =="
assert "the fixture renders and exits 0"             "$(eq "$rwrc" 0)"
assert "the cell holds a flex wrapper, not the flex itself" \
  "$(fhas '<td><div class="trow"><span class="tfile"><span class="tid">' "$RW")"
assert "…and the title lives in its own second column" "$(fhas '</span><div class="tmain">' "$RW")"
assert "…for every task row, not just the first"     \
  "$(eq "$(grep -oF '<div class="trow">' "$RW" | wc -l | tr -d ' ')" 2)"
# NARROW IS THE DEFAULT, and that is what makes "uniform" true by construction rather
# than by luck: the base rule is a COLUMN, so below the breakpoint there is no width at
# which one row is one line and the next is two.
assert "the base rule stacks filename over title"    "$(fhas '.trow{display:flex;flex-direction:column;' "$RW")"
assert "…and .tmain stacks inside it"                "$(fhas '.tmain{display:flex;flex-direction:column;' "$RW")"
# ONE ROW LAYOUT AT EVERY WIDTH, AND THE SECOND ONE IS DELETED RATHER THAN RE-TUNED.
# There was a `@media (min-width:1200px)` block that turned `.trow` back into a row with
# `.tfile` pinned to a fixed 56-character flex basis, so that every title started at the
# same x. It bought that at a price the owner read off the rendered page: above 1200px a
# title sat ~400px to the right of its own filename, with the gap growing on every
# filename shorter than the longest one. So what used to be asserted ABOUT the breakpoint
# is now asserted about its ABSENCE — the assertions are re-expressed, not dropped, since
# a rule nobody pins is a rule that comes back.
#
# tidrule() IS KEPT ON PURPOSE. It existed to prove the row rules were INSIDE the
# breakpoint; the same helper now proves there is no such block for anything to be inside,
# so the claim is measured by the code that used to measure its opposite.
tidrule() { python3 - "$1" <<'PYR'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"@media \(min-width:1200px\)\{(.*?)\n\}", src, re.S)
sys.stdout.write(m.group(1) if m else "")
PYR
}
assert "there is no width-conditional block at all"  "$(eq "$(tidrule "$RW")" "")"
assert "…no min-width media query in the sheet"      "$(fhasnt '@media (min-width' "$RW")"
assert "…no fixed flex basis on the filename column" "$(fhasnt 'flex:0 0 56ch' "$RW")"
assert "…nor any flex basis on .tfile at all"        "$(fhasnt '.trow>.tfile{flex:' "$RW")"
assert "…and the title column takes no flex either"  "$(fhasnt '.tmain{flex:1 1 auto}' "$RW")"
assert "…no row direction anywhere on the page"      "$(fhasnt 'flex-direction:row' "$RW")"
# THE STALE DERIVATION WENT WITH IT. A comment measuring a 56-character column against
# the longest filename in the bundle describes nothing once the column is gone, and a
# derivation for a rule that no longer exists is worse than no comment: the next reader
# takes it for a live constraint.
assert "…and the 56ch derivation comment is gone"    "$(fhasnt 'WHERE 56ch COMES FROM' "$RW")"
assert "…including its measured character count"     "$(fhasnt '56ch' "$RW")"
# THE PROPERTY THE MEDIA QUERY EXISTED FOR IS STILL HELD, by the base rule alone: filename
# line 1, title line 2, so every title starts at the cell's own left edge — the same x on
# every row, at every width, with nothing to re-measure when a longer filename arrives.
# The fixture renders the longest filename in the bundle, so that claim is anchored to a
# real name rather than to a comment.
assert "…the one rule still stacks filename over title" "$(fhas '.trow{display:flex;flex-direction:column;' "$RW")"
assert "…and that longest name really is on the page" "$(fhas '>017-write-for-a-human-who-will-not-read</span>' "$RW")"
# DEGRADATION for a name longer still: it CLIPS rather than overflowing the cell — and
# clipping replaced wrapping deliberately. A wrapped filename makes the cell three lines,
# which pushes the title down and takes the pills out of level with its first line (the
# `padding-top:19px` above is a constant, and it can only be one). The comment on
# `.trow` has always said a third line is not allowed; this is the rule that makes it so.
assert "…a longer name clips rather than overflowing" "$(fhas '.tfile>.tid{margin-right:0;min-width:0;white-space:nowrap;overflow:hidden;' "$RW")"
assert "…and the 760px fallback hands the wrap back"  "$(fhas '.tfile>.tid{white-space:normal;overflow:visible;overflow-wrap:anywhere}' "$RW")"
# VERTICALLY CENTRED. Against a two-line title every other cell in the row — the state,
# the dependencies, the PR link — sat pinned to the first line and read as though it
# belonged to that line rather than to the row.
# The row is a grid now, so the padding is the ROW's; the cell keeps the alignment.
assert "cells are centred, not baselined"            "$(fhas 'td{padding:0;vertical-align:middle;' "$RW")"
assert "…and no baseline rule survives on td"        "$(fhasnt 'vertical-align:baseline' "$RW")"

echo "== the promote chip sits in the PR column, on the rows that have no PR =="
# IT MOVED OUT OF THE TASK CELL. It used to ride on the filename's own line, which cost
# the task column width on every draft row; the PR cell is empty on exactly those rows,
# so the chip is free there. The task cell is back to filename over title, nothing else.
assert "it sits in the PR cell"                      \
  "$(flat < "$RW" | fhas_in '<td class="prs"><button class="promote"')"
assert "…and the filename line carries only the filename" \
  "$(flat < "$RW" | fhasnt_in '<span class="tid">001-local-board</span><button class="promote"')"
# THE THIRD LINE IS STILL GONE, stated as the absence that would bring it back: a promote
# control opening `.tmain` is exactly the markup that stacked it above the title.
assert "…and never opens the title column"           "$(flat < "$RW" | fhasnt_in '<div class="tmain"><button class="promote"')"
assert "…after the title it belongs to, in its own row" "$(python3 -c "
import sys
t = open('$RW').read()
sys.exit(0 if t.index('Short name, long title') < t.index('class=\"promote\"') else 1)" && echo 0 || echo 1)"
assert "…only on a draft row"                        "$(eq "$(grep -oF 'class="promote"' "$RW" | wc -l | tr -d ' ')" 1)"
# THE PAYLOAD IS THE HANDLE AND THE VERB, and nothing else. It was three sentences —
# `In the loopd instance, promote <handle> from draft to ready: review its acceptance
# criteria, tighten any that are not testable, then set status: ready.` — which told an
# agent how to do a job it already knows, and was a SECOND spelling of the decision the
# rail's Approve copies for the same task. Both halves are pinned: the short form is
# there, and the prose form is absent from the page.
assert "…still only COPYING, and now handle + verb"  "$(fhas 'class="promote" data-copy="jitter/task-001: promote to ready"' "$RW")"
assert "…and the three-sentence prompt is gone"      "$(fhasnt 'In the loopd instance, promote' "$RW")"
assert "…from every rendered page"                   "$(fhasnt 'tighten any that are not testable' "$HB")"
# IT LOOKS LIKE A CONTROL AT REST, which is the property the old outline bought and the
# soft-blue fill keeps: a chip only visible under a pointer is invisible to a touch
# screen. Filled at rest, brighter on hover — hover is a state change, not the moment
# the control appears. Both halves, so a fill with no hover state would not pass.
assert "the chip is filled at rest, in the soft blue" "$(fhas 'border-radius:6px;background:var(--ok-soft);color:var(--ok);' "$RW")"
assert "…and hover only brightens what is already there" "$(fhas '.promote:hover,.promote:focus-visible{filter:brightness(1.15)}' "$RW")"
assert "…so nothing appears on hover that was not there" "$(yes_if python3 -c "
import re, sys
m = re.search(r'\.promote:hover[^{]*\{([^}]*)\}', open('$RW').read())
sys.exit(0 if m and 'background' not in m.group(1) and 'color:' not in m.group(1) else 1)")"

# ---------------------------------------------------------------------------
# THE PR AND DEPENDS-ON CELLS WRAP, AND BOTH WIDTHS ARE DERIVED RATHER THAN CHOSEN.
#
# `006-scaffold-configuration-studio-bff` carries nine PRs on one task, and the PR cell
# rendered them as ONE UNBROKEN LINE — 386px measured at 1400px: the widest thing in the
# table, in one of the columns nobody reads first, taking the width from the task name. The Depends-on cell had the same
# shape one step smaller — it reserved room for TWO refs and separated them with `", "`,
# a character that costs width and carries no information beside pills that are already
# discrete boxes.
#
# WHAT A HARNESS CAN AND CANNOT SAY HERE. There is no layout engine in this file, so it
# asserts the three things a regression must break — the class that lets the cell wrap at
# all, the rule that reserves the line, and the ARITHMETIC behind the number in that rule
# — and nothing about pixels on a screen. The rendered check is the PR body's job. The
# arithmetic is the half that would otherwise rot: `107px` and a `calc()` are both
# unfalsifiable as literals, so each is re-derived here from the same terms the comment
# beside it names, and the derivation is written so that it fails if the target changes.
mkdir -p "$TMP/cells"
mk "$TMP/cells" "cells" '[
 {"slug":"006-scaffold-configuration-studio-bff","title":"Nine PRs on one task","kind":"build",
  "status":"active","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001-nine-prs","title":"Nine pull requests","status":"in-review",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,
            "depends_on":["task-002","task-010","task-011","task-012"],"in_flight":false,
            "prs":[{"repo":"o/r","number":2101,"url":"https://github.com/o/r/pull/2101"},
                   {"repo":"o/r","number":2102,"url":"https://github.com/o/r/pull/2102"},
                   {"repo":"o/r","number":2103,"url":"https://github.com/o/r/pull/2103"},
                   {"repo":"o/r","number":2104,"url":"https://github.com/o/r/pull/2104"},
                   {"repo":"o/r","number":2105,"url":"https://github.com/o/r/pull/2105"},
                   {"repo":"o/r","number":2106,"url":"https://github.com/o/r/pull/2106"},
                   {"repo":"o/r","number":2107,"url":"https://github.com/o/r/pull/2107"},
                   {"repo":"o/r","number":2108,"url":"https://github.com/o/r/pull/2108"},
                   {"repo":"o/r","number":2109,"url":"https://github.com/o/r/pull/2109"}]},
           {"id":"task-002-three-deps","title":"Three dependencies","status":"ready",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,
            "depends_on":["task-001","task-010","task-011"],"in_flight":false,
            "prs":[{"repo":"o/r","number":2110,"url":"https://github.com/o/r/pull/2110"},
                   {"repo":"o/r","number":2111,"url":"https://github.com/o/r/pull/2111"}]},
           {"id":"task-010-one-of-each","title":"One of each","status":"ready",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "open_question_ids":[],"advisor_notes":0,"depends_on":["task-001"],
            "in_flight":false,
            "prs":[{"repo":"o/r","number":2112,"url":"https://github.com/o/r/pull/2112"}]}]}]'
CE="$TMP/cells.html"
cerc=0; bash "$GEN" --out "$CE" "$TMP/cells" >/dev/null 2>&1 || cerc=$?

echo "== the PR cell wraps at two refs, on a width read off its own font =="
assert "the fixture renders and exits 0"             "$(eq "$cerc" 0)"
# NON-VACUITY FIRST: nine refs really are in that one cell, or everything below is a
# claim about an empty cell.
assert "nine refs really render in one cell"         "$(yes_if python3 -c "
import re, sys
page = open('$CE', encoding='utf-8').read()
cells = re.findall(r'<td class=\"prs\">(.*?)</td>', page, re.S)
sys.exit(0 if cells and max(len(re.findall(r'<a href', c)) for c in cells) == 9 else 1)")"
assert "the cell carries its own class"              "$(fhas '<td class="prs">' "$CE")"
assert "…which lets it wrap inside its track"        "$(fhas 'td.prs{white-space:normal;' "$CE")"
# A plain assignment, not inline: bash 3.2 brace-expands a quoted `{a,b}` inside "$(…)".
PRS_MONO="td.prs{white-space:normal;font-family:'JetBrains Mono',ui-monospace,Menlo,monospace;
  font-size:13px;overflow-wrap:anywhere}"
assert "…and gives the cell one monospace context"   "$(fhas "$PRS_MONO" "$CE")"
# REFS ARE SPACE-SEPARATED — no comma, the form the Depends-on cell now copies.
assert "…refs are separated by a space"              "$(fhas '#2101</a> <a href' "$CE")"
assert "…and never by a comma"                       "$(fhasnt '</a>, <a' "$CE")"
# THE COLUMN IS A TRACK NOW, NOT A RESERVATION. The row is a five-track grid from the
# handoff, so the PR column is a fixed 90px whatever the cell holds: nine refs wrap
# inside it instead of taking the width from the task name, and a row with one ref pays
# nothing. That deletes the conditional `min-width` this used to need.
assert "…the PR column is a fixed track, not a floor" "$(fhas 'grid-template-columns:minmax(0,1fr) 105px 140px 80px 90px;' "$CE")"
assert "…and no reservation is left behind"          "$(fhasnt 'min-width:107px' "$CE")"
assert "…nor a cap pretending to work"               "$(fhasnt 'td.prs{white-space:normal;max-width' "$CE")"
assert "…the unconditional rule reserves nothing"    "$(yes_if python3 -c "
import re, sys
m = re.search(r'td\.prs\{([^}]*)\}', open('$CE', encoding='utf-8').read())
sys.exit(0 if m and 'min-width' not in m.group(1) and 'max-width' not in m.group(1) else 1)")"
# ONE TEMPLATE, SHARED BY THE HEAD ROW AND EVERY BODY ROW — which is what makes the
# columns line up at all. Written once in the sheet, so the two cannot drift apart; the
# assertion is that there is exactly one of it, not that two copies happen to agree.
assert "…and the head and body rows share one template" "$(yes_if python3 -c "
import re, sys
src = open('$CE', encoding='utf-8').read()
n = len(re.findall(r'grid-template-columns:minmax\(0,1fr\) 105px 140px 80px 90px', src))
sys.exit(0 if n == 1 else 1)")"

echo "== the Depends on cell allows three refs, space-separated =="
assert "pills are separated by a space"              "$(fhas '</button> <button class="dep"' "$CE")"
assert "…and the \", \" separator is gone"            "$(fhasnt '</button>, <button' "$CE")"
# THE 140px TRACK REPLACES THE `calc()`. Same property, one number instead of a
# derivation that had to be re-done every time a pill's padding moved: the cell wraps
# inside its own track and cannot take width from the task column.
assert "…and the cell wraps inside its own track"    "$(fhas '.deps{white-space:normal}' "$CE")"
assert "…with no derived width left in the sheet"    "$(fhasnt 'min-width:calc(' "$CE")"
# BOTH CELLS JOIN THE SAME WAY, which is the point of dropping the comma: one form for
# two columns of the same kind of thing.
assert "…so both cells use one separator form"       "$(yes_if python3 -c "
import re, sys
page = open('$CE', encoding='utf-8').read()
sys.exit(0 if '</button> <button class=\"dep\"' in page and '#2101</a> <a href' in page
             and ', <a' not in page and ', <button' not in page else 1)")"

echo "== a waiting row carries the task filename, so the file can be found =="
assert "the filename precedes the title"             \
  "$(rail_of "$TM" 'Terminal and live' | flat | fhas_in '<span class="tid">014-still-live</span><span class="what">Still live</span>')"
assert "…with task- and .md both dropped"            "$(rail_of "$TM" 'Terminal and live' | fhasnt_in '>task-014')"
# A close item has no task id at all, so it gets no filename rather than an empty span.
assert "…and a close item carries none"              "$(rail_of "$TM" 'Finished and proposing' | fhasnt_in 'class="tid"')"
assert "…the close item really is there"             "$(rail_of "$TM" 'Finished and proposing' | fhas_in 'class="verb">close')"

echo "== the waiting block separates from the card holding it =="
# THE FILL IS A LAYER NOW, NOT A TINT. It was `--signal` 16% mixed into `--sunk`,
# because the palette had three backgrounds and the block needed a fourth. The soft-slate
# theme ships four — ground, surface, sunk, inner — so the block is plain `--sunk` set
# INTO a `--surface` card, with the decision cards inside it on `--inner`. Same hue
# discipline: a second accent would compete with the one that means "needs you".
assert "the fill is the recessed layer itself"       "$(fhas '.rail{background:var(--sunk);' "$BOUT")"
assert "…and is no longer a tint of the card"        "$(fhasnt 'color-mix(in srgb,var(--signal) 16%,var(--sunk))' "$BOUT")"
assert "…nor the card's own surface"                 "$(fhasnt 'color-mix(in srgb,var(--signal) 8%,var(--surface))' "$BOUT")"
assert "…with the decision cards a layer deeper"     "$(fhas '.ask{display:flex;flex-direction:column;padding:14px 16px;
  background:var(--inner);' "$BOUT")"
assert "the pink left rail is kept"                  "$(fhas 'border-left:4px solid var(--signal);' "$BOUT")"
assert "…and so is the WAITING FOR YOU · N label"    "$(fhas '<h2>Waiting for you · ' "$BOUT")"
assert "…rendered upper case, as it reads on the page" "$(fhas ".rail h2{margin:0;font:700 11px/1.4 'Inter',system-ui,sans-serif;text-transform:uppercase" "$BOUT")"
# NO SECOND ACCENT. Every colour the block uses is --signal, --ink, --sunk, --surface,
# --line or --muted; --accent and --ok appearing inside a .rail rule would be a second
# thing competing for "this one needs you".
assert "no second accent enters the block"           "$(yes_if python3 -c "
import re, sys
src = open('$BOUT', encoding='utf-8').read()
rules = re.findall(r'(?:^|\})\s*(\.rail[^{}]*)\{([^}]*)\}', src)
bad = [s for s, b in rules if 'var(--accent)' in b or 'var(--ok)' in b or 'var(--stop)' in b]
sys.exit(0 if rules and not bad else 1)")"
# THE LABEL TAKES --signal-soft-text, the one token every "this wants you" surface
# shares: the header's "N items need you", the decision card's verb and this label all
# render in the same pink, so the reader learns one colour and not three.
assert "the label takes the needs-you pink"          "$(fhas 'letter-spacing:.1em;color:var(--signal-soft-text)}' "$BOUT")"
assert "…and not the mix the tinted fill needed"     "$(fhasnt 'color-mix(in srgb,var(--signal) 78%,var(--ink))' "$BOUT")"
# THE BREADCRUMB WAS THE LEAST LEGIBLE THING IN THE BLOCK, measurably: --dim on .ask's
# surface is 3.45:1, under AA's 4.5:1 for .75rem text.
assert "the breadcrumb is off --dim"                 "$(fhas '.where{width:100%;font-size:13px;color:var(--muted);' "$BOUT")"
assert "…and --dim is not still on it"               "$(fhasnt '.where{width:100%;font-size:13px;color:var(--dim)' "$BOUT")"
# THE RATIOS ARE COMPUTED HERE, not copied from the PR body — a number quoted in prose
# and nowhere else is a number nobody re-checks. One theme, because loopd is dark-only.
contrast_ok() { # <fg> <bg> <min> -> 0 when the pair clears <min>
  python3 - "$1" "$2" "$3" <<'PYC'
import sys
def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def lum(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
a, b = lum(sys.argv[1]), lum(sys.argv[2])
lo, hi = sorted((a, b))
sys.exit(0 if (hi + 0.05) / (lo + 0.05) >= float(sys.argv[3]) else 1)
PYC
}
# --muted on --inner, the pair the breadcrumb actually renders as (.ask is --inner).
assert "--muted clears AA on the card (6.42:1)"      "$(yes_if contrast_ok '#9aa4b5' '#1c212b' 4.5)"
# NON-VACUITY: the colour it replaced must FAIL the same check, or this asserts nothing
# about the change.
assert "…where --dim failed it (3.45:1)"             "$(contrast_ok '#6c7488' '#1c212b' 4.5 && echo 1 || echo 0)"
# The rail label — --signal-soft-text on --sunk.
assert "the label clears AA on the rail (7.54:1)"    "$(yes_if contrast_ok '#ff7ac2' '#14171c' 4.5)"
# SEPARATION IS WHAT THE FOUR LAYERS BUY, so each adjacent pair is measured. The numbers
# are small on purpose — loopd separates with 1px --line borders first and tone second,
# so these are tighter than a shadow-led palette's and the border is what carries it.
assert "the rail separates from the card (1.04:1)"   "$(yes_if contrast_ok '#14171c' '#171b22' 1.03)"
assert "the decision card separates from the rail (1.11:1)" "$(yes_if contrast_ok '#1c212b' '#14171c' 1.10)"

echo "== advisor_notes is the loop's inbox, so the board renders none of it =="
assert "an untriaged concern shows no pill"          "$(fhasnt 'concern' "$OUT")"
assert "…and never as an awaiting verb"              "$(fhasnt 'class="verb">advisor' "$OUT")"

echo "== a PR is a real link =="
assert "PR links to GitHub"                          "$(fhas 'href="https://github.com/o/r/pull/41"' "$OUT")"
assert "…and opens safely"                           "$(fhas 'rel="noopener noreferrer"' "$OUT")"

echo "== a retained project's deliverables panel =="
# A hand-written SNAPSHOT.json, exactly as write-snapshot.sh would emit it for a
# `status: done` project carrying `deliverable_paths:` — this harness is about the
# RENDERER's own shape check, so the hostile entries below are ones a human could
# still hand-edit into project.md even though closeout never writes them.
mk "$TMP/delivs" "delivs" '[
 {"slug":"with-delivs","title":"Shipped review","kind":"research","status":"done",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[],
  "deliverable_paths":["/projects/with-delivs/deliverables/report.md",
                        "/projects/with-delivs/deliverables/summary.html",
                        "/projects/with-delivs/deliverables/site/index.html",
                        "/projects/other-project/deliverables/report.md",
                        "/Users/attacker/.ssh/id_rsa",
                        "/projects/with-delivs/deliverables/../../../etc/passwd",
                        "/projects/with-delivs/deliverables/site/../../../etc/shadow",
                        "/projects/with-delivs/deliverables/report.md ]   # from /Users/attacker/notes [old]",
                        "/projects/with-delivs/deliverables/report.md /Users/attacker/Desktop/report.md",
                        "/projects/with-delivs/deliverables/see#/Users/attacker/secret",
                        "/projects/with-delivs/deliverables/report.md\n/Users/attacker/Desktop/notes.md",
                        "/projects/with-delivs\u0308/deliverables/elsewhere.md"]},
 {"slug":"..","title":"Hostile slug","kind":"research","status":"done",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[],
  "deliverable_paths":["/projects/../deliverables/id_rsa",
                        "/projects/../../Users/attacker/deliverables/id_rsa"]},
 {"slug":"no-delivs","title":"Closed with nothing stamped","kind":"build","status":"done",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[],"deliverable_paths":[]}]'
DOUT="$TMP/delivs.html"
rc4=0; bash "$GEN" --out "$DOUT" "$TMP/delivs" >/dev/null 2>&1 || rc4=$?
assert "a bundle-relative deliverable renders as a copy button" \
  "$(fhas 'data-copy="/projects/with-delivs/deliverables/report.md"' "$DOUT")"
assert "…labelled by filename, not the full path"    "$(fhas '>report.md</button>' "$DOUT")"
assert "…and a second one too"                        "$(fhas 'data-copy="/projects/with-delivs/deliverables/summary.html"' "$DOUT")"
assert "…reusing the existing data-what convention"   "$(fhas 'data-what="Deliverable path"' "$DOUT")"
assert "a NESTED deliverable renders too, not dropped" \
  "$(fhas 'data-copy="/projects/with-delivs/deliverables/site/index.html"' "$DOUT")"
assert "…labelled by its filename only, not its nested path" "$(fhas '>index.html</button>' "$DOUT")"
assert "the panel is titled with a count that matches what renders" \
  "$(fhas 'Deliverables · 3' "$DOUT")"
echo "== every rendered path is bundle-relative to THIS project — nothing else survives =="
assert "another project's deliverable is dropped"     "$(fhasnt 'other-project/deliverables' "$DOUT")"
assert "an absolute filesystem path is dropped"       "$(fhasnt 'attacker' "$DOUT")"
# LOOK INSIDE THE VALUE. `fhasnt 'data-copy="/Users'` only says no value BEGINS with
# /Users — and the leak this exists to catch puts the absolute path in the MIDDLE of a
# value whose first characters are a perfectly good bundle-relative prefix (a swallowed
# YAML comment, see the last fixture entry). Spelled the first way, this assertion read
# green on a page that was leaking, which is worse than not having it at all.
no_copy_value_with() { # <needle> <file>
  ! grep -qF -- "$1" <<<"$(grep -o 'data-copy="[^"]*"' "$2")"
}
assert "…and no /Users ANYWHERE inside a data-copy value" \
  "$(yes_if no_copy_value_with '/Users' "$DOUT")"
assert "a traversal attempt is dropped"               "$(fhasnt 'etc/passwd' "$DOUT")"
assert "a traversal attempt through a nested segment is dropped too" "$(fhasnt 'etc/shadow' "$DOUT")"
# A REAL path with a YAML trailing comment folded into it. The writer strips that comment
# before it can ever get this far (write-snapshot.sh's deliverable_path_entries), so what
# this fixture stands for is the input that never met the writer at all: SNAPSHOT.json is
# a file on disk, and this renderer reads it back without knowing who wrote it. Its prefix
# is this project's and it has no `..`, so a guard that only anchors the prefix passes it
# — and it carries an absolute path.
assert "a swallowed YAML comment is dropped, not rendered as a path" \
  "$(fhasnt 'report.md ]' "$DOUT")"
# THE VECTOR THAT NEEDS NO COMMENT AT ALL, and the reason this guard stopped listing bad
# characters and started requiring a whole shape. Two paths in one value: correct prefix,
# no `..`, no `#`, nothing on any denylist — and rendered whole it puts the publisher's
# home directory in a copy button labelled `report.md`, so the page looks right. What
# rejects it is that a deliverable path may not contain WHITESPACE, and this value does.
assert "two paths sharing one value are dropped, not rendered as one" \
  "$(fhasnt 'Desktop/report.md' "$DOUT")"
# …and the same shape with no whitespace either, which is why `#` is excluded on its own
# account and not merely as the character a comment starts with.
assert "an absolute path glued on after a # is dropped too" \
  "$(fhasnt 'deliverables/see#' "$DOUT")"
# A NEWLINE and a second path after an otherwise perfect value. This is what fullmatch()
# buys over a prefix test plus an end anchor: Python's `$` also matches just before a
# trailing newline, so "the whole value, with no remainder" has to be the match itself.
assert "a trailing remainder after a newline is dropped" \
  "$(fhasnt 'Desktop/notes.md' "$DOUT")"
# THE SLUG IS CHECKED BY THE SAME RULE AS EVERY OTHER SEGMENT. It used to be interpolated
# into the prefix and trusted, so a hand-written snapshot claiming its slug was `..` got
# `/projects/../deliverables/<file>` rendered as this project's own deliverable — the
# guard compared the value against a prefix the value itself had chosen.
assert "a hostile slug cannot render a path out of the bundle" \
  "$(fhasnt 'data-copy="/projects/../' "$DOUT")"
# THE SLUG AGAIN, THROUGH A COMBINING MARK. bundle_deliverable() strips category-M
# characters before it tests the SHAPE, so that a macOS-decomposed filename is not
# dropped. Strip them from the whole value and they come off the SLUG too: `with-delivs`
# + U+0308 reduces to `with-delivs`, the shape matches, and a button would point at a
# NEIGHBOURING project's directory while claiming to be this project's deliverable.
# What rejects it is that the slug is pinned on the ORIGINAL value, not on the stripped
# one — the mark-tolerance is bought for the filename segments only.
# Asserted with no_copy_value_with and not a whole-file `fhasnt`, for the reason this
# file already learned once: a page-wide grep is only an assertion while no OTHER
# fixture can satisfy it, and the thing being denied here is specifically a data-copy
# VALUE.
assert "a combining mark in the slug does not smuggle in another project's path" \
  "$(yes_if no_copy_value_with 'elsewhere.md' "$DOUT")"
# THROUGH `card`, NOT `t.index('</details>')`. This is an ABSENCE claim, and the old
# boundary made it a much smaller one than it reads as: a card nests a <details> per rail
# item, so the slice ended at the first ask and said nothing about the rest of the card. A
# panel rendered just past that point satisfied it.
assert "…and that project gets no deliverables panel at all" \
  "$(card "$DOUT" 'Hostile slug' | fhasnt_in 'class="delivs"')"
# Not a second `Deliverables · 3` grep — that was byte-identical to the assertion above
# and could not fail independently of it. Counting the BUTTONS is the half the heading
# cannot certify: heading and list are built from the same filtered sequence, so a
# desync between them is exactly what a count of one and not the other would miss.
DELIV_BTNS="$(grep -oF 'data-what="Deliverable path"' "$DOUT" | grep -c . || true)"
assert "…and the buttons themselves number 3, matching that heading (saw $DELIV_BTNS)" \
  "$(eq "$DELIV_BTNS" 3)"
echo "== absent/empty deliverable_paths renders no panel, and no error =="
# The exit code itself, not file non-emptiness — a renderer that wrote partial output
# and then failed would still pass a `test -s` check.
assert "it still exits 0"                             "$(eq "$rc4" 0)"
assert "…and produces non-empty output"               "$(yes_if test -s "$DOUT")"
assert "no deliverables panel for a project with none" \
  "$(card "$DOUT" 'Closed with nothing stamped' | fhasnt_in 'class="delivs"')"
echo "== it reuses the ONE existing clipboard helper — no second <script> =="
# -c counts LINES, not occurrences — a second <script> on the SAME line as the first
# would still read 1 and pass. -o prints one match per line, so piping to `wc -l` counts
# occurrences regardless of how many share a line.
assert "exactly one <script> element on this page too" \
  "$(eq "$(grep -oF '<script' "$DOUT" | wc -l | tr -d ' ')" 1)"

echo "== collapsing is still <details>, and no script drives it =="
# A SCRIPT-DRIVEN VERSION WAS TRIED AND REJECTED BEFORE, so this is a constraint rather
# than a preference — and the page carries a <script> for the clipboard, which is exactly
# what makes "no script drives the collapsing" a thing that can rot quietly. So it is
# asserted on the script's BODY: the one function on this page must not know that
# <details> exists.
board_script() { # <file> -> the body of the single <script> element
  python3 - "$1" <<'PYS'
import re, sys
m = re.search(r"<script>(.*?)</script>", open(sys.argv[1], encoding="utf-8").read(), re.S)
sys.stdout.write(m.group(1) if m else "")
PYS
}
for f in "$OUT" "$BOUT" "$TM" "$RW" "$DOUT"; do
  assert "exactly one <script> on $(basename "$f")" \
    "$(eq "$(grep -oF '<script' "$f" | wc -l | tr -d ' ')" 1)"
done
# ASSERTED ON THE CONSTRUCTS, NOT ON THE WORD. The helper's own comments discuss <details>
# at length — they have to, because the one thing it deliberately does NOT do is cancel the
# toggle, and that decision belongs where the next editor reads it. So `fhasnt 'details'`
# would be red on a correct file for the wrong reason. These are the only ways a script can
# drive a <details>, and not one of them appears in prose.
for k in ".open=" ".open =" "toggleAttribute" "querySelector('details" "closest('details" "setAttribute('open" "removeAttribute('open"; do
  assert "the script never does: $k"                 "$(board_script "$RW" | fhasnt_in "$k")"
done
# NON-VACUITY, both halves: the extractor really returned the helper (not an empty string
# that trivially contains none of the above), and the same check FLAGS a planted driver.
assert "…and that script really is the clipboard helper" "$(board_script "$RW" | fhas_in 'clipboard')"
assert "…while the same check flags a planted driver" \
  "$(printf '%s\n' "d.open=true" | fhas_in ".open=")"
# THE ROWS ARE STILL <details>-COLLAPSED. The markup is the mechanism; if it were gone the
# assertions above would be true of a page that no longer collapses at all.
assert "the cards are still <details> elements"      "$(fhas '<details class="proj' "$RW")"

echo "== the ONE clipboard helper is reused, and file:// is not re-derived =="
# `navigator.clipboard` DOES work over file:// — Chromium treats `file:` as potentially
# trustworthy — measured during ai-bridge#74 and deliberately not re-measured here. What
# this pins is that the settled shape is still the shipped one and that nobody added a
# SECOND helper beside it: one async write, one legacy fallback, on the whole page.
# THE CALL, not the name — `navigator.clipboard.writeText` appears twice on a correct page,
# once in the capability GUARD and once in the call it guards, so counting the name counts
# the guard as a second helper.
assert "one navigator.clipboard write, not two"      \
  "$(eq "$(grep -oF 'navigator.clipboard.writeText(' "$RW" | wc -l | tr -d ' ')" 1)"
assert "…and one legacy fallback behind it"          \
  "$(eq "$(grep -oF "document.execCommand('copy')" "$RW" | wc -l | tr -d ' ')" 1)"
# THE NEW CONTROLS USE IT RATHER THAN BRINGING THEIR OWN. Both of this task's new/moved
# buttons copy through the same [data-copy] convention — a promote control with its own
# onclick would be the second helper this criterion forbids.
assert "the promote control copies via [data-copy]"  "$(fhas 'class="promote" data-copy=' "$RW")"
assert "…and the unnumbered Q handle does too"       "$(fhas 'class="qbtn nonum" data-copy=' "$QN")"
assert "no inline handler anywhere on the page"      "$(fhasnt 'onclick=' "$RW")"

echo "== no slice in this file cuts a card at the first nested </details> =="
# THE TRAP THIS GUARDS, recorded in task-015's doc: a card now nests a <details> per rail
# item, so `t.index('</details>', i)` ends the slice at the FIRST ask. An absence asserted
# that way reads a few hundred bytes and reports green on a page that is wrong immediately
# after them. `card()` ends a card where the NEXT card begins instead.
#
# A SCAN, not a promise, because the boundary is retyped at every new call site and the
# failure is invisible in review — the assertion still passes, it just stops meaning what
# it says.
# THE NEEDLE IS ASSEMBLED, NOT TYPED, and the planted offender below is built from the same
# piece. A scanner whose own body — or whose own fixture line — contains the pattern it scans
# for reports a permanent offender, and a check that is red on a correct file is a check
# somebody deletes. Splitting the literal keeps both lines from matching.
CLOSE_TAG="</de""tails>"
slice_offenders() { # <file> -> offending lines, if any
  grep -nE "(index|find)\\('$CLOSE_TAG'" "$1" | grep -v '^[0-9]*:[[:space:]]*#' || true
}
assert "no </details> slice boundary survives here"  "$(eq "$(slice_offenders "$0")" '')"
# NON-VACUITY: the same scan must find a planted one, or it is asserting nothing.
PLANT="$TMP/planted-slice.sh"
printf '%s\n' "j = t.index('$CLOSE_TAG', i)" > "$PLANT"
assert "…and the same scan flags a planted one"      \
  "$([ -n "$(slice_offenders "$PLANT")" ] && echo 0 || echo 1)"
# AND THE HELPER REALLY SPANS THEM. The scan above says nobody uses the bad boundary; this
# says the good one reaches past the rail — `$TM`'s first card nests a <details> per ask,
# and the task TABLE is rendered after the rail closes, so a slice that stopped at the
# first ask could not contain it.
assert "a card slice reaches past its nested asks"   \
  "$(card "$TM" 'Terminal and live' | fhas_in '<table')"
assert "…and the rail it had to cross really nests one" \
  "$(rail_of "$TM" 'Terminal and live' | fhas_in '<details')"

echo "== both themes are defined on bare :root =="
assert "no token defined only in a media/theme block" "$(yes_if python3 -c "
import re,sys
css=open('$OUT').read()
root=set(re.findall(r'--([a-z0-9-]+)\s*:', re.search(r':root\{(.*?)\}', css, re.S).group(1)))
allt=set(re.findall(r'--([a-z0-9-]+)\s*:', css))
sys.exit(0 if not (allt-root) else 1)")"
assert "body paints its own background"               "$(fhas 'background:var(--ground)' "$OUT")"

echo "== absence is safe =="
mkdir -p "$TMP/nosnap"
rc2=0; bash "$GEN" --out "$TMP/none.html" "$TMP/nosnap" >/dev/null 2>&1 || rc2=$?
assert "an instance with no snapshot exits 0"        "$(eq "$rc2" 0)"
assert "…and writes nothing"                         "$(fhasnt x "$TMP/none.html" 2>/dev/null || echo 0)"

echo "== --out creates its directory, but only when there is something to write =="
# THE TICK RENDERS TO `.board-live/board.html`, a directory that exists on a machine
# which has run watch-board.sh and on no other. A renderer that raised FileNotFoundError
# the first time each tick called it would be a board nobody ever sees — so the parent is
# created here rather than in every caller.
rcd=0; bash "$GEN" --standalone --out "$TMP/fresh/deeper/board.html" "$TMP/alpha" >/dev/null 2>&1 || rcd=$?
assert "a missing --out directory is created"        "$(eq "$rcd" 0)"
assert "…and the page is written into it"            "$(yes_if test -s "$TMP/fresh/deeper/board.html")"
# The other half, and the one that keeps "absence is safe" above true: an instance that
# is off the board must leave no trace at all, so the mkdir sits AFTER the nothing-to-write
# exit rather than beside the argument parsing.
rcd2=0; bash "$GEN" --out "$TMP/untouched/board.html" "$TMP/nosnap" >/dev/null 2>&1 || rcd2=$?
assert "…while a board with no snapshot exits 0"     "$(eq "$rcd2" 0)"
assert "…and creates no directory at all"            "$(yes_if test ! -e "$TMP/untouched")"

echo "== one drifted instance must not blank the board =="
mkdir -p "$TMP/bad/$AB_DIR"; printf 'not json at all\n' > "$TMP/bad/$AB_SNAPSHOT"
rc3=0; bash "$GEN" --out "$TMP/mixed.html" "$TMP/bad" "$TMP/alpha" >/dev/null 2>&1 || rc3=$?
assert "a broken snapshot is skipped, not fatal"     "$(eq "$rc3" 0)"
assert "…and the good instance still renders"        "$(fhas 'Alpha Bridge Board' "$TMP/mixed.html")"
assert "…and it is a VISIBLE note, not a silent absence" "$(fhas 'Unreadable snapshot' "$TMP/mixed.html")"
assert "…naming the instance by directory NAME"      "$(fhas "bad/$AB_SNAPSHOT" "$TMP/mixed.html")"
assert "…and never by its path"                      "$(fhasnt "$TMP/bad" "$TMP/mixed.html")"
# THE OTHER HALF, and the one this layout did not have before the consolidation: valid
# JSON carrying wrong TYPES. `"tasks":"three"` parses, so nothing above catches it — the
# string was then iterated as a list of task dicts and `.get` raised AttributeError,
# which meant NO FILE WAS WRITTEN AT ALL. One drifted instance blanked the published
# board for every healthy one. Measured against the pre-consolidation script; it is why
# every count and every container here goes through toint()/tolist()/todict().
mkdir -p "$TMP/drift"
drift_case() { # <label> <snapshot json>
  printf '%s\n' "$2" > "$TMP/drift/$AB_SNAPSHOT"
  # Removed first: a page left behind by the previous case would satisfy the
  # "still renders" half even if this case wrote nothing at all.
  rm -f "$TMP/drift.html"
  local rc=0 out
  out="$(bash "$GEN" --out "$TMP/drift.html" "$TMP/alpha" "$TMP/drift" 2>&1)" || rc=$?
  assert "$1: exits 0"                           "$(eq "$rc" 0)"
  assert "$1: no traceback"                      "$(grep -qF Traceback <<<"$out" && echo 1 || echo 0)"
  # alpha's own project, not the page title: with two instances on the board the title
  # is the generic "Bridge Board", so asserting on it would prove nothing about alpha.
  assert "$1: the healthy instance still renders" "$(fhas 'Live work' "$TMP/drift.html")"
}
drift_case "tasks is not a list" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":"three"}]}'
drift_case "projects is not a list" \
  '{"group":"drift","counts":{"tasks":"many"},"projects":"lots"}'
drift_case "a non-numeric phase total" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":"two","done":"one"},"tasks":[]}]}'
drift_case "a task is a string, not an object" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":["oops"]}]}'
# A NUMERIC task id, on a task the decision rail renders. Found by reading this diff, not
# by any of the cases above: the rail concatenated the id with a string, so `"id": 5`
# raised TypeError and wrote no file at all — the same one-instance-blanks-the-board
# failure, reached through the one field that was still handled raw.
drift_case "a task id is a number" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[{"id":5,"title":"numeric id","status":"draft","awaiting":"approve","open_questions":0}]}]}'
rm -rf "$TMP/drift"

echo "== an absurd question count cannot render forever =="
# toint() cannot catch this one: the type is right and the value is absurd. A button per
# question means a nine-digit count renders for hours and produces a page nobody can
# open, so the count is capped. Runs with a timeout because the failure mode IS the hang.
mk "$TMP/manyq" "manyq" '[
 {"slug":"p","title":"Question flood","kind":"build","status":"active","awaiting_close":false,
  "phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Absurd count","status":"draft","assignee":"",
            "awaiting":"answer","open_questions":900000000,"advisor_notes":0,
            "depends_on":[],"in_flight":false,"prs":[]}]}]'
QOUT="$TMP/manyq.html"
qrc=0
( bash "$GEN" --out "$QOUT" "$TMP/manyq" >/dev/null 2>&1 ) &
qpid=$!
for _ in $(seq 1 30); do kill -0 "$qpid" 2>/dev/null || break; sleep 1; done
if kill -0 "$qpid" 2>/dev/null; then kill -9 "$qpid" 2>/dev/null; qrc=1; fi
wait "$qpid" 2>/dev/null || true
assert "the page renders instead of hanging"         "$(eq "$qrc" 0)"
assert "…and it was written"                         "$(yes_if test -s "$QOUT")"
# THE COUNT NO LONGER PRODUCES LABELS AT ALL, which is a stronger answer to the same
# hazard than the cap was: with no question text carried there is nothing to number, so
# one honest unnumbered handle is emitted whatever the count says. Nine digits and one
# digit render the same page.
assert "…with one honest unnumbered handle"          "$(fhas '>?</button>' "$QOUT")"
assert "…and no fabricated first question"           "$(fhasnt 'Q1</button>' "$QOUT")"
assert "…and no fabricated twenty-fifth either"      "$(fhasnt 'Q25</button>' "$QOUT")"
assert "…exactly one handle, not nine hundred million" \
  "$(eq "$(grep -oF 'class="qbtn' "$QOUT" | wc -l | tr -d ' ')" 2)"

echo "== a PR URL is a link only on http/https, here too =="
mk "$TMP/hostile" "hostile" '[
 {"slug":"p","title":"Scheme check","kind":"build","status":"active","awaiting_close":false,
  "phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Two PRs, one hostile","status":"in-review","assignee":"",
            "awaiting":"","open_questions":0,"advisor_notes":0,"depends_on":[],"in_flight":false,
            "prs":[{"repo":"o/r","number":41,"url":"https://github.com/o/r/pull/41"},
                   {"repo":"o/r","number":9,"url":"javascript:alert(1)"}]}]}]'
OUT2="$TMP/scheme.html"
bash "$GEN" --out "$OUT2" "$TMP/hostile" >/dev/null 2>&1
# The other rule this layout did not carry: it wrote the snapshot's URL straight into
# the href, so a `javascript:` PR URL became a live link on a page meant for publishing.
assert "a javascript: URL is never an href"          "$(fhasnt 'href="javascript:' "$OUT2")"
assert "…and is inert text instead"                  "$(fhas 'link withheld: not http/https' "$OUT2")"
assert "…while the http PR link beside it still works" "$(fhas 'href="https://github.com/o/r/pull/41"' "$OUT2")"

echo "== flags =="
assert "an unknown flag is refused"                  "$(yes_if bash -c "bash '$GEN' --nope 2>/dev/null; [ \$? -eq 2 ]")"
assert "--help prints the header"                    "$(yes_if grep -q 'Artifact page body' <<<"$(bash "$GEN" --help 2>&1)")"

echo "== --layout is REMOVED, and is refused by name =="
# WHY A REFUSAL AND NOT AN IGNORED FLAG. Every caller that passed `--layout` was written
# when the flag chose between two DIFFERENT pages, so accepting-and-ignoring it would
# hand that caller a page it did not ask for, silently — which is the exact failure the
# deletion exists to close (the tick published `table` while watch-board.sh rendered
# `columns`). Exit 2, and say the flag was REMOVED rather than "unknown", so the stderr
# line tells a human what happened instead of looking like a typo.
for form in "--layout table" "--layout columns" "--layout=table" "--layout"; do
  assert "\`$form\` exits 2"                          "$(yes_if bash -c "bash '$GEN' $form --out '$TMP/x.html' '$TMP/alpha' 2>/dev/null; [ \$? -eq 2 ]")"
  assert "…saying the flag was REMOVED"                "$(yes_if grep -q 'was removed' <<<"$(bash "$GEN" $form --out "$TMP/x.html" "$TMP/alpha" 2>&1 >/dev/null)")"
done
assert "…and writes no page"                         "$(fhasnt x "$TMP/x.html" 2>/dev/null || echo 0)"
# The rejected page is DELETED, not merely unreachable: nothing selects it and nothing
# renders it, so the markup and its selector are both gone from the script.
assert "the kanban strip is not in the page"         "$(fhasnt 'class="cols"' "$OUT")"
assert "…and the decision rail IS"                   "$(fhas 'class="rail"' "$OUT")"
assert "…no columns renderer in the script"          "$(fhasnt 'render_columns' "$REPO/plugin/scripts/build-board.sh")"
assert "…and no layout variable to select one"       "$(fhasnt 'BOARD_LAYOUT' "$REPO/plugin/scripts/build-board.sh")"

echo "== --standalone is wrapping, not markup =="
SA="$TMP/sa.html"
bash "$GEN" --standalone --out "$SA" "$TMP/alpha" >/dev/null 2>&1
assert "--standalone opens with a doctype"           "$(yes_if grep -qF '<!doctype html>' <<<"$(head -1 "$SA")")"
assert "…with exactly one <body>"                    "$(eq "$(grep -cF '<body>' "$SA")" 1)"
assert "…the <style> in <head> and the board in <body>" "$(yes_if python3 -c "
import sys
t=open('$SA').read()
head=t[t.index('<head>'):t.index('</head>')]
body=t[t.index('<body>'):t.index('</body>')]
sys.exit(0 if '<style>' in head and 'class=\"board\"' in body and '<h1>' not in head else 1)")"
assert "…and the same markup as the page body"       "$(fhas 'class="rail"' "$SA")"

echo "== no caller anywhere in the repo passes the removed flag =="
# THE INVARIANT IS "NO CALLER", NOT "NO CALLER UNDER symlink/". The obvious check here is
# `grep -rn -- --layout symlink/`, and it would have passed on a tree carrying three live
# instructions to run the flag — README.md's command block, docs/operations.md's two
# tables, and seed/instance.config.json's own `$board` note. That is the same shape as
# the retired-renderer rot pinned at the bottom of this file: the check's SCOPE was
# narrower than the promise it stood for.
#
# It is also not a line-scoped grep. `.claude/commands/pm-loop.md` wrapped one invocation
# across a newline (`build-board.sh --layout` / `table`), so a scanner that reads a file
# line by line can miss the half of an invocation that sits on the next line. Whitespace
# is flattened first, and fixture (c) below is that exact shape.
#
# ONE scanner serves the real check and every fixture: a fixture that re-implements the
# rule proves the copy, not the shipped check.
layout_callers() { # <root> -> one path per line that INVOKES build-board.sh with --layout
  python3 - "$1" <<'PYL'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
# The only two files where the flag's NAME may still appear: the script that refuses it
# (its header records why it went, and its arg loop names it to refuse it) and this
# harness, which asserts that refusal. Neither is a caller. Nothing else is exempt.
SKIP = {"plugin/scripts/build-board.sh", "tests/artifact-board.test.sh"}
# An INVOCATION, not a mention: `build-board.sh` followed by whitespace and then only
# argument-shaped tokens up to `--layout`. Prose about the removal ("`build-board.sh`
# refuses `--layout` by name") cannot match, because a backtick is not an argument
# character and the run of tokens has to be unbroken.
INVOKE = re.compile(r"""build-board\.sh(?:\s+(?!--layout)[-\w=./$"'{}\[\]:]+){0,6}\s+--layout""")

for f in sorted(root.rglob("*")):
    if not f.is_file() or f.is_symlink():
        continue
    rel = f.relative_to(root).as_posix()
    if rel.split("/")[0].startswith(".") and rel.split("/")[0] != ".claude":
        continue
    if rel in SKIP:
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if INVOKE.search(re.sub(r"\s+", " ", text)):
        print(rel)
PYL
}
CALLERS="$(layout_callers "$REPO")"
assert "no tracked file invokes build-board.sh --layout${CALLERS:+ (saw: $(printf '%s' "$CALLERS" | tr '\n' ' '))}" \
  "$(eq "$CALLERS" "")"

# NON-VACUITY, and specifically for what a narrower check would have missed. Each fixture
# is fed to the SAME function above.
FIX="$TMP/callers"; mkdir -p "$FIX/docs"
printf 'run `scripts/build-board.sh --layout table` each tick\n'          > "$FIX/docs/a.md"
printf 'scripts/build-board.sh --out "$out" --layout table\n'             > "$FIX/b.sh"
printf 'the tick runs `scripts/build-board.sh --layout\ntable` and publishes\n' > "$FIX/docs/c.md"
FOUND="$(layout_callers "$FIX")"
for f in docs/a.md b.sh docs/c.md; do
  assert "…flags a planted caller in $f" "$(grep -qx -- "$f" <<<"$FOUND" && echo 0 || echo 1)"
done
# …and does NOT flag the two shapes that are not callers, or the guard is just a ban on
# the string and the header explaining the removal could never be written.
rm -f "$FIX/docs/a.md" "$FIX/b.sh" "$FIX/docs/c.md"
printf '`build-board.sh` refuses `--layout` by name, so a stale caller fails loudly\n' > "$FIX/docs/d.md"
printf 'scripts/build-board.sh --out "$out" --standalone\n'               > "$FIX/e.sh"
assert "…and flags neither prose about the removal nor a clean call" "$(eq "$(layout_callers "$FIX")" "")"
rm -rf "$FIX"

echo "== there is only ONE HTML renderer now =="
# path-scan: absent — asserted GONE; a resolving path here is the regression
assert "build-artifact-board.sh is gone"             "$(yes_if test ! -e "$REPO/plugin/scripts/build-artifact-board.sh")"
# The runnable form, not the name: build-board.sh's own header still explains what was
# merged into it, and a comment recording that is not a caller.
assert "…and no machinery still tells anyone to run it" "$(yes_if bash -c "! grep -rlF scripts/build-artifact-board '$REPO/symlink' >/dev/null 2>&1")"

# THE DOCS WERE THE HALF THAT ROTTED, so they are asserted too. Deleting the script and
# sweeping symlink/ left FIVE live instructions to run it: four in docs/operations.md (a
# copy-pasteable command block, the renderer comparison table, the "which renderer"
# decision table, and the paragraph under it) and one inside seed/instance.config.json's
# own `$board` explanation. Each was a reader's entry point, no test looked outside
# symlink/, and the assertion above passed the entire time.
#
# THE BARE NAME here, not the runnable form as above: prose names a script without a
# `scripts/` prefix as often as with one, and a doc has no reason to carry retired
# machinery at all — that history belongs in build-board.sh's header and in git. So the
# rule for these three trees is the simple one: don't name it.
# install.sh is deliberately NOT in this list — tests/retire-machinery.test.sh owns that
# file, beside the sweep behaviour it is about.
for tree in docs README.md seed; do
  assert "no retired renderer named in $tree" \
    "$(yes_if bash -c "! grep -rlF build-artifact-board '$REPO/$tree' >/dev/null 2>&1")"
done
# NON-VACUITY: the same expression must FIND a planted mention, or it checks nothing.
mkdir -p "$TMP/tree"; printf 'run scripts/build-artifact-board.sh\n' > "$TMP/tree/doc.md"
assert "…and the same check finds a planted one" \
  "$(yes_if bash -c "grep -rlF build-artifact-board '$TMP/tree' >/dev/null 2>&1")"
rm -rf "$TMP/tree"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
