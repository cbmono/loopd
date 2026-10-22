#!/usr/bin/env bash
#
# deploy-mode.test.sh — deploy-mode.sh resolves a task to manual/auto/n/a/UNKNOWN through
# service-doc.sh, and reflect-deploy.sh writes the `merged, not deployed` note, `do: deploy`
# entry and block for `manual` only, once. Reasoning: kb-retrieval-and-papercut-fixes/task-008.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MODE="$REPO/plugin/scripts/deploy-mode.sh"
WRITE="$REPO/plugin/scripts/reflect-deploy.sh"
FOLD="$REPO/plugin/scripts/fold-answers.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deploy-mode.XXXXXX")" || { echo "deploy-mode.test: mktemp failed" >&2; exit 2; }
TMP="$(cd "$TMP" && pwd -P)" || exit 2
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
mode() { bash "$MODE" "$@" 2>/dev/null; echo "rc=$?"; }
sum() { cksum < "$1"; }

S="$TMP/knowledge/services"; T="$TMP/projects/p/tasks/task-001.md"
mkdir -p "$S" "$TMP/projects/p/tasks"; echo '{}' > "$TMP/instance.config.json"
svc() { # <slug> <repo> <path> [deploy line]
  printf -- '---\ntype: Service\ntitle: %s\nrepo: %s\npath: %s\nstatus: active\n%s---\n' \
    "$1" "$2" "$3" "${4:+$4
}" > "$S/$1.md"
}
task() { # <target_repo> [extra frontmatter lines] [status]
  { printf -- '---\ntype: Task\ntitle: "Ship it"\nkind: build\nstatus: %s\n' "${3:-done}"
    [ -z "$1" ] || printf 'target_repo: %s\n' "$1"
    [ -z "${2:-}" ] || printf '%s\n' "$2"
    printf 'pr: [ "https://github.com/acme/web/pull/42" ]\nacceptance_criteria: [ "it works" ]\nopen_questions: [ ]\n---\n\n# Context\n\nx\n\n# Notes\n- created\n'
  } > "$T"
}

echo "== resolution =="
svc web acme/web '(whole repo)'
task acme/web
ok "a Service with no deploy: ⇒ auto"           "$(mode "$T")" "auto
rc=0"
svc web acme/web '(whole repo)' 'deploy: manual'
ok "a Service-level manual"                     "$(mode "$T")" "manual
rc=0"
task acme/web 'deploy: auto'
ok "the task's own value wins over its Service" "$(mode "$T")" "auto
rc=0"
svc web acme/web '(whole repo)'; task acme/web 'deploy: "manual"'
ok "a task-level manual"                        "$(mode "$T")" "manual
rc=0"
task acme/other
ok "no matching Service doc ⇒ auto"             "$(mode "$T")" "auto
rc=0"
task ""
ok "no resolvable target_repo ⇒ UNKNOWN"        "$(mode "$T")" "UNKNOWN
rc=3"
task acme/web 'kind: research'; sed -i.bak '/^kind: build$/d' "$T"
ok "a research task ⇒ n/a"                      "$(mode "$T")" "n/a
rc=0"

echo "== refusals: invalid, unreadable, unparsable =="
task acme/web 'deploy: sometimes'
ok "an invalid task deploy: is refused"         "$(mode "$T")" "UNKNOWN
rc=3"
task acme/web; svc web acme/web '(whole repo)' 'deploy: nightly'
ok "an invalid Service deploy: is refused"      "$(mode "$T")" "UNKNOWN
rc=3"
svc web acme/web '(whole repo)' $'deploy: manual\ndeploy: auto'
task acme/web 'deploy:'
ok "an empty task deploy: is refused, not auto"  "$(mode "$T")" "UNKNOWN
rc=3"
task acme/web 'deploy: ""'
ok "…nor a quoted empty one"                    "$(mode "$T")" "UNKNOWN
rc=3"
task acme/web; svc web acme/web '(whole repo)' 'deploy:'
ok "an empty Service deploy: is refused"        "$(mode "$T")" "UNKNOWN
rc=3"
ok "two different deploy: lines are UNKNOWN"    "$(mode "$T")" "UNKNOWN
rc=3"
printf -- '---\ntype: Service\nrepo: acme/web\nstatus: active\ndeploy: auto\n' > "$S/web.md"
ok "an unterminated Service doc is UNKNOWN"     "$(mode "$T")" "UNKNOWN
rc=3"
svc web acme/web '(whole repo)'; chmod 000 "$S/web.md"
if [ -r "$S/web.md" ]; then echo "  SKIP  unreadable Service doc (running as root)"
else ok "an unreadable Service doc is UNKNOWN"   "$(mode "$T")" "UNKNOWN
rc=3"; fi
chmod 644 "$S/web.md"

echo "== tied Services: any manual wins, never a slug-order pick =="
rm -f "$S"/*.md
svc a-mono acme/mono apps/api; svc b-mono acme/mono apps/web 'deploy: manual'
task acme/mono
ok "the first slug alone would say auto"        "$(bash "$REPO/plugin/scripts/service-doc.sh" "$T" | sed "s#^$TMP/##")" knowledge/services/a-mono.md
ok "…but the tied pair resolves manual"         "$(mode "$T")" "manual
rc=0"
svc a-mono acme/mono apps/api 'deploy: manual'; svc b-mono acme/mono apps/web
ok "…whichever slug carries it"                 "$(mode "$T")" "manual
rc=0"
sed -i.bak 's/title: "Ship it"/title: "Fix apps\/web"/' "$T"
ok "a path the task names breaks the tie"       "$(mode "$T")" "auto
rc=0"
ok "the resolver reads no repo: and no services/" "$(grep -cE 'val (target_)?repo|repo:|services/' "$MODE" | tr -d ' ')" 0
ok "…it calls service-doc.sh for both"          "$(grep -cE 'service-doc\.sh" --(repo|ties)' "$MODE" | tr -d ' ')" 2

echo "== the writer: manual =="
rm -f "$S"/*.md; svc web acme/web '(whole repo)' 'deploy: manual'; task acme/web
out="$(bash "$WRITE" "$T" 2>&1)"; rc=$?
ok "it writes and names the entry"              "$out rc=$rc" "deploy-owed Q1 rc=0"
ok "one merged, not deployed note"              "$(grep -c '^\* .* · merged, not deployed · acme/web · https://github.com/acme/web/pull/42 · Q1$' "$T")" 1
ok "one do: deploy entry naming repo and PR"    "$(bash "$FOLD" --list "$T" open_questions | grep -c '^Q1: do: deploy acme/web — https://github.com/acme/web/pull/42 merged, not deployed')" 1
ok "its ### Q1 block"                           "$(grep -c '^### Q1$' "$T")" 1
ok "never a hand-off, nor a needs handed off"   "$(grep -cE 'hand-off|needs handed off' "$T")" 0
ok "no .handoffs store is created"              "$(find "$TMP" -name '.handoffs' | wc -l | tr -d ' ')" 0
before="$(sum "$T")"
ok "a re-run writes nothing"                    "$(bash "$WRITE" "$T" 2>&1; echo "rc=$?")" "already Q1
rc=1"
ok "…byte-identical"                            "$(sum "$T")" "$before"
bash "$FOLD" --answer "Q1: do: deploy acme/web — https://github.com/acme/web/pull/42 merged, not deployed; answer done once it is live" done "$T" >/dev/null 2>&1
ok "answered and folded"                        "$(bash "$FOLD" --list "$T" answered_questions | grep -c 'Q1: do: deploy .* --- done$')" 1
ok "…a run after the answer writes nothing"     "$(bash "$WRITE" "$T" >/dev/null 2>&1; echo $?)" 1

echo "== the writer: everything else leaves the file alone =="
check_same() { # <label> <want-rc>
  local b; b="$(sum "$T")"; bash "$WRITE" "$T" >/dev/null 2>&1; local rc=$?
  ok "$1 (rc)" "$rc" "$2"; ok "$1 (byte-identical)" "$(sum "$T")" "$b"
}
svc web acme/web '(whole repo)'; task acme/web;                check_same "auto" 1
task acme/web 'kind: research'; sed -i.bak '/^kind: build$/d' "$T"; check_same "n/a" 1
task acme/web 'deploy: manual' in-review;                      check_same "a task not yet done" 2
task acme/web 'deploy: manual'; sed -i.bak '/^pr:/d' "$T";    check_same "no pr: to name" 2

echo "== step 5 calls the writer =="
S5="$REPO/plugin/tick-steps/step-5-reflect-merges.md"
ok "step 5 runs reflect-deploy.sh per done task"  "$(grep -cF 'scripts/reflect-deploy.sh <task-path>' "$S5" | tr -d ' ')" 1
ok "…and never reports a manual merge as shipped" "$(grep -cF 'report the task as merged, NOT shipped' "$S5" | tr -d ' ')" 1

echo "== the writer: UNKNOWN fails toward manual, durably =="
svc web acme/web '(whole repo)'; task acme/web 'deploy: bogus'
ok "UNKNOWN writes a deploy entry (exit 3)"     "$(bash "$WRITE" "$T" 2>/dev/null; echo "rc=$?")" "deploy-unknown Q1
rc=3"
ok "…one deploy UNKNOWN note"                   "$(grep -c '^\* .* · merged, deploy UNKNOWN · acme/web · https://github.com/acme/web/pull/42 · Q1$' "$T")" 1
ok "…a do: deploy entry, so AWAITING.md shows it" "$(bash "$FOLD" --list "$T" open_questions | grep -c '^Q1: do: deploy acme/web — https://github.com/acme/web/pull/42 merged, deploy state UNKNOWN')" 1
ok "…its ### Q1 block"                          "$(grep -c '^### Q1$' "$T")" 1
before="$(sum "$T")"
ok "…and a re-run writes nothing"               "$(bash "$WRITE" "$T" 2>/dev/null; echo "rc=$?")" "already Q1
rc=1"
ok "…byte-identical"                            "$(sum "$T")" "$before"
task ""
ok "no target_repo: still written, and says so" "$(bash "$WRITE" "$T" >/dev/null 2>&1; bash "$FOLD" --list "$T" open_questions | grep -c '^Q1: do: deploy (no target_repo) — ')" 1

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
