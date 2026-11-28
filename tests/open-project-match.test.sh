#!/usr/bin/env bash
#
# open-project-match.test.sh — plugin/scripts/open-project-match.sh: the one open project of the
# same kind (and repo, when given) sharing two or more content words with the ask, or nothing.
# Fixtures under mktemp; no git, no network. Reasoning: prefer-tasks-in-open-projects/task-003.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
M="$REPO/plugin/scripts/open-project-match.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/opm.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s — got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
N=0
fresh() { B="$TMP/b$((++N))"; mkdir -p "$B/projects"; }
proj() { # <slug> <frontmatter lines>
  mkdir -p "$B/projects/$1"; printf -- '---\ntype: Project\n%s---\n\n# Context\n' "$2" > "$B/projects/$1/project.md"; }
match() { # <ask> <args...>
  printf '%s\n' "$1" > "$TMP/ask"; shift
  bash "$M" "$B" "$@" --text-file "$TMP/ask" 2>/dev/null; echo "rc=$?"; }
T=$'\t'
WEB=$'title: "Retry failed webhook deliveries"\ndescription: "Webhook deliveries that fail are retried with backoff."\n'
ASK='Webhook retries should cap the backoff delay'

echo "== a match, and what keeps one out =="
fresh
proj webhooks "$WEB"$'kind: build\ntarget_repo: Owner/Name\nstatus: active\ntimestamp: 2026-11-01T00:00:00Z\n'
ok "same kind and repo, three shared words" "$(match "$ASK" build owner/name)" "webhooks${T}Retry failed webhook deliveries"$'\nrc=0'
ok "no repo given: kind alone" "$(match "$ASK" build)" "webhooks${T}Retry failed webhook deliveries"$'\nrc=0'
ok "a repo URL is the same <org>/<repo>" "$(match "$ASK" build https://github.com/owner/name.git)" "webhooks${T}Retry failed webhook deliveries"$'\nrc=0'
ok "a kind miss prints nothing" "$(match "$ASK" research)" "rc=0"
ok "a repo miss prints nothing" "$(match "$ASK" build owner/other)" "rc=0"
ok "exactly two shared words match" "$(match 'Webhook delivery dashboard' build)" "webhooks${T}Retry failed webhook deliveries"$'\nrc=0'
ok "one shared word prints nothing" "$(match 'Webhook dashboards for the sales team' build)" "rc=0"
ok "zero shared words prints nothing" "$(match 'Export invoices as spreadsheets' build)" "rc=0"

echo "== open means not done =="
fresh
proj closed "$WEB"$'kind: build\nstatus: done\ntimestamp: 2026-11-09T00:00:00Z\n'
ok "a closed project never matches" "$(match "$ASK" build)" "rc=0"
proj held "$WEB"$'status: paused\ntimestamp: 2026-11-01T00:00:00Z\n'
ok "paused is open, and no kind: is build" "$(match "$ASK" build)" "held${T}Retry failed webhook deliveries"$'\nrc=0'

proj noted "$WEB"$'kind: build\nstatus: "done" # closed\ntimestamp: 2026-11-09T00:00:00Z\n'
proj quoted "$WEB"$'kind: build\nstatus: \'done\' # closed\ntimestamp: 2026-11-09T00:00:00Z\n'
ok "a quoted done with a trailing comment is closed" "$(match "$ASK" build)" "held${T}Retry failed webhook deliveries"$'\nrc=0'

echo "== URLs are not a feature area =="
fresh
proj issue $'title: "Fix https://github.com/acme/web/issues/12"\ndescription: "See https://github.com/acme/web/issues/12"\ntarget_repo: acme/web\nstatus: active\ntimestamp: 2026-11-01T00:00:00Z\n'
proj webhooks "$WEB"$'target_repo: acme/web\nstatus: active\ntimestamp: 2026-10-01T00:00:00Z\n'
ok "an issue-URL ask matches no project by its URL" "$(match 'https://github.com/acme/web/issues/99' build acme/web)" "rc=0"
ok "the words beside a URL still match" "$(match "$ASK https://github.com/acme/web/issues/99" build acme/web)" "webhooks${T}Retry failed webhook deliveries"$'\nrc=0'

echo "== generic words are not a feature area =="
fresh
proj generic $'title: "New skill for project tasks"\ndescription: "Add a task to a project when you want one."\nkind: build\nstatus: active\ntimestamp: 2026-11-01T00:00:00Z\n'
ok "an unrelated project sharing only two generic words" "$(match 'Add a new task to the project skill for invoice exports' build)" "rc=0"

echo "== single quotes =="
fresh
proj keys $'title: \'Rotate the webhook\'\'s signing keys\'\ndescription: \'Signing keys rotate monthly\'\nkind: build\nstatus: active\ntimestamp: 2026-11-01T00:00:00Z\n'
ok "a single-quoted description holding a quote" "$(match "The webhook's signing keys leak in logs" build)" "keys${T}Rotate the webhook's signing keys"$'\nrc=0'

echo "== ties and ranking =="
fresh
proj a-older "$WEB"$'kind: build\nstatus: active\ntimestamp: 2026-10-01T00:00:00Z\n'
proj b-newer "$WEB"$'kind: build\nstatus: active\ntimestamp: 2026-11-01T00:00:00Z\n'
proj alpha $'title: "Webhook backoff"\ndescription: "x"\nkind: build\nstatus: active\ntimestamp: 2026-11-20T00:00:00Z\n'
ok "a tie goes to the newest timestamp, read last" "$(match "$ASK" build)" "b-newer${T}Retry failed webhook deliveries"$'\nrc=0'
ok "more shared words beat a newer project" "$(match 'retried webhook deliveries with backoff' build)" "b-newer${T}Retry failed webhook deliveries"$'\nrc=0'
fresh
proj a-newer "$WEB"$'kind: build\nstatus: active\ntimestamp: 2026-11-01T00:00:00Z\n'
proj b-older "$WEB"$'kind: build\nstatus: active\ntimestamp: 2026-10-01T00:00:00Z\n'
ok "a tie goes to the newest timestamp, read first" "$(match "$ASK" build)" "a-newer${T}Retry failed webhook deliveries"$'\nrc=0'

echo "== nothing to match, and usage =="
fresh
ok "no projects prints nothing" "$(match "$ASK" build)" "rc=0"
ok "an unknown kind is usage" "$(match "$ASK" infra)" "rc=2"
ok "no --text-file is usage" "$(bash "$M" "$B" build 2>/dev/null; echo "rc=$?")" "rc=2"
ok "an unreadable text file exits 2" "$(bash "$M" "$B" build --text-file "$TMP/absent" 2>/dev/null; echo "rc=$?")" "rc=2"

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
