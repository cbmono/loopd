#!/usr/bin/env bash
#
# kb-usage.test.sh — plugin/scripts/kb-usage.sh: the citation store, and the absence of the
# retired archive-sweep verb. Dates are pinned with --today. Reasoning: knowledge-base-reflector/task-005.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
USAGE="$REPO/plugin/scripts/kb-usage.sh"
BUILD="$REPO/plugin/scripts/build-kb-index.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"
[ -x "$USAGE" ] || { echo "kb-usage.test: $USAGE is missing or not executable" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kbusage.XXXXXX")" || { echo "kb-usage.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
code() { grep -vE '^[[:space:]]*#' "$1"; }

D="$TMP/bundle"
mkdir -p "$D/knowledge/findings" "$D/$AB_DIR"
item() { # <slug> <category> <timestamp>
  { printf -- '---\ntype: Finding\ntitle: Title %s\ndescription: d\nlesson: l %s\ncategory: %s\n' "$1" "$1" "$2"
    printf 'tags: [ ]\nstatus: current\nprovenance: machine\ntimestamp: %sT00:00:00Z\n---\n\n# Finding\n\nThe claim of %s.\n' "$3" "$1"
  } >"$D/knowledge/findings/$1.md"
}
item cited-learning  learning 2025-01-01
item stale-gotcha    gotcha   2025-01-01
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D/knowledge/vocab.md"
: >"$D/knowledge/log.md"
printf '{ "org": "example-org" }\n' >"$D/instance.config.json"
cp "$REPO/plugin/seed/SCHEMA.md" "$D/$AB_DIR/SCHEMA.md"
cd "$D" || exit 2
bash "$BUILD" >/dev/null 2>&1
git init -q . && git config user.name example-user-007 && git config user.email u@example.com
git add -A && GIT_AUTHOR_DATE=2025-01-01T00:00:00Z GIT_COMMITTER_DATE=2025-01-01T00:00:00Z git commit -qm init

echo "== criterion 1: one citation reaches the store =="
printf 'Fixed it per [[cited-learning]] and [[stale-gotcha]], not [[nope]].\n' >"$TMP/result.md"
out="$("$USAGE" record --source task-001.result --text-file "$TMP/result.md" --brief cited-learning 2>/dev/null)"; rc=$?
STORE="$D/$AB_DIR/citations/task-001.result.txt"
ok "record passes cite-check's exit code through (3: dropped)" "$rc" 3
ok "…and its report"                                  "$(grep -c '^KEPT cited-learning ' <<<"$out")" 1
ok "the store file is named for the source"           "$([ -f "$STORE" ] && echo yes || echo no)" yes
ok "a KEPT citation is stored"                        "$(grep -cx 'KEPT cited-learning' "$STORE")" 1
ok "an UNREAD one is stored: a real doc someone wanted" "$(grep -cx 'UNREAD stale-gotcha' "$STORE")" 1
ok "a FABRICATED one is not: it names no document"    "$(grep -c 'nope' "$STORE")" 0
cp "$STORE" "$TMP/first"
"$USAGE" record --source task-001.result --text-file "$TMP/result.md" --brief cited-learning --today 2027-01-01 >/dev/null 2>&1
ok "a re-run is idempotent: same file, same recorded date" "$(cmp -s "$TMP/first" "$STORE" && echo same || echo differs)" same
ok "record with no index stores nothing (exit 2)" \
  "$(cd "$TMP" && mkdir -p bare/knowledge && "$USAGE" --instance bare record --source x --text-file "$TMP/result.md" --brief a >/dev/null 2>&1; echo "$?/$(ls "$TMP/bare/$AB_DIR/citations" 2>/dev/null | wc -l | tr -d ' ')")" 2/0
ok "a source id carrying a path is refused" \
  "$("$USAGE" record --source ../x --text-file "$TMP/result.md" --brief a >/dev/null 2>&1; echo $?)" 2
rm -f "$STORE"

echo
echo "== --task: a citation of the task's own new Finding is SELF, never counted as a read =="
# D3: self-citation = the Finding's adding commit postdates the task's first DISPATCH line.
TASK="$TMP/task-009.md"
printf -- '---\ntype: Task\n---\n\n# Notes\n\n* DISPATCH 2026-03-01T12:00:00Z · software-engineer · model opus\n* DISPATCH 2026-02-01T09:00:00Z · software-engineer · model opus\n' >"$TASK"
item own-new-finding learning 2026-03-02
git add knowledge/findings/own-new-finding.md \
  && GIT_AUTHOR_DATE=2026-02-15T10:00:00Z GIT_COMMITTER_DATE=2026-02-15T10:00:00Z git commit -qm finding
item rebased-old gotcha 2025-06-01
git add knowledge/findings/rebased-old.md \
  && GIT_AUTHOR_DATE=2025-06-01T00:00:00Z GIT_COMMITTER_DATE=2026-04-01T00:00:00Z git commit -qm rebased
item uncommitted-new learning 2026-03-03
printf 'Per [[own-new-finding]], [[stale-gotcha]], [[rebased-old]], [[uncommitted-new]] and [[cited-learning]].\n' >"$TMP/self.md"
out="$("$USAGE" record --source task-009.result --task "$TASK" --text-file "$TMP/self.md" --brief cited-learning 2>/dev/null)"; rc=$?
STORE="$D/$AB_DIR/citations/task-009.result.txt"
ok "record --task still passes cite-check's exit code through" "$rc" 3
ok "added after the EARLIEST DISPATCH, before a resume: SELF" "$(grep -cx 'SELF own-new-finding' "$STORE")" 1
ok "…and is not stored UNREAD"                       "$(grep -c 'UNREAD own-new-finding' "$STORE")" 0
ok "…and the printed report says SELF"               "$(grep -c '^SELF own-new-finding ' <<<"$out")" 1
ok "an uncommitted Finding has no adding commit: SELF" "$(grep -cx 'SELF uncommitted-new' "$STORE")" 1
ok "an older Finding, not carried, stays UNREAD"     "$(grep -cx 'UNREAD stale-gotcha' "$STORE")" 1
ok "an older Finding rebased after DISPATCH stays UNREAD" "$(grep -cx 'UNREAD rebased-old' "$STORE")" 1
ok "an older Finding the brief carried stays KEPT"   "$(grep -cx 'KEPT cited-learning' "$STORE")" 1
"$USAGE" record --source task-009.pr --text-file "$TMP/self.md" --brief cited-learning >/dev/null 2>&1
ok "without --task grading is unchanged: UNREAD"     "$(grep -cx 'UNREAD own-new-finding' "$D/$AB_DIR/citations/task-009.pr.txt")" 1
printf -- '---\ntype: Task\n---\n' >"$TMP/undispatched.md"
"$USAGE" record --source task-010.result --task "$TMP/undispatched.md" --text-file "$TMP/self.md" --brief cited-learning >/dev/null 2>&1
ok "a task with no DISPATCH line: grading unchanged" "$(grep -c '^SELF ' "$D/$AB_DIR/citations/task-010.result.txt")" 0
ok "an unreadable --task is refused (exit 2)" \
  "$("$USAGE" record --source x --task "$TMP/nope.md" --text-file "$TMP/self.md" --brief a >/dev/null 2>&1; echo $?)" 2
rm -f "$D/knowledge/findings/uncommitted-new.md" "$D/$AB_DIR"/citations/task-0*.txt

echo
echo "== every prompt that tells an agent to write a Finding says: only when a later task would hit it =="
PHRASE='only when a later task would plausibly hit the same problem'
for f in plugin/seed/CONVENTIONS.md plugin/tick-steps/step-3-dispatch.md plugin/seed/CLAUDE.md \
         plugin/seed/.claude/rules/knowledge-base.md plugin/agents/qa-reviewer.md \
         plugin/tick-steps/step-7-knowledge-base.md plugin/agents/project-manager.md; do
  ok "$f carries the phrase" "$(grep -qF "$PHRASE" "$REPO/$f" && echo yes || echo no)" yes
done
OLD='capture `Finding`s as a byproduct|If you discover something durable and|capture a new `Finding` if you discover one'
ok "the probe sees a planted old wording" "$(printf 'If you discover something durable and\n' | grep -cE "$OLD")" 1
ok "no file under plugin/ keeps the write-by-default wording" "$(grep -rlE "$OLD" "$REPO/plugin" | wc -l | tr -d ' ')" 0
ok "step 5 passes --task to kb-usage record" \
  "$(grep -c 'kb-usage.sh record --source <id> --task <task-path>' "$REPO/plugin/tick-steps/step-5-reflect-merges.md")" 1

echo
echo "== the archive sweep is retired: record is the only verb =="
ok "sweep is refused as an unknown argument"       "$("$USAGE" sweep >/dev/null 2>&1; echo $?)" 2
ok "…and so is its --propose flag"                 "$("$USAGE" record --propose >/dev/null 2>&1; echo $?)" 2
SWEPT='kb-usage\.sh( \[--instance DIR\])? sweep|kb-propose'
ok "the probe sees a planted mention"              "$(printf 'run kb-usage.sh sweep\nkb-propose.sh\n' | grep -cE "$SWEPT")" 2
ok "no file under plugin/ names the sweep verb or kb-propose" "$(grep -rlE "$SWEPT" "$REPO/plugin" | wc -l | tr -d ' ')" 0
(cd "$REPO" && git ls-files -z -- . ':!docs/releases' ':!tests/kb-usage.test.sh' >"$TMP/tracked") || {
  echo "kb-usage.test: cannot list tracked files" >&2; exit 2; }
ok "…nor any tracked file outside the release notes" \
  "$(cd "$REPO" && xargs -0 grep -lE "$SWEPT" <"$TMP/tracked" 2>/dev/null | wc -l | tr -d ' ')" 0
# Every line that could remove or move a file is pinned: the temp-file pair in `record`, and
# nothing else.
DELETES="$(code "$USAGE" | grep -nE '(^|[^a-z])(rm|unlink|mv|truncate|shred|rmdir)([^a-z]|$)|os\.remove|git (rm|mv)' | sed 's/^[0-9]*://; s/^[[:space:]]*//')"
ok "kb-usage.sh's only rm/mv are its own temp file"    "$(printf '%s\n' "$DELETES" | grep -cv '"\$t"')" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
