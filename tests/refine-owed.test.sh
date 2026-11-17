#!/usr/bin/env bash
# refine-owed.test.sh — an unrefined draft is owed work: the digest names it and step 2,
# and `tick-delta.sh check` never reads a clean tree IDLE past it.
#
# Why (2026-11-17): a new project's five drafts sat unrefined. The digest named step 2 for
# every draft, refined or not, so a busy tick read it as noise; and `check` had no rule for
# an unrefined draft, so once the tree was clean every tick went IDLE.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/plugin/scripts/bundle-paths.sh"
S="$REPO/plugin/scripts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/refineowed.XXXXXX")" || { echo "refine-owed.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

INST="$TMP/inst"
mkdir -p "$INST/projects/a/tasks" "$INST/projects/b/tasks" "$INST/scripts"
cp "$S"/*.sh "$S"/*.py "$INST/scripts/"; cp -R "$S/lib" "$INST/scripts/lib"
cp -R "$REPO/plugin/tick-steps" "$INST/tick-steps"
mkdir -p "$INST/.loopd"; : > "$INST/.loopd/SCHEMA.md"
printf '/%s\n' "$AB_STATE_DIR" > "$INST/.gitignore"; printf '{}\n' > "$INST/instance.config.json"
GIT -C "$INST" init -q

project() { printf -- '---\ntype: Project\nkind: build\ntarget_repo: example-org/example-repo\nstatus: %s\n%b---\n' "$2" "${3:-}" > "$INST/projects/$1/project.md"; }
unrefined() { printf -- '---\ntype: Task\nkind: build\nstatus: draft\nacceptance_criteria: [ ]\n%b---\n' "${2:-}" > "$INST/$1"; }
refined() { # a draft step 2 owes nothing: criteria, a critique receipt and verified facts
  printf -- '---\ntype: Task\nkind: build\nstatus: draft\nacceptance_criteria: [ "x" ]\n'"\
"'advisor_notes:\n  - "2026-11-01T10:00:00Z · advisor: approach critique — no concerns"\n---\n\n'"\
"'## Verified facts (as of example-org/example-repo@0123456789abcdef0123456789abcdef01234567)\n\n- a · b\n' > "$INST/$1"; }
commit() { GIT -C "$INST" add -A && GIT -C "$INST" commit -qm fx; }
digest() { "$INST/scripts/tick-delta.sh" digest --instance "$INST" 2>/dev/null; }
check() { local out rc; out="$("$INST/scripts/tick-delta.sh" check --instance "$INST" 2>&1)"; rc=$?
          printf 'rc:%s %s' "$rc" "$(head -1 <<<"$out" | cut -c1-30)"; }
record() { "$INST/scripts/tick-delta.sh" record --instance "$INST" >/dev/null 2>&1; }
names_step2() { digest | grep '^steps:' | grep -q 'step-2-refine-drafts.md' && echo yes || echo no; }

echo "== digest: refine owed lines and the step-2 name =="
project a active
unrefined projects/a/tasks/t1.md
unrefined projects/a/tasks/t2.md
project b paused
refined projects/b/tasks/t1.md
: > "$INST/projects/b/design.md"
commit
ok "two unrefined drafts in an active project → two refine owed lines" "$(digest | grep -c '^refine owed ')" 2
ok "…naming exactly those two"  "$(digest | sed -n 's/^refine owed //p' | sort | tr '\n' ' ')" \
   "projects/a/tasks/t1.md projects/a/tasks/t2.md "
ok "…and the steps line names step 2"                              "$(names_step2)" yes

refined projects/a/tasks/t1.md; refined projects/a/tasks/t2.md; : > "$INST/projects/a/design.md"
project b active
commit
ok "every draft refined → no refine owed line"                     "$(digest | grep -c '^refine owed ')" 0
ok "…and step 2 is not named"                                      "$(names_step2)" no

printf -- '---\ntype: Task\nkind: build\nstatus: draft\nacceptance_criteria: [ "x" ]\n---\n' > "$INST/projects/a/tasks/t2.md"
commit
ok "a refined build draft with no critique receipt still names step 2" "$(names_step2)" yes
ok "…without being refine owed"                                     "$(digest | grep -c '^refine owed ')" 0
refined projects/a/tasks/t2.md; commit

echo "== check: a clean tree with an unrefined draft is never IDLE =="
record
ok "all refined, clean and recorded → IDLE"                        "$(check | cut -c1-10)" "rc:0 IDLE:"
unrefined projects/a/tasks/t3.md; commit; record
ok "an unrefined draft in an active project → owed, not IDLE" \
   "$(check)" "rc:1 DELTA: refine owed projects/a/"
project a paused; commit; record
ok "the same draft in a paused project → IDLE"                     "$(check | cut -c1-10)" "rc:0 IDLE:"
project a active; unrefined projects/a/tasks/t3.md 'open_questions:\n  - "Q1: which repo?"\n'; commit; record
ok "a draft waiting on its open question → IDLE"                   "$(check | cut -c1-10)" "rc:0 IDLE:"
project a active 'inputs: later\n'; unrefined projects/a/tasks/t3.md; commit; record
ok "a draft whose project waits on inputs → IDLE"                  "$(check | cut -c1-10)" "rc:0 IDLE:"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
