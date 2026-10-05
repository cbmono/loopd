#!/usr/bin/env bash
# iced — the board is on hold (owner's decision, 2026-10-05). `run.sh --iced`, the nightly
# workflow and any PR whose diff names this file's subject still run it. Thaw: delete these lines.
#
# build-board.test.sh — a paused project leaves `Active` for its own `Paused` tab and keeps a
# card marker, and a paused project owned by the OTHER human is marked too. Two owners on
# purpose: a single-owner fixture cannot see the other-owners half at all.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$TPL/plugin/scripts/build-board.sh"
WRITER="$TPL/plugin/scripts/write-snapshot.sh"
. "$TPL/plugin/scripts/bundle-paths.sh"
command -v python3 >/dev/null 2>&1 || { echo "  (python3 absent — skipped)"; echo "pass=0 fail=0"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/build-board.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }

INST="$TMP/_ai-bridge-two"; mkdir -p "$INST/$AB_DIR"
printf 'stub\n' > "$INST/$AB_SCHEMA"
printf '{ "org": "o", "defaultOwner": "example-user-007" }\n' > "$INST/instance.config.json"
printf '{ "ownerGithubUser": "example-user-007" }\n' > "$INST/instance.config.local.json"
mkproj() { # <slug> <title> <status> [<owner>]
  mkdir -p "$INST/projects/$1/tasks"
  { printf -- '---\ntype: Project\ntitle: %s\nkind: build\nstatus: %s\n' "$2" "$3"
    [ -z "${4:-}" ] || printf 'owner: %s\n' "$4"; printf -- '---\n'; } > "$INST/projects/$1/project.md"
  printf -- '---\ntype: Task\ntitle: %s work\nstatus: ready\n---\n' "$2" > "$INST/projects/$1/tasks/task-001.md"
}
mkproj live   "Live one"   active
mkproj held   "Held one"   paused
mkproj theirs "Their held" paused example-user-008
git -C "$INST" init -q; git -C "$INST" -c user.email=t@example.com -c user.name=T add -A
git -C "$INST" -c user.email=t@example.com -c user.name=T commit -qm fixture

render() { # <page>
  : > "$INST/$AB_SNAPSHOT"
  ( cd "$INST" && SNAPSHOT_NOW=2026-09-28T00:00:00Z bash "$WRITER" --quiet ) >/dev/null 2>&1
  ( cd "$INST" && bash "$GEN" --out "$1" . ) >/dev/null 2>&1; }
facets() { # <page> <title> -> the facets on that project's card wrapper
  python3 -c 'import re,sys
h = open(sys.argv[1]).read()
m = re.search(r"<div class=\"pcard\" data-f=\"([^\"]*)\">\s*<details[^>]*>\s*<summary class=\"phead\">\s*<span class=\"ptitle\">" + re.escape(sys.argv[2]) + "<", h)
print(m.group(1) if m else "<no card>")' "$1" "$2"; }
tab() { grep -oE "data-pick=\"$2\">[^<]*" "$1" | sed 's/.*· //'; }
has_word() { case " $1 " in *" $2 "*) echo yes ;; *) echo no ;; esac; }

P1="$TMP/paused.html"; render "$P1"
ok "paused card carries the pause facet"   "$(has_word "$(facets "$P1" 'Held one')" pause)" yes
ok "…and not act"                          "$(has_word "$(facets "$P1" 'Held one')" act)" no
ok "active card carries act"               "$(has_word "$(facets "$P1" 'Live one')" act)" yes
ok "…and not pause"                        "$(has_word "$(facets "$P1" 'Live one')" pause)" no
ok "Paused tab counts the one paused project of mine" "$(tab "$P1" pause)" 1
ok "the paused card carries its marker" \
  "$(grep -qF 'class="ptitle">Held one</span><span class="tag paused">⏸ Paused</span>' <<<"$(tr -d '\n' < "$P1")" && echo yes || echo no)" yes
ok "the other human's paused project is marked in its row" \
  "$(grep -qF '⏸ Paused' <<<"$(grep -oE 'Their held</td>.{0,120}' "$P1")" && echo yes || echo no)" yes

sed -i.bak 's/^status: paused$/status: active/' "$INST/projects/held/project.md"; rm -f "$INST/projects/held/project.md.bak"
P2="$TMP/active.html"; render "$P2"
ok "Active drops by one when the project is paused" "$(( $(tab "$P2" act) - $(tab "$P1" act) ))" 1
ok "…and Paused is 0 once it resumes"      "$(tab "$P2" pause)" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
