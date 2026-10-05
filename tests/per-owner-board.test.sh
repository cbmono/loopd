#!/usr/bin/env bash
#
# per-owner-board.test.sh — the board is PER OWNER: your own projects come from this
# clone's SNAPSHOT.json, and every other owner's come from the TRACKED task documents at
# your current git HEAD.
#
# WHY THIS EXISTS, AND WHY IT OUTLIVED THE PUBLISH PATH. It was written when each human
# published their own board: artifact publishing is account-scoped — the update path needs
# an artifact the account owns and no share level grants it — so two humans sharing a
# bundle could never share one published page. The cross-owner view therefore had to come
# from the one thing both clones genuinely share, which is git. Publishing is now deleted
# and the board is a local file per machine, and NOTHING BELOW CHANGED: sourcing the
# section from HEAD was never a workaround for the publish path, it was the only design
# that ever worked, and it is what makes a per-machine board lose nothing on a shared
# bundle.
#
# THE FOUR CLAIMS THIS FILE PINS, and each is a way the section could be quietly wrong:
#
#   1. TWO SECTIONS, ONE PROJECT IN EACH. A project this clone owns renders in the own
#      section and NOT in the other-owners one, and vice versa. Rendering a project twice
#      is the failure a naive "add a second section" produces, and it looks fine.
#   2. THE SOURCE IS HEAD, NOT THE WORKING TREE AND NOT A SNAPSHOT. Proven the only way
#      that cannot be faked: a project DELETED from the working tree still renders (it is
#      still in HEAD), and an uncommitted title change does NOT (it is not). No clone ever
#      holds another's SNAPSHOT.json — that file is gitignored — so a renderer that read
#      one would render nothing here and pass a weaker assertion.
#   3. AN ABSENT OR UNKNOWN OWNER IS NOT A CRASH. No `ownerGithubUser`, no `defaultOwner`,
#      an owner naming nobody the bundle knows, a directory that is not a git repository
#      at all: every one of those is a page that renders, exit 0, and no traceback.
#   4. THE SECTION IS A FUNCTION OF THE SHA. Two runs at one HEAD produce byte-identical
#      markup; a commit that changes another owner's document changes it. A wall-clock
#      cache would pass the first half and fail the second, which is exactly why the
#      cache is keyed to the SHA and the timer is only the fallback.
#
# NAMED, AND COLLAPSED FOR ERGONOMICS ONLY. The other owners are named in the rendered
# HTML. Collapsing their section does not hide that — the names are in the markup whether
# the <details> is open or shut — so the assertions below check the NAME is present and
# that the block merely starts closed. Nothing here should be read as testing a privacy
# control, because the collapse is not one. (It mattered more when the page was published;
# a local file is still a file, and a file can be copied somewhere.)
# See /knowledge/findings/board-owner-identity-named-not-redacted.md.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

TPL="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$TPL/plugin/scripts/build-board.sh"
WRITER="$TPL/plugin/scripts/write-snapshot.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/perowner.XXXXXX")" || {
  echo "per-owner-board.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
fhas()   { grep -qF -- "$1" "$2" && echo 0 || echo 1; }
fhasnt() { grep -qF -- "$1" "$2" && echo 1 || echo 0; }
eq()     { [[ "$1" == "$2" ]] && echo 0 || echo 1; }

command -v python3 >/dev/null 2>&1 || {
  echo "  (python3 absent — build-board cases cannot run)"; echo "pass=0 fail=0"; exit 0; }

# ---------------------------------------------------------------- the fixture
INST="$TMP/_ai-bridge-team"; mkdir -p "$INST/projects" "$INST/$AB_DIR"
printf 'stub\n' > "$INST/$AB_SCHEMA"

mkproj() { # <slug> <title> <owner-or-empty> <task-status>...
  local slug="$1" title="$2" owner="$3"; shift 3
  mkdir -p "$INST/projects/$slug/tasks"
  { echo '---'
    echo 'type: Project'
    echo "title: $title"
    echo 'kind: build'
    echo 'status: active'
    [[ -n "$owner" ]] && echo "owner: $owner"
    echo '---'
    echo
    echo '# Context'
  } > "$INST/projects/$slug/project.md"
  local i=0
  for st in "$@"; do
    i=$((i+1))
    printf -- '---\ntype: Task\ntitle: %s work %d\nkind: build\nstatus: %s\nassignee: software-engineer\n---\n\n# Context\n' \
      "$title" "$i" "$st" > "$INST/projects/$slug/tasks/$(printf 'task-%03d' "$i").md"
  done
}

cfg() { # <tracked-json>
  printf '%s\n' "$1" > "$INST/instance.config.json"
}
local_cfg() { printf '%s\n' "$1" > "$INST/instance.config.local.json"; }

cfg '{ "org": "o", "defaultOwner": "alice" }'
local_cfg '{ "ownerGithubUser": "alice" }'

mkproj mine    "Mine"     ""        in-progress done
mkproj alice-2 "Also mine" alice    ready
mkproj bobs    "Bobs work" bob      in-progress done done
mkproj carols  "Carols"    Carol    draft

git -C "$INST" init -q 2>/dev/null
git -C "$INST" config user.email test@example.com
git -C "$INST" config user.name  Test
git -C "$INST" add -A >/dev/null 2>&1
git -C "$INST" commit -qm "fixture" >/dev/null 2>&1

: > "$INST/$AB_SNAPSHOT"            # presence is the switch; the writer fills it
( cd "$INST" && SNAPSHOT_NOW=2026-08-26T00:00:00Z bash "$WRITER" --quiet ) >/dev/null 2>&1

echo "== the writer carries owner, deliberately =="
assert "the snapshot names an owner at all"      "$(fhas '"owner"' "$INST/$AB_SNAPSHOT")"
assert "…the value, verbatim"                    "$(fhas '"owner": "bob"' "$INST/$AB_SNAPSHOT")"
assert "…and an unowned project carries an empty one" \
  "$(fhas '"owner": ""' "$INST/$AB_SNAPSHOT")"
# The header's rule and the code must not contradict each other: the file says owner is
# carried on purpose, and points at the Finding that records the decision.
assert "the writer's own header says it is carried on purpose" \
  "$(fhas 'IS CARRIED, AND THAT IS A REVERSAL' "$WRITER")"
assert "…and points at the Finding" \
  "$(fhas '/knowledge/findings/board-owner-identity-named-not-redacted.md' "$WRITER")"
assert "…and no longer lists it as never carried" \
  "$(no_if grep -qE '^#     · .owner:. — on a bundle shared by two humans' "$WRITER")"
assert "…while authorEmail stays on the never list" \
  "$(fhas 'authorEmail' "$WRITER")"
assert "the _carries key says so too"            "$(fhas 'project owner' "$INST/$AB_SNAPSHOT")"

echo
echo "== two owners, two sections, and nothing rendered twice =="
PAGE="$TMP/board.html"
rc=0; ( cd "$INST" && bash "$GEN" --out "$PAGE" . ) >"$TMP/run1.err" 2>&1 || rc=$?
assert "the render exits 0"                      "$(eq "$rc" 0)"
assert "…and writes a page"                      "$(yes_if test -s "$PAGE")"
assert "…with no Python traceback"               "$(fhasnt 'Traceback (most recent call last)' "$TMP/run1.err")"
assert "my own project is in the own section"    "$(fhas 'class="ptitle">Mine<' "$PAGE")"
assert "…and so is one I own by name"            "$(fhas 'class="ptitle">Also mine<' "$PAGE")"
assert "there is an Other owners heading"        "$(fhas 'Other owners' "$PAGE")"
assert "…naming bob"                             "$(fhas '>bob<' "$PAGE")"
assert "…and Carol, verbatim"                    "$(fhas '>Carol<' "$PAGE")"
assert "one collapsed block per other owner"     "$(eq "$(grep -cF 'class="proj other"' "$PAGE")" 2)"
# The whole point of the partition: somebody else's project must not also render as one
# of mine. A project card is `class="ptitle">TITLE<`; the other-owners table is not.
assert "another owner's project is NOT an own card" \
  "$(fhasnt 'class="ptitle">Bobs work<' "$PAGE")"
assert "…but it is listed under its owner"       "$(fhas 'Bobs work' "$PAGE")"

echo
echo "== collapsed by default, named either way =="
assert "the other-owners block starts closed"    "$(fhasnt 'class="proj other" open' "$PAGE")"
assert "…with a summary to expand it"            "$(fhas 'class="proj other"><summary' "$PAGE")"
# Ergonomics, not redaction — and the page says so where a reader will find it.
assert "the page states the names are published anyway" \
  "$(fhas 'names of other owners are on this page whether' "$PAGE")"

echo
echo "== bundle-relative paths only =="
assert "a project path is bundle-relative"       "$(fhas '/projects/bobs/' "$PAGE")"
assert "no filesystem path to the fixture leaks" "$(fhasnt "$TMP" "$PAGE")"
assert "…nor an absolute home path"              "$(fhasnt '/Users/' "$PAGE")"
assert "…nor a tmp root"                         "$(fhasnt '/var/folders/' "$PAGE")"

echo
echo "== the source is HEAD: not the working tree, not anybody's snapshot =="
# Nothing else can produce this pair of answers. Deleted from the working tree but still
# in HEAD ⇒ present. Changed in the working tree but not committed ⇒ the OLD text.
rm -rf "$INST/projects/bobs"
sed -i.bak 's/^title: Carols$/title: Carols RENAMED/' "$INST/projects/carols/project.md"
rm -f "$INST/projects/carols/project.md.bak"
( cd "$INST" && SNAPSHOT_NOW=2026-08-26T00:00:00Z bash "$WRITER" --quiet ) >/dev/null 2>&1
PAGE2="$TMP/board2.html"
( cd "$INST" && bash "$GEN" --out "$PAGE2" . ) >"$TMP/run2.err" 2>&1
assert "a project deleted from the working tree still renders" "$(fhas 'Bobs work' "$PAGE2")"
assert "an uncommitted rename does NOT render"   "$(fhasnt 'Carols RENAMED' "$PAGE2")"
assert "…the committed title does"               "$(fhas '>Carols<' "$PAGE2")"
git -C "$INST" checkout -q -- projects 2>/dev/null
git -C "$INST" clean -qfd projects 2>/dev/null

echo
echo "== keyed to the SHA: identical at one HEAD, different at the next =="
( cd "$INST" && SNAPSHOT_NOW=2026-08-26T00:00:00Z bash "$WRITER" --quiet ) >/dev/null 2>&1
others() { # <page> -> just the other-owners section
  awk '/Other owners/{p=1} p' "$1"
}
A="$TMP/a.html"; B="$TMP/b.html"
( cd "$INST" && bash "$GEN" --out "$A" . ) >/dev/null 2>&1
( cd "$INST" && bash "$GEN" --out "$B" . ) >/dev/null 2>&1
others "$A" > "$TMP/a.frag"; others "$B" > "$TMP/b.frag"
assert "the fragment is non-empty"               "$(yes_if test -s "$TMP/a.frag")"
assert "two runs at one HEAD are byte-identical" "$(yes_if cmp -s "$TMP/a.frag" "$TMP/b.frag")"
assert "…and the whole page is too"              "$(yes_if cmp -s "$A" "$B")"
assert "a cache was written, keyed to the SHA" \
  "$(yes_if grep -qF "$(git -C "$INST" rev-parse HEAD)" "$INST/$AB_BOARD_OTHERS")"
assert "…and it is gitignored by the seed" \
  "$(yes_if grep -qF '.board-others.json' "$TPL/plugin/seed/.gitignore")"
# Read through the resolver, not for a literal: init-bundle.sh spells the layout as
# `__AB_BOARD_OTHERS__` and ab_expand is what turns it back into a path.
assert "…and install.sh backfills that line"  \
  "$(yes_if bash -c '. "$1/plugin/scripts/bundle-paths.sh"; grep -qF "/$AB_BOARD_OTHERS" <<<"$(ab_expand < "$1/plugin/scripts/init-bundle.sh")"' _ "$TPL")"

# The wall clock is the FALLBACK, and only for the case where there is no SHA to key on.
# Hiding .git is the cheapest faithful version of that: `git rev-parse HEAD` fails, a
# fresh computation would return nothing, and serving the recent cached answer is what
# stops a momentarily unreadable repository from deleting every other owner off a
# published page.
mv "$INST/.git" "$INST/.git-off"
G="$TMP/g.html"; rcg=0
( cd "$INST" && bash "$GEN" --out "$G" . ) >"$TMP/g.err" 2>&1 || rcg=$?
assert "no SHA to key on: the render still exits 0"  "$(eq "$rcg" 0)"
assert "…and the recent cached section is served"    "$(fhas '>bob<' "$G")"
assert "…with no traceback"                          "$(fhasnt 'Traceback (most recent call last)' "$TMP/g.err")"
# …and it is a fallback, not a schedule: an EXPIRED entry is not served, so nothing here
# can quietly become a timer-driven refresh.
python3 - "$INST/$AB_BOARD_OTHERS" <<'PYX'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["at"] = 0
json.dump(d, open(p, "w", encoding="utf-8"))
PYX
H="$TMP/h.html"
( cd "$INST" && bash "$GEN" --out "$H" . ) >/dev/null 2>&1
assert "…and an EXPIRED entry is not served"         "$(fhasnt 'class="sep others"' "$H")"
assert "…nor any block for one"                      "$(fhasnt 'class="proj other"' "$H")"
mv "$INST/.git-off" "$INST/.git"

# A commit that changes another owner's document MUST move the section — the assertion a
# wall-clock cache fails.
sed -i.bak 's/^title: Bobs work$/title: Bobs renamed work/' "$INST/projects/bobs/project.md"
rm -f "$INST/projects/bobs/project.md.bak"
git -C "$INST" add -A >/dev/null 2>&1
git -C "$INST" commit -qm "bob renames" >/dev/null 2>&1
C="$TMP/c.html"
( cd "$INST" && bash "$GEN" --out "$C" . ) >/dev/null 2>&1
assert "a new HEAD recomputes the section"       "$(fhas 'Bobs renamed work' "$C")"
assert "…and the stale title is gone"            "$(fhasnt 'class="dim">Bobs work' "$C")"

echo
echo "== an unknown or absent owner is a page, never a crash =="
# No configured human at all. Every OWNED project is then somebody else's — the clone
# cannot prove a name is its own, the same refusal the dispatch gate makes — and unowned
# work still clears. What must not happen is a traceback.
rm -f "$INST/instance.config.local.json"
cfg '{ "org": "o" }'
( cd "$INST" && SNAPSHOT_NOW=2026-08-26T00:00:00Z bash "$WRITER" --quiet ) >/dev/null 2>&1
D="$TMP/d.html"; rcd=0
( cd "$INST" && bash "$GEN" --out "$D" . ) >"$TMP/d.err" 2>&1 || rcd=$?
assert "no ownerGithubUser: exits 0"             "$(eq "$rcd" 0)"
assert "…writes a page"                          "$(yes_if test -s "$D")"
assert "…with no traceback"                      "$(fhasnt 'Traceback (most recent call last)' "$TMP/d.err")"
assert "…unowned work is still mine"             "$(fhas 'class="ptitle">Mine<' "$D")"
assert "…and a named owner is still named"       "$(fhas '>bob<' "$D")"

# A directory that is not a git repository has no HEAD to key on: no second section, no
# error, and the own half renders exactly as before.
NOGIT="$TMP/_ai-bridge-solo"; mkdir -p "$NOGIT" "$NOGIT/$AB_DIR"
printf 'stub\n' > "$NOGIT/$AB_SCHEMA"
cp "$INST/instance.config.json" "$NOGIT/instance.config.json"
cp -R "$INST/projects" "$NOGIT/projects"
: > "$NOGIT/$AB_SNAPSHOT"
( cd "$NOGIT" && SNAPSHOT_NOW=2026-08-26T00:00:00Z bash "$WRITER" --quiet ) >/dev/null 2>&1
E="$TMP/e.html"; rce=0
( cd "$NOGIT" && bash "$GEN" --out "$E" . ) >"$TMP/e.err" 2>&1 || rce=$?
assert "a non-repo instance: exits 0"            "$(eq "$rce" 0)"
assert "…writes a page"                          "$(yes_if test -s "$E")"
assert "…with no traceback"                      "$(fhasnt 'Traceback (most recent call last)' "$TMP/e.err")"
# The Other owners TAB is always in the row (it names a filter, like every other tab);
# what an instance with no other owners must not have is the SECTION under it.
assert "…and simply has no second section"       "$(fhasnt 'class="sep others"' "$E")"
assert "…nor any block for one"                  "$(fhasnt 'class="proj other"' "$E")"
assert "…while the tab still names the filter"   "$(fhas 'data-pick="other">Other owners · 0' "$E")"

# An owner nobody has ever heard of, in a bundle with no defaultOwner and no local file:
# it is a string, it renders as a string, and it is HTML-escaped like every other string
# that comes out of a document.
mkproj hostile "Hostile" '<script>alert(1)</script>' draft
git -C "$INST" add -A >/dev/null 2>&1
git -C "$INST" commit -qm "hostile owner" >/dev/null 2>&1
( cd "$INST" && SNAPSHOT_NOW=2026-08-26T00:00:00Z bash "$WRITER" --quiet ) >/dev/null 2>&1
F="$TMP/f.html"; rcf=0
( cd "$INST" && bash "$GEN" --out "$F" . ) >"$TMP/f.err" 2>&1 || rcf=$?
assert "an unknown owner: exits 0"               "$(eq "$rcf" 0)"
assert "…with no traceback"                      "$(fhasnt 'Traceback (most recent call last)' "$TMP/f.err")"
assert "…and the owner name is escaped, not markup" \
  "$(fhasnt '<script>alert(1)</script>' "$F")"
assert "…rendered as inert text"                 "$(fhas '&lt;script&gt;' "$F")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
