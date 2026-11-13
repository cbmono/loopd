#!/usr/bin/env bash
#
# docs-drift.test.sh — the user-facing docs and the plugin they describe agree, and every
# link in them lands.
#
# WHY. The README was rewritten as a short front door, and the reference material moved
# to docs/reference.md, docs/getting-started.md and CONTRIBUTING.md. Short pages drift
# quietly: an agent added under plugin/agents/ that the README's team table never names, a
# `/loopd:<cmd>` left behind after a skill is renamed, a link into a heading that was
# reworded. Each of those reads fine and is wrong. Four checks, each a function over a
# file (or a root) so a mutant can be fed to the same code:
#
#   (a) every plugin/agents/*.md is named, as `<name>`, in README.md's `## The team` section;
#   (b) every /<plugin>:<cmd> in README.md and docs/getting-started.md is a real
#       plugin/skills/<cmd>/SKILL.md;
#   (c) every relative markdown link in README.md, docs/getting-started.md,
#       docs/reference.md and CONTRIBUTING.md resolves — and its #anchor too, by GitHub's
#       slug rules, when the target is a .md file;
#   (d) docs/releases/ does not exist: per-version release notes are retired, and git
#       history plus PR descriptions are the record (CONTRIBUTING.md).
#
# NON-VACUOUS BY CONSTRUCTION. Each check also runs on a mutant carrying exactly the drift
# it exists to catch, and the mutant must go red.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
README="$REPO/README.md"
DOCS="README.md docs/getting-started.md docs/reference.md CONTRIBUTING.md"
for f in $DOCS; do
  [ -f "$REPO/$f" ] || { echo "docs-drift.test: missing $REPO/$f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "docs-drift.test: python3 checks the links" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/docs-drift.XXXXXX")" \
  || { echo "docs-drift.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-60s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-60s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# --- (a) ---------------------------------------------------------------------------------
agents() { find "$REPO/plugin/agents" -maxdepth 1 -name '*.md' -exec basename {} .md \; | sort; }
team_section() { awk '/^## The team$/ { f=1; next } f && /^## / { exit } f' "$1"; }
unnamed_agents() { # <readme> -> each plugin agent its team section never names, or none
  local a miss="" sec; sec="$(team_section "$1")"
  for a in $(agents); do grep -qF "\`$a\`" <<<"$sec" || miss="${miss:+$miss }$a"; done
  echo "${miss:-none}"
}

# --- (b) ---------------------------------------------------------------------------------
ghost_commands() { # <file>... -> each /$PN:<cmd> with no plugin/skills/<cmd>/SKILL.md, or none
  local c miss=""
  for c in $(grep -ohE "/${PN}:[a-z][a-z0-9-]*" "$@" 2>/dev/null | sed "s|^/${PN}:||" | sort -u); do
    [ -f "$REPO/plugin/skills/$c/SKILL.md" ] || miss="${miss:+$miss }$c"
  done
  echo "${miss:-none}"
}

# --- (c) ---------------------------------------------------------------------------------
# broken_links <file> <as-path> — every relative link in <file> that does not resolve, read
# as if the file lived at <as-path> (repo-relative), so a mutant in $TMP resolves like the
# real file. One line per broken link; empty output is clean.
broken_links() {
  python3 - "$REPO" "$1" "$2" <<'PY'
import os, re, sys
repo, src, as_path = sys.argv[1], sys.argv[2], sys.argv[3]

FENCE = re.compile(r'^\s*(```|~~~)')
def body(text):
    out, fenced = [], False
    for line in text.split('\n'):
        if FENCE.match(line):
            fenced = not fenced; out.append(''); continue
        out.append('' if fenced else line)
    return out

def slug(text):
    t = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', text)      # a link renders as its text
    t = re.sub(r'<[^>]+>', '', t)                            # inline HTML renders as nothing
    t = t.strip().lower()
    t = re.sub(r'[^\w\- ]', '', t, flags=re.UNICODE)         # GitHub keeps letters, digits, _ - and space
    return t.replace(' ', '-')

HEAD = re.compile(r'^(?:>\s*)*(#{1,6})\s+(.*?)\s*#*\s*$')
ANCHOR = re.compile(r'<a\s+(?:id|name)="([^"]+)"')
cache = {}
def anchors(path):
    if path in cache: return cache[path]
    seen, found = {}, set()
    for line in body(open(path, encoding='utf-8').read()):
        for a in ANCHOR.findall(line): found.add(a)
        m = HEAD.match(line)
        if not m: continue
        s = slug(m.group(2))
        n = seen.get(s, 0); seen[s] = n + 1
        found.add(s if n == 0 else '%s-%d' % (s, n))
    cache[path] = found
    return found

LINK = re.compile(r'\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
CODE = re.compile(r'`+[^`]*`+')
here = os.path.dirname(os.path.join(repo, as_path))
self_abs = os.path.join(repo, as_path)
for n, line in enumerate(body(open(src, encoding='utf-8').read()), 1):
    for target in LINK.findall(CODE.sub('', line)):
        if re.match(r'^[a-z][a-z0-9+.-]*:', target, re.I):
            continue                                         # http:, https:, mailto: — not ours
        path, _, frag = target.partition('#')
        dest = self_abs if path == '' else os.path.normpath(os.path.join(here, path))
        if path and not os.path.exists(dest):
            print('%s:%d: %s — no such file' % (as_path, n, target)); continue
        if frag and dest.endswith('.md'):
            pool = anchors(src) if path == '' else anchors(dest)
            if frag not in pool:
                print('%s:%d: %s — no such anchor' % (as_path, n, target))
PY
}
all_broken() { local f; for f in $DOCS; do broken_links "$REPO/$f" "$f"; done; }

# --- (d) ---------------------------------------------------------------------------------
releases_dir() { [ -e "$1/docs/releases" ] && echo present || echo absent; } # <root>

echo
echo "== (a) every plugin agent is named in the README's team section =="
ok "the README has exactly one '## The team' heading" "$(grep -c '^## The team$' "$README" | tr -d ' ')" 1
ok "…and plugin/agents/ ships agents" "$([ -n "$(agents)" ] && echo yes || echo no)" yes
ok "every plugin/agents/*.md is named there" "$(unnamed_agents "$README")" none

echo
echo "== (b) every /${PN}:<cmd> in README.md and getting-started.md is a real skill =="
ok "the two pages name at least one command" \
   "$([ -n "$(grep -ohE "/${PN}:[a-z]" "$README" "$REPO/docs/getting-started.md")" ] && echo yes || echo no)" yes
ok "no command names a skill that does not exist" "$(ghost_commands "$README" "$REPO/docs/getting-started.md")" none

echo
echo "== (c) every relative link and #anchor in the four pages resolves =="
for f in $DOCS; do
  ok "$f carries relative links" \
     "$(grep -qE '\]\((\.\./|[A-Za-z0-9_.-]+(/|\.md|#)|#)' "$REPO/$f" && echo yes || echo no)" yes
done
broken="$(all_broken)"
ok "no broken link or anchor" "$([ -z "$broken" ] && echo none || printf '%s' "$broken" | tr '\n' ' ')" none

echo
echo "== (d) the retired docs/releases/ stays retired =="
ok "docs/releases/ does not exist" "$(releases_dir "$REPO")" absent

echo
echo "== the mutants go RED — each check discriminates =="
victim="$(agents)"; victim="${victim%%$'\n'*}"   # the first, with no early-exit pipe
grep -vF "\`$victim\`" "$README" > "$TMP/no-agent.md"
ok "mutant A: a dropped team row names the missing agent" "$(unnamed_agents "$TMP/no-agent.md")" "$victim"

printf 'Run `/%s:no-such-command` next.\n' "$PN" > "$TMP/ghost.md"
ok "mutant B: a command with no skill is named" "$(ghost_commands "$README" "$TMP/ghost.md")" no-such-command

{ cat "$REPO/docs/getting-started.md"; printf '\nSee [nowhere](no-such-page.md).\n'; } > "$TMP/dead-file.md"
ok "mutant C: a link to a missing file is reported" \
   "$(broken_links "$TMP/dead-file.md" docs/getting-started.md | grep -c 'no-such-page.md — no such file' | tr -d ' ')" 1

{ cat "$REPO/docs/getting-started.md"; printf '\nSee [commands](reference.md#no-such-heading).\n'; } > "$TMP/dead-anchor.md"
ok "mutant D: a link to a missing anchor in another page is reported" \
   "$(broken_links "$TMP/dead-anchor.md" docs/getting-started.md | grep -c 'reference.md#no-such-heading — no such anchor' | tr -d ' ')" 1

sed 's/^## Install$/## Installing/' "$README" > "$TMP/renamed-heading.md"
ok "mutant E: a self-link whose heading was reworded is reported" \
   "$(printf '[x](#install)\n' >> "$TMP/renamed-heading.md"; broken_links "$TMP/renamed-heading.md" README.md | grep -c '#install — no such anchor' | tr -d ' ')" 1

ok "…while the same link into the real README resolves" \
   "$(printf '[x](../README.md#install)\n' > "$TMP/good.md"; broken_links "$TMP/good.md" docs/x.md | wc -l | tr -d ' ')" 0

mkdir -p "$TMP/root/docs/releases"
ok "mutant F: a recreated docs/releases/ is reported" "$(releases_dir "$TMP/root")" present

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
