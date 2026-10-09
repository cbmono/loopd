#!/usr/bin/env bash
#
# install-era-wording.test.sh — every surviving mention of `install.sh`, `upgrade.sh` or
# `symlink/` in the shipped surface is DECLARED, nothing may tell a reader to run either
# retired script, and the retired `/pm-loop` command name appears nowhere at all.
#
# WHY THIS IS A TEST AND NOT A ONE-OFF SWEEP. `install.sh` and `upgrade.sh` are refusal
# stubs that exit 2, and `symlink/` is a directory that no longer exists — so a sentence
# naming one of them is either HISTORY, which is fine and often load-bearing, or a stale
# instruction, which is a defect. The two look identical to a grep, and they read
# identically to a reviewer who already knows which is which. That is exactly the class
# that rots: ai-bridge-v2/task-025 found eight files carrying the wording months after the
# replatform, and two of them were not history at all — `docs/pm-design.md` pointed a
# reader at `symlink/.claude/commands/pm-loop.md` in the present tense for a file that had
# moved into `plugin/`, and `docs/conventions.md`'s own table of contents linked to
# `#…letting-installsh-sweep-the-links` for a heading that had been renamed out from under
# it. Finding those cost a hunt across 56 mentions. THE POINT OF THIS FILE IS THAT THE
# NEXT SWEEP IS A DIFF INSTEAD.
#
# THE FOUR PROPERTIES, AND WHY EACH IS SHAPED THE WAY IT IS. The last two are stated at
# their own sections below, because what makes them different is that they have no
# allowlist.
#
#   1. THE INVENTORY EQUALS THE ALLOWLIST, EXACTLY — a new mention fails, and so does a
#      new FILE. `ALLOWED` below is the declared set: one row per file, the number of
#      matching LINES it may carry, and the reason that file is allowed to carry them.
#      Equality is asserted in BOTH directions. An unknown file or a raised count is the
#      new mention this file exists to catch; a count that DROPPED, or a file that went
#      quiet, is also a failure, because a stale allowlist entry is an allowance nobody
#      re-read — it silently re-opens the budget it was meant to spend.
#
#      COUNTS, NOT LINE NUMBERS. A line number churns on every edit above it, which would
#      turn this into a file everyone re-baselines without reading; a count moves only
#      when a mention is genuinely added or removed. The trade is stated rather than
#      hidden: deleting one historical mention and adding one stale mention in the SAME
#      file passes here. The reason cells are what a reviewer reads to close that gap, and
#      property 2 catches the worst version of it outright.
#
#   2. NOTHING IN SCOPE INSTRUCTS A READER TO RUN EITHER RETIRED SCRIPT. This is the half
#      that does not depend on anyone maintaining a number. `./install.sh`, `bash
#      upgrade.sh`, "run install.sh" and friends are matched wherever they appear in
#      scope, and there is no allowlist for them at all — a bundle installed today has
#      `/<plugin>:init` and `/<plugin>:welcome fix`, and any surviving imperative for
#      the old pair sends its reader to a script that exits 2.
#
#   3. NOTHING IN SCOPE CLAIMS, IN THE PRESENT TENSE, THAT A SHIPPED FILE IS SYMLINKED,
#      SHARED, OR IDENTICAL ACROSS INSTANCES. Its own section states the grammar and why
#      it has no allowlist either. Added by ai-bridge-v2/task-031, which found five such
#      claims that properties 1 and 2 are structurally unable to see: the false sentence
#      says the WORD `symlinked`, and the word contains none of `install.sh`,
#      `upgrade.sh` or `symlink/`.
#
# SCOPE IS THE TRACKED SHIPPED SURFACE: `README.md`, `docs/`, `plugin/` and `.claude/`.
# Two exclusions, both deliberate and both the task's: `docs/migrating.md` is the
# conversion guide, whose entire job is to name the old commands, and `docs/releases/` is a
# frozen record of what shipped. The repo ROOT `install.sh` / `upgrade.sh` stubs are out of
# scope too — they are the retirement, not a mention of it. `tests/` is out of scope, which
# is what lets this file quote the tokens it looks for.
#
# `.claude/` JOINED THE SCOPE IN task-031, and it cost one collision, fixed rather than
# excluded: `.claude/rules/installer.md` declares `- "/install.sh"` in its YAML `paths:`
# block, which is the rule saying WHICH FILE IT LOADS FOR, and `RUN_RE` matched that
# verbatim as an imperative. See `body_lines` below.
#
# EVERY PROPERTY IS PROVEN CAPABLE OF FAILING against a fixture copy of the tree that
# plants exactly the defect it checks — and property 3, which must NOT fire on history,
# is additionally proven capable of PASSING a planted historical sentence. A check that
# can only pass is not a check, and a claim grammar that fires on history is an allowlist
# with extra steps.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-era-wording.XXXXXX")" || {
  echo "install-era-wording.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# The pattern, written once. `symlink/` needs no word boundary — the directory is gone, so
# every occurrence of the literal path component is a mention of the retired layout.
ERA_RE='install\.sh|upgrade\.sh|symlink/'

# An IMPERATIVE to run one of the retired scripts, as opposed to naming it. Path-prefixed
# (`./install.sh`, `<clone>/upgrade.sh`), interpreter-prefixed (`bash install.sh`), or
# verb-prefixed ("run install.sh", "re-run upgrade.sh"). Deliberately narrow: the job is to
# catch a surviving instruction, not to police every sentence that contains a verb.
#
# THE `.` (source) FORM IS DELIBERATELY ABSENT. It was in the first cut and matched an
# ordinary sentence-ending period — "AND THAT IS THE WHOLE CHANGE. install.sh stamped 37
# files" — which is prose, and history, and exactly what this half must not flag. Nothing
# in this repo sources either script, so the alternative bought a false positive and no
# coverage.
RUN_RE='(\./|/)(install|upgrade)\.sh|(bash|sh|zsh|exec|source) +(install|upgrade)\.sh|(run|Run|RUN|running|re-run|Re-run) +`?(install|upgrade)\.sh'

# A YAML FRONTMATTER PATH GLOB IS NOT AN IMPERATIVE, and that is a real collision rather
# than a hypothetical one: `.claude/rules/installer.md` opens with
#
#     paths:
#       - "/install.sh"       # the deprecation stub; delete this entry when the stub goes
#       - "/upgrade.sh"       # ditto
#
# which is the rule declaring WHICH FILES IT LOADS FOR — the exact opposite of telling
# anyone to run one — and `RUN_RE`'s `(\./|/)(install|upgrade)\.sh` alternative matches it
# character for character. Fixed STRUCTURALLY and not by an allowlist entry: a sequence
# item whose whole value is a path, INSIDE the leading `---` block, is blanked before
# `RUN_RE` sees it. Blanked and not deleted, so line numbers still point at the file.
# Nothing else is exempted — a path in prose, or a `paths:` entry anywhere but the
# frontmatter, is read exactly as before.
FM_PATH_ITEM_RE='^[[:space:]]*-[[:space:]]*"?/[A-Za-z0-9._*/-]+"?[[:space:]]*(#.*)?$'

# body_lines — the file with those frontmatter path globs blanked, line numbers preserved.
body_lines() { # <file>
  awk -v re="$FM_PATH_ITEM_RE" '
    NR==1 && $0 == "---" { fm=1; print; next }
    fm    && $0 == "---" { fm=0; print; next }
    fm    && $0 ~ re      { print ""; next }
                          { print }
  ' "$1"
}

# =========================================================================================
# THE DECLARED SET — `<path> <matching-lines> <why this file may carry them>`
#
# Add a row only after reading the mention and deciding it is HISTORY. If it is an
# instruction, or a present-tense claim about how the machinery works today, fix the
# sentence instead; that is what this table is for.
# =========================================================================================
ALLOWED='
.claude/rules/installer.md	4	the paths: globs that load this rule for the two stubs, the sentence naming them AS the stubs, and the conversion sweep /symlink/ target test
README.md	4	the three lines naming install.sh as the thing /'"${PN}:"'init replaced or converts a bundle from, past tense, and the Scripts row for init-bundle.sh
docs/conventions.md	2	the relocation History blockquote, and the retired unstamped-machinery row, both past tense
docs/operations.md	2	the /symlink/ target test the conversion sweep STILL applies, and the eight commands that became skills
docs/pm-design.md	1	where the two step files moved FROM, past tense
plugin/README.md	2	names the retired install.sh as the thing /'"${PN}:"'init converts a bundle from
plugin/RETIRED	2	the plugin-migration audit: sixteen machinery paths, none of them seed content
plugin/hooks/session-banner.sh	3	live legacy-link detection, plus two past-tense incident notes
plugin/scripts/init-bundle.sh	23	the replacement itself — its header is the record of what install.sh and upgrade.sh did
plugin/scripts/refresh-seeds.sh	4	the record of upgrade.sh stage 4, which is what this script is
plugin/scripts/resolve-autonomy.sh	1	what used to stamp AUTONOMY.md, and the note that nothing stamps it now
plugin/scripts/task-owner.sh	1	an SC2295 trap install.sh HAD, cited as precedent
plugin/scripts/write-snapshot.sh	1	why AUTONOMY.md stopped living under the machinery, past tense
plugin/skills/init/SKILL.md	1	names the old install.sh as the thing a Convert run converts a bundle from
'

# scope_files — the tracked shipped surface, minus the two documented exclusions.
scope_files() { # <root>
  ( cd "$1" && git ls-files -- README.md docs plugin .claude 2>/dev/null ) \
    | grep -vx 'docs/migrating\.md' | grep -v '^docs/releases/'
}

# inventory — `<path>\t<matching lines>` for every scoped file with at least one, sorted.
# Counts LINES, which is what `grep -c` gives and what the allowlist above declares.
inventory() { # <root>
  local root="$1" f n
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    n="$(grep -cE "$ERA_RE" "$root/$f" 2>/dev/null)" || n=0
    [ "${n:-0}" -gt 0 ] && printf '%s\t%s\n' "$f" "$n"
  done < <(scope_files "$root") | LC_ALL=C sort
}

# imperatives — `<path>:<line>:<text>` for every surviving instruction to run either stub.
imperatives() { # <root>
  local root="$1" f
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    body_lines "$root/$f" | grep -nE "$RUN_RE" 2>/dev/null | sed "s|^|$f:|"
  done < <(scope_files "$root")
}

# The allowlist as `<path>\t<count>`, in the same shape and order `inventory` emits.
declared() {
  printf '%s\n' "$ALLOWED" | grep -v '^[[:space:]]*$' \
    | awk -F'\t' '{ printf "%s\t%s\n", $1, $2 }' | LC_ALL=C sort
}

# =======================================================================================
echo "== 1. every mention in scope is declared, and every declaration is still real =="
# =======================================================================================
inventory "$REPO" > "$TMP/actual"
declared              > "$TMP/declared"

ok "the allowlist declares a reason for every file it allows" \
   "$(printf '%s\n' "$ALLOWED" | grep -v '^[[:space:]]*$' | awk -F'\t' 'NF!=3 || $3=="" {n++} END{print n+0}')" 0
ok "…and every count it declares is a number" \
   "$(printf '%s\n' "$ALLOWED" | grep -v '^[[:space:]]*$' | awk -F'\t' '$2 !~ /^[0-9]+$/ {n++} END{print n+0}')" 0

undeclared="$(LC_ALL=C comm -23 "$TMP/actual" "$TMP/declared")"
stale="$(LC_ALL=C comm -13 "$TMP/actual" "$TMP/declared")"

ok "no undeclared mention in README.md, docs/ or plugin/" \
   "$([ -z "$undeclared" ] && echo none || printf '%s' "$undeclared" | tr '\n' ' ')" none
ok "no allowlist row that no longer matches the tree" \
   "$([ -z "$stale" ] && echo none || printf '%s' "$stale" | tr '\n' ' ')" none

# The two exclusions are asserted rather than assumed: if either stops being excluded, the
# counts above become a running battle with a document whose job is to name the old names.
ok "docs/migrating.md is excluded from the scope" \
   "$(scope_files "$REPO" | grep -cx 'docs/migrating\.md' | tr -d ' ')" 0
ok "…and so is docs/releases/" \
   "$(scope_files "$REPO" | grep -c '^docs/releases/' | tr -d ' ')" 0
# …and that the scope is not empty, which would make every check above vacuously true.
ok "the scope is non-empty" \
   "$([ "$(scope_files "$REPO" | wc -l | tr -d ' ')" -gt 50 ] && echo yes || echo no)" yes

# =======================================================================================
echo
echo "== 2. nothing in scope tells a reader to RUN install.sh or upgrade.sh =="
# =======================================================================================
# No allowlist here on purpose. Both scripts exit 2, so an instruction to run either is a
# defect wherever it is, and a reader who has only ever known the plugin cannot tell that
# from the sentence.
found="$(imperatives "$REPO")"
ok "no surviving instruction to run either retired script" \
   "$([ -z "$found" ] && echo none || head -3 <<<"$found" | tr '\n' ' ')" none

# The frontmatter carve-out, both directions, on the real file that motivated it. Without
# `body_lines` the first of these is 2 — the `paths:` globs — and adding `.claude/` to the
# scope would have had to buy that with an exclusion instead of a fix.
ok "a paths: glob naming the stubs is not read as an imperative" \
   "$(imperatives "$REPO" | grep -c '^\.claude/rules/installer\.md' | tr -d ' ')" 0
blanked="$(diff <(body_lines "$REPO/.claude/rules/installer.md") \
                "$REPO/.claude/rules/installer.md" | grep '^> ' | sed 's/^> //')"
ok "…the carve-out blanked something, so the two above are not vacuous" \
   "$([ -n "$blanked" ] && echo yes || echo no)" yes
ok "…and every line it blanked was a frontmatter path glob" \
   "$(printf '%s\n' "$blanked" | grep -cvE "$FM_PATH_ITEM_RE" | tr -d ' ')" 0

# =======================================================================================
echo
echo "== 3. both checks are capable of failing =="
# =======================================================================================
# A fixture copy of the tracked scope, so the mutants below cannot touch the checkout. It
# is a git repo of its own, because `scope_files` asks git what is tracked.
#
# Copied from the WORKING TREE and not from `git archive HEAD`: this harness has to agree
# with the tree a reviewer is looking at, and a fixture built from HEAD reproduces the last
# commit instead — which makes the equality check below fail on every branch that has done
# any of the sweeping, i.e. exactly the branches this file exists for.
FIX="$TMP/fixture"; mkdir -p "$FIX"
while IFS= read -r f; do
  mkdir -p "$FIX/$(dirname "$f")" && cp "$REPO/$f" "$FIX/$f"
done < <( cd "$REPO" && git ls-files -- README.md docs plugin .claude 2>/dev/null )
( cd "$FIX" && git init -q . && git add -A && \
  git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false commit -qm f ) >/dev/null 2>&1

ok "the fixture reproduces the real inventory" \
   "$(diff -q <(inventory "$FIX") <(inventory "$REPO") >/dev/null && echo same || echo differs)" same

# (a) a NEW mention in an already-allowed file raises its count
printf '\n<!-- a fresh mention of symlink/.claude/commands/ -->\n' >> "$FIX/docs/pm-design.md"
mutant="$(LC_ALL=C comm -23 <(inventory "$FIX") "$TMP/declared")"
ok "…a new mention in an allowed file is undeclared" \
   "$(printf '%s' "$mutant" | grep -c '^docs/pm-design\.md' | tr -d ' ')" 1

# (b) a mention in a file the allowlist has never heard of
printf '\n<!-- symlink/.claude/agents/ -->\n' >> "$FIX/docs/onboarding.md"
mutant="$(LC_ALL=C comm -23 <(inventory "$FIX") "$TMP/declared")"
ok "…a mention in an unlisted file is undeclared" \
   "$(printf '%s' "$mutant" | grep -c '^docs/onboarding\.md' | tr -d ' ')" 1

# (c) a surviving instruction to run the retired installer
printf '\nStamp the bundle: `./install.sh ~/workspace/foo/_ai-bridge-foo`\n' >> "$FIX/docs/onboarding.md"
printf '\nThen `bash upgrade.sh` to merge the seeds.\n' >> "$FIX/docs/operations.md"
mut_run="$(imperatives "$FIX")"
ok "…a planted ./install.sh instruction is caught" \
   "$(printf '%s' "$mut_run" | grep -c '^docs/onboarding\.md' | tr -d ' ')" 1
ok "…and a planted bash-upgrade.sh instruction is caught" \
   "$(printf '%s' "$mut_run" | grep -c '^docs/operations\.md' | tr -d ' ')" 1

# (d) the carve-out is a carve-out and not a hole: an imperative in the BODY of the very
# file whose frontmatter is exempt is still caught.
printf '\nStamp it first: `./install.sh <bundle>`\n' >> "$FIX/.claude/rules/installer.md"
ok "…an imperative in the body of a frontmatter-carved file is caught" \
   "$(imperatives "$FIX" | grep -c '^\.claude/rules/installer\.md' | tr -d ' ')" 1

# (e) the reverse direction: an allowlist row whose file has gone quiet
sed -i.bak -E 's/install\.sh|upgrade\.sh|symlink\//RETIRED-NAME/g' "$FIX/docs/pm-design.md" && rm -f "$FIX/docs/pm-design.md.bak"
ok "…a row whose mentions all disappeared is reported stale" \
   "$(LC_ALL=C comm -13 <(inventory "$FIX") "$TMP/declared" | grep -c '^docs/pm-design\.md' | tr -d ' ')" 1

# =======================================================================================
echo
echo "== 4. the retired /pm-loop command name is gone from the shipped surface =="
# =======================================================================================
# THE SAME REPLATFORM RETIRED A SECOND NAME, and it rots the same way. `/pm-loop` became
# `/<plugin>:dispatch` in ai-bridge-v2/task-005, and the sweep reached the command file
# and not the strings around it: the first 1.0.0 session on a real bundle printed
# "18 items need you — see the board above, or run /pm-loop" out of `session-banner.sh`,
# a command the installed plugin does not have. `grep` found ~60 more across `plugin/`.
#
# WHY IT NEEDS NO ALLOWLIST, WHICH IS THE DIFFERENCE FROM PROPERTY 1. `install.sh` is a
# refusal stub that still exists, so naming it can be legitimate history; `/pm-loop` is a
# command the runtime cannot resolve at all, so every mention inside the shipped surface
# reads as an instruction whatever the sentence around it intends. The two documents where
# naming it IS the job — `docs/migrating.md`, the conversion guide, and `docs/releases/`,
# the frozen record of what shipped — are already out of `scope_files`, and property 1
# asserts that exclusion above. So the budget here is zero and stays zero.
#
# THE PLUGIN HALF IS ASSERTED IN THE CRITERION'S OWN FORM — `grep -r 'pm-loop' plugin/`,
# on the tree rather than through `git ls-files` — because that is the command the task
# was written against and an untracked file under `plugin/` ships just the same.
PM_RE='pm-loop'

# pm_hits — `<path>:<line>:<text>` for every surviving mention in the tracked scope.
pm_hits() { # <root>
  local root="$1" f
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    grep -nE "$PM_RE" "$root/$f" 2>/dev/null | sed "s|^|$f:|"
  done < <(scope_files "$root")
}

pm_found="$(pm_hits "$REPO")"
ok "no /pm-loop mention in README.md, docs/ or plugin/" \
   "$([ -z "$pm_found" ] && echo none || head -3 <<<"$pm_found" | tr '\n' ' ')" none
ok "…and plugin/ carries none, counted as the criterion counts it" \
   "$( ( cd "$REPO" && grep -r 'pm-loop' plugin/ 2>/dev/null | wc -l ) | tr -d ' ' )" 0

# CAPABLE OF FAILING, both halves, against the same fixture tree property 3 built. A
# document and a script, because the two halves read the tree by different routes.
printf '\nRun `/pm-loop` when the queue has work.\n' >> "$FIX/docs/sharing.md"
printf '\n# a /pm-loop tick renders it\n'            >> "$FIX/plugin/scripts/build-board.sh"
ok "…a planted mention in a doc is caught" \
   "$(pm_hits "$FIX" | grep -c '^docs/sharing\.md' | tr -d ' ')" 1
ok "…and a planted mention under plugin/ fails the criterion's own grep" \
   "$( ( cd "$FIX" && grep -r 'pm-loop' plugin/ 2>/dev/null | wc -l ) | tr -d ' ' )" 1

# =======================================================================================
echo
echo "== 5. nothing in scope claims a shipped file IS symlinked, shared or identical =="
# =======================================================================================
# WHY THIS PROPERTY EXISTS AT ALL. Properties 1 and 2 sweep `install.sh`, `upgrade.sh` and
# `symlink/`, and are STRUCTURALLY unable to see the defect ai-bridge-v2/task-031 found:
# the false sentence says the WORD `symlinked`, which contains none of those three
# strings. Five documents still described the pre-plugin model, and four of them SHIP INTO
# EVERY BUNDLE a `/<plugin>:init` stamp creates — `plugin/seed/SCHEMA.md` told its owner
# "this file is symlinked from the `loopd` template and is identical across every
# instance", which is the opposite of the copy-once contract 1.0.0 shipped, and reads to
# that owner as "your edits here are pointless". The same file's own README already said
# the right thing 180 lines further down.
#
# WHY IT HAS NO ALLOWLIST, WHICH IS THE WHOLE DESIGN. The obvious move was to widen
# property 1's `ALLOWED` table with the bare word forms. That table declares a per-file
# COUNT, so a file may swap a historical mention for a new present-tense falsehood and
# keep its number — property 1's own header says so — and the scale settles it anyway:
# measured at `182664d`, the bare words `symlinked`/`symlinks`/`symlink` match **201 lines
# across 49 files** inside property 1's scope, 324 across 86 tree-wide. Nobody re-reads a
# 49-row table.
#
# So this property asserts a GRAMMAR and budgets ZERO. The five findings are all
# present-tense CLAIMS; not one of the ~200 legitimate mentions is. Three classes fall
# outside it BY CONSTRUCTION rather than by an allowlist entry, and each has a mutant
# below proving it:
#
#   HISTORY          `normalize` blanks `was|were|been|no longer|never|used to be`
#                    immediately before `symlinked`, so a past-tense sentence cannot
#                    reach the grammar. This is why `docs/conventions.md`'s invariant-20
#                    rationale could be moved to the past tense instead of re-argued.
#   THE `repos/`     the sweep's own logic — "never writes THROUGH a symlinked
#   SYMLINKS AND     directory", "a symlinked parent", "a symlinked root", "$TMPDIR is
#   THE CONVERSION   symlinked on macOS" — all true, all about somebody's machine rather
#   SWEEP            than about a shipped file, and all outside the closed noun lists.
#   NAMING A STUB    a sentence may call `install.sh` a deprecation stub; what it may not
#                    do is call a LIVE `/<plugin>:` command one.
#
# THE GRAMMAR IS MATCHED AGAINST A NORMALIZED LINE, not the raw one, because the claim is
# written four different ways with markdown in the middle of it — `is **symlinked in**
# from the template` is one of the five and no plain-text pattern reaches it.

# normalize — lowercase, strip markdown emphasis and backticks, collapse space runs, then
# neutralize the past-tense and negated forms. `tr` and a POSIX `sed -E` only: this repo
# refuses GNU-only regex escapes in shipped scripts because they are a silent wrong ANSWER
# on a BSD box rather than an error, and the same reasoning applies to its harnesses.
normalize() { # reads stdin
  tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[*`_]//g; s/  +/ /g' \
    | sed -E 's/(is|are|was|were) +(no longer|never|not) +symlinked/formerly-linked/g' \
    | sed -E 's/(no longer|never|not|nothing|nobody|none) +(is|are|was|were) +symlinked/formerly-linked/g' \
    | sed -E 's/(was|were|been|used to be|no longer|never) +symlinked/formerly-linked/g' \
    | sed -E 's/(was|were) +(a|an|the) +symlinked/formerly-linked/g'
}

# CLAIM_RE — a PRESENT-TENSE claim that a SHIPPED file IS symlinked, shared or identical
# across instances. Four shapes, and the two closed lists are what keep history and the
# surviving `repos/` links out without anyone maintaining a table:
#
#   symlinked from|into|to …       provenance — it came from the template, or goes into
#                                  an instance. `plugin/seed/agents/index.md`'s
#                                  "(symlinked from the loopd template)" has no verb
#                                  at all, so the verb cannot be what this matches on.
#   <our noun> is|are symlinked    the bare predicate. CLOSED subject list, which is why
#                                  "$TMPDIR is symlinked on macOS" is not a hit.
#   a|an|the symlinked <our noun>  the attributive form. Same closed noun list, which is
#                                  why "through a symlinked directory" is not a hit.
#   identical|shared across …      the half that actually tells an owner not to edit.
CLAIM_RE='symlinked (in )?(from|into|to)( |$)'
CLAIM_RE="$CLAIM_RE"'|( |^)(machinery|files?|docs?|documents?|scripts?|agents?|commands?|hooks?|cop(y|ies)|this|that|it|they|which) (is|are) symlinked'
CLAIM_RE="$CLAIM_RE"'|( |^)(a|an|the) symlinked [a-z./-]*(template|machinery|file|script|doc|settings|cop(y|ies)|checkout|instance|bundle)'
CLAIM_RE="$CLAIM_RE"'|(identical|shared|the same) across (all|every|each|any) instances?'

# The second clause, which needs three conditions and so cannot be one regex: a line that
# calls a LIVE slash command a retirement stub. `.claude/rules/installer.md:15` said
# `/<plugin>:init` and `/<plugin>:welcome fix` were the one-screen stubs that exit 2 —
# backwards, and that file's frontmatter hands the rule to an agent exactly when it is
# about to edit the installer, so the agent is told at load time that the command it is
# fixing is retired. Naming `install.sh` or `upgrade.sh` on the line is what makes the
# CORRECT sentence green, and is also why `plugin/README.md`'s note about the retired
# `ai-bridge-v2` marketplace name — which names no slash command — is not a hit.
STUB_RE='(deprecation|refusal|one-screen) stubs?'
LIVE_CMD_RE='/'"$PN"':[a-z-]+'

# claim_hits — `<path>:<line>:<the real line>` for every present-tense claim in scope.
# The match runs on the normalized text; the REPORT quotes the file, so a failure names
# something a reader can go and find.
claim_hits() { # <root>
  local root="$1" f n
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      printf '%s:%s:%s\n' "$f" "$n" "$(sed -n "${n}p" "$root/$f")"
    done < <(normalize < "$root/$f" | grep -nE "$CLAIM_RE" | cut -d: -f1)
  done < <(scope_files "$root")
}

# stub_hits — `<path>:<line>:<the real line>` for every line calling a live command a stub.
stub_hits() { # <root>
  local root="$1" f n
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      printf '%s:%s:%s\n' "$f" "$n" "$(sed -n "${n}p" "$root/$f")"
    done < <(normalize < "$root/$f" | grep -nE "$STUB_RE" | grep -E "$LIVE_CMD_RE" \
             | grep -vE '(install|upgrade)\.sh' | cut -d: -f1)
  done < <(scope_files "$root")
}

claims="$(claim_hits "$REPO")"
ok "no present-tense symlinked/shared/identical claim in scope" \
   "$([ -z "$claims" ] && echo none || head -3 <<<"$(printf '%s' "$claims" | cut -d: -f1-2)" | tr '\n' ' ')" none

stubs="$(stub_hits "$REPO")"
ok "no live /${PN}: command is called a deprecation stub" \
   "$([ -z "$stubs" ] && echo none || head -3 <<<"$(printf '%s' "$stubs" | cut -d: -f1-2)" | tr '\n' ' ')" none

# =======================================================================================
echo
echo "== 6. the claim grammar catches the five findings, and leaves history alone =="
# =======================================================================================
# THE FIVE, RESTORED VERBATIM as they stood at `182664d`, into a fresh fixture. This is
# the check that would have been red before ai-bridge-v2/task-031 and is green after, and
# it is pinned by content rather than by a count so that rewording one of the five cannot
# quietly retire its coverage.
PRE="$TMP/pre"; mkdir -p "$PRE/plugin/seed/agents" "$PRE/docs" "$PRE/.claude/rules"
cat > "$PRE/plugin/seed/SCHEMA.md" <<'PRE_EOF'
> **Generic template file.** This file is symlinked from the `loopd`
> template and is identical across every instance. Instance-specific values
PRE_EOF
cat > "$PRE/plugin/seed/agents/index.md" <<'PRE_EOF'
> **Generic template file** (symlinked from the `loopd` template).
PRE_EOF
cat > "$PRE/plugin/seed/README.md" <<'PRE_EOF'
is **symlinked in** from the template and gitignored; the slash commands come from
(gitignored) — never edit the symlinked `.claude/settings.json`, which is shared
across all instances.
PRE_EOF
cat > "$PRE/docs/schema.md" <<'PRE_EOF'
That file is machinery: it is symlinked into every instance, every role agent reads it,
PRE_EOF
sed "s/__PN__/$PN/g" > "$PRE/.claude/rules/installer.md" <<'PRE_EOF'
`plugin/seed/`. **`/__PN__:init` and `/__PN__:welcome fix` at the root are one-screen deprecation stubs**
that print the `/__PN__:init` line and exit 2; they ship for one version and are then
PRE_EOF
( cd "$PRE" && git init -q . && git add -A && \
  git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false commit -qm p ) >/dev/null 2>&1

ok "finding 1 — plugin/seed/SCHEMA.md is caught" \
   "$(claim_hits "$PRE" | grep -c '^plugin/seed/SCHEMA\.md' | tr -d ' ')" 2
ok "finding 2 — plugin/seed/agents/index.md is caught" \
   "$(claim_hits "$PRE" | grep -c '^plugin/seed/agents/index\.md' | tr -d ' ')" 1
ok "finding 3 — plugin/seed/README.md is caught, both lines" \
   "$(claim_hits "$PRE" | grep -c '^plugin/seed/README\.md' | tr -d ' ')" 2
ok "finding 4 — docs/schema.md is caught" \
   "$(claim_hits "$PRE" | grep -c '^docs/schema\.md' | tr -d ' ')" 1
ok "finding 5 — the inverted installer rule is caught by the stub clause" \
   "$(stub_hits "$PRE" | grep -c '^\.claude/rules/installer\.md' | tr -d ' ')" 1

# …AND THE THREE CLASSES THAT MUST STAY OUT. A grammar that fires on these is an allowlist
# with extra steps, which is the instrument this property exists instead of.
QUIET="$TMP/quiet"; mkdir -p "$QUIET/docs" "$QUIET/.claude/rules"
cat > "$QUIET/docs/history.md" <<'QUIET_EOF'
0.36.0 was a git checkout you cloned, and every script was symlinked into every instance.
The machinery used to be symlinked from this template; it no longer is symlinked at all.
This file was a symlinked template once, and nothing is symlinked into a bundle today.
QUIET_EOF
cat > "$QUIET/docs/sweep.md" <<'QUIET_EOF'
`--config` never writes through a symlinked directory, and a symlinked parent means
another provider owns it. Read the paths `git worktree list` emits, or a symlinked root
makes the comparison wrong. ($TMPDIR is symlinked on macOS, so this bites the fixture.)
`repos/<name>` is a symlink view of those clones, and the only symlinks a stamp leaves.
QUIET_EOF
sed "s/__PN__/$PN/g" > "$QUIET/.claude/rules/installer.md" <<'QUIET_EOF'
**`install.sh` and `upgrade.sh` at the root are one-screen deprecation stubs** that print
the `/__PN__:init` line and exit 2. `/__PN__:init` is the working replacement.
QUIET_EOF
( cd "$QUIET" && git init -q . && git add -A && \
  git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false commit -qm q ) >/dev/null 2>&1

ok "history is outside the grammar by construction" \
   "$(claim_hits "$QUIET" | grep -c '^docs/history\.md' | tr -d ' ')" 0
ok "…so are the repos/ links and the conversion sweep's own logic" \
   "$(claim_hits "$QUIET" | grep -c '^docs/sweep\.md' | tr -d ' ')" 0
ok "…and so is the CORRECTED installer sentence, which names the real stubs" \
   "$(stub_hits "$QUIET" | grep -c '^\.claude/rules/installer\.md' | tr -d ' ')" 0

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
