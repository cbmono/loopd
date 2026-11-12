#!/usr/bin/env bash
# plugin/scripts/merge-queue.sh against a `gh` stub: hold, clear and unknown, loopd's own
# tests.yml, every false clear QA found on #493, the D3 bound under --pr, the reason the mark
# keeps (stripped and bounded), tick-delta.sh's DELTA for a held mark and the merge-row warning
# build-awaiting.sh renders.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SH="$REPO/plugin/scripts/merge-queue.sh"
. "$REPO/plugin/scripts/bundle-paths.sh"
command -v jq >/dev/null 2>&1 || { echo "merge-queue.test: jq is required by the gh stub" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/merge-queue.XXXXXX")" || { echo "merge-queue.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi }

# The stub answers from $FIX: workflows.json, files/<name> (at.<ref>/<name> instead, when that
# directory exists), runs.<status>.json; *.fail breaks a call, branch.missing 404s the branch.
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOS'
#!/usr/bin/env bash
[ "$1" = api ] || exit 1; shift
filter="."; url=""
while [ $# -gt 0 ]; do
  case "$1" in --jq) filter="$2"; shift 2 ;; -H) shift 2 ;; --paginate) shift ;; *) url="$1"; shift ;; esac
done
case "$url" in
  */actions/workflows) [ -e "$FIX/workflows.fail" ] && { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
                       jq -r "$filter" "$FIX/workflows.json" ;;
  */branches/*) [ -e "$FIX/branch.missing" ] && { echo "gh: Branch not found (HTTP 404)" >&2; exit 1; }; echo '{}' ;;
  */contents/*) f="${url#*/contents/}"; ref="${f#*\?ref=}"; d="$FIX/files"; [ -d "$FIX/at.$ref" ] && d="$FIX/at.$ref"
                f="$d/$(basename "${f%%\?*}")"
                [ -f "$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$f" ;;
  */actions/runs\?status=*) st="${url#*status=}"; st="${st%%&*}"
                [ -e "$FIX/runs.fail" ] && { echo "gh: Bad credentials (HTTP 401)" >&2; exit 1; }
                [ -f "$FIX/runs.$st.json" ] || exit 0; jq -r "$filter" "$FIX/runs.$st.json" ;;
  *) exit 1 ;;
esac
EOS
chmod +x "$BIN/gh"

fixture() { # <name> -> sets FIX, a repo with loopd's own tests.yml and no runs
  FIX="$TMP/$1"; mkdir -p "$FIX/files"; export FIX
  cp "$REPO/.github/workflows/tests.yml" "$FIX/files/tests.yml"
  printf '{"workflows":[{"path":".github/workflows/tests.yml","state":"active"}]}\n' > "$FIX/workflows.json"
}
run() { # <status> <id> <event> <branch> [pr] [file] [head_sha] -> appends a run to runs.<status>.json
  local f="$FIX/runs.$1.json" pr="[]"
  [ -n "${5:-}" ] && pr="[{\"number\":$5,\"base\":{\"ref\":\"main\"}}]"
  [ -f "$f" ] || printf '{"workflow_runs":[]}' > "$f"
  jq --argjson r "{\"id\":$2,\"path\":\".github/workflows/${6:-tests.yml}\",\"event\":\"$3\",\"head_branch\":\"$4\",\"head_sha\":\"${7:-run$2}\",\"status\":\"$1\",\"pull_requests\":$pr,\"html_url\":\"https://github.com/example-org/example-repo/actions/runs/$2\"}" \
    '.workflow_runs += [$r]' "$f" > "$f.n" && mv "$f.n" "$f"
}
mq() { PATH="$BIN:$PATH" bash "$SH" example-org/example-repo main "$@" 2>&1; }
rc() { mq "$@" >/dev/null; echo $?; }

echo "== loopd's own tests.yml: group keyed by branch, cancel-in-progress: true =="
fixture own
ok "no run pending is clear (exit 0)"                       "$(rc)" 0
run in_progress 11 pull_request feat-x 5
ok "a PR run in progress is another group: clear"           "$(rc)" 0
run in_progress 12 push main
ok "a main push run in progress holds (exit 1)"             "$(rc)" 1
out="$(mq)"
ok "…naming the group"                                      "$(grep -c "group 'tests-Tests-refs/heads/main'" <<<"$out")" 1
ok "…and the run"                                           "$(grep -c 'run 12 (Tests, in_progress, push on main)' <<<"$out")" 1
ok "…and the merge-row token"                               "$(grep -cx 'merge-row: ##mq1 main tests-Tests-refs/heads/main' <<<"$out")" 1

echo "== queued, waiting and pending hold too =="
for st in queued waiting pending; do
  fixture "$st"; run "$st" 21 push main
  ok "a $st main run holds"                                 "$(rc)" 1
done

echo "== what a push to main does not start never holds =="
fixture other
sed 's/branches: \[main\]/branches: [release]/' "$REPO/.github/workflows/tests.yml" > "$FIX/files/tests.yml"
run in_progress 31 push release
ok "a workflow whose push filter excludes main is clear"    "$(rc)" 0
fixture headref
cat > "$FIX/files/tests.yml" <<'YML'
name: CI
on:
  push:
    branches:
      - main
      - 'release/**'
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    concurrency:
      group: ci-${{ github.head_ref || github.run_id }}
      cancel-in-progress: true
    steps:
      - run: |
          echo "group: not-a-key"
YML
run in_progress 41 push main
run in_progress 42 pull_request feat-y 6
ok "a job-level head_ref || run_id group never collides"    "$(rc)" 0

echo "== unknown: an unevaluable group, a gh failure =="
fixture actor
sed 's/\${{ github.ref }}/${{ github.actor }}/' "$REPO/.github/workflows/tests.yml" > "$FIX/files/tests.yml"
ok "a group expression bash cannot evaluate is exit 2"      "$(rc)" 2
ok "…naming it"                                             "$(mq | grep -c "^unknown: .*github.actor }}' — bash cannot evaluate it")" 1
fixture fnc
sed "s/\${{ github.ref }}/\${{ format('{0}', github.ref) }}/" "$REPO/.github/workflows/tests.yml" > "$FIX/files/tests.yml"
ok "a function call is unknown too"                         "$(rc)" 2
fixture ghwf; : > "$FIX/workflows.fail"
ok "gh failing to list the workflows is exit 2"             "$(rc)" 2
ok "…with a merge-row token naming the reason"              "$(mq | grep -c '^merge-row: ##mq2 gh could not list the workflows')" 1
fixture ghruns; : > "$FIX/runs.fail"
ok "gh failing to list the runs is exit 2"                  "$(rc)" 2
fixture fork; run in_progress 51 pull_request feat-z
ok "a run whose group needs a missing PR number is unknown" "$(rc)" 2

echo "== every false clear the QA review found answers hold or unknown =="
fixture case; run in_progress 71 push MAIN
ok "a group that differs only in case holds (exit 1)"       "$(rc)" 1
trig() { # <name> <on: block> -> a fixture whose only workflow has that trigger, a main run in progress
  fixture "$1"; printf 'name: CI\n%s\nconcurrency: ci-${{ github.ref }}\njobs:\n  b:\n    runs-on: x\n' "$2" > "$FIX/files/tests.yml"
  run in_progress 72 push main
}
trig flow 'on: { push: { branches: [main] } }'
ok "a flow-style on: is unknown (exit 2)"                   "$(rc)" 2
trig scalar $'on:\n  push:\n    branches: main'
ok "a scalar branches: is unknown"                          "$(rc)" 2
trig multiline $'on:\n  push:\n    branches: [main,\n      release]'
ok "a multi-line [ list is unknown"                         "$(rc)" 2
trig anchor $'on:\n  push:\n    branches: &b [main]'
ok "an &anchor is unknown"                                  "$(rc)" 2
trig alias $'on:\n  push:\n    branches:\n      - *b'
ok "an *alias is unknown"                                   "$(rc)" 2
ok "…naming the file and the trigger"                       "$(mq | grep -c '^unknown: .github/workflows/tests.yml: its push trigger cannot be read')" 1
trig quoted $'on:\n  push:\n    branches:\n      - \'main\' # prod\n      - "rel" # x'
ok "a quoted branch with a trailing comment is read: hold"  "$(rc)" 1
trig quotedflow $'on:\n  push:\n    branches: [\'main\'] # prod'
ok "…in a flow list too"                                    "$(rc)" 1
fixture nobranch; : > "$FIX/branch.missing"
ok "a branch the host does not have is unknown"             "$(rc)" 2
fixture norepo; rm -f "$FIX/files/tests.yml"
ok "every workflow 404 at the branch is unknown"            "$(rc)" 2
fixture onegone; printf '{"workflows":[{"path":".github/workflows/tests.yml","state":"active"},{"path":".github/workflows/gone.yml","state":"active"}]}\n' > "$FIX/workflows.json"
ok "one workflow absent at the branch is skipped: clear"    "$(rc)" 0
fixture reusable; printf '  call:\n    uses: ./.github/workflows/shared.yml\n' >> "$FIX/files/tests.yml"
ok "a job calling a reusable workflow is unknown"           "$(rc)" 2
fixture ownbranch; mkdir -p "$FIX/at.main"; cp "$FIX/files/tests.yml" "$FIX/at.main/"
printf 'name: Feat\non: push\nconcurrency: tests-Tests-refs/heads/main\njobs:\n  b:\n    runs-on: x\n' > "$FIX/files/feat.yml"
run in_progress 73 push feat-only "" feat.yml
ok "a run of a workflow only on its own branch holds"       "$(rc)" 1
rm -f "$FIX/files/feat.yml"
ok "…and is unknown when its file cannot be read"           "$(rc)" 2
fixture requested; run requested 74 push main
ok "a requested main run holds"                             "$(rc)" 1

echo "== --pr: a mark per PR and head, and D3's bound of 2 unknowns =="
B="$TMP/bundle"; mkdir -p "$B/projects/demo/tasks" "$B/$AB_DIR"; printf '{}\n' > "$B/instance.config.json"
H1=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222
M="$B/$AB_MERGE_HOLDS/example-org_example-repo_7"
fixture bound; run in_progress 61 push main
ok "a hold with --pr is exit 1"                             "$(rc --pr 7 --head "$H1" --instance "$B")" 1
ok "…and writes a hold mark"                                "$(cut -f3 "$M")" hold
ok "…of five fields: a hold carries no reason"              "$(awk -F'\t' '{ print NF }' "$M")" 5
ok "…in a directory that ignores itself"                    "$(cat "$B/$AB_MERGE_HOLDS/.gitignore")" '*'
rm -f "$FIX/runs.in_progress.json"
ok "clear drops the mark"                                   "$(rc --pr 7 --head "$H1" --instance "$B")$([ -e "$M" ] && echo kept || echo gone)" "0gone"
: > "$FIX/runs.fail"
ok "unknown, tick 1: exit 2"                                "$(rc --pr 7 --head "$H1" --instance "$B")" 2
WHY='gh could not list requested runs of example-org/example-repo'
ok "…and the mark's 6th field is the reason"                "$(cut -f3,6 "$M")" "unknown	$WHY"
ok "…after the five fields every reader takes by position"  "$(cut -f1-5 "$M")" "$H1	1	unknown	example-org/example-repo	7"
out="$(mq --pr 7 --head "$H1" --instance "$B")"; c=$?
ok "unknown, tick 2: exit 3, the merge is the human's"      "$c" 3
ok "…printing the owner's merge-row token"                  "$(grep -cxF "merge-row: ##mq2 $WHY" <<<"$out")" 1
ok "…and the human mark keeps the last reason"              "$(cut -f2,3,6 "$M")" "2	human	$WHY"
out="$(mq --pr 7 --head "$H1" --instance "$B")"; c=$?
ok "…and a re-run at that head stays exit 3"                "$c" 3
ok "…with the token again"                                  "$(grep -cxF "merge-row: ##mq2 $WHY" <<<"$out")" 1
ok "…and no increment"                                      "$(cut -f2,3 "$M")" "2	human"
ok "a new head starts the count again"                      "$(rc --pr 7 --head "$H2" --instance "$B")" 2
ok "usage: --pr without a 40-hex head is exit 4"            "$(rc --pr 7 --head abc --instance "$B")" 4

echo "== the reason is one line, free of control characters, at most 200 characters =="
# A branch name is the one reason input this harness can fill with every byte it wants.
fixture dirty; : > "$FIX/branch.missing"
BR="$(printf 'ma\tin\nx\033[31m\001%0300d' 0)"
out="$(PATH="$BIN:$PATH" bash "$SH" example-org/example-repo "$BR" --pr 7 --head "$H2" --instance "$B" 2>&1)"
WANT="$(printf 'branch ma in x[31m%0300d' 0 | cut -c1-200)"
ok "a tab and a newline become a space, ESC and ^A go"      "$(cut -f6 "$M")" "$WANT"
ok "…cut to 200 characters"                                 "$(cut -f6 "$M" | tr -d '\n' | wc -c | tr -d ' ')" 200
ok "…leaving a one-line mark of six fields"                 "$(wc -l < "$M" | tr -d ' ') $(awk -F'\t' '{ print NF }' "$M")" "1 6"
ok "…and the same reason on the line the tick quotes"       "$(grep -cxF "unknown: $WANT" <<<"$out")" 1
ok "…and in the merge-row token"                            "$(grep -cxF "merge-row: ##mq2 $WANT" <<<"$out")" 1

echo "== tick-delta.sh check: a held mark is a DELTA =="
STUB2="$TMP/bin2"; mkdir -p "$STUB2"
cat > "$STUB2/gh" <<'EOS'
#!/usr/bin/env bash
f="."; while [ $# -gt 0 ]; do [ "$1" = --jq ] && f="$2"; shift; done
jq -r "$f" <<'J'
{"data":{"repository":{"pullRequest":{"state":"OPEN","headRefOid":"abc1234","reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewThreads":{"totalCount":0,"nodes":[]},"reviews":{"totalCount":0,"nodes":[]},"comments":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}}}}
J
EOS
chmod +x "$STUB2/gh"
printf -- '---\ntype: Task\nstatus: in-review\npr: ["https://github.com/example-org/example-repo/pull/7"]\n---\n' > "$B/projects/demo/tasks/t1.md"
printf -- '---\ntype: Project\nstatus: active\nautonomy: yolo\n---\n' > "$B/projects/demo/project.md"
printf '/%s\n' "$AB_STATE_DIR" > "$B/.gitignore"
git -C "$B" init -q && git -C "$B" add -A && git -C "$B" -c user.name=t -c user.email=t@example.com commit -qm init
TD() { PATH="$STUB2:$PATH" bash "$REPO/plugin/scripts/tick-delta.sh" "$@" --instance "$B" 2>&1; }
TD digest >/dev/null; TD record >/dev/null
printf '%s\t0\thold\texample-org/example-repo\t7\n' "$H2" > "$M"
ok "a hold mark on an in-review PR is a DELTA"              "$(TD check | grep -c '^DELTA: merge-queue.sh holds the delegated merge of example-org/example-repo#7 (hold)')" 1
printf '%s\t1\tunknown\texample-org/example-repo\t7\tgh could not list the workflows of example-org/example-repo\n' "$H2" > "$M"
ok "an unknown mark's DELTA names its reason"               "$(TD check | grep -cxF 'DELTA: merge-queue.sh holds the delegated merge of example-org/example-repo#7 (unknown: gh could not list the workflows of example-org/example-repo) — step 4 re-checks it.')" 1
printf '%s\t3\thuman\texample-org/example-repo\t7\n' "$H2" > "$M"
ok "a mark handed to the human is not: IDLE"                "$(TD check | cut -c1-5)" "IDLE:"
printf '%s\t1\tunknown\texample-org/example-repo\t8\n' "$H2" > "$M"
ok "a mark for a PR on no in-flight task is not"            "$(TD check | grep -c '^DELTA: merge-queue')" 0

echo "== build-awaiting.sh: one warning line on a human merge row =="
: > "$B/$AB_AWAITING"
L='[example-repo#7](https://github.com/example-org/example-repo/pull/7)'
aw() { bash "$REPO/plugin/scripts/build-awaiting.sh" --instance "$B" --merge "$B/projects/demo/tasks/t1.md=$1" >/dev/null 2>&1; cat "$B/$AB_AWAITING"; }
out="$(aw "$L ##mq1 main tests-Tests-refs/heads/main")"
ok "exit 1: the in-progress warning"                        "$(grep -cxF '  > warning: a tests-Tests-refs/heads/main run is in progress on main; merging now cancels it' <<<"$out")" 1
ok "…under the merge row, which keeps its link"             "$(awk -v l=" · $L" '/^\* 🔀 \*\*merge\*\*/ { r = substr($0, length($0) - length(l) + 1) == l; getline w; print r (w ~ /^  > warning: /) }' <<<"$out")" 11
out="$(aw "$L ##mq2 gh could not list the workflows of example-org/example-repo")"
ok "exit 2: the unknown warning"                            "$(grep -cxF '  > warning: concurrency unknown: gh could not list the workflows of example-org/example-repo' <<<"$out")" 1
out="$(aw "$L ##mq2 group 'a ##mq1 b c' cannot be evaluated")"
ok "the first token decides, whatever the reason quotes"    "$(grep -cxF "  > warning: concurrency unknown: group 'a ##mq1 b c' cannot be evaluated" <<<"$out")" 1
out="$(aw "$L")"
ok "exit 0: no warning line"                                "$(grep -c 'warning:' <<<"$out")" 0
ok "the warning is not counted as a row"                    "$(aw "$L ##mq2 x" | grep -c '^\* ')" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
