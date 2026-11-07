#!/usr/bin/env bash
# verified-facts.test.sh — plugin/scripts/verified-facts.sh against fixture clones (present,
# missing, stale, research, unknown, malformed; only named paths count; it fetches; it
# writes no task doc) and the promote-row marks build-awaiting.sh renders from it, plus the
# SCHEMA / step 2 / step 8 / AUTONOMY wiring. Reasoning: ai-control-panel-guards/task-002.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VF="$REPO/plugin/scripts/verified-facts.sh"
BA="$REPO/plugin/scripts/build-awaiting.sh"
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/verified-facts.XXXXXX")" || { echo "mktemp -d failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
has() { printf '%s\n' "$1" | grep -cF -- "$2" | tr -d ' '; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.name=t \
  -c user.email=t@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  -c init.defaultBranch=main "$@"; }
commit() { mkdir -p "$1/$(dirname "$2")"; echo "$RANDOM" >> "$1/$2"; GIT -C "$1" add -A; GIT -C "$1" commit -qm "$2"; }

UP="$TMP/upstream/app"; mkdir -p "$UP"; GIT init -q "$UP"
commit "$UP" src/a.sh; commit "$UP" src/b.sh; commit "$UP" "src/with space.sh"
SHA="$(GIT -C "$UP" rev-parse HEAD)"
RR="$TMP/repos"; mkdir -p "$RR"
GIT clone -q "$UP" "$RR/app"
GIT clone -q "$UP" "$RR/nofetch"; GIT -C "$RR/nofetch" remote set-url origin "$TMP/nowhere"
# Upstream moves after the clone: only a fetch lets the clone see src/b.sh change.
commit "$UP" src/b.sh; commit "$UP" "src/with space.sh"
# A remote whose default moved to trunk after the clone: the clone's origin/HEAD still says main.
MV="$TMP/upstream/moved"; GIT clone -q "$UP" "$MV"; GIT clone -q "$MV" "$RR/moved"
GIT -C "$MV" checkout -qb trunk; commit "$MV" src/a.sh; GIT -C "$MV" symbolic-ref HEAD refs/heads/trunk

B="$TMP/bundle"; P="$B/projects/demo"; mkdir -p "$P/tasks" "$B/$AB_DIR"
printf '{ "org": "example-org", "reposRoot": "%s" }\n' "$RR" > "$B/instance.config.json"
printf '# SCHEMA\n' > "$B/$AB_SCHEMA"
printf -- '---\ntype: Project\ntitle: "Demo"\nkind: build\ntarget_repo: example-org/app\nstatus: active\n---\n' > "$P/project.md"
task() { # <id> <extra frontmatter> <body after # Context>
  printf -- '---\ntype: Task\ntitle: "%s"\nstatus: draft\n%bacceptance_criteria: [ "x" ]\nopen_questions: [ ]\n---\n\n# Context\n\nWhy.\n\n%s\n# Notes\n' \
    "$1" "$2" "$3" > "$P/tasks/$1.md"
}
facts() { printf '## Verified facts (as of %s@%s)\n\n' "$1" "$2"; shift 2; printf '%s\n' "$@"; }
task t-present ''  "$(facts example-org/app "$SHA" '- `src/a.sh` · defines main(); CI `harness suite` proves it')"
task t-stale   ''  "$(facts example-org/app "$SHA" '- src/b.sh · defines helper()')"
task t-missing ''  ''
task t-research 'kind: research\n' ''
task t-nosha   ''  "$(facts example-org/app "$(printf 'f%.0s' $(seq 40))" '- src/a.sh · x')"
task t-short   ''  "$(facts example-org/app "${SHA:0:12}" '- src/a.sh · x')"
task t-nolines ''  "$(facts example-org/app "$SHA" 'Premise holds.')"
task t-other   ''  "$(facts example-org/elsewhere "$SHA" '- src/a.sh · x')"
task t-noclone 'target_repo: example-org/absent\n' "$(facts example-org/absent "$SHA" '- src/a.sh · x')"
task t-space   ''  "$(facts example-org/app "$SHA" '- src/a.sh · x' '- `src/with space.sh` · y')"
task t-badline ''  "$(facts example-org/app "$SHA" '- src/a.sh · x' '- a fact line naming no path')"
task t-moved 'target_repo: example-org/moved\n' "$(facts example-org/moved "$SHA" '- src/a.sh · x')"
task t-nofetch 'target_repo: example-org/nofetch\n' "$(facts example-org/nofetch "$SHA" '- src/a.sh · x')"

vf() { local o rc; o="$(cd "$B" && bash "$VF" "$@" 2>/dev/null)"; rc=$?; echo "$o $rc"; }
echo "== verdicts =="
before="$(cat "$P"/tasks/*.md | cksum)"
ok "present, named path unchanged ⇒ verified 0"         "$(vf "$P/tasks/t-present.md")" "verified 0"
ok "a named path changed on the default branch ⇒ stale 3" "$(vf "$P/tasks/t-stale.md")" "stale 3"
ok "no section ⇒ missing 1"                             "$(vf "$P/tasks/t-missing.md")" "missing 1"
ok "kind: research ⇒ research 5, no check owed"         "$(vf "$P/tasks/t-research.md")" "research 5"
ok "sha absent from the clone ⇒ unknown 4"              "$(vf "$P/tasks/t-nosha.md")" "unknown 4"
ok "a short sha is not the grammar ⇒ missing 1"         "$(vf "$P/tasks/t-short.md")" "missing 1"
ok "a section naming no path ⇒ missing 1"               "$(vf "$P/tasks/t-nolines.md")" "missing 1"
ok "facts about another repo ⇒ missing 1"               "$(vf "$P/tasks/t-other.md")" "missing 1"
ok "no clone ⇒ unknown 4"                               "$(vf "$P/tasks/t-noclone.md")" "unknown 4"
ok "a changed path holding a space is checked ⇒ stale 3" "$(vf "$P/tasks/t-space.md")" "stale 3"
ok "a fact line it cannot read fails the section ⇒ missing 1" "$(vf "$P/tasks/t-badline.md")" "missing 1"
ok "the remote's moved default is read, not origin/HEAD ⇒ stale 3" "$(vf "$P/tasks/t-moved.md")" "stale 3"
ok "a failed fetch ⇒ unknown 4"                         "$(vf "$P/tasks/t-nofetch.md")" "unknown 4"
ok "--presence never runs git: stale reads present 0"   "$(vf --presence "$P/tasks/t-stale.md")" "present 0"
ok "--presence on a missing section ⇒ missing 1"        "$(vf --presence "$P/tasks/t-missing.md")" "missing 1"
ok "no argument ⇒ usage 2"                              "$(vf)" " 2"
ok "no task document is rewritten"                      "$(cat "$P"/tasks/*.md | cksum)" "$before"

echo "== promote-row marks =="
touch "$B/$AB_AWAITING"
bash "$BA" --instance "$B" --facts "$P/tasks/t-stale.md=stale" --facts "$P/tasks/t-nofetch.md=unknown" \
  --facts "$P/tasks/t-present.md=verified" --facts "$P/tasks/t-research.md=missing" >/dev/null
page="$(cat "$B/$AB_AWAITING")"
row() { printf '%s\n' "$page" | grep -F "[$1](" ; }
ok "missing ⇒ row marked unverified"        "$(has "$(row t-missing)" '· unverified · refined & clean')" 1
ok "stale verdict ⇒ row marked stale"       "$(has "$(row t-stale)" '· stale · refined & clean')" 1
ok "unknown verdict ⇒ row marked unverified" "$(has "$(row t-nofetch)" '· unverified (facts UNKNOWN) · ')" 1
ok "verified ⇒ row carries no mark"         "$(has "$(row t-present)" ') · refined & clean')" 1
ok "research ⇒ never marked, whatever --facts says" "$(has "$(row t-research)" ') · refined & clean')" 1
ok "a section missing outranks a passed verdict" \
  "$(bash "$BA" --instance "$B" --facts "$P/tasks/t-missing.md=verified" >/dev/null; has "$(grep -F '[t-missing](' "$B/$AB_AWAITING")" '· unverified ·')" 1
ok "no --facts and a section present ⇒ no mark" \
  "$(bash "$BA" --instance "$B" >/dev/null; has "$(grep -F '[t-stale](' "$B/$AB_AWAITING")" ') · refined & clean')" 1
ok "an unknown verdict word is a usage error" "$(bash "$BA" --instance "$B" --facts "$P/tasks/t-stale.md=fine" >/dev/null 2>&1; echo $?)" 2

echo "== wiring =="
SCHEMA="$REPO/plugin/seed/SCHEMA.md"; S2="$REPO/plugin/tick-steps/step-2-refine-drafts.md"
S8="$REPO/plugin/tick-steps/step-8-render.md"; AUT="$REPO/plugin-yolo/companion/AUTONOMY.md"
ok "SCHEMA defines the heading grammar"       "$(grep -c '^## Verified facts (as of <owner>/<repo>@<40-char sha>)' "$SCHEMA")" 1
ok "step 2 runs the pass and the check"       "$(grep -c 'verified-facts.sh' "$S2" | awk '$1>0{print "yes"}')" yes
ok "step 8 passes --facts to the renderer"    "$(grep -c -- '--facts' "$S8" | awk '$1>0{print "yes"}')" yes
ok "yolo promotion refuses on a non-zero exit" "$(sed -n '/^## Promotion under `yolo`/,/^## Merge under/p' "$AUT" | grep -c 'verified-facts.sh')" 1

echo; echo "verified-facts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
