#!/usr/bin/env bash
#
# service-doc.test.sh — plugin/scripts/service-doc.sh picks ONE Service doc per task:
# per-app path match in a monorepo, basename fallback, project-inherited target_repo, the
# deprecated/prose-path tie, and its three exit codes. Reasoning:
# kb-retrieval-and-papercut-fixes/task-003.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/service-doc.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/service-doc.XXXXXX")" || { echo "service-doc.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
run() { bash "$SCRIPT" "$@" 2>/dev/null | sed "s#^$TMP/##"; }
rc()  { bash "$SCRIPT" "$@" >/dev/null 2>&1; echo $?; }

svc() { # <slug> <repo> <path> [status]
  printf -- '---\ntype: Service\ntitle: %s\nrepo: %s\npath: %s\nstatus: %s\n---\n\n# Overview\n' \
    "$1" "$2" "$3" "${4:-active}" > "$TMP/knowledge/services/$1.md"
}
task() { # <file> <target_repo or empty> <title>
  { printf -- '---\ntype: Task\ntitle: "%s"\n' "$3"
    [ -z "$2" ] || printf 'target_repo: %s\n' "$2"
    printf 'acceptance_criteria: [ "it works" ]\n---\n\n# Notes\n'; } > "$1"
}
mkdir -p "$TMP/knowledge/services" "$TMP/projects/p/tasks"
echo '{}' > "$TMP/instance.config.json"
T="$TMP/projects/p/tasks/task-001.md"

echo "== a monorepo's per-app docs: the one the task names wins =="
svc mono-web acme/mono apps/web
svc mono-api acme/mono apps/api
svc mono acme/mono '(whole repo)'
task "$T" acme/mono "Fix the login form in apps/web"
ok "the task naming apps/web gets mono-web.md" "$(run "$T")" knowledge/services/mono-web.md
task "$T" acme/mono "Rate-limit apps/api"
ok "…and apps/api gets mono-api.md"            "$(run "$T")" knowledge/services/mono-api.md
svc mono-web-admin acme/mono apps/web/admin
task "$T" acme/mono "Admin page under apps/web/admin"
ok "the longest named path wins"               "$(run "$T")" knowledge/services/mono-web-admin.md

echo "== basename fallback, then the first slug =="
task "$T" acme/mono "Bump a dependency"
ok "no path named ⇒ <repo-basename>.md"        "$(run "$T")" knowledge/services/mono.md
rm "$TMP/knowledge/services/mono.md"
ok "no basename doc ⇒ the lexically first slug" "$(run "$T")" knowledge/services/mono-api.md

echo "== two docs for one repo, one deprecated, both prose paths =="
svc loopd acme/loopd '(whole repo; everything ships under src/)'
svc loopd-legacy acme/loopd '(the pre-rename name)' deprecated
task "$T" acme/loopd "Ship it"
a="$(run "$T")"; b="$(run "$T")"
ok "loopd.md wins"                               "$a" knowledge/services/loopd.md
ok "…on every run"                               "$b" "$a"
rm "$TMP/knowledge/services/loopd.md"
ok "a deprecated doc alone is no match (exit 1)" "$(rc "$T")" 1
ok "…and prints nothing"                         "$(run "$T")" ""

echo "== target_repo is inherited from project.md =="
svc solo acme/solo '(whole repo)'
task "$T" "" "No repo on the task"
printf -- '---\ntype: Project\ntarget_repo: "acme/solo"\n---\n' > "$TMP/projects/p/project.md"
ok "the project's repo is used"        "$(run "$T")" knowledge/services/solo.md
ok "--repo prints the inherited repo"  "$(run --repo "$T")" acme/solo
task "$T" acme/widget "The task's own repo still wins"
ok "…but never over the task's own"    "$(run --repo "$T")" acme/widget
rm "$TMP/projects/p/project.md"; task "$T" "" "Neither"
ok "neither set ⇒ exit 1"              "$(rc "$T")" 1
ok "…and --repo exits 1 too"           "$(rc --repo "$T")" 1

echo "== it refuses rather than guessing =="
ok "a missing task exits 2"            "$(rc "$TMP/nope.md")" 2
printf 'no frontmatter\n' > "$TMP/bare.md"
ok "a task with no frontmatter exits 2" "$(rc "$TMP/bare.md")" 2
ok "no arguments exits 2"              "$(rc)" 2

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
