#!/usr/bin/env bash
#
# kb-index-integrity.test.sh — `knowledge/index.md` is DERIVED, and the five defects that
# were repaired by hand on 2026-09-05/06 are now measured instead.
#
# WHY THIS SHAPE. The index was hand-curated across 133 findings: rows with empty summary
# cells, two findings with no row at all, rows whose unescaped `|` split the table into the
# wrong number of cells, and — in the whole life of the KB — not one finding ever
# superseded. Every one of those is invisible to a reader and fatal to an agent that reads
# the KB index-first, so each gets a FIXTURE CARRYING THAT DEFECT and an assertion that the
# checker goes red naming it.
#
# NON-VACUOUS BY CONSTRUCTION. The same checker runs on a clean fixture first and must exit
# 0. "It refuses" alone would pass a script that refuses everything — `.claude/rules/tests.md`.
# Each defect is planted into a fresh copy of that same clean tree, so a red is caused by
# the plant and nothing else.
#
# ok() compares actual to expected, in that order. Seeded ai-bridge-next/task-007.
set -uo pipefail

# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$(dirname "$0")/../plugin/scripts/bundle-paths.sh"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/plugin/scripts/build-kb-index.sh"
CITE="$REPO/plugin/scripts/cite-check.sh"
VOCAB="$REPO/plugin/seed/knowledge/vocab.md"
SEED_INDEX="$REPO/plugin/seed/knowledge/index.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
SEED_CLAUDE="$REPO/plugin/seed/CLAUDE.md"
CATALOGUER="$REPO/plugin/agents/cataloguer.md"
CLOSE="$REPO/plugin/skills/close-project/SKILL.md"
KB_RULE="$REPO/plugin/seed/.claude/rules/knowledge-base.md"
VALIDATE="$REPO/plugin/scripts/validate-bundle.sh"

for f in "$BUILD" "$CITE" "$VOCAB" "$SEED_INDEX" "$SCHEMA" "$SEED_CLAUDE" "$CATALOGUER" \
         "$CLOSE" "$KB_RULE" "$VALIDATE"; do
  [ -r "$f" ] || { echo "kb-index-integrity.test: missing $f" >&2; exit 2; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kb-index-integrity.XXXXXX")" \
  || { echo "kb-index-integrity.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has()  { grep -qF -- "$2" "$1" && echo yes || echo no; }
hasre(){ grep -qE -- "$2" "$1" && echo yes || echo no; }

# A clean bundle: three findings (one with a pipe in its title, one superseded pair),
# a runbook, and the shipped vocabulary.
seed_bundle() { # <dir>
  local d=$1
  mkdir -p "$d/knowledge/findings" "$d/knowledge/services" "$d/knowledge/runbooks" \
           "$d/knowledge/teams" "$d/knowledge/references"
  cp "$VOCAB" "$d/knowledge/vocab.md"
  : > "$d/knowledge/log.md"   # the generated index links it; every stamped bundle has one
  cat > "$d/knowledge/findings/pipe-in-title.md" <<'EOF'
---
type: Finding
title: A bare `grep | head | cut` assignment aborts under `set -e`
description: unused when a lesson is present
lesson: Assign a pipeline's result as an `if` condition, or `set -e` kills the script.
category: gotcha
tags: [ ci, false-green ]
status: current
timestamp: 2026-09-06T00:00:00Z
---
EOF
  cat > "$d/knowledge/findings/old-rule.md" <<'EOF'
---
type: Finding
title: The old rule
description: d
lesson: Replaced — see the new rule.
tags: [ github-actions ]
status: superseded
superseded_by: new-rule
timestamp: 2026-09-06T00:00:00Z
---

## Superseded 2026-09-06 — replaced by [[new-rule]]
EOF
  cat > "$d/knowledge/findings/new-rule.md" <<'EOF'
---
type: Finding
title: The new rule
description: d
lesson: This is what replaced the old rule.
tags: [ knowledge-base ]
status: current
supersedes: [ old-rule ]
timestamp: 2026-09-06T00:00:00Z
---
EOF
  cat > "$d/knowledge/runbooks/do-a-thing.md" <<'EOF'
---
type: Runbook
title: Do a thing
description: The steps for doing the thing.
timestamp: 2026-09-06T00:00:00Z
---
EOF
}

check_rc() { ( cd "$1" && bash "$BUILD" --check >"$TMP/out.$$" 2>&1; echo $? ); }
strict_rc() { ( cd "$1" && bash "$BUILD" --check --strict >"$TMP/out.$$" 2>&1; echo $? ); }
check_out() { cat "$TMP/out.$$"; }

echo "== the clean fixture builds, and the checker clears it =="
CLEAN="$TMP/clean"; seed_bundle "$CLEAN"
( cd "$CLEAN" && bash "$BUILD" >/dev/null 2>&1 )
ok "the generator wrote an index"        "$([ -f "$CLEAN/knowledge/index.md" ] && echo yes || echo no)" yes
ok "…and --check clears it (exit 0)"     "$(check_rc "$CLEAN")" 0
ok "…reporting the two supersession edges" "$(check_out | grep -c '2 supersession edge')" 1

echo
echo "== derived, not hand-written =="
cp "$CLEAN/knowledge/index.md" "$TMP/pass1"
( cd "$CLEAN" && bash "$BUILD" >/dev/null 2>&1 )
ok "a second pass is byte-identical"     "$(cmp -s "$TMP/pass1" "$CLEAN/knowledge/index.md" && echo same || echo differs)" same
ok "the summary is the lesson: verbatim" "$(has "$CLEAN/knowledge/index.md" 'This is what replaced the old rule.')" yes
ok "…not the description:"               "$(has "$CLEAN/knowledge/index.md" 'unused when a lesson is present')" no
ok "a pipe in a title is escaped"        "$(has "$CLEAN/knowledge/index.md" 'grep \| head \| cut')" yes
ok "it says it is derived"               "$(has "$CLEAN/knowledge/index.md" 'do not hand-edit')" yes

echo
echo "== superseded rows sit in their own section, BELOW the current ones =="
SUPHDR="$(grep -n '^### Superseded findings' "$CLEAN/knowledge/index.md" | cut -d: -f1)"
CURROW="$(grep -n 'findings/new-rule.md' "$CLEAN/knowledge/index.md" | cut -d: -f1)"
OLDROW="$(grep -n 'findings/old-rule.md' "$CLEAN/knowledge/index.md" | cut -d: -f1)"
ok "there is a Superseded section"       "$([ -n "$SUPHDR" ] && echo yes || echo no)" yes
ok "the current row is above it"         "$([ "$CURROW" -lt "$SUPHDR" ] && echo yes || echo no)" yes
ok "the superseded row is below it"      "$([ "$OLDROW" -gt "$SUPHDR" ] && echo yes || echo no)" yes
ok "…and names its replacement"          "$(sed -n "${OLDROW}p" "$CLEAN/knowledge/index.md" | grep -c 'new-rule |')" 1

echo
echo "== one fixture per defect: each measured RED, and named =="
plant() { # <name> — a fresh copy of the clean tree, index already built
  rm -rf "${TMP:?}/${1:?}"; cp -R "$CLEAN" "$TMP/$1"; printf '%s' "$TMP/$1"
}

D="$(plant no-row)"
grep -v 'pipe-in-title' "$D/knowledge/index.md" > "$D/k" && mv "$D/k" "$D/knowledge/index.md"
ok "a Finding with no index row: red"    "$(check_rc "$D")" 1
ok "…and the message names it"           "$(check_out | grep -c 'no index row')" 1

D="$(plant ghost-row)"
sed 's#/knowledge/findings/new-rule.md#/knowledge/findings/ghost.md#' "$D/knowledge/index.md" > "$D/k" && mv "$D/k" "$D/knowledge/index.md"
ok "a row pointing at no file: red"      "$(check_rc "$D")" 1
ok "…and the message names it"           "$(check_out | grep -c 'points at no file')" 1

D="$(plant empty-summary)"
sed 's#| This is what replaced the old rule. |#|  |#' "$D/knowledge/index.md" > "$D/k" && mv "$D/k" "$D/knowledge/index.md"
ok "an empty summary cell: red"          "$(check_rc "$D")" 1
ok "…and the message names it"           "$(check_out | grep -c 'empty summary cell')" 1

D="$(plant raw-pipe)"
sed 's#grep \\| head#grep | head#' "$D/knowledge/index.md" > "$D/k" && mv "$D/k" "$D/knowledge/index.md"
ok "an unescaped pipe in a cell: red"    "$(check_rc "$D")" 1
ok "…and the message names the cell count" "$(check_out | grep -c 'cells, expected 4')" 1

D="$(plant bad-status)"
sed 's#/knowledge/findings/new-rule.md` | current |#/knowledge/findings/new-rule.md` | open |#' "$D/knowledge/index.md" > "$D/k" && mv "$D/k" "$D/knowledge/index.md"
ok "a status outside the enum: red"      "$(check_rc "$D")" 1
ok "…and the message names the enum"     "$(check_out | grep -c 'outside {current, superseded, corrected, archived}')" 1

echo
echo "== corrected IS in the enum, on both readers =="
D="$(plant corrected)"
sed 's#^status: current#status: corrected#' "$D/knowledge/findings/new-rule.md" > "$D/k" && mv "$D/k" "$D/knowledge/findings/new-rule.md"
( cd "$D" && bash "$BUILD" >/dev/null 2>&1 )
ok "a corrected Finding clears --check"  "$(check_rc "$D")" 0
ok "validate-bundle allows it too"       "$(hasre "$VALIDATE" 'Finding\).*current superseded corrected')" yes

echo
echo "== archived IS in the enum, renders as history, and is never citable (task-005) =="
D="$(plant archived)"
sed 's#^status: current#status: archived#; s#^tags:#provenance: machine\ntags:#' "$D/knowledge/findings/pipe-in-title.md" > "$D/k" && mv "$D/k" "$D/knowledge/findings/pipe-in-title.md"
( cd "$D" && bash "$BUILD" >/dev/null 2>&1 )
ok "an archived Finding clears --check"  "$(check_rc "$D")" 0
printf '{}\n' > "$D/instance.config.json"
vb_errors() { ( cd "$D" && bash "$VALIDATE" knowledge/findings/pipe-in-title.md 2>&1 | sed -n 's/.* \([0-9]*\) errors.*/\1/p' ); }
ok "validate-bundle allows it too"       "$(vb_errors)" 0
sed 's#^status: archived#status: retired#' "$D/knowledge/findings/pipe-in-title.md" > "$D/k"
cp "$D/knowledge/findings/pipe-in-title.md" "$D/keep" && mv "$D/k" "$D/knowledge/findings/pipe-in-title.md"
ok "…and refuses a status outside it (control)" "$(vb_errors)" 1
mv "$D/keep" "$D/knowledge/findings/pipe-in-title.md"; rm -f "$D/instance.config.json"
ARCHDR="$(grep -n '^### Archived findings' "$D/knowledge/index.md" | cut -d: -f1)"
ARCROW="$(grep -n 'findings/pipe-in-title.md' "$D/knowledge/index.md" | cut -d: -f1)"
SUPHDR2="$(grep -n '^### Superseded findings' "$D/knowledge/index.md" | cut -d: -f1)"
ok "it sits in its own section, below Superseded" \
   "$([ -n "$ARCHDR" ] && [ "$ARCHDR" -gt "$SUPHDR2" ] && [ "$ARCROW" -gt "$ARCHDR" ] && echo yes || echo no)" yes
ok "…once, and still on disk"            "$(grep -c 'findings/pipe-in-title.md' "$D/knowledge/index.md")/$([ -f "$D/knowledge/findings/pipe-in-title.md" ] && echo yes)" 1/yes
ok "with no archived Finding there is no such section" \
   "$(grep -c '^### Archived' "$CLEAN/knowledge/index.md")" 0
printf 'See [[pipe-in-title]] and [[new-rule]].\n' > "$TMP/arch-cite.txt"
ok "cite-check drops a carried archived slug" \
   "$(bash "$CITE" --text-file "$TMP/arch-cite.txt" --brief pipe-in-title,new-rule --index "$D/knowledge/index.md" | grep -c '^ARCHIVED pipe-in-title ')" 1
ok "…exit 3: dropped, the line still cites" \
   "$(bash "$CITE" --text-file "$TMP/arch-cite.txt" --brief pipe-in-title,new-rule --index "$D/knowledge/index.md" >/dev/null; echo $?)" 3

echo
echo "== the controlled vocabulary is closed, and aliases resolve =="
D="$(plant good-alias)"
sed 's#tags: \[ ci, false-green \]#tags: [ github-actions, vacuous-pass ]#' "$D/knowledge/findings/pipe-in-title.md" > "$D/k" && mv "$D/k" "$D/knowledge/findings/pipe-in-title.md"
ok "two ALIASES are accepted"            "$(check_rc "$D")" 0
D="$(plant bad-tag)"
sed 's#tags: \[ ci, false-green \]#tags: [ ci, banana ]#' "$D/knowledge/findings/pipe-in-title.md" > "$D/k" && mv "$D/k" "$D/knowledge/findings/pipe-in-title.md"
ok "an invented tag is refused"          "$(check_rc "$D")" 1
ok "…and the message names the vocab"    "$(check_out | grep -c "tag 'banana' is not in knowledge/vocab.md")" 1

echo
echo "== typed supersession edges must resolve, and both ends must agree =="
D="$(plant dangling-edge)"
sed 's#^superseded_by: new-rule#superseded_by: never-existed#' "$D/knowledge/findings/old-rule.md" > "$D/k" && mv "$D/k" "$D/knowledge/findings/old-rule.md"
ok "a dangling edge is refused"          "$(check_rc "$D")" 1
ok "…and the message names the slug"     "$(check_out | grep -c 'supersession edge names no Finding: never-existed')" 1
D="$(plant half-supersede)"
sed 's#^status: superseded#status: current#' "$D/knowledge/findings/old-rule.md" > "$D/k" && mv "$D/k" "$D/knowledge/findings/old-rule.md"
ok "superseded_by: without the status: red" "$(check_rc "$D")" 1
ok "…and validate-bundle fails it too"   "$(hasre "$VALIDATE" 'carries superseded_by: but status is not')" yes

echo
echo "== bundle-relative links in knowledge/** resolve, or WARN with file:line =="
# One document carrying every case at a known line, so an assertion names the line it
# expects and a shifted report is a failure rather than a silent pass.
D="$(plant links)"
mkdir -p "$D/projects/live/tasks"
: > "$D/projects/live/tasks/task-001.md"
cat >> "$D/knowledge/findings/new-rule.md" <<'EOF'

Live absolute [t1](/projects/live/tasks/task-001.md) and relative [t2](old-rule.md).
Dead absolute [t3](/projects/closed/tasks/task-009.md).
Dead relative [t4](../runbooks/gone.md).
External [t5](https://example.invalid/x.md) and anchor [t6](#heading) and [t7](mailto:a@b.c).
Fragment on a live target [t8](/knowledge/vocab.md#tags).
Not markdown, so not ours: [t9](../assets/diagram.png).

```md
Inside a fence: [t10](/projects/closed/tasks/task-fence.md)
```
EOF
LINK_RC="$(check_rc "$D")"
ok "a broken link WARNS, never errors"     "$LINK_RC" 0
ok "…exactly the two dead links"           "$(check_out | grep -c 'link resolves to nothing')" 2
ok "…the dead absolute one, at file:line"  "$(check_out | grep -c 'new-rule.md:13$')" 1
ok "…and the dead relative one"            "$(check_out | grep -c 'new-rule.md:14$')" 1
ok "…naming the target that failed"        "$(check_out | grep -c '/projects/closed/tasks/task-009.md')" 1
ok "a live absolute link is silent"        "$(check_out | grep -c 'task-001.md')" 0
ok "…a live relative one too"              "$(check_out | grep -c 'old-rule.md$')" 0
ok "an external URL is not ours"           "$(check_out | grep -c 'example.invalid')" 0
ok "…nor a bare anchor or mailto:"         "$(check_out | grep -c 'heading\|mailto')" 0
ok "a #fragment resolves on the file"      "$(check_out | grep -c 'vocab.md')" 0
ok "a relative non-.md link is skipped"    "$(check_out | grep -c 'diagram.png')" 0
ok "a link inside a fence is an example"   "$(check_out | grep -c 'task-fence.md')" 0
ok "--strict promotes the warning to red"  "$(strict_rc "$D")" 1
ok "…saying so"                            "$(check_out | grep -c 'warnings are failures')" 1
CLEAN_RC="$(check_rc "$CLEAN")"
ok "the clean fixture breaks no link"      "$(check_out | grep -c 'link resolves to nothing')" 0
ok "…and still clears"                     "$CLEAN_RC" 0

echo
echo "== source: is a durable URL — a dangling path token WARNs, and never fails --check =="
# One document carrying every token shape, so "handled explicitly" cannot be satisfied by
# a value the tokeniser silently declines to look at.
add_source() { # <dir> <slug> <value> — insert a source: line above status:
  awk -v v="$3" '/^status:/ && !done { print "source: " v; done=1 } { print }' \
    "$1/knowledge/findings/$2.md" > "$1/k" && mv "$1/k" "$1/knowledge/findings/$2.md"
}

D="$(plant source-url)"
add_source "$D" new-rule 'https://github.com/cbmono/ai-bridge/pull/192'
ok "a PR URL carries no path token"        "$(check_rc "$D")" 0
ok "…so nothing is reported about it"      "$(check_out | grep -c 'source:')" 0

D="$(plant source-dangling)"
add_source "$D" pipe-in-title '/projects/closed/tasks/task-009.md'
ok "a dangling /projects path: --check clears" "$(check_rc "$D")" 0
ok "…reported at WARN, naming the doc"     "$(check_out | grep -c '^  WARN   knowledge/findings/pipe-in-title.md$')" 1
ok "…with the target"                      "$(check_out | grep -c 'source: resolves to nothing: /projects/closed/tasks/task-009.md')" 1
ok "…and what to write instead"            "$(check_out | grep -c 'blob/<sha> permalink')" 1
ok "…contributing 0 to the error count"    "$(check_out | grep -c '^build-kb-index: 0 error(s), 1 warning(s).$')" 1
# Non-vacuous: exit 0 alone would pass a checker that never looked at the field.
ok "…but --strict still turns it red"      "$(strict_rc "$D")" 1

D="$(plant source-escape)"
add_source "$D" pipe-in-title '/..'
# `.$tok` is `./..`, which EXISTS — so the existence test alone accepts a path
# outside the bundle as a valid bundle-relative source.
ok "a /.. token: --check still only warns"  "$(check_rc "$D")" 0
ok "…but it never rides the parent's existence" "$(check_out | grep -c 'source: escapes the bundle root: /\.\.')" 1

D="$(plant source-symlink)"
mkdir -p "$TMP/outside"; : > "$TMP/outside/leaked.md"
# The escape a text check cannot see: from the bundle's side the token spells no `..`,
# and the symlink still lands outside. `/inside` is the other half — not all links leave.
ln -s ../outside "$D/escaped"
ln -s knowledge/vocab.md "$D/inside"
add_source "$D" pipe-in-title '/escaped, /escaped/leaked.md'
add_source "$D" new-rule '/inside'
ok "a symlink out of the bundle: only warns" "$(check_rc "$D")" 0
ok "…the symlink itself is refused"          "$(check_out | grep -c 'escapes the bundle root: /escaped$')" 1
ok "…and so is a path through it"            "$(check_out | grep -c 'escapes the bundle root: /escaped/leaked.md$')" 1
ok "…neither read as resolving to nothing"   "$(check_out | grep -c 'resolves to nothing')" 0
ok "a symlink that stays inside is silent"   "$(check_out | grep -c '/inside')" 0

D="$(plant source-live)"
add_source "$D" new-rule '/knowledge/vocab.md'
ok "a path that resolves today is silent"  "$(check_rc "$D")" 0

D="$(plant source-prose)"
add_source "$D" new-rule '/knowledge/vocab.md — TICK 2026-08-31T18:26:13Z (ai-bridge#88)'
ok "PROSE around a live path still clears" "$(check_rc "$D")" 0
add_source "$D" pipe-in-title '/objectives/gone.md, /knowledge/vocab.md'
ok "a comma list: still only a warning"    "$(check_rc "$D")" 0
ok "…and it checks EVERY token"            "$(check_out | grep -c 'source: resolves to nothing')" 1
ok "…the dead one being the objectives path" "$(check_out | grep -c 'nothing: /objectives/gone.md')" 1

ok "the clean fixture carries no source:"  "$(check_rc "$CLEAN")" 0

echo
echo "== the policy is in the seed, so the NEXT document is written correctly =="
ok "SCHEMA names the field's own section"  "$(has "$SCHEMA" '#### `source:` is a durable URL, not a path into `projects/`')" yes
ok "…the PR URL first"                     "$(has "$SCHEMA" "the task's PR URL")" yes
ok "…the commit-pinned fallback"           "$(has "$SCHEMA" 'a commit-pinned permalink**, when there is no PR')" yes
ok "…the tokenisation rule the count uses" "$(has "$SCHEMA" 'every token beginning with `/` must resolve')" yes
ok "…the severity, and that it is WARN"    "$(has "$SCHEMA" 'A dangling token is a WARN')" yes
ok "…the measurement WARN rests on"        "$(has "$SCHEMA" '322 dangling of 514')" yes
ok "…and that body links are their own population" "$(has "$SCHEMA" 'different population')" yes
ok "…no ERROR claim survives the flip"     "$(has "$SCHEMA" 'A dangling token is an ERROR')" no
ok "…the old bare-path example is gone"    "$(has "$SCHEMA" 'e.g. /projects/.../tasks/<id>.md or a PR URL')" no
ok "validate-bundle points at the owner"   "$(has "$VALIDATE" 'build-kb-index.sh --check` owns it')" yes

echo
echo "== a superseded Finding is never citable =="
printf 'The rule applies [[new-rule]] and [[old-rule]].\nOnly history here [[old-rule]].\n' > "$TMP/cites.md"
CITE_RC=$( cd "$CLEAN" && bash "$CITE" --text-file "$TMP/cites.md" --brief new-rule,old-rule >"$TMP/cite.out" 2>&1; echo $? )
ok "a line that cited only it goes EMPTY (exit 1)" "$CITE_RC" 1
ok "…the superseded id is reported SUPERSEDED"     "$(grep -c '^SUPERSEDED old-rule' "$TMP/cite.out")" 2
ok "…and the current one is still KEPT"            "$(grep -c '^KEPT new-rule' "$TMP/cite.out")" 1

echo
echo "== what ships is what the generator would produce =="
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
cp -R "$REPO/plugin/seed/knowledge" "$EMPTY/knowledge"
cp "$VOCAB" "$EMPTY/knowledge/vocab.md"
( cd "$EMPTY" && bash "$BUILD" >/dev/null 2>&1 )
ok "the seed index is byte-identical to a rebuild" "$(cmp -s "$SEED_INDEX" "$EMPTY/knowledge/index.md" && echo same || echo differs)" same
ok "the seed ships the vocabulary"       "$([ -r "$VOCAB" ] && echo yes || echo no)" yes
ok "…with a longest-match instruction"   "$(has "$VOCAB" 'longest match')" yes

echo
echo "== the documents that tell agents to do this =="
ok "SCHEMA documents the supersede move" "$(has "$SCHEMA" 'Superseding a Finding')" yes
ok "…with both typed edges"              "$(hasre "$SCHEMA" '^supersedes:.*Findings this one replaces')" yes
ok "…and the dated section it requires"  "$(has "$SCHEMA" '## Superseded 2026-09-06 — replaced by')" yes
ok "…and tags: pointing at vocab.md"     "$(has "$SCHEMA" 'from /knowledge/vocab.md ONLY')" yes
ok "the cataloguer rebuilds, never edits" "$(has "$CATALOGUER" 'scripts/build-kb-index.sh --check')" yes
ok "…and runs the supersede pass"        "$(has "$CATALOGUER" 'Supersede rather than delete')" yes
ok "close-project step 2 supersedes"     "$(has "$CLOSE" 'supersede what this project made untrue')" yes
ok "…and rebuilds the index"             "$(has "$CLOSE" 'scripts/build-kb-index.sh')" yes
ok "seed CLAUDE.md: index first"         "$(has "$SEED_CLAUDE" 'index first, at most three, superseded rows are history')" yes
ok "…and it drops the old 1–3 wording"   "$(has "$SEED_CLAUDE" 'open only the 1–3')" no
ok "the KB rule repeats the three points" "$(has "$KB_RULE" 'history, not guidance')" yes
ok "the README row names the link check" "$(has "$REPO/README.md" 'bundle-relative link in `knowledge/**`')" yes

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
