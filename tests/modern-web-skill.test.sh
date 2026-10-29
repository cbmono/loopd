#!/usr/bin/env bash
#
# modern-web-skill.test.sh — the condensed modern-web reference skill ships whole, with
# provenance, inside its size ceiling, and both code-writing roles are pointed at it.
#
# WHY. plugin/skills/modern-web/ is a CONDENSED DERIVATIVE of Google Chrome's
# modern-web-guidance skill (Apache-2.0), one file per kept category, pinned to one upstream
# commit. Four things can rot without any other harness noticing: the router table in
# SKILL.md and the guides/ directory can disagree (a row naming a file that is gone, or a
# guide no row reaches — unreachable for the only reader it has); a guide can lose the
# two-line source comment that ties it to the pinned commit, which is the one thing a
# re-sync needs; the directory can grow past the ceiling the owner set, so that a role
# agent opening one guide pays for prose; and the paragraph that sends the engineer and the
# reviewer to the guides can be edited out. Each is asserted here, and the two that are
# parsers (the table/directory diff and the sha check) are proven by removal against a
# planted mutant, because a scanner asserted only against a clean tree reports "no findings"
# identically whether it works or does nothing at all.
#
# THE SHA HAS ONE SOURCE: NOTICE.md's `Pinned commit` row. Every guide must carry that
# same sha in its header comment, so a re-sync that updates the NOTICE and forgets a guide
# fails here, and so does one that updates a guide and forgets the NOTICE.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$REPO/plugin/skills/modern-web"
SKILL="$SKILL_DIR/SKILL.md"
NOTICE="$SKILL_DIR/NOTICE.md"
GUIDES="$SKILL_DIR/guides"
AGENTS="$REPO/plugin/agents"
CEILING=122880     # 120 KiB for the whole directory — the owner's number
GUIDE_LINES=250    # per guide — "under ~250 lines"
[ -d "$SKILL_DIR" ] || { echo "modern-web-skill.test: missing $SKILL_DIR" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/modern-web-skill.XXXXXX")" || {
  echo "modern-web-skill.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# Here-strings, never a pipe into grep -q (no-early-exit-pipe.test.sh).
saw() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
has() { grep -qF -- "$2" <<<"$(cat "$1")" && echo yes || echo no; }

# fm <file> <key> — a frontmatter value, read from between the first `---` pair only.
fm() {
  awk -v k="$2" 'NR==1 && $0=="---" {infm=1; next}
                 infm && $0=="---" {exit}
                 infm && index($0, k ":")==1 {sub("^" k ":[ ]*", ""); print; exit}' "$1"
}
# pinned_sha <notice> — the 40-hex sha on the `Pinned commit` row; empty when absent.
pinned_sha() { grep -E '^\| Pinned commit \|' "$1" | grep -oE '[0-9a-f]{40}' | sort -u; }
# table_guides <skill> — every `guides/<x>.md` the router table names, sorted, unique.
table_guides() { grep -E '^\|' "$1" | grep -oE 'guides/[a-z0-9-]+\.md' | sort -u; }
# dir_guides <guides-dir> — every guide file present, as `guides/<x>.md`, sorted.
dir_guides() { ( cd "$1" && ls *.md 2>/dev/null | sed 's|^|guides/|' | sort ); }
# table_vs_dir <skill> <guides-dir> — the symmetric difference; empty is the green state.
table_vs_dir() {
  diff <(table_guides "$1") <(dir_guides "$2") | grep -E '^[<>]' \
    | sed 's/^< /table-only: /; s/^> /dir-only: /'
}
# unsourced <guides-dir> <sha> — guides whose first two lines are not the source comment
# carrying <sha>; empty is the green state.
unsourced() {
  local f head
  for f in "$1"/*.md; do
    head="$(sed -n '1,2p' "$f" | tr '\n' ' ')"
    case "$head" in
      "<!-- Condensed from GoogleChrome/modern-web-guidance "*" at $2, Apache-2.0 "*"-->"*) ;;
      *) basename "$f" ;;
    esac
  done
}
# dir_bytes <dir> — the byte total of every regular file under it, one level deep or two.
dir_bytes() { cat "$1"/* "$1"/guides/* 2>/dev/null | wc -c | tr -d ' '; }

# =======================================================================================
echo "== 1. the skill is a model-invocable reference, with the frontmatter the loader keys on =="
# =======================================================================================
ok "SKILL.md ships"                                   "$([ -f "$SKILL" ] && echo yes || echo no)" yes
ok "…name: modern-web"                                "$(fm "$SKILL" name)" modern-web
ok "…description is non-empty"                        "$([ -n "$(fm "$SKILL" description)" ] && echo yes || echo no)" yes
ok "…and names browser-facing work, so the model reaches for it" \
  "$(saw "$(fm "$SKILL" description)" "browser")" yes
ok "…user-invocable: false (not in the / menu)"       "$(fm "$SKILL" user-invocable)" false
ok "…no disable-model-invocation (the model may open it)" "$(fm "$SKILL" disable-model-invocation)" ""
ok "…and the body is a router: a table with a Guide column" \
  "$(grep -c '^| Category |' "$SKILL" | tr -d ' ')" 1
ok "…that names the NOTICE for provenance"            "$(has "$SKILL" 'NOTICE.md')" yes

# =======================================================================================
echo "== 2. the router table and guides/ agree, both ways =="
# =======================================================================================
n="$(table_guides "$SKILL" | grep -c .)"
ok "the table names guides (>= 8)"                    "$([ "$n" -ge 8 ] && echo yes || echo "no ($n)")" yes
d="$(table_vs_dir "$SKILL" "$GUIDES")"
[ -z "$d" ] || printf '%s\n' "$d" | sed 's/^/        /'
ok "every table row resolves and every guide has a row" "$(printf '%s' "$d" | grep -c .)" 0

# =======================================================================================
echo "== 3. provenance: NOTICE pins one sha, and every guide carries it =="
# =======================================================================================
ok "NOTICE.md ships"                                  "$([ -f "$NOTICE" ] && echo yes || echo no)" yes
SHA="$(pinned_sha "$NOTICE")"
ok "…with exactly one 40-hex Pinned commit"           "$(printf '%s' "$SHA" | grep -c .)" 1
ok "…names the upstream repository"                   "$(has "$NOTICE" 'GoogleChrome/modern-web-guidance')" yes
ok "…names the licence"                               "$(has "$NOTICE" 'Apache License, Version 2.0')" yes
ok "…says the files are condensed derivatives"        "$(has "$NOTICE" 'condensed derivatives')" yes
ok "…and carries a Re-sync section with the diff command" \
  "$([ "$(grep -c '^## Re-sync' "$NOTICE")" -eq 1 ] && [ "$(grep -c 'git diff' "$NOTICE")" -ge 1 ] && echo yes || echo no)" yes
ok "the licence text ships beside it"                 "$([ -f "$SKILL_DIR/LICENSE" ] && echo yes || echo no)" yes
ok "…and is the Apache 2.0 text"                      "$(has "$SKILL_DIR/LICENSE" 'Apache License')" yes
u="$(unsourced "$GUIDES" "$SHA")"
[ -z "$u" ] || printf '%s\n' "$u" | sed 's/^/        UNSOURCED /'
ok "every guide opens with the source comment carrying that sha" "$(printf '%s' "$u" | grep -c .)" 0

# =======================================================================================
echo "== 4. size: the directory stays under the ceiling, each guide under $GUIDE_LINES lines =="
# =======================================================================================
bytes="$(dir_bytes "$SKILL_DIR")"
ok "plugin/skills/modern-web/ is under $CEILING bytes ($bytes)" "$([ "$bytes" -le "$CEILING" ] && echo yes || echo no)" yes
over=""
for f in "$GUIDES"/*.md; do
  l="$(grep -c '' "$f")"
  [ "$l" -le "$GUIDE_LINES" ] || over="$over $(basename "$f")=$l"
done
ok "no guide is over $GUIDE_LINES lines${over:+ (over:$over)}" "$([ -z "$over" ] && echo yes || echo no)" yes

# =======================================================================================
echo "== 5. the two code-writing roles are pointed at the guides =="
# =======================================================================================
for a in software-engineer qa-reviewer; do
  ok "$a.md opens guides under skills/modern-web/guides/" \
    "$(has "$AGENTS/$a.md" 'skills/modern-web/guides/')" yes
done
ok "…the engineer names the guide on the Verified: line" \
  "$(grep -A8 'modern-web guide' "$AGENTS/software-engineer.md" | grep -c 'Verified:' | tr -d ' ')" 1
ok "…the reviewer names it in the review" \
  "$(grep -A8 'modern-web guide' "$AGENTS/qa-reviewer.md" | grep -c 'in the review' | tr -d ' ')" 1

# =======================================================================================
echo "== 6. non-vacuity: the parsers flag a planted stray guide and a planted stale sha =="
# =======================================================================================
MUT="$TMP/modern-web"
cp -R "$SKILL_DIR" "$MUT"
ok "the copy is green before mutation" \
  "$(( printf '%s' "$(table_vs_dir "$MUT/SKILL.md" "$MUT/guides")"; printf '%s' "$(unsourced "$MUT/guides" "$SHA")" ) | grep -c .)" 0
printf '%s\n' '<!-- Condensed from GoogleChrome/modern-web-guidance skills/modern-web-guidance/guides/x/ (1 guide)' \
  '     at 0000000000000000000000000000000000000000, Apache-2.0 — see ../NOTICE.md -->' '' '# Stray' \
  > "$MUT/guides/stray.md"
first="$(ls "$MUT/guides" | grep -v '^stray\.md$' | sed -n '1p')"
sed -i.bak '2s/.*/     (sha line removed by the mutant)/' "$MUT/guides/$first" && rm -f "$MUT/guides/$first.bak"
ok "mutant: the stray guide is reported as dir-only"   "$(saw "$(table_vs_dir "$MUT/SKILL.md" "$MUT/guides")" "dir-only: guides/stray.md")" yes
ok "…and nothing else is reported by the table diff"   "$(table_vs_dir "$MUT/SKILL.md" "$MUT/guides" | grep -c .)" 1
ok "mutant: the stale-sha stray and the stripped guide are both unsourced" \
  "$(unsourced "$MUT/guides" "$SHA" | sort | tr '\n' ' ')" "$(printf '%s\n' "$first" stray.md | sort | tr '\n' ' ')"

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
