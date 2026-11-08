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
git add -A && git commit -qm init

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
