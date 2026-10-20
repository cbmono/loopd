#!/usr/bin/env bash
#
# deliverables-file-rule.test.sh — "Where files go": a role agent's non-code output lives in
# projects/<slug>/deliverables/, PII-adjacent data in its ignored local/ subfolder, never `~`.
# Pins the seed .gitignore by `git check-ignore` (the reader that decides), the CONVENTIONS
# section, SCHEMA's `artifacts:` on both kinds, and the pointer in each role agent.
# A mutant .gitignore without the line must flip the local/ verdict, so the check is not vacuous.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/plugin/seed"
CONV="$SEED/CONVENTIONS.md"; SCHEMA="$SEED/SCHEMA.md"; GI="$SEED/.gitignore"
for f in "$CONV" "$SCHEMA" "$GI"; do
  [ -f "$f" ] || { echo "deliverables-file-rule.test: missing $f" >&2; exit 2; }
done
command -v git >/dev/null 2>&1 || { echo "deliverables-file-rule.test: git required" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/deliverables-rule.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
       else printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { "$@" >/dev/null 2>&1 && echo yes || echo no; }
ignored() { yn git -C "$1" check-ignore -q --no-index "$2"; }   # <bundle> <path>
section() { awk '/^## Where files go$/{f=1;next} f&&/^## /{exit} f' "$CONV"; }

echo "== the seed .gitignore keeps local/ off GitHub and nothing else =="

bundle() { # <dir> <gitignore> — a bare bundle carrying that ignore file
  mkdir -p "$1"; git -c init.defaultBranch=main init -q "$1"; cp "$2" "$1/.gitignore"; }
bundle "$TMP/b" "$GI"
ok "projects/x/deliverables/local/y is ignored"     "$(ignored "$TMP/b" projects/x/deliverables/local/y)" yes
ok "…at any depth below local/"                     "$(ignored "$TMP/b" projects/x/deliverables/local/a/b.csv)" yes
ok "projects/x/deliverables/y is NOT ignored"       "$(ignored "$TMP/b" projects/x/deliverables/y)" no
ok "projects/x/sources/y is NOT ignored"            "$(ignored "$TMP/b" projects/x/sources/y)" no
ok "a deliverable NAMED local is NOT ignored"       "$(ignored "$TMP/b" projects/x/deliverables/local.md)" no
ok "a top-level deliverables/local/ is NOT ignored" "$(ignored "$TMP/b" deliverables/local/y)" no

grep -vxF '/projects/*/deliverables/local/' "$GI" > "$TMP/mutant.gitignore"
bundle "$TMP/m" "$TMP/mutant.gitignore"
ok "mutant without the line really differs"         "$(yn cmp -s "$GI" "$TMP/mutant.gitignore")" no
ok "…and then local/ is NOT ignored (non-vacuous)"  "$(ignored "$TMP/m" projects/x/deliverables/local/y)" no
ok "the line sits above the Instance additions block" \
  "$(awk '/^\/projects\/\*\/deliverables\/local\/$/{l=NR} /^# Instance additions/{a=NR} END{print (l && a && l<a) ? "yes" : "no"}' "$GI")" yes

echo "== CONVENTIONS carries the section, with every row =="

S="$(section)"
ok "CONVENTIONS.md has '## Where files go'"         "$(yn grep -qx '## Where files go' "$CONV")" yes
ok "…routing consumables to deliverables/"          "$(yn grep -qF '`projects/<slug>/deliverables/`, listed in the task'"'"'s `artifacts:`' <<<"$S")" yes
ok "…inputs to sources/"                            "$(yn grep -qF '`projects/<slug>/sources/`' <<<"$S")" yes
ok "…PII-adjacent data to deliverables/local/"      "$(yn grep -qF '`projects/<slug>/deliverables/local/`' <<<"$S")" yes
ok "…and ~ / the bundle root to never — ask"        "$(yn grep -qF '`~`, `/`, another repo, the bundle root | **never** — ask' <<<"$S")" yes
ok "…and a hand-over names the project path"        "$(yn grep -qF 'never a home-directory one' <<<"$S")" yes

echo "== SCHEMA: artifacts: on both kinds, local/ in the project layout =="

ART="$(grep -m1 '^artifacts:' "$SCHEMA")"
ok "artifacts: is no longer RESEARCH only"          "$(yn grep -qF 'RESEARCH only' <<<"$ART")" no
ok "…and names a BUILD task's non-code output"      "$(yn grep -qF 'BUILD task' <<<"$ART")" yes
ok "SCHEMA names deliverables/local/ and its ignore" "$(yn grep -qF '`/projects/*/deliverables/local/`' "$SCHEMA")" yes

echo "== every role agent that writes points at the section =="

for a in software-engineer devops-engineer qa-reviewer cataloguer project-manager; do
  ok "$a.md points at \"Where files go\""           "$(yn grep -qF '"Where files go"' "$REPO/plugin/agents/$a.md")" yes
done

printf '\n  %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
