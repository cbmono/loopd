#!/usr/bin/env bash
#
# board-renderers.test.sh — the two renderers added over the SAME snapshot the HTML
# board already reads: scripts/print-board.sh (terminal) and scripts/watch-board.sh
# (a local page kept fresh by a watcher). tests/snapshot.test.sh owns the writer and
# the HTML renderer; this file owns everything that is new.
#
# The properties that matter are the negative ones, in this order:
#   · THE OFF SWITCH IS INHERITED, NOT REIMPLEMENTED. No SNAPSHOT.json ⇒ that instance
#     is absent from the terminal board and from the live page, and NEITHER renderer
#     creates one. A renderer that resurrected the file would quietly undo
#     "delete it to take this instance off the board", which is the one promise the
#     whole feature rests on.
#   · A DRIFTED INSTANCE CANNOT BLANK THE BOARD. Valid JSON with wrong TYPES
#     (`"tasks": "many"`) is the case that already broke this once: a bare int() raised
#     before any output was produced, so one drifted instance took every healthy one
#     down with it. Each case asserts BOTH halves — this instance degrades AND the
#     healthy instance beside it still renders. A fix that dropped every instance would
#     pass the first half alone.
#   · UNTRUSTED TEXT REACHES A TERMINAL, WHICH HAS ITS OWN METACHARACTERS AND THEY ARE
#     WORSE THAN HTML'S. A title carrying ESC would clear the screen or repaint what
#     the reader has already read; a title carrying a newline would forge a row, so the
#     board would REPORT WORK THAT DOES NOT EXIST; a tab would forge a column; a bidi
#     override would reorder the line. Titles are human prose, so all four are asserted
#     as absent, and the payload is asserted present as inert text — stripped, not
#     silently dropped.
#   · COLOUR IS A TTY PROPERTY. Piped output must contain no escape byte at all, or
#     every board redirected into a file, a PR body or a ticket is corrupted. The
#     positive direction is asserted too (`--color always` DOES emit one), because
#     "no escapes" alone would pass a script that printed nothing.
#   · NUMBERS NEVER TRUNCATE. A clipped count is a WRONG number, which is worse than a
#     missing one, so narrowing drops whole all-zero columns and clips NAMES.
#   · THE WATCHER IS INTERRUPTIBLE AND LEAVES NOTHING BEHIND. Exit 0 on a signal, no
#     stamp file, no orphaned child. A watcher you cannot stop cleanly is a watcher
#     nobody starts.
#   · THE LIVE PAGE IS GITIGNORED, checked against git's own answer rather than the
#     pattern text — and on an instance whose .gitignore predates the line, which is
#     every instance that exists today.
#
# The fixture builds its own instances under mktemp, so these assertions describe this
# test's content and not whatever the real bundles hold. The hostile snapshots are
# HAND-WRITTEN on purpose: the writer cannot emit an ESC (it strips C0), and each
# renderer's defence has to hold independently of the writer's.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
WRITER="$TPL/plugin/scripts/write-snapshot.sh"
BOARD="$TPL/plugin/scripts/build-board.sh"
PRINT="$TPL/plugin/scripts/print-board.sh"
WATCH="$TPL/plugin/scripts/watch-board.sh"
BRIDGE_INSTALL="$TPL/plugin/scripts/init-bundle.sh"
for f in "$WRITER" "$BOARD" "$PRINT" "$WATCH" "$BRIDGE_INSTALL"; do
  [[ -f "$f" ]] || { echo "board-renderers.test: missing $f" >&2; exit 2; }
done
# Both renderers reach the same python3 the HTML board already requires (see
# build-board.sh's header for why JSON parsing and escaping are not awk's job). A
# machine without it cannot run the board at all, so say so rather than reporting green
# on half a feature.
command -v python3 >/dev/null 2>&1 || {
  echo "board-renderers.test: needs python3 (the board does too — see build-board.sh)." >&2; exit 2; }

# TWO STEPS, NEVER ONE — the one-expression form is DESTRUCTIVE. When $TMPDIR names a
# directory that does not exist, `mktemp -d` fails, the inner substitution of
# `TMP="$(cd "$(mktemp -d …)" && pwd)"` is empty, `cd ""` SUCCEEDS WITHOUT MOVING (a
# documented bash no-op), `pwd` returns this script's own cwd — the checkout — and the
# trap below deletes it. That happened twice on 2026-08-23. So the creation is guarded
# here, and the normalisation below is handed a path already known good.
# tests/harness-temp-safety.test.sh fails on the one-expression form anywhere in tests/.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-renderers.XXXXXX")" || {
  echo "board-renderers.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
# cd+pwd normalises the path: TMPDIR carries a trailing slash on macOS, so the raw
# mktemp result contains `//`, and a path assertion then matches nothing either way.
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

# install.sh REFUSES to run from a linked git worktree — deliberately, see its own
# header — and every role agent works in one (CONVENTIONS.md), so $TPL routinely IS one.
# Running $BRIDGE_INSTALL against $TPL as-is would trip that same guard, and the three
# calls below would silently stamp nothing, starving every assertion downstream of them
# — ai-bridge-v4/task-029. The guard is not weakened or bypassed: it is still asked the
# same question it always asks, and still answers correctly. What changes is WHERE these
# calls run it from. Re-pointing at the MAIN working tree (`git worktree list`) would
# dodge the guard but run the WRONG install.sh whenever a change — like this one —
# touches install.sh or symlink/ itself, so instead: a one-time, filesystem-level copy of
# THIS checkout (uncommitted changes included, since it copies files rather than
# `git archive`-ing a committed tree) into a directory outside any git repository at all,
# where the guard's own test (`--git-dir` vs `--git-common-dir`) cannot fire for lack of
# a repository to ask about. Skipped entirely — $BRIDGE_INSTALL stays $TPL/plugin/scripts/init-bundle.sh —
# when $TPL is already a main tree or no git repo at all, which is exactly install.sh's
# own two non-firing cases, so a plain clone pays nothing extra here.
if command -v git >/dev/null 2>&1; then
  _tpl_gd="$(git -C "$TPL" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _tpl_gc="$(git -C "$TPL" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_tpl_gd" ] && [ -n "$_tpl_gc" ] && [ "$_tpl_gd" != "$_tpl_gc" ]; then
    INSTALL_SRC="$TMP/install-src"
    # The copy below reads all of $TPL, so the destination must not live INSIDE $TPL --
    # $TMP comes from $TMPDIR, which a caller can point anywhere, including into the
    # checkout. `cp -R "$TPL"/. "$TPL/…"` copies a tree into itself. Compare resolved
    # paths and refuse rather than recurse; same abort-loudly shape as the mktemp guard
    # above (task-017), because a wrong answer here is silent and expensive.
    _tpl_res="$(cd -- "$TPL" && pwd -P)"
    _src_res="$(cd -- "$TMP" && pwd -P)"
    case "$_src_res/" in
      "$_tpl_res"/*) echo "board-renderers.test: TMPDIR ($_src_res) is inside the template tree ($_tpl_res); the install-source copy would recurse. Point TMPDIR outside the checkout." >&2; exit 2 ;;
    esac
    mkdir -p "$INSTALL_SRC"
    cp -R "$TPL"/. "$INSTALL_SRC"/
    rm -rf "$INSTALL_SRC/.git"
    BRIDGE_INSTALL="$INSTALL_SRC/plugin/scripts/init-bundle.sh"
  fi
fi

pass=0; fail=0; skip=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { grep -qF <<<"$2" -- "$1" && echo 0 || echo 1; }
hasnt()  { grep -qF <<<"$2" -- "$1" && echo 1 || echo 0; }
fhas()   { grep -qF -- "$1" "$2" && echo 0 || echo 1; }
fhasnt() { grep -qF -- "$1" "$2" && echo 1 || echo 0; }
eq()     { [[ "$1" == "$2" ]] && echo 0 || echo 1; }
# The longest line, in CHARACTERS. awk's length() counts BYTES on macOS and this output
# is full of multibyte punctuation (·, ›, —, …), so an awk version of this check reports
# a correctly-fitted table as overflowing.
maxlen() { printf '%s\n' "$1" | python3 -c 'import sys; print(max((len(l) for l in sys.stdin.read().splitlines()), default=0))'; }
fits()   { [[ "$(maxlen "$1")" -le "$2" ]] && echo 0 || echo 1; }

ESC="$(printf '\033')"

# ---------------------------------------------------------------- fixture
new_instance() { # <dir> — the minimum both renderers require of an instance root
  mkdir -p "$1" "$1/$AB_DIR"
  : > "$1/$AB_SCHEMA"
  cat > "$1/instance.config.json" <<CFG
{ "org": "fixture-org", "reposRoot": "$TMP/repos" }
CFG
}

ALPHA="$TMP/group/_ai-bridge-alpha"     # real content, written by the writer
BETA="$TMP/group/_ai-bridge-beta"       # unparseable snapshot
GAMMA="$TMP/group/_ai-bridge-gamma"     # no snapshot at all — off the board
DELTA="$TMP/group/_ai-bridge-delta"     # hand-written hostile snapshot
new_instance "$ALPHA"; new_instance "$BETA"; new_instance "$GAMMA"; new_instance "$DELTA"

mkdir -p "$ALPHA/projects/ci/tasks" "$ALPHA/projects/ci/phases"
cat > "$ALPHA/projects/ci/project.md" <<'PRJ'
---
type: Project
title: CI hardening
kind: build
status: active
---
PRJ
cat > "$ALPHA/projects/ci/phases/phase-1.md" <<'PH'
---
type: Phase
title: Groundwork
order: 1
status: done
---
PH
cat > "$ALPHA/projects/ci/phases/phase-2.md" <<'PH'
---
type: Phase
title: Rollout
order: 2
status: active
---
PH
cat > "$ALPHA/projects/ci/tasks/task-001.md" <<'TSK'
---
type: Task
title: Rotate the publish token
kind: build
status: blocked
assignee: devops-engineer
---
TSK
cat > "$ALPHA/projects/ci/tasks/task-002.md" <<'TSK'
---
type: Task
title: Bump the pinned toolchain
kind: build
status: in-review
assignee: software-engineer
pr: [ "https://github.com/acme/monorepo/pull/2725" ]
---
TSK
cat > "$ALPHA/projects/ci/tasks/task-003.md" <<'TSK'
---
type: Task
title: Cache the dependency store
kind: build
status: in-progress
assignee: software-engineer
---
TSK
# A very long title, for the clipping assertions. Long enough that no sane terminal
# width leaves it intact, so "piped output is never clipped" is a real assertion.
mkdir -p "$ALPHA/projects/verbose/tasks"
cat > "$ALPHA/projects/verbose/project.md" <<'PRJ'
---
type: Project
title: LONGTITLE-a-deliberately-overlong-project-name-that-no-terminal-width-leaves-intact-END
kind: build
status: active
---
PRJ

touch "$ALPHA/$AB_SNAPSHOT"
( cd "$ALPHA" && SNAPSHOT_NOW=2026-08-23T00:00:00Z bash "$WRITER" --quiet )

printf '{ this is not json' > "$BETA/$AB_SNAPSHOT"

# The hostile snapshot, written through json.dump so every escape is unambiguous. Each
# attack gets its OWN project, so one table row per attack and a forged row is visible
# as a row that does not begin with the instance name.
python3 - "$DELTA/$AB_SNAPSHOT" <<'PY'
import json, sys

def proj(slug, title, status="ready"):
    return {"slug": slug, "title": title, "kind": "build", "status": "active",
            "autonomy": "gated", "awaiting_close": False,
            "phase_progress": {"done": 0, "total": 0}, "phases": [],
            "tasks": [{"id": "task-001", "title": "t", "kind": "build",
                       "status": status, "assignee": "software-engineer", "phase": "",
                       "in_flight": False, "awaiting": "", "open_questions": 0,
                       "prs": []}]}

snap = {
    "group": "delta",
    "generated_at": "2026-08-23T00:00:00Z",
    "counts": {"projects": 5, "tasks": 5, "awaiting": 1},
    "projects": [
        # ESC: a clear-screen and a colour change, both of which must arrive inert.
        proj("ansi", "ANSITITLE\u001b[2J\u001b[31mPAYLOAD"),
        # A newline would forge a whole row — the board reporting work nobody has.
        proj("newline", "ROWA\nFORGEDROW"),
        # A tab would forge a column inside a row.
        proj("tab", "COLA\tCOLB"),
        # A right-to-left override reorders the line a reader is trying to trust.
        proj("bidi", "BIDIA‮BIDIB"),
        # A status outside the schema enum: counted under OTHER and named, never
        # silently dropped.
        proj("drifted", "DRIFTEDSTATUS", status="made-up-status"),
    ],
}
snap["projects"][0]["tasks"][0]["awaiting"] = "merge"
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(snap, fh)
PY

echo "== print-board: self-detecting, and silent where it does not apply =="
mkdir -p "$TMP/stranger"
S_OUT="$( cd "$TMP/stranger" && bash "$PRINT" 2>&1 )"; S_RC=$?
assert "outside an instance root -> exits 0"        "$(eq "$S_RC" 0)"
assert "…and prints absolutely nothing"             "$(eq "$S_OUT" "")"
assert "…and creates no file there"                 "$(no_if test -e "$TMP/stranger/$AB_SNAPSHOT")"

echo
echo "== print-board: bad flags refuse rather than guess =="
for bad in --nope --width=x --color=purple; do
  RC=0; OUT="$( cd "$ALPHA" && bash "$PRINT" "$bad" 2>&1 >/dev/null )" || RC=$?
  assert "'$bad' exits 2"           "$(eq "$RC" 2)"
  assert "…and says so on stderr"   "$(no_if test -z "$OUT")"
done

echo
echo "== print-board: the off switch, and a broken instance cannot blank the board =="
OUT="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" "$BETA" "$GAMMA" "$DELTA" 2>"$TMP/pb.err" )"; RC=$?
ERR="$(cat "$TMP/pb.err")"
assert "exits 0 with a malformed snapshot in the list" "$(eq "$RC" 0)"
assert "the healthy instance renders"                  "$(has 'CI hardening' "$OUT")"
assert "…and so does the hostile one beside it"        "$(has 'delta' "$OUT")"
assert "gamma has no snapshot, so it is absent"        "$(hasnt 'gamma' "$OUT")"
assert "…and the reason is on stderr, not on the board" "$(has 'off the board' "$ERR")"
assert "beta is a VISIBLE note, not a silent absence"  "$(has "unreadable $AB_SNAPSHOT" "$OUT")"
assert "…naming the instance by directory NAME"        "$(has '_ai-bridge-beta' "$OUT")"
assert "…and not by its path"                          "$(hasnt '/_ai-bridge-beta' "$OUT")"
assert "…telling the human what to re-run"             "$(has 'write-snapshot.sh' "$OUT")"
assert "no filesystem path reaches the output"         "$(hasnt "$TMP" "$OUT")"
assert "neither renderer created gamma's snapshot"     "$(no_if test -e "$GAMMA/$AB_SNAPSHOT")"
assert "an out-of-enum status is counted under OTHER"  "$(has 'OTHER' "$OUT")"
assert "…and named, so drift is visible"               "$(has 'made-up-status' "$OUT")"

echo
echo "== print-board: untrusted text at a TERMINAL sink =="
assert "ZERO escape bytes in the output"        "$(hasnt "$ESC" "$OUT")"
assert "an ESC title arrives as inert text"     "$(has 'ANSITITLE[2J[31mPAYLOAD' "$OUT")"
# A forged row would be a line that does not start with the instance name. Asserting
# the two halves land on the SAME line is what proves the newline could not split it.
FORGED_LINE="$(printf '%s\n' "$OUT" | grep -F 'FORGEDROW' || true)"
assert "a newline in a title cannot forge a row" "$(has 'ROWA FORGEDROW' "$FORGED_LINE")"
assert "…and that row still starts with the instance" "$(yes_if grep -q '^delta ' <<<"$FORGED_LINE")"
assert "a tab in a title cannot forge a column"  "$(has 'COLA COLB' "$OUT")"
assert "…and no tab survives into the output"    "$(hasnt "$(printf '\t')" "$OUT")"
assert "a bidi override is stripped"             "$(hasnt "$(printf '\342\200\256')" "$OUT")"
assert "…and its text survives around it"        "$(has 'BIDIABIDIB' "$OUT")"
# One row per project, counted off the instance column: a forged row would make six.
assert "delta renders exactly 5 rows, one per project" \
  "$(eq "$(printf '%s\n' "$OUT" | grep -c '^delta ' || true)" 5)"

echo
echo "== print-board: colour is a TTY property =="
assert "piped output carries no escape byte" "$(hasnt "$ESC" "$( cd "$ALPHA" && bash "$PRINT" 2>/dev/null )")"
# The positive direction, so the assertion above cannot pass on a script that prints
# nothing: forced colour DOES emit one.
assert "--color always does emit one"        "$(has "$ESC" "$( cd "$ALPHA" && bash "$PRINT" --color always 2>/dev/null )")"
assert "--no-color suppresses it again"      "$(hasnt "$ESC" "$( cd "$ALPHA" && bash "$PRINT" --color always --no-color 2>/dev/null )")"
# A truecolor escape is 19 bytes; counted as width, it wrapped the footnote ~15 columns early.
for w in 100 40; do
  assert "colour moves no line break: --color always, SGR stripped, is --color never (width $w)" \
    "$(eq "$( cd "$ALPHA" && COLORTERM=truecolor bash "$PRINT" --color always --width "$w" 2>/dev/null \
               | LC_ALL=C sed "s/${ESC}\[[0-9;]*m//g" )" \
          "$( cd "$ALPHA" && bash "$PRINT" --color never --width "$w" 2>/dev/null )")"
done
# NO_COLOR can only be observed with a real TTY, since a pipe is already colourless.
# The pty comes from python3's stdlib rather than script(1): script's arguments differ
# between BSD and GNU, and whether it can allocate a terminal at all depends on how this
# harness was launched — which made the assertion COUNT drift between runs. python3 is
# already a hard requirement of the board, so this costs nothing and always runs.
tty_out() { # <cmd...> -> the command's output, with its stdout on a real terminal
  ( cd "$ALPHA" && python3 -c 'import pty,sys; sys.exit(pty.spawn(sys.argv[1:]))' "$@" 2>/dev/null )
}
assert "on a TTY, colour is on by default" "$(has "$ESC" "$(tty_out bash "$PRINT" --width 100)")"
assert "…and NO_COLOR turns it off"        "$(hasnt "$ESC" "$(NO_COLOR=1 tty_out bash "$PRINT" --width 100)")"
assert "…while NO_COLOR= (empty) does not" "$(has "$ESC" "$(NO_COLOR= tty_out bash "$PRINT" --width 100)")"
assert "…and --color always beats NO_COLOR, as documented" \
  "$(has "$ESC" "$(NO_COLOR=1 tty_out bash "$PRINT" --color always --width 100)")"

echo
echo "== print-board: a narrow terminal degrades, and no NUMBER is ever clipped =="
WIDE="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" 2>/dev/null )"
assert "unlimited width prints the table"          "$(has 'INSTANCE  PROJECT' "$WIDE")"
assert "…with every enum column"                   "$(yes_if grep -q 'DRAFT READY PROG REVIEW BLOCK DONE CANC' <<<"$WIDE")"
assert "…and an unclipped long title (a pipe is not narrow)" "$(has 'LONGTITLE-a-deliberately-overlong-project-name-that-no-terminal-width-leaves-intact-END' "$WIDE")"
N80="$( cd "$ALPHA" && bash "$PRINT" --width 80 "$ALPHA" 2>/dev/null )"
assert "at 80 columns it is still a table"         "$(has 'INSTANCE' "$N80")"
assert "…no line exceeds the width"                "$(fits "$N80" 80)"
assert "…the long title is clipped with an ellipsis" "$(has '…' "$N80")"
assert "…all-zero columns are dropped to make room" "$(has 'omitted to fit the width' "$N80")"
assert "…a column that was dropped had a zero total" "$(hasnt 'CANC' "$N80")"
assert "…AWAIT is never dropped"                    "$(has 'AWAIT' "$N80")"
# The counts must be identical at every width: dropping a zero column hides nothing,
# and a clipped number would be a wrong number.
# Every non-zero number on a row must survive narrowing unchanged. Dropping a column
# of zeros hides no work; clipping a count would report a WRONG number, and the two are
# indistinguishable on the page unless something compares them.
nonzero() { printf '%s\n' "$1" | grep -F 'CI hardening' | grep -oE '[0-9]+' | grep -v '^0$' | tr '\n' ' '; }
assert "every non-zero count survives narrowing unchanged" "$(eq "$(nonzero "$N80")" "$(nonzero "$WIDE")")"
assert "…and there was something to compare"               "$(no_if test -z "$(nonzero "$WIDE")")"
NARROW="$( cd "$ALPHA" && bash "$PRINT" --width 34 "$ALPHA" 2>/dev/null )"
assert "below the table's minimum it becomes a list" "$(hasnt 'INSTANCE' "$NARROW")"
assert "…with a labelled block per project"          "$(has 'phases' "$NARROW")"
# The property is the full enum name rather than the table's abbreviation ("REVIEW").
# Not "in-review 1": the block wraps at the width, so the name and its count can
# legitimately land on different lines, and asserting the pair makes the test fail for
# a formatting reason that has nothing to do with the property.
assert "…naming statuses in full, not as column headers" "$(has 'in-review' "$NARROW")"
assert "…and not the abbreviation"                       "$(hasnt 'REVIEW' "$NARROW")"
assert "…and no line exceeds the width"              "$(fits "$NARROW" 34)"

echo
echo "== print-board: a drifted snapshot cannot blank the board =="
# THE MAJOR CASE. Valid JSON, wrong TYPES — the malformed path above never sees these,
# and a bare int() would raise before a single line was printed, taking the healthy
# instance down too. Both halves are asserted for every case.
DRIFT="$TMP/group/_ai-bridge-drift"
mkdir -p "$DRIFT" "$DRIFT/$AB_DIR"
drift_case() { # <label> <snapshot json>
  printf '%s\n' "$2" > "$DRIFT/$AB_SNAPSHOT"
  local rc=0 out
  out="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" "$DRIFT" 2>&1 )" || rc=$?
  assert "$1: exits 0"                            "$(eq "$rc" 0)"
  assert "$1: no traceback"                        "$(hasnt 'Traceback' "$out")"
  assert "$1: something was printed"               "$(has 'Bridge Board' "$out")"
  assert "$1: the healthy instance still renders"  "$(has 'CI hardening' "$out")"
}
drift_case "a non-numeric task count" \
  '{"group":"drift","counts":{"tasks":"many","projects":1,"awaiting":0},"projects":[]}'
drift_case "a non-numeric phase total" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":"two","done":"one"},"phases":[],"tasks":[]}]}'
drift_case "a non-string group" \
  '{"group":5,"counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[{"id":"t","title":"T","status":"blocked","awaiting":"unblock","open_questions":0,"prs":[]}]}]}'
drift_case "projects is not a list" \
  '{"group":"drift","counts":{"tasks":1},"projects":"lots"}'
drift_case "tasks is not a list" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":"three"}]}'
drift_case "a task is a string, not an object" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":["oops"]}]}'
# ANCHORED to the instance column: a bare `has 5` would pass on any board, since the
# counts alone print plenty of digits.
printf '%s\n' '{"group":5,"counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[]}]}' > "$DRIFT/$AB_SNAPSHOT"
D5="$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" "$DRIFT" 2>/dev/null )"
assert "a non-string group becomes the row's instance cell" \
  "$(yes_if grep -q '^5  *Drifted' <<<"$D5")"
rm -rf "$DRIFT"

echo
echo "== discovery is explicit, never a glob (both new scripts ask build-board) =="
D1="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )"
assert "no args, no boardInstances -> just this instance" "$(has '1 instance(s)' "$D1")"
assert "…and the output says where the list came from"    "$(has 'this instance' "$D1")"
python3 - "$ALPHA/instance.config.json" "$DELTA" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["boardInstances"] = [".", sys.argv[2]]
json.dump(d, open(p, "w"), indent=2)
PY
D2="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )"
assert "boardInstances is used when no dirs are named"    "$(has '2 instance(s)' "$D2")"
assert "…and is named as the source"                      "$(has 'boardInstances' "$D2")"
assert "named dirs override the config"                   "$(has '1 instance(s)' "$( cd "$ALPHA" && bash "$PRINT" "$DELTA" 2>&1 )")"
LIST="$( cd "$ALPHA" && bash "$BOARD" --list-instances 2>/dev/null )"
assert "--list-instances resolves the same two"           "$(eq "$(printf '%s\n' "$LIST" | grep -c . )" 2)"
assert "…as paths, one per line"                          "$(has "$DELTA" "$LIST")"
assert "…and writes no board file"                        "$(no_if test -e "$ALPHA/board.html")"
LIST2="$( cd "$ALPHA" && bash "$BOARD" --list-instances "$GAMMA" 2>/dev/null )"
assert "…and named dirs still win there"                  "$(eq "$LIST2" "$GAMMA")"
printf 'not json at all' > "$ALPHA/instance.config.json"
D3="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )"
assert "an unreadable config falls back to this instance"  "$(has '1 instance(s)' "$D3")"
assert "…and says so"                                      "$(has 'unreadable' "$D3")"
assert "…with no traceback"                                "$(hasnt 'Traceback' "$D3")"
for shape in '["a","b"]' '"just-a-string"' '5' 'null' 'true'; do
  printf '%s\n' "$shape" > "$ALPHA/instance.config.json"
  RC=0; OUT2="$( cd "$ALPHA" && bash "$PRINT" 2>&1 )" || RC=$?
  assert "a config whose top level is $shape falls back, exit 0" "$(eq "$RC" 0)"
  assert "…rendering just this instance"  "$(has '1 instance(s)' "$OUT2")"
  assert "…with no traceback"             "$(hasnt 'Traceback' "$OUT2")"
done
new_instance "$ALPHA"   # restore a clean config

echo
echo "== watch-board: self-detecting, and silent where it does not apply =="
W_OUT="$( cd "$TMP/stranger" && bash "$WATCH" --once 2>&1 )"; W_RC=$?
assert "outside an instance root -> exits 0"  "$(eq "$W_RC" 0)"
assert "…and prints absolutely nothing"       "$(eq "$W_OUT" "")"
assert "…and creates no output directory"     "$(no_if test -e "$TMP/stranger/$AB_BOARD_DIR")"
for bad in --nope --interval=0 --interval=x; do
  RC=0; ( cd "$ALPHA" && bash "$WATCH" "$bad" >/dev/null 2>&1 ) || RC=$?
  assert "'$bad' exits 2" "$(eq "$RC" 2)"
done

echo
echo "== watch-board --once: one render, into a gitignored directory =="
O_OUT="$( cd "$ALPHA" && bash "$WATCH" --once "$ALPHA" "$BETA" "$GAMMA" 2>&1 )"; O_RC=$?
PAGE="$ALPHA/$AB_BOARD_DIR/board.html"
assert "exits 0"                                  "$(eq "$O_RC" 0)"
assert "…and says what it rendered"               "$(has 'rendered' "$O_OUT")"
assert "the page is written"                      "$(yes_if test -s "$PAGE")"
assert "…as a standalone document, openable directly" "$(yes_if grep -qF '<!doctype html>' <<<"$(head -1 "$PAGE")")"
assert "…rendering the healthy instance"          "$(fhas 'CI hardening' "$PAGE")"
assert "…and the malformed one as a visible note" "$(fhas 'Unreadable snapshot' "$PAGE")"
assert "an instance with no snapshot is absent"   "$(fhasnt '_ai-bridge-gamma' "$PAGE")"
assert "…and its snapshot was NOT created"        "$(no_if test -e "$GAMMA/$AB_SNAPSHOT")"
assert "the mtime stamp is cleaned up"            "$(no_if test -e "$ALPHA/$AB_BOARD_DIR/.watch-stamp")"
assert "nothing else is left in the output dir"   "$(eq "$(ls -A "$ALPHA/$AB_BOARD_DIR" | grep -c . )" 1)"
# It refreshes the snapshot before rendering, so the page reflects the DOCUMENTS rather
# than the last /pm-loop tick. A new task must appear without running the writer.
cat > "$ALPHA/projects/ci/tasks/task-004.md" <<'TSK'
---
type: Task
title: NEWTASK-added-since-the-last-snapshot
kind: build
status: ready
---
TSK
( cd "$ALPHA" && bash "$WATCH" --once "$ALPHA" >/dev/null 2>&1 )
assert "--once refreshes the snapshot first"      "$(fhas 'NEWTASK-added-since-the-last-snapshot' "$PAGE")"
# The terminal board is project-level — task TITLES never appear on it, only counts —
# so the refreshed snapshot shows up as a task total, and that is what to assert.
assert "…and the terminal board counts it too"   "$(has '4 task(s)' "$( cd "$ALPHA" && bash "$PRINT" --width 0 "$ALPHA" 2>/dev/null )")"

echo
echo "== watch-board: the watch mechanism is probed, and degrades to a declared poll =="
# No `timeout` here: it is GNU coreutils and absent from a stock macOS, which is the
# machine this suite is run on. Start the watcher in the background, let it announce
# itself, then signal it — which also exercises the interrupt path a second time.
STUBDIR="$TMP/stub"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/fswatch" <<'STUB'
#!/bin/sh
# Stand-in for fswatch: block until killed. The watcher's fswatch branch is then
# exercised on a machine that does not have the real binary — which is most of them,
# and precisely why the fallback exists.
while :; do sleep 1; done
STUB
chmod +x "$STUBDIR/fswatch"
# Poll for a NEEDLE rather than sleeping a guessed duration — see `briefly` below for
# why a fixed sleep here was the actual defect, not a machine-dependent one. Ceiling of
# 200 * 0.05s = 10s so a genuinely broken watcher still fails in finite time instead of
# hanging; a healthy one resolves in well under a second.
wait_for() { # <file> <needle> [max-tries]
  local file="$1" needle="$2" tries="${3:-200}" n=0
  while (( n < tries )); do
    grep -qF -- "$needle" "$file" 2>/dev/null && return 0
    sleep 0.05
    n=$((n+1))
  done
  return 1
}
wait_for_count() { # <file> <needle> <want> [max-tries] — the needle's Nth occurrence, not its first
  local file="$1" needle="$2" want="$3" tries="${4:-200}" n=0 have
  while (( n < tries )); do
    have="$(grep -cF -- "$needle" "$file" 2>/dev/null || true)"
    (( ${have:-0} >= want )) && return 0
    sleep 0.05
    n=$((n+1))
  done
  return 1
}
briefly() { # <env-prefix...> -- run the watcher until it announces itself, then stop it
  local log="$TMP/briefly.log"; : > "$log"
  # `exec`, so the background job IS the watcher and a TERM reaches it rather than the
  # subshell that spawned it. Getting this wrong makes the signal assertions pass for
  # the wrong reason — the subshell dies, the watcher is orphaned, and its exit status
  # is never read.
  ( cd "$ALPHA" && exec env "$@" bash "$WATCH" --interval 1 "$ALPHA" ) >"$log" 2>&1 &
  local p=$!
  # THE BOUND GOES ON THE CHILD, because this child never exits on its own: it is a watch
  # loop, and the `kill -TERM` below only runs if THIS harness survives to reach it. A CI
  # timeout, a spend limit or a plain SIGKILL leaves the watcher reparented to pid 1,
  # re-rendering a board every second forever — the failure `CONVENTIONS.md` → "Anything you
  # background must be reaped by something that outlives YOU" is written from. The watchdog
  # is a SIBLING, so it fires whether or not we are here, and `sleep` bounds the watchdog
  # itself. 120s is ~20x the measured announce-and-stop time, so it never fires in a healthy
  # run; the kill after `wait` retires it the moment the watcher is actually gone.
  # `>/dev/null` on the watchdog is load-bearing: killing it leaves its own `sleep` behind,
  # and a `sleep` holding this harness's stdout blocks the `out=$(bash …)` the CI loop reads
  # it through — a finished harness that looks like a 2-minute hang.
  ( sleep 120; kill -TERM "$p" 2>/dev/null ) >/dev/null 2>&1 &
  local wd=$!
  # This used to be a fixed `sleep 2`, racing the initial render — a real subprocess
  # chain (write-snapshot.sh, then build-board.sh) whose duration is host- and
  # load-dependent, not a constant. Under load the message below hadn't been printed
  # yet when the 2s elapsed, and every assertion reading $log came back empty. The
  # announcement line is printed on EVERY branch (poll, fswatch, or the fswatch-asked-
  # for-but-absent fallback) right after the mechanism is decided, so waiting for it
  # is the actual event to wait for rather than a guess at how long it takes.
  wait_for "$log" "in a browser and reload it" 200 || true
  kill -TERM "$p" 2>/dev/null || true
  wait "$p" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  cat "$log"
}
POLL_MSG="$(briefly WATCH_BOARD_WATCHER=poll)"
assert "forced polling says so, and how often"               "$(has 'polling 1 path(s) every 1s' "$POLL_MSG")"
FS_MSG="$(briefly WATCH_BOARD_WATCHER=auto PATH="$STUBDIR:$PATH")"
assert "with fswatch on PATH the probe picks it"             "$(has 'with fswatch' "$FS_MSG")"
assert "…and does not claim to be polling"                   "$(hasnt 'polling' "$FS_MSG")"
assert "…and it still stops cleanly"                         "$(has 'stopped. The page is still at' "$FS_MSG")"
assert "…leaving no fswatch child behind"                    "$(no_if pgrep -f "$STUBDIR/fswatch")"
FS_ASK="$(briefly WATCH_BOARD_WATCHER=fswatch PATH="/usr/bin:/bin")"
assert "asking for an absent fswatch falls back, saying why" "$(has 'asked for but is not installed' "$FS_ASK")"
# Forced absent via PATH, same as the FS_ASK case above — never asked of the host with a
# bare `command -v fswatch`. This used to skip itself on any machine that happens to have
# fswatch installed, which means the "auto, no fswatch" branch went completely untested
# on exactly the runners most likely to have it (a dev laptop with it brewed in). Both
# branches must run everywhere, or CI coverage depends on which machine picks up the job.
assert "the bare probe on a machine without fswatch polls" \
  "$(has 'fswatch not found' "$(briefly WATCH_BOARD_WATCHER=auto PATH="/usr/bin:/bin")")"
RC=0; ( cd "$ALPHA" && WATCH_BOARD_WATCHER=nonsense bash "$WATCH" --once >/dev/null 2>&1 ) || RC=$?
assert "an unknown WATCH_BOARD_WATCHER refuses rather than guessing" "$(eq "$RC" 2)"


echo
echo "== watch-board: it re-renders on a change, and stops cleanly =="
rm -rf "$ALPHA/$AB_BOARD_DIR"
# `exec` again: the background job must BE the watcher, or `wait` below reads the
# subshell's status instead of the watcher's and the exit-0-on-TERM assertion is vacuous.
( cd "$ALPHA" && exec bash "$WATCH" --interval 1 "$ALPHA" ) >"$TMP/watch.log" 2>&1 &
WPID=$!
# Same bound as `briefly` above, and for the same reason: this section drives the watcher
# through a change and a TERM, and every one of those steps is reached only if this harness
# is still alive. See the comment there.
( sleep 300; kill -TERM "$WPID" 2>/dev/null ) >/dev/null 2>&1 &
WATCHDOG=$!
# Same defect as `briefly` above, same fix: wait for the render to actually land in the
# log instead of a fixed sleep racing it. A `sleep 2` here is exactly the assertion below
# it — "has rendered once already" — turned into a guess about how long that takes.
wait_for "$TMP/watch.log" "rendered" 200 || true
assert "the watcher is running"                 "$(yes_if kill -0 "$WPID")"
assert "…and has rendered once already"         "$(fhas 'rendered' "$TMP/watch.log")"
assert "…leaving its stamp file in place"       "$(yes_if test -e "$ALPHA/$AB_BOARD_DIR/.watch-stamp")"
BEFORE="$(grep -c 'rendered' "$TMP/watch.log" || true)"
cat > "$ALPHA/projects/ci/tasks/task-005.md" <<'TSK'
---
type: Task
title: WATCHED-CHANGE-appeared-while-watching
kind: build
status: ready
---
TSK
# The same defect the two waits above already fixed, in the one hunk that still had it:
# `sleep 4` is the assertion below turned into a guess about how long a re-render takes,
# and on a loaded runner it loses — this is the pair that went red in CI at 9fdd8db while
# passing on every laptop. The watcher writes the page BEFORE it logs `rendered`, so
# waiting on the count carries the page assertion too.
wait_for_count "$TMP/watch.log" "rendered" $(( BEFORE + 1 )) 400 || true
AFTER="$(grep -c 'rendered' "$TMP/watch.log" || true)"
assert "a task-document write triggers a re-render" "$(yes_if test "$AFTER" -gt "$BEFORE")"
assert "…and the change is on the page"             "$(fhas 'WATCHED-CHANGE-appeared-while-watching' "$PAGE")"
kill -TERM "$WPID" 2>/dev/null || true
WRC=0; wait "$WPID" 2>/dev/null || WRC=$?
kill "$WATCHDOG" 2>/dev/null || true
assert "a TERM exits 0 — stopping a watcher is not a failure" "$(eq "$WRC" 0)"
assert "…saying the page is still there"            "$(fhas 'stopped. The page is still at' "$TMP/watch.log")"
assert "…removing its stamp file"                   "$(no_if test -e "$ALPHA/$AB_BOARD_DIR/.watch-stamp")"
assert "…leaving the page it produced"              "$(yes_if test -s "$PAGE")"
assert "…and no child process behind it"            "$(no_if pgrep -P "$WPID" )"

echo
echo "== the live page is gitignored — git's own answer, not the pattern text =="
assert "seed/.gitignore ignores the live directory" "$(yes_if grep -qF "$AB_BOARD_DIR" "$TPL/plugin/seed/.gitignore")"
INST="$TMP/group/_ai-bridge-stamped"
mkdir -p "$INST"
( cd "$INST" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$INST" >/dev/null 2>&1 </dev/null
mkdir -p "$INST/$AB_BOARD_DIR" && : > "$INST/$AB_BOARD_DIR/board.html" && : > "$INST/$AB_BOARD_DIR/probe.txt"
assert "a FRESH stamp ignores the page" \
  "$(yes_if git -C "$INST" check-ignore -q "$AB_BOARD_DIR"/board.html)"
# The probe file, not board.html: the seed carries a bare `board.html` line that matches
# at ANY depth, so board.html inside the directory is ignored either way and cannot show
# whether the DIRECTORY line is present. A test that cannot fail is worse than none.
assert "…and the whole directory, not just the page" \
  "$(yes_if git -C "$INST" check-ignore -q "$AB_BOARD_DIR"/probe.txt)"
# The case that actually matters: every instance in existence was stamped before this
# directory existed, so the line has to reach an OLD .gitignore too.
OLD="$TMP/group/_ai-bridge-old"
mkdir -p "$OLD"
( cd "$OLD" && git init -q . ) 2>/dev/null || true
bash "$BRIDGE_INSTALL" "$OLD" >/dev/null 2>&1 </dev/null
python3 - "$OLD/.gitignore" <<'PY'
import sys
p = sys.argv[1]
keep = [l for l in open(p).read().splitlines() if ".board-live" not in l]
open(p, "w").write("\n".join(keep) + "\n")
PY
mkdir -p "$OLD/$AB_BOARD_DIR" && : > "$OLD/$AB_BOARD_DIR/probe.txt"
assert "…and with the line removed, git no longer ignores it" \
  "$(no_if git -C "$OLD" check-ignore -q "$AB_BOARD_DIR"/probe.txt)"
bash "$BRIDGE_INSTALL" "$OLD" >/dev/null 2>&1 </dev/null
assert "…a re-run of install.sh puts it back"  "$(yes_if git -C "$OLD" check-ignore -q "$AB_BOARD_DIR"/probe.txt)"
assert "…exactly once, not once per run"       "$(eq "$(grep -cF '.board-live' "$OLD/.gitignore")" 1)"
echo
echo "== a fresh instance is named by its directory, not \".\" =="
# install.sh seeds a snapshot with an EMPTY group, and the default discovery target is
# Path("."), whose .name is empty too — so both renderers fell through and labelled the
# instance ".". Asserted here for BOTH of them, even though tests/snapshot.test.sh owns
# the HTML board otherwise: the fallback is shared, and it was fixed in one change.
FRESH_TTY="$( cd "$INST" && bash "$PRINT" --width 0 2>/dev/null )"
assert "the terminal board names the instance"     "$(yes_if grep -q '^stamped ' <<<"$FRESH_TTY")"
assert "…and never labels a row \".\""              "$(yes_if grep -qv '^\. ' <<<"$FRESH_TTY")"
( cd "$INST" && bash "$BOARD" --out "$TMP/fresh.html" >/dev/null 2>&1 )
# The HTML board puts the name in its masthead, title-cased ("stamped" -> "Stamped").
# The "." bug shows there as a LEADING SPACE, not as a dot: the title is built from
# `group.split(".")[0]`, so a group of "." would title the page " Bridge Board" — which
# looks like a stray space and reads as no instance name at all. Both halves are
# asserted, because either alone passes on the other's failure.
assert "the HTML board names it too"                "$(fhas '<h1>Stamped Bridge Board</h1>' "$TMP/fresh.html")"
assert "…and never an empty name in the masthead"   "$(fhasnt '<h1> Bridge Board' "$TMP/fresh.html")"

# ---------------------------------------------------------------------------
# THE LOOPD DUOTONE. The handoff is a set of NUMBERS — one dark palette, five grid
# tracks, one breakpoint — so what is asserted here is those numbers, read back off the
# rendered page. A design pinned in prose is a design that drifts.
#
# WHY THIS FILE AND NOT tests/artifact-board.test.sh: that one owns the page's MARKUP
# contracts (handles, escaping, what a button copies). The palette, the tab row and the
# breakpoint are the RENDERER's own output and belong beside the other renderer
# assertions here.
SLATE="$TMP/slate.html"
( cd "$ALPHA" && bash "$BOARD" --standalone --out "$SLATE" >/dev/null 2>&1 )

# The hex a token carries inside ONE declaration block, or "" — so a token defined only
# in some other block reads as absent rather than as the value it has somewhere else.
tokval() { # <file> <selector> <token-name>
  python3 - "$1" "$2" "$3" <<'PYT'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(re.escape(sys.argv[2]) + r"\{([^}]*)\}", src)
if not m:
    sys.exit(0)
v = re.search(r"--" + re.escape(sys.argv[3]) + r":\s*(#[0-9a-fA-F]{3,8})", m.group(1))
sys.stdout.write(v.group(1) if v else "")
PYT
}

echo "== the loopd palette: one dark theme, off the rendered page =="
assert "the page renders at all"                     "$(yes_if test -s "$SLATE")"
# Every value is copied from the brand's tokens.css. loopd is dark-only — the token set
# carries no light ground — so there is ONE :root block and no [data-theme] override.
DARK_TOKENS='ground #101318
surface #171b22
sunk #14171c
inner #1c212b
raise #1c212b
ink #e9edf4
muted #9aa4b5
dim #6c7488
line #262c37
signal #ff7ac2
signal-ink #14171c
ok #5ea2ff
stop #ff7ac2
accent #5ea2ff
accent-ink #14171c'
while read -r name hex; do
  [ -n "$name" ] || continue
  assert "--$name is $hex"                           "$(eq "$(tokval "$SLATE" ':root' "$name")" "$hex")"
done <<< "$DARK_TOKENS"
# THE PALETTE CLOSES. Ten values, and the page may not contain an eleventh: this is the
# assertion a third accent fails, whichever rule smuggles it in. The list IS tokens.css's
# — a hex that is not in the brand's token file cannot appear here either.
LOOPD_HEXES='#101318 #14171c #171b22 #1c212b #262c37 #5ea2ff #6c7488 #9aa4b5 #e9edf4 #ff7ac2'
assert "…and the page holds those ten and no other" \
  "$(eq "$(grep -oE '#[0-9a-fA-F]{6}' "$SLATE" | tr 'A-F' 'a-f' | sort -u | tr '\n' ' ')" \
        "$LOOPD_HEXES ")"
# The soft fills and the soft text: they are their own tokens, so an absent one reads as
# "" and fails here rather than silently rendering unstyled. --ok-soft is BLUE because
# approve is a machine-coloured affordance; --stop-soft is pink because reject is not.
softs() { # <selector> <expected, space separated name:hex>
  local sel="$1"; shift
  local ok=0 pair
  for pair in "$@"; do
    [ "$(tokval "$SLATE" "$sel" "${pair%%:*}")" = "${pair##*:}" ] || ok=1
  done
  echo "$ok"
}
assert "the soft fills and the soft text are carried" \
  "$(softs ':root' signal-soft:#ff7ac21f signal-soft-text:#ff7ac2 \
           ok-soft:#5ea2ff1f stop-soft:#ff7ac21f neutral-soft:#1c212b neutral-soft-text:#e9edf4)"
# THE NEEDS-YOU PILL IS THE PINK ITSELF, not the soft fill — it is the one filled thing
# on a collapsed row. Both halves: the fill is --signal, the text is --signal-ink.
assert "the needs-you pill is filled with --signal"  "$(fhas '.c.you{background:var(--signal);color:var(--signal-ink);' "$SLATE")"
assert "…and the pill is not drawn in the soft fill" "$(fhasnt '.c.you{background:var(--signal-soft)' "$SLATE")"
assert "the header's needs-you text is --signal-soft-text" "$(fhas '.sub .sig{color:var(--signal-soft-text);font-weight:600}' "$SLATE")"
# TWO COLOURS, AND PINK MEANS A PERSON. Machine state is blue by construction: the four
# status tones the renderer can emit resolve to --accent, --ok or --dim, and the only
# one that resolves to pink is `blocked`, which is what a human has to unblock.
assert "every machine state resolves to blue or dim" "$(fhas '.state.ok{color:var(--ok)} .state.accent{color:var(--accent)}' "$SLATE")"
assert "…--ok is the same blue as --accent"          "$(eq "$(tokval "$SLATE" ':root' ok)" "$(tokval "$SLATE" ':root' accent)")"
assert "…and only a blocked task takes --stop"       "$(yes_if python3 -c "
import re, sys
src = open('$BOARD', encoding='utf-8').read()
m = re.search(r'^TONE = \{(.*?)\}', src, re.S | re.M)
tone = dict(re.findall(r'\"([a-z-]+)\": \"([a-z]+)\"', m.group(1) if m else ''))
sys.exit(0 if tone and [k for k, v in tone.items() if v == 'stop'] == ['blocked'] else 1)")"
assert "…while queued, running and merged are blue"   "$(yes_if python3 -c "
import re, sys
src = open('$BOARD', encoding='utf-8').read()
m = re.search(r'^TONE = \{(.*?)\}', src, re.S | re.M)
tone = dict(re.findall(r'\"([a-z-]+)\": \"([a-z]+)\"', m.group(1) if m else ''))
sys.exit(0 if all(tone.get(k) in ('accent', 'ok') for k in ('ready', 'in-progress', 'in-review', 'done')) else 1)")"
# The active tab is BLUE: which tab you are reading is the machine's state, and a filled
# pink pill there would be a pink pixel that is not a decision waiting.
assert "the active tab pill is filled blue"          "$(fhas 'background:var(--accent);
  border-color:var(--accent);color:var(--accent-ink);font-weight:700}' "$SLATE")"
assert "…and the focus ring is blue too"             "$(fhas ':focus-visible{outline:2px solid var(--accent);' "$SLATE")"
# GEOMETRY FROM THE TOKENS: radii are --loopd-r-l/m/s (12/10/6) or the pill, and the one
# shadow on the page is --loopd-shadow on the toast, the only floating chrome.
assert "every radius is 12, 10, 6, 0 or the pill"    "$(eq "$(grep -oE 'border-radius:[^;}]+' "$SLATE" | sort -u | tr '\n' ' ')" \
  'border-radius:0 border-radius:10px border-radius:12px border-radius:6px border-radius:999px ')"
assert "…the shadow token is tokens.css's"          "$(fhas '--shadow:0 24px 80px rgba(0,0,0,.5);' "$SLATE")"
assert "…and only the floating toast casts one"      "$(eq "$(grep -oE 'box-shadow:[^;}]+' "$SLATE" | tr '\n' ' ')" 'box-shadow:var(--shadow) ')"

echo "== the tab row filters project rows, and All is what ships =="
assert "the board carries the default tab"           "$(fhas '<div class="board" data-tab="all">' "$SLATE")"
for pick in all you act pause fin other; do
  assert "…a $pick tab is rendered"                  "$(fhas "data-pick=\"$pick\"" "$SLATE")"
done
assert "…six of them and no more"                    "$(eq "$(grep -oF '<button class="tab' "$SLATE" | wc -l | tr -d ' ')" 6)"
assert "…labelled from the handoff"                  "$(yes_if python3 -c "
import re, sys
labels = re.findall(r'data-pick=\"[a-z]+\">([^<]*) · [0-9]+</button>', open('$SLATE', encoding='utf-8').read())
sys.exit(0 if labels == ['All', 'Needs you', 'Active', 'Paused', 'Finished', 'Other owners'] else 1)")"
# THE COUNTS ARE THE BOARD'S OWN, and each is re-derived here from what actually
# rendered — a tab saying 3 over 4 cards is the only way a filter can lie. `Needs you`
# counts ITEMS, exactly as the masthead tally does, while the other five count PROJECTS;
# that asymmetry is the handoff's and is pinned rather than smoothed over.
assert "…and every count matches the rows it filters" "$(yes_if python3 -c "
import re, sys
page = open('$SLATE', encoding='utf-8').read()
tabs = dict((p, int(n)) for p, n in
            re.findall(r'data-pick=\"([a-z]+)\">[^<]*· ([0-9]+)</button>', page))
facets = re.findall(r'<div class=\"pcard\" data-f=\"([^\"]*)\">', page)
mine = [f for f in facets if 'other' not in f.split()]
awaiting = int(re.search(r'awaiting you</dt><dd>([0-9]+)</dd>', page).group(1))
sys.exit(0 if tabs['all'] == len(mine)
             and tabs['you'] == awaiting
             and sum(1 for f in mine if 'you' in f.split())
                 == len(re.findall(r'class=\"c you\"', page))
             and tabs['act'] == sum(1 for f in mine if 'act' in f.split())
             and tabs['pause'] == sum(1 for f in mine if 'pause' in f.split())
             and tabs['fin'] == sum(1 for f in mine if 'fin' in f.split())
             and tabs['other'] == len(re.findall(r'class=\"proj other\"', page)) else 1)")"
# FILTERING IS CSS, NOT A LIST OF ROWS THE SCRIPT WALKS: the script writes ONE attribute
# and every hide is a selector on it, so nothing can go out of step with the markup.
assert "each tab hides by selector, not by script"   "$(fhas '.board[data-tab="you"] .pcard:not([data-f~="you"]),' "$SLATE")"
assert "…for the Active tab too"                     "$(fhas '.board[data-tab="act"] .pcard:not([data-f~="act"]),' "$SLATE")"
assert "…and the Finished one"                       "$(fhas '.board[data-tab="fin"] .pcard:not([data-f~="fin"]),' "$SLATE")"
assert "…and the script writes one attribute"        "$(fhas "b.setAttribute('data-tab', p.getAttribute('data-pick'));" "$SLATE")"
# OTHER OWNERS IS A TAB, NOT A TRAILING SECTION any more: hidden under All, shown under
# its own tab, and its divider goes with it.
assert "other owners are hidden under All"           "$(fhas '.board[data-tab="all"] .pcard[data-f~="other"],' "$SLATE")"
assert "…and so is the heading that led that section" "$(fhas '.board[data-tab="all"] .sep.others,' "$SLATE")"
assert "…the facet the tab selects on is on the card" "$(fhas '<div class="pcard" data-f="' "$SLATE")"

echo "== dark-only, and the theme toggle is gone with the light palette =="
# THERE IS NO THEME CONTROL. loopd is a dark-only brand, so there is nothing to toggle:
# no stored choice, no [data-theme] attribute, no system preference consulted. Asserted
# as absences, because a half-removed toggle is a control that renders and does nothing.
assert "no segmented theme control is rendered"      "$(fhasnt '<div class="seg"' "$SLATE")"
assert "…no segment writes a theme"                  "$(fhasnt 'data-set-theme' "$SLATE")"
assert "…nothing renders a data-theme attribute"     "$(fhasnt 'data-theme' "$SLATE")"
assert "…prefers-color-scheme is not consulted"      "$(fhasnt 'prefers-color-scheme' "$SLATE")"
assert "…and no theme choice is stored"              "$(fhasnt 'ai-bridge-board-theme' "$SLATE")"
# STILL ONE SCRIPT. The clipboard helper and the tabs share the single inline <script>
# this page has always had — a second one would be a second place for the page's only
# scripted behaviour to live.
assert "the page carries exactly one script element" "$(eq "$(grep -oF '<script>' "$SLATE" | wc -l | tr -d ' ')" 1)"

echo "== the five-track task grid, and the phone layout below 760px =="
assert "the row is the handoff's five tracks"        "$(fhas 'grid-template-columns:minmax(0,1fr) 105px 140px 80px 90px;' "$SLATE")"
assert "…written once, so head and body cannot drift" "$(eq "$(grep -oF 'grid-template-columns:minmax(0,1fr) 105px 140px 80px 90px' "$SLATE" | wc -l | tr -d ' ')" 1)"
assert "…and it is still a <table>, not a stack of divs" "$(fhas '<table><thead><tr>' "$SLATE")"
assert "the state cells carry the handoff's glyphs"  "$(yes_if python3 -c "
import re, sys
states = set(re.findall(r'<span class=\"state[^\"]*\">(.)', open('$SLATE', encoding='utf-8').read()))
sys.exit(0 if states and states <= set('✓◐■◇⊘') else 1)")"
assert "the breakpoint is at 760px"                  "$(fhas '@media (max-width:760px){' "$SLATE")"
# WHAT THE BREAKPOINT HAS TO DO, one assertion each — a media query that exists and
# changes nothing is the failure this would otherwise miss.
assert "…the header row has nothing left to label"   "$(fhas 'thead{display:none}' "$SLATE")"
assert "…the row becomes a wrapping meta line"       "$(fhas 'tr{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:12px 0}' "$SLATE")"
assert "…with the task cell on a line of its own"    "$(fhas 'td:first-child{width:100%}' "$SLATE")"
assert "…the action buttons reach 40px"              "$(fhas '.acts button{min-height:40px;' "$SLATE")"
assert "…and the tab pills scroll instead of wrapping" "$(fhas '.tabwrap{flex-wrap:nowrap;overflow-x:auto;' "$SLATE")"
assert "…while the desktop rule lets them wrap"      "$(fhas '.tabwrap{display:flex;gap:8px;flex-wrap:wrap;' "$SLATE")"
# NON-VACUITY: every rule above must be INSIDE the query, or they describe the desktop.
assert "…and all of it really is inside the query"   "$(yes_if python3 -c "
import re, sys
src = open('$SLATE', encoding='utf-8').read()
m = re.search(r'@media \(max-width:760px\)\{(.*?)\n\}', src, re.S)
body = m.group(1) if m else ''
need = ['thead{display:none}', 'tr{display:flex;flex-wrap:wrap',
        'td:first-child{width:100%}', '.acts button{min-height:40px',
        '.tabwrap{flex-wrap:nowrap']
sys.exit(0 if body and all(n in body for n in need) else 1)")"

echo "== the handoff's measurements, one assertion per number =="
# EVERY SIZE IN README §1–§2, read back off the sheet. A redesign whose numbers live
# only in a source document is a redesign that drifts on the first edit; these are the
# values the artboards were drawn at, so a changed one has to be changed here too.
sized() { # <label> <literal css>
  assert "$1" "$(fhas "$2" "$SLATE")"
}
sized "header title 23px/700"            'h1{font-size:23px;font-weight:700;'
sized "snapshot line 14px"               '.sub{color:var(--muted);margin:6px 0 0;font-size:14px}'
sized "stat number 21px/700"             '.tally dd{order:1;margin:0;font:700 21px/1.25'
sized "stat label 12px"                  '.tally dt{order:2;font-size:12px;'
sized "tab pill 13px, 6px 16px, 999px"   "font:500 13px/1 'Inter',system-ui,sans-serif;padding:6px 16px;border-radius:999px;"
sized "project card 12px radius"         '.proj{background:var(--surface);border:1px solid var(--line);border-radius:12px}'
sized "collapsed row 15px 20px padding"  'padding:15px 20px;list-style:none;border-radius:12px}'
sized "project title 15px/600"           '.ptitle{font-weight:600;letter-spacing:-.01em;flex:0 1 auto;min-width:0;font-size:15px;'
sized "project date 13px"                '.pdate{font-size:13px;color:var(--muted);'
sized "count summary 13px"               '.counts{display:flex;gap:6px;flex-wrap:wrap;margin-left:auto;align-items:center;
  font-size:13px;'
sized "needs-you pill 6px 14px, 999px"   'padding:6px 14px;border-radius:999px;margin-left:8px}'
sized "finished divider 12px/600 .08em"  '.sep{font-size:12px;text-transform:uppercase;letter-spacing:.08em;'
sized "decision rail 12px radius, 16px"  'border-left:4px solid var(--signal);border-radius:12px;padding:16px;'
sized "rail label 11px/700 uppercase"    ".rail h2{margin:0;font:700 11px/1.4 'Inter',system-ui,sans-serif;text-transform:uppercase;
  letter-spacing:.1em;"
sized "decision card 10px radius"        'border:1px solid var(--line);border-radius:10px}'
sized "decision card 14px 16px padding"  '.ask{display:flex;flex-direction:column;padding:14px 16px;'
sized "verb mono 11px/600 uppercase"     ".verb{font:600 11px/1.5 'JetBrains Mono',ui-monospace,Menlo,monospace;text-transform:uppercase;"
sized "card title 15px/600, 1.45 lh"     '.what{width:100%;font-size:15px;font-weight:600;line-height:1.45;'
sized "breadcrumb 13px"                  '.where{width:100%;font-size:13px;color:var(--muted);'
sized "action button 9px 16px, 10px"     'border-radius:10px;
  padding:9px 16px;'
sized "task id mono 11px"                '.tid{color:var(--muted);font-size:11px;'
sized "task title 14px"                  '.tbtn{background:none;border:0;padding:0;font:400 14px/1.4'
sized "state 12px/600"                   '.state{font-size:12px;font-weight:600;'
sized "depends-on mono 12px"             "button.dep{font-family:'JetBrains Mono',ui-monospace,Menlo,monospace;font-size:12px;"
sized "Q chip 6px radius"                'border:0;border-radius:6px;padding:2px 8px;'
sized "PR ref 13px in the activity blue" 'td a{color:var(--accent);text-decoration:none;'
sized "row 18px column gap, 12px rows"   'gap:0 18px;
  align-items:start;padding:12px 4px;border-top:1px solid var(--line)}'
# THE PILLS ARE LEVEL WITH THE TITLE'S FIRST LINE, and the offset is pinned in bytes
# because nothing else can catch it: `align-items:start` alone levels them with the
# FILENAME line above the title, which renders as a near-miss on every wrapped row.
# 19px = `.tfile`'s pinned 17px line + `.trow`'s 2px gap, so both halves are pinned too.
sized "pill cells offset to the title line"  'td:not(:first-child){padding-top:19px}'
sized "…derived from a filename line pinned in bytes" 'line-height:17px}'
sized "…and the filename stays on ONE line"           '.tfile>.tid{margin-right:0;min-width:0;white-space:nowrap;overflow:hidden;
  text-overflow:ellipsis}'
sized "the 760px fallback drops the offset with the grid" 'td:not(:first-child){padding-top:0}'
assert "the title is never clamped"                   "$(fhasnt 'line-clamp' "$SLATE")"
# EVERY ACTION IS VISIBLE ON DESKTOP — no overflow menu, stated as the absence of one
# and as the presence of the wrap that replaces it.
assert "the action row wraps rather than collapsing" "$(fhas '.acts{display:flex;flex-wrap:wrap;gap:8px;' "$SLATE")"
assert "…and no overflow control is rendered"        "$(fhasnt 'data-what="More"' "$SLATE")"

echo "== the signal pill is LAST on the meta row, whatever else that row carries =="
# THE BUG THIS PINS, and why the assertion is on ORDER rather than presence: the pill was
# emitted before `concerns`, `phases` and `deliverables`, so the one chip whose job is to
# be found at a glance sat at a different x-position on every card. Presence was already
# true while it was broken. The fix is SOURCE ORDER — no `margin-left:auto`, no new
# positioning rule — so the pill's own CSS is pinned below as well.
ORDER="$TMP/group/_ai-bridge-order"
new_instance "$ORDER"
python3 - "$ORDER/$AB_SNAPSHOT" <<'PY'
import json, sys

def task(i, status, awaiting="", notes=0):
    return {"id": "task-%03d" % i, "title": "t%d" % i, "kind": "build",
            "status": status, "assignee": "software-engineer", "phase": "",
            "in_flight": False, "awaiting": awaiting, "open_questions": 0,
            "advisor_notes": notes, "prs": []}

def proj(slug, title, tasks, phases=(0, 0), deliv=()):
    return {"slug": slug, "title": title, "kind": "build", "status": "active",
            "autonomy": "gated", "awaiting_close": False,
            "phase_progress": {"done": phases[0], "total": phases[1]},
            "phases": [], "deliverable_paths": list(deliv), "tasks": tasks}

snap = {
    "group": "order",
    "generated_at": "2026-09-08T00:00:00Z",
    "counts": {"projects": 3, "tasks": 6, "awaiting": 3},
    "projects": [
        # Every optional pill at once — done, in progress, pending, concerns, phases,
        # deliverables AND a signal count of two.
        proj("loaded", "EVERYPILL",
             [task(1, "done"), task(2, "in-progress"),
              task(3, "draft", awaiting="approve", notes=2),
              task(4, "in-review", awaiting="merge")],
             phases=(1, 3), deliv=["/projects/loaded/deliverables/report.md"]),
        # A signal count and nothing optional — the row the loaded one has to line up with.
        proj("bare", "SIGNALONLY", [task(1, "draft", awaiting="approve")]),
        # Concerns and phases but NOTHING awaiting: absent means zero, so no pill at all.
        proj("quiet", "NOSIGNAL", [task(1, "in-progress", notes=1)], phases=(1, 2)),
    ],
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(snap, fh)
PY
ORDERED="$TMP/ordered.html"
( cd "$ORDER" && bash "$BOARD" --standalone --out "$ORDERED" "$ORDER" >/dev/null 2>&1 )
assert "the ordering fixture renders"                "$(yes_if test -s "$ORDERED")"
# The pill classes of one card's meta span, in the order they were EMITTED.
pills() { python3 -c "
import re, sys
for chunk in open('$ORDERED', encoding='utf-8').read().split('<div class=\"pcard\"')[1:]:
    t = re.search(r'<span class=\"ptitle\">([^<]*)</span>', chunk)
    if not t or t.group(1) != sys.argv[1]:
        continue
    seg = chunk.split('<span class=\"counts\">', 1)[1].split('</summary>', 1)[0]
    print(' '.join(re.findall(r'<span class=\"(c [a-z]+|tag)\"', seg)))
" "$1"; }
assert "a row carrying every pill puts the signal last" \
  "$(eq "$(pills EVERYPILL)" "c ok c run c wait tag tag c you")"
assert "…and a row with a signal count and no concerns puts it in the same place" \
  "$(eq "$(pills SIGNALONLY)" "c ok c run c wait c you")"
assert "…while a row with nothing awaiting emits no signal pill at all" \
  "$(eq "$(pills NOSIGNAL)" "c ok c run c wait tag")"
# THE CONCERNS PILL IS GONE, and the fixture that used to prove it renders keeps its
# non-zero `advisor_notes` so the assertion is about the RENDERER and not about the data.
assert "an untriaged concern renders no pill"        "$(fhasnt '<span class="c note"' "$ORDERED")"
assert "…and no concern text anywhere on the page"   "$(fhasnt 'concern' "$ORDERED")"
assert "…and the plural signal reads 'need you'"     "$(fhas '<span class="c you"><b>2</b> need you</span>' "$ORDERED")"
assert "…the singular one 'needs you'"               "$(fhas '<span class="c you"><b>1</b> needs you</span>' "$ORDERED")"
# THE DISMISS CONTROL IS OUTSIDE THE META SPAN, to its right, exactly as before — the
# pill moving to the end of the span must not have carried it inside.
assert "the ✕ stays outside the meta span"           "$(yes_if python3 -c "
import re, sys
page = open('$ORDERED', encoding='utf-8').read()
ok = 0
for chunk in page.split('<div class=\"pcard\"')[1:]:
    seg = chunk.split('<span class=\"counts\">', 1)[1].split('</summary>', 1)[0]
    if not re.search(r'</span>\n</span>\n<button class=\"pclose\"', seg):
        sys.exit(1)
    ok += 1
sys.exit(0 if ok == 3 else 1)")"
# SOURCE ORDER, NOT CSS. The pill's own rules are pinned whole, so a later
# `margin-left:auto` (or any other positioning declaration) on it goes red here.
assert "the pill carries no positioning rule"        "$(yes_if python3 -c "
import re, sys
bodies = re.findall(r'\.c\.you\{([^}]*)\}', open('$ORDERED', encoding='utf-8').read())
sys.exit(0 if bodies == ['background:var(--signal);color:var(--signal-ink);font-weight:700;\n  padding:6px 14px;border-radius:999px;margin-left:8px',
                         'font-size:12px;padding:4px 10px;margin-left:0'] else 1)")"

echo "== the page still renders from SNAPSHOT.json alone, and stays escaped =="
# The hostile instance renders through the SAME new markup: a title carrying ESC, a
# newline, a tab and a bidi override reaches the tab row's neighbours and the pill, and
# none of it may arrive as anything but text.
HOSTILE="$TMP/hostile.html"
( cd "$DELTA" && bash "$BOARD" --standalone --out "$HOSTILE" "$DELTA" >/dev/null 2>&1 )
assert "the hostile snapshot renders"                "$(yes_if test -s "$HOSTILE")"
assert "…with no unescaped angle bracket from a title" "$(fhasnt '<span class="ptitle">ANSITITLE<' "$HOSTILE")"
assert "…and the tab counts are integers, never text" "$(yes_if python3 -c "
import re, sys
n = re.findall(r'data-pick=\"[a-z]+\">[^<]*· ([^<]*)</button>', open('$HOSTILE', encoding='utf-8').read())
sys.exit(0 if n and all(x.isdigit() for x in n) else 1)")"
assert "…and no snapshot text reaches the script"    "$(yes_if python3 -c "
import re, sys
src = open('$HOSTILE', encoding='utf-8').read()
m = re.search(r'<script>(.*?)</script>', src, re.S)
sys.exit(0 if m and 'ANSITITLE' not in m.group(1) and 'FORGEDROW' not in m.group(1) else 1)")"

# ---------------------------------------------------------------- Closed section
# A closed project has NO FOLDER, so the snapshot's `closed` array is the only route it
# has to the page — and its URLs come from a tracked markdown file, which is the same
# untrusted-text class as a title or a PR URL. The two properties that matter: the
# section renders collapsed from the array alone, and a `javascript:` deliverable URL
# is inert text, never an href.
echo
echo "== the board's Closed section =="
CL="$TMP/group/_ai-bridge-closed"
mkdir -p "$CL" "$CL/$AB_DIR"
cat > "$CL/$AB_SNAPSHOT" <<'JSON'
{ "_schema": "ai-bridge board snapshot v1", "group": "closed",
  "generated_at": "2026-09-08T00:00:00Z",
  "counts": {"projects": 0, "tasks": 0, "awaiting": 0},
  "closed": [
    {"slug": "ai-bridge-2x", "closed": "2026-09-08", "sha": "8fefa76aaaaaaaa",
     "outcome": "ten merged PRs",
     "deliverables": [
       {"path": "/projects/ai-bridge-2x/project.md",
        "url": "https://github.com/o/r/blob/8fefa76/projects/ai-bridge-2x/project.md"},
       {"path": "/projects/ai-bridge-2x/sources/screens.html",
        "url": "javascript:alert(1)"}]}],
  "projects": [] }
JSON
CLH="$TMP/closed-board.html"
( cd "$CL" && bash "$BOARD" --standalone --out "$CLH" "$CL" >/dev/null 2>&1 )
assert "a snapshot with \`closed\` renders the section"  "$(fhas 'Closed · 1' "$CLH")"
assert "…COLLAPSED — its <details> carries no \`open\`"  "$(yes_if python3 -c "
import sys
src = open('$CLH', encoding='utf-8').read()
tag = src[:src.index('Closed · 1')].rsplit('<details', 1)[1].split('>', 1)[0]
sys.exit(0 if ' open' not in tag else 1)")"
assert "…it opens to the per-deliverable link"           "$(fhas 'blob/8fefa76/projects/ai-bridge-2x/project.md' "$CLH")"
# THE CELL, not the bare sha: `8fefa76` is in the permalink one column over, so a
# renderer that dropped the Pinned column entirely still passed the old assertion.
assert "…the pinned sha is shown, short"                 "$(fhas '<td class="dim">8fefa76</td>' "$CLH")"
# The slug is unique only inside one instance, so the row names the group it came from.
assert "…and the instance group beside the slug"         "$(fhas 'ai-bridge-2x <span class="dim">· closed</span>' "$CLH")"
assert "…and the one-line outcome"                       "$(fhas 'ten merged PRs' "$CLH")"
assert "a javascript: deliverable URL is NOT a link"    "$(fhasnt 'javascript:' "$CLH")"
assert "…it renders as inert text instead"               "$(fhas 'link withheld: not http/https' "$CLH")"
# The count is over PROJECTS and the chip over deliverables — a section claiming one and
# showing the other is the presence-assertion failure this repo has already paid for.
assert "…and the chip counts deliverables, not projects" "$(fhas '<b>2</b> deliverable' "$CLH")"

# Two instances closing the SAME slug. `group` is per-snapshot, so without it stamped
# onto each record these two rows are indistinguishable — which is the whole reason the
# aggregation carries it.
CL2="$TMP/group/_ai-bridge-other"
mkdir -p "$CL2" "$CL2/$AB_DIR"
sed 's/"group": "closed"/"group": "other"/' "$CL/$AB_SNAPSHOT" > "$CL2/$AB_SNAPSHOT"
TWOH="$TMP/closed-two.html"
( cd "$TMP" && bash "$BOARD" --standalone --out "$TWOH" "$CL" "$CL2" >/dev/null 2>&1 )
assert "two instances, same slug: the first row names its group"  "$(fhas 'ai-bridge-2x <span class="dim">· closed</span>' "$TWOH")"
assert "…and the second names the other one"                      "$(fhas 'ai-bridge-2x <span class="dim">· other</span>' "$TWOH")"

NOCL="$TMP/group/_ai-bridge-nocl"
mkdir -p "$NOCL" "$NOCL/$AB_DIR"
python3 - "$CL/$AB_SNAPSHOT" "$NOCL/$AB_SNAPSHOT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); d.pop("closed")
open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(d))
PY
NOCLH="$TMP/nocl-board.html"
( cd "$NOCL" && bash "$BOARD" --standalone --out "$NOCLH" "$NOCL" >/dev/null 2>&1 )
assert "a snapshot with NO \`closed\` key renders the page" "$(yes_if test -s "$NOCLH")"
assert "…and no Closed section at all"                     "$(fhasnt 'Closed · ' "$NOCLH")"

# THE RENDERERS SHIP WITH THE PLUGIN, NOT INTO A BUNDLE (task-013). This used to assert
# that a stamp LINKED them into `<bundle>/scripts/`; a bundle carries no machinery now, so
# the property worth pinning is that the plugin ships both and that a stamp put no link
# where the old ones were — the same question, asked of the design that replaced it.
BR_TPL="$(cd "$(dirname "$BRIDGE_INSTALL")/../.." && pwd)"
assert "the plugin ships print-board.sh"       "$(yes_if test -f "$BR_TPL/plugin/scripts/print-board.sh")"
assert "…and watch-board.sh"                   "$(yes_if test -f "$BR_TPL/plugin/scripts/watch-board.sh")"
assert "…and the stamped bundle links neither" "$(yes_if sh -c '! test -e "$1/scripts"' _ "$INST")"

echo
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
