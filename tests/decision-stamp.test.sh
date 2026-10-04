#!/usr/bin/env bash
#
# decision-stamp.test.sh — the three stamps that name the human behind a recorded
# decision, driven against fixtures with TWO DIFFERENT GIT AUTHORS.
#
# WHY TWO AUTHORS IS THE WHOLE DESIGN OF THIS FILE. A stamp that resolves the login from
# this clone's own `ownerGithubUser` is correct on a one-human bundle and WRONG the moment
# two humans share one — every promotion, every folded answer and every closeout would
# read as the human whose loop happened to notice it. A check run on one author cannot
# tell the two implementations apart: both print the same right answer. So the promotion
# and answer-fold stamps are driven on the SAME task file, committed twice, with only the
# git author changed between the two runs, and the assertion is that the answer CHANGES
# with it. The `people` row is then deleted and the same commit must go `<unknown>`, which
# pins that the login came from the reverse lookup rather than from anywhere else.
#
# `<unknown>` IS AN OUTPUT, NOT A FAILURE TO PRODUCE ONE. The defect this whole feature
# exists to close is a decision recorded with nobody's name on it, so a resolver that
# printed nothing when it could not attribute would reintroduce it one layer down — the
# caller would write no `by` at all, and an absent stamp is indistinguishable from a
# decision nobody made. Every unattributable case below therefore asserts BOTH the token
# on stdout and the exit 1 beside it, and `<` cannot occur in a GitHub login, so the
# token can never be read back as one.
#
# THE PROSE HALF IS FIXED STRINGS, and it is half the criterion: the stamp is written by
# agents reading `project-manager.md` and the skills, so a script nobody is told to call
# is a rule with no reader. A moved anchor fails here rather than passing silently.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
STAMP="$REPO/plugin/scripts/decision-stamp.sh"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
SEED_CLAUDE="$REPO/plugin/seed/CLAUDE.md"
SEED_README="$REPO/plugin/seed/README.md"
PM="$REPO/plugin/agents/project-manager.md"
ANSWER="$REPO/plugin/skills/answer/SKILL.md"
CLOSE="$REPO/plugin/skills/close-project/SKILL.md"
DISPATCH="$REPO/plugin/skills/dispatch/SKILL.md"
SHARING="$REPO/docs/sharing.md"
README="$REPO/README.md"

[ -x "$STAMP" ] || { echo "decision-stamp.test: $STAMP is missing or not executable" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || {
  echo "decision-stamp.test: needs python3, as resolve-config.sh does" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/decision-stamp.XXXXXX")" || {
  echo "decision-stamp.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
hasf() { # <file> <fixed string> -> yes|no
  [ "$(grep -cF -- "$2" "$1")" -gt 0 ] && echo yes || echo no
}

# Two logins, two addresses, both verified-unclaimed placeholders in the shape the seed
# already ships (docs/sharing.md: an example is the thing people copy verbatim).
A_LOGIN="example-user-007"; A_MAIL="007@example.com"
B_LOGIN="example-user-008"; B_MAIL="008@example.com"

# Prints `<stdout>|<exit code>` so one assertion pins both halves of a refusal — the
# token that gets written into the document AND the code a caller can branch on.
run() { # <args…> -> "<stdout>|<rc>"
  local out rc
  out="$("$STAMP" "$@" 2>/dev/null)"; rc=$?
  printf '%s|%s\n' "$out" "$rc"
}

# A bundle root resolve-config.sh will read: the tracked `people` roster both clones share,
# plus this clone's own gitignored identity.
bundle() { # <dir> <tracked-json-body> [<local-json-body>]
  local d="$1"
  mkdir -p "$d/projects/demo/tasks"
  printf '# SCHEMA\n' > "$d/SCHEMA.md"
  printf '%s\n' "$2" > "$d/instance.config.json"
  if [ -n "${3:-}" ]; then printf '%s\n' "$3" > "$d/instance.config.local.json"
  else rm -f "$d/instance.config.local.json"; fi
}

TRACKED="{\"org\":\"demo\",\"people\":{\"$A_LOGIN\":\"$A_MAIL\",\"$B_LOGIN\":\"$B_MAIL\"}}"
TRACKED_NO_B="{\"org\":\"demo\",\"people\":{\"$A_LOGIN\":\"$A_MAIL\"}}"
LOCAL_A="{\"ownerGithubUser\":\"$A_LOGIN\"}"

# One commit on one file, authored by whoever is named — the whole discriminator of this
# harness. The date is FIXED so the promotion line's timestamp is checkable rather than
# "whatever today is", which would pass on a script printing `date -u` and ignoring git.
commit_as() { # <repo> <file> <name> <email> <iso-date> <message>
  ( cd "$1" || exit 2
    printf 'edit %s\n' "$6" >> "$2"
    git add -A >/dev/null 2>&1
    GIT_AUTHOR_NAME="$3" GIT_AUTHOR_EMAIL="$4" GIT_AUTHOR_DATE="$5" \
    GIT_COMMITTER_NAME="$3" GIT_COMMITTER_EMAIL="$4" GIT_COMMITTER_DATE="$5" \
      git commit -q -m "$6" >/dev/null 2>&1 )
}

newrepo() { # <dir>
  ( cd "$1" || exit 2
    git init -q . >/dev/null 2>&1
    git config user.name  "nobody"
    git config user.email "nobody@example.com"
    git config commit.gpgsign false )
}

echo "== --self: this clone's human, and a refusal it must not fail open on =="
S="$TMP/self"; bundle "$S" "$TRACKED" "$LOCAL_A"
ok "--self prints the local ownerGithubUser" \
   "$(cd "$S" && run --self)" "$A_LOGIN|0"

# The tracked file is the fallback, not the winner: a shared bundle's two clones both read
# it, so a tracked value that outranked the local one would give them one identity.
bundle "$S" "{\"org\":\"demo\",\"ownerGithubUser\":\"$B_LOGIN\"}" ""
ok "…falls back to the tracked file when there is no local one" \
   "$(cd "$S" && run --self)" "$B_LOGIN|0"
bundle "$S" "{\"org\":\"demo\",\"ownerGithubUser\":\"$B_LOGIN\"}" "$LOCAL_A"
ok "…and the LOCAL file wins where both carry it" \
   "$(cd "$S" && run --self)" "$A_LOGIN|0"

bundle "$S" "$TRACKED" ""
ok "no ownerGithubUser anywhere ⇒ <unknown> and exit 1, never silence" \
   "$(cd "$S" && run --self)" "<unknown>|1"

# task-owner.sh's exact username rule, and the same fail-closed direction: the loose form
# accepted `alice--ops`, so a typo would have been stamped into a document as a person.
bundle "$S" "$TRACKED" '{"ownerGithubUser":"alice--ops"}'
ok "a value that is not a GitHub username is refused, not stamped" \
   "$(cd "$S" && run --self)" "<unknown>|1"
bundle "$S" "$TRACKED" '{"ownerGithubUser":"-alice"}'
ok "…leading hyphen likewise" "$(cd "$S" && run --self)" "<unknown>|1"

# The cwd here is the repo root, which is no instance at all, so this can only pass by
# actually reading the named directory.
bundle "$S" "$TRACKED" "$LOCAL_A"
ok "--instance answers for a bundle that is not the cwd" \
   "$(run --instance "$S" --self)" "$A_LOGIN|0"

echo
echo "== --author: the answer-fold stamp, TWO AUTHORS on one file =="
R="$TMP/two"; bundle "$R" "$TRACKED" "$LOCAL_A"; newrepo "$R"
TASK="projects/demo/tasks/task-001.md"
commit_as "$R" "$TASK" "human" "$A_MAIL" "2026-01-02T03:04:05Z" "answer Q1"
ok "the reply commit's author resolves through people" \
   "$(cd "$R" && run --author "$TASK")" "$A_LOGIN|0"

# The SAME file, the SAME clone, only the git author changed. This is the pin: a resolver
# that read `ownerGithubUser` here would still print A and look perfectly correct.
commit_as "$R" "$TASK" "human" "$B_MAIL" "2026-02-03T04:05:06Z" "answer Q2"
ok "…and a reply pushed from the OTHER clone resolves to the OTHER human" \
   "$(cd "$R" && run --author "$TASK")" "$B_LOGIN|0"
ok "…which is NOT this clone's own login" \
   "$([ "$B_LOGIN" != "$A_LOGIN" ] && echo differs || echo same)" differs

# Mutant: same commit, `people` row deleted. Proves the login came from the reverse
# lookup and not from the config, the author name, or a coincidence.
bundle "$R" "$TRACKED_NO_B" "$LOCAL_A"
ok "drop B's people row and the same commit goes <unknown>" \
   "$(cd "$R" && run --author "$TASK")" "<unknown>|1"

# Route 2: a plain `git commit` whose user.name IS a login `people` knows.
bundle "$R" "$TRACKED" "$LOCAL_A"
commit_as "$R" "$TASK" "$B_LOGIN" "someone@elsewhere.invalid" "2026-03-04T05:06:07Z" "by name"
ok "an author NAME that is a known login resolves too" \
   "$(cd "$R" && run --author "$TASK")" "$B_LOGIN|0"
# …and only where `people` knows it, or any string in a git config becomes an attribution.
bundle "$R" "$TRACKED_NO_B" "$LOCAL_A"
ok "…but a name in no people map is not an attribution" \
   "$(cd "$R" && run --author "$TASK")" "<unknown>|1"

# Route 3: a human in no roster at all, identified by this clone's own configured address.
bundle "$R" "{\"org\":\"demo\"}" "{\"ownerGithubUser\":\"$A_LOGIN\",\"authorEmail\":\"solo@example.com\"}"
commit_as "$R" "$TASK" "human" "solo@example.com" "2026-04-05T06:07:08Z" "solo"
ok "this clone's own authorEmail resolves to this clone's login" \
   "$(cd "$R" && run --author "$TASK")" "$A_LOGIN|0"

U="$TMP/uncommitted"; bundle "$U" "$TRACKED" "$LOCAL_A"; newrepo "$U"
: > "$U/$TASK"
ok "a file with no commit yet ⇒ <unknown> and exit 1" \
   "$(cd "$U" && run --author "$TASK")" "<unknown>|1"

N="$TMP/nogit"; bundle "$N" "$TRACKED" "$LOCAL_A"; : > "$N/$TASK"
ok "outside a git working tree ⇒ exit 2, a refusal and not a stamp" \
   "$(cd "$N" && run --author "$TASK")" "|2"
ok "a path that does not exist ⇒ exit 2" \
   "$(cd "$R" && run --author "projects/demo/tasks/nope.md")" "|2"

echo
echo "== --promotion: the ready-made # Notes line, and the date is the COMMIT's =="
P="$TMP/promote"; bundle "$P" "$TRACKED" "$LOCAL_A"; newrepo "$P"
commit_as "$P" "$TASK" "human" "$A_MAIL" "2026-05-06T07:08:09Z" "status: ready"
ok "one line, the exact documented shape" \
   "$(cd "$P" && run --promotion "$TASK")" "promoted 2026-05-06T07:08:09Z by $A_LOGIN|0"

# A hand-promotion by the other human on their own clone, same file, same tick.
commit_as "$P" "$TASK" "human" "$B_MAIL" "2026-06-07T08:09:10Z" "status: ready (again)"
ok "the other human's promotion carries the other login AND their date" \
   "$(cd "$P" && run --promotion "$TASK")" "promoted 2026-06-07T08:09:10Z by $B_LOGIN|0"

# The timestamp is UTC-normalised, so a promoter in another zone does not write a local
# clock into a document every other clone reads.
commit_as "$P" "$TASK" "human" "$A_MAIL" "2026-07-08T09:10:11+05:00" "offset"
ok "an offset commit date is normalised to UTC Z" \
   "$(cd "$P" && run --promotion "$TASK")" "promoted 2026-07-08T04:10:11Z by $A_LOGIN|0"

bundle "$P" "$TRACKED_NO_B" ""
commit_as "$P" "$TASK" "human" "$B_MAIL" "2026-08-09T10:11:12Z" "unattributable"
ok "unattributable still WRITES a line — the date survives, the login is <unknown>" \
   "$(cd "$P" && run --promotion "$TASK")" "promoted 2026-08-09T10:11:12Z by <unknown>|1"

echo
echo "== usage =="
ok "no mode ⇒ exit 2"          "$(run --instance "$TMP/self")" "|2"
ok "a bare trailing --instance ⇒ exit 2, never a spin" "$(run --instance)" "|2"
ok "--author with no path ⇒ exit 2" "$(run --author)" "|2"
ok "an unknown flag ⇒ exit 2"  "$(run --nope)" "|2"
ok "--help exits 0"            "$( { "$STAMP" --help >/dev/null 2>&1; echo $?; } )" 0

echo
echo "== SCHEMA.md is the normative shape, and it names all four stamps =="
ok "the section exists"              "$(hasf "$SCHEMA" '## Decisions name the human')" yes
ok "a login, never an address"        "$(hasf "$SCHEMA" 'GitHub login — never an address')" yes
ok "stamp 1: an answered question"    "$(hasf "$SCHEMA" '`<ISO 8601> by <login> · <the entry verbatim>`')" yes
ok "stamp 2: a promotion"             "$(hasf "$SCHEMA" '`promoted <ISO 8601> by <login>`')" yes
ok "stamp 3: a preview approval"      "$(hasf "$SCHEMA" '`preview approved <ISO 8601> by <login>`')" yes
ok "stamp 4: the tick ledger line"    "$(hasf "$SCHEMA" '`* TICK <ISO 8601> by <login> …`')" yes
ok "it names the one resolver"        "$(hasf "$SCHEMA" '`scripts/decision-stamp.sh` is the')" yes
ok "…and says the stamp is written anyway" "$(hasf "$SCHEMA" '`<unknown>`')" yes
ok "…and that none of it is a gate"   "$(hasf "$SCHEMA" '**None of this is a gate**')" yes
ok "the answered_questions field carries the by" \
   "$(hasf "$SCHEMA" '  - "<ISO 8601> by <login> · Q1:')" yes

echo
echo "== the agents and skills that write the stamps are told to =="
# The fold is fold-answers.sh's since ai-bridge-v3/task-024 — the script resolves the login
# so the model can never compose the stamp — and the preview/closeout stamps moved with
# their steps.
FOLD="$REPO/plugin/scripts/fold-answers.sh"
S5="$REPO/plugin/tick-steps/step-5-reflect-merges.md"
S6="$REPO/plugin/tick-steps/step-6-close-projects.md"
ok "the folder stamps the human whose answer it was" "$(hasf "$FOLD" '**`by <login>` names the human whose answer it was**')" yes
ok "…from the resolver, not its own reading" \
   "$(hasf "$PM" '/scripts/decision-stamp.sh')" yes
ok "PM stamps promotions, once, before dispatch" \
   "$(hasf "$PM" 'Stamp promotions — every task past `draft`, once')" yes
ok "…and says a HAND-promotion is attributed too" \
   "$(hasf "$PM" '**So a HAND-promotion is attributed')" yes
ok "PM stamps a preview approval"     "$(hasf "$S5" '`preview approved <ISO 8601> by <login>`')" yes
ok "PM's ledger line names the login it ran as" \
   "$(hasf "$PM" '`* TICK <ISO-8601 timestamp> by <login> open:')" yes
ok "…the idle line too"               "$(hasf "$PM" '`* TICK <ISO-8601> by <login> idle')" yes
ok "…and the close keeps it"          "$(hasf "$PM" 'copies its timestamp and its `by <login>`')" yes
ok "PM stamps a project closeout"     "$(hasf "$S6" 'stamped `by <login>` from')" yes
ok "/${PN}:answer writes the by"  "$(hasf "$ANSWER" 'then ` by <login> · `')" yes
ok "…and may actually run the resolver" \
   "$(hasf "$ANSWER" 'scripts/decision-stamp.sh:*)')" yes
ok "/${PN}:close-project writes the by" "$(hasf "$CLOSE" '`by <login>`, naming the')" yes
ok "…names the resolver in its own steps" "$(hasf "$CLOSE" '/scripts/decision-stamp.sh --self')" yes
ok "…and may actually run it"         "$(hasf "$CLOSE" 'scripts/decision-stamp.sh:*)')" yes
ok "the dispatch skill's summary agrees" \
   "$(hasf "$DISPATCH" '`<ISO 8601> by <login> · <the entry verbatim>`')" yes
ok "the seed CLAUDE.md shows the answer form" \
   "$(hasf "$SEED_CLAUDE" '`<ISO 8601> by <login> · <entry>`')" yes
ok "the seed README shows it to the human" \
   "$(hasf "$SEED_README" '`<ISO 8601> by <login> · <the entry')" yes

echo
echo "== sharing.md carries the approve/continue split =="
ok "a promotion runs nothing on the promoter's machine" \
   "$(hasf "$SHARING" "A promotion never runs anything on the promoter's machine")" yes
ok "…only the owner's loop dispatches" \
   "$(hasf "$SHARING" "only the owner's loop dispatches")" yes
ok "…named as the approve/continue split" \
   "$(hasf "$SHARING" 'which is the approve/continue split')" yes
ok "README documents the script where this repo documents scripts" \
   "$(hasf "$README" '| `decision-stamp.sh` |')" yes

echo
TOTAL=$((pass + fail))
printf '\n  %d passed, %d failed (%d assertions)\n' "$pass" "$fail" "$TOTAL"
[ "$fail" -eq 0 ] || exit 1
