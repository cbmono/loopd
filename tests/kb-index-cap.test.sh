#!/usr/bin/env bash
#
# kb-index-cap.test.sh — build-kb-index.sh caps knowledge/index.md at 8,000 words (D1:
# Services, Runbooks, Teams, References, then Findings newest first), and the readers that
# need EVERY id — cite-check.sh, --check, validate-bundle.sh — still see a doc past the cap.
#
# Non-vacuous: the fixture's rows alone are over 8,000 words, and the capped-out docs are
# graded against a slug no doc carries (FABRICATED). Reasoning: slim-knowledge-base/task-001.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/plugin/scripts/build-kb-index.sh"
CITE="$REPO/plugin/scripts/cite-check.sh"
VALIDATE="$REPO/plugin/scripts/validate-bundle.sh"
# shellcheck source=../plugin/scripts/bundle-paths.sh
. "$REPO/plugin/scripts/bundle-paths.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kb-index-cap.XXXXXX")" || { echo "kb-index-cap.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
listed() { grep -qF "/knowledge/$1.md\`" "$D/knowledge/index.md" && echo yes || echo no; }

D="$TMP/bundle"
mkdir -p "$D/knowledge/findings" "$D/knowledge/services" "$D/knowledge/runbooks" "$D/$AB_DIR"
cp "$REPO/plugin/seed/knowledge/vocab.md" "$D/knowledge/vocab.md"
cp "$REPO/plugin/seed/SCHEMA.md" "$D/$AB_DIR/SCHEMA.md"
: > "$D/knowledge/log.md"
printf '{ "org": "example-org" }\n' > "$D/instance.config.json"
LONG='alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango'
doc() { # <kind> <slug> <type> <timestamp> [status] [extra frontmatter line]
  { printf -- '---\ntype: %s\ntitle: %s %s %s %s\nlesson: %s %s %s %s %s %s\n' "$3" "$2" "$LONG" "$LONG" "$LONG" \
      "$LONG" "$LONG" "$LONG" "$LONG" "$LONG" "$LONG"
    printf 'tags: [ ci ]\nstatus: %s\ntimestamp: %s\n' "${5:-current}" "$4"
    [ -z "${6:-}" ] || printf '%s\n' "$6"
    printf -- '---\n\nBody.\n'; } > "$D/knowledge/$1/$2.md"
}
doc services  the-service  Service 2020-01-01T00:00:00Z active
doc runbooks  the-runbook  Runbook 2020-01-01T00:00:00Z active
i=100
while [ "$i" -le 149 ]; do doc findings "f$i" Finding "2026-01-01T00:0${i}Z"; i=$((i+1)); done
doc findings tie-a Finding 2026-06-01T00:00:00Z
doc findings tie-b Finding 2026-06-01T00:00:00Z
doc findings old-current    Finding 2019-01-01T00:00:00Z
doc findings old-superseded Finding 2019-01-01T00:00:00Z superseded 'superseded_by: tie-a'
doc findings old-archived   Finding 2019-01-01T00:00:00Z archived

echo "== the cap =="
ROWWORDS=$(cat "$D"/knowledge/*/*.md | grep -E '^(title|lesson):' | wc -w | tr -d ' ')
ok "the fixture's titles and lessons alone exceed 8,000 words" "$([ "$ROWWORDS" -gt 8000 ] && echo yes || echo no)" yes
( cd "$D" && bash "$BUILD" >/dev/null 2>&1 )
W=$(wc -w < "$D/knowledge/index.md" | tr -d ' ')
ok "the written index is at most 8,000 words (wc -w: $W)" "$([ "$W" -le 8000 ] && echo yes || echo no)" yes
ok "…and close to it, so the cap is what stopped it"     "$([ "$W" -gt 7800 ] && echo yes || echo no)" yes
ok "it says rows are past the cap"     "$(grep -c '^\*\*Capped:\*\* [0-9]* of 57 rows' "$D/knowledge/index.md")" 1
ok "the Service is listed despite its old timestamp" "$(listed services/the-service)" yes
ok "…and the Runbook"                  "$(listed runbooks/the-runbook)" yes
ok "the newest Findings are listed"    "$(listed findings/tie-a)/$(listed findings/f149)" yes/yes
ok "the oldest are not"                "$(listed findings/old-current)/$(listed findings/old-superseded)/$(listed findings/old-archived)" no/no/no
ok "an equal timestamp is ordered by slug" \
   "$(grep -nE 'findings/tie-[ab]\.md' "$D/knowledge/index.md" | cut -d: -f1 | tr '\n' ' ' | awk '{ print ($1 < $2) ? "yes" : "no" }')" yes
cp "$D/knowledge/index.md" "$TMP/pass1"
( cd "$D" && bash "$BUILD" >/dev/null 2>&1 )
ok "a rebuild is byte-identical"       "$(cmp -s "$TMP/pass1" "$D/knowledge/index.md" && echo same || echo differs)" same

echo
echo "== every id survives the cap =="
( cd "$D" && bash "$BUILD" --check >"$TMP/check" 2>&1 ); rc=$?
ok "--check clears a capped index (exit 0)" "$rc" 0
ok "…and no ERROR for a capped-out doc"  "$(grep -c 'ERROR' "$TMP/check")" 0
( cd "$D" && bash "$VALIDATE" knowledge/index.md >"$TMP/vb" 2>&1 )
ok "validate-bundle's --print diff agrees with the file" "$(grep -c 'generator would not produce' "$TMP/vb")" 0
printf 'See [[old-current]] and [[tie-a]].\nSee [[old-superseded]] and [[tie-a]].\nSee [[old-archived]] and [[tie-a]].\nSee [[no-such-finding]] and [[tie-a]].\n' > "$TMP/text"
OUT="$(cd "$D" && bash "$CITE" --text-file "$TMP/text" --brief tie-a,old-superseded,old-archived)"
ok "a current Finding past the cap is UNREAD, not FABRICATED" "$(grep -c '^UNREAD old-current ' <<<"$OUT")" 1
ok "a superseded one past the cap is SUPERSEDED, not KEPT"    "$(grep -c '^SUPERSEDED old-superseded ' <<<"$OUT")" 1
ok "an archived one past the cap is ARCHIVED, not KEPT"       "$(grep -c '^ARCHIVED old-archived ' <<<"$OUT")" 1
ok "a slug no doc carries is still FABRICATED (control)"      "$(grep -c '^FABRICATED no-such-finding ' <<<"$OUT")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
