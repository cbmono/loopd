#!/usr/bin/env bash
#
# ticket-prefix.test.sh — a PR title carries NO ticket tag unless the installation sets
# `ticketPrefix`, and a role agent learns which from its brief's `## PR title`, never by
# reading config. The seed used to hardcode one organisation's Jira key as the universal
# fallback (`[DPT-0]`); both mutants below restore it and must go RED.
#
# Reasoning: dispatch-reporting-defects/task-030. Same shape as commit-attribution.test.sh.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BRIEF="$REPO/plugin/scripts/dispatch-brief.sh"
SEED_CFG="$REPO/plugin/seed/instance.config.json"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
PM="$REPO/plugin/tick-steps/step-3-dispatch.md"
for f in "$BRIEF" "$SEED_CFG" "$CONV" "$SCHEMA" "$PM"; do
  [ -f "$f" ] || { echo "ticket-prefix.test: $f not found" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "ticket-prefix.test: python3 required" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { "$@" >/dev/null 2>&1 && echo yes || echo no; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ticket-prefix.XXXXXX")" || {
  echo "ticket-prefix.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

HEADING="$(sed -n "s/^TITLE_HEADING='\(.*\)'$/\1/p" "$BRIEF")"

# <name> [json-value] — a bundle whose ONLY variable is the key. No value ⇒ key absent.
bundle() {
  local d="$TMP/$1"
  mkdir -p "$d/projects/demo/tasks"
  if [ $# -ge 2 ]; then
    printf '{ "org": "acme", "ticketPrefix": %s }\n' "$2" > "$d/instance.config.json"
  else
    printf '{ "org": "acme" }\n' > "$d/instance.config.json"
  fi
  { printf -- '---\ntype: Task\ntitle: "Ship the widget"\nkind: build\n'
    printf 'target_repo: acme/widget\nstatus: ready\n'
    printf 'acceptance_criteria: [ "one" ]\ntimestamp: 2026-01-01T00:00:00Z\n---\n\n# Context\n\nX.\n'
  } > "$d/projects/demo/tasks/task-001.md"
  printf '%s' "$d"
}
# <brief-script> <bundle> — the `## PR title` body, blank lines dropped.
section() {
  awk -v h="$HEADING" '$0==h{f=1;next} f&&/^## /{exit} f&&NF' \
    <<<"$(bash "$1" "$2/projects/demo/tasks/task-001.md" 2>/dev/null)"
}
# The title format the brief hands an agent: its first backticked span.
format_of() { head -1 <<<"$(sed -n 's/^[^`]*`\([^`]*\)`.*/\1/p' <<<"$1")"; }
# yes when <section> documents an untagged title and names no `[XYZ-n]` tag anywhere.
untagged() {
  local f; f="$(format_of "$1")"
  [ -n "$f" ] && [[ "$f" != *"["* ]] && ! grep -Eq '\[[A-Z][A-Z0-9_]*-[0-9<]' <<<"$1"
}
# yes when <conventions-file>'s PR-title rule documents an untagged format and no DPT.
conv_untagged() {
  local line; line="$(grep -m1 '^- PR title format:' "$1")"
  [ -n "$line" ] && [[ "$(format_of "$line")" != *"["* ]] && ! grep -q 'DPT' "$1"
}

echo "== the heading has one copy, and the PM pastes it =="
ok "dispatch-brief.sh defines TITLE_HEADING"   "$HEADING" "## PR title"
ok "step-3 names \`## PR title\`"              "$(yn grep -qF '`## PR title`' "$PM")" yes

echo "== absent key ⇒ no tag at all =="
D="$(bundle absent)"
BODY="$(section "$BRIEF" "$D")"
ok "the section exists"                        "$([ -n "$BODY" ] && echo yes || echo no)" yes
ok "absent ⇒ ticketPrefix: none"               "$(yn grep -q '^ticketPrefix: none' <<<"$BODY")" yes
ok "…title format carries no bracketed tag"    "$(yn untagged "$BODY")" yes
for v in null '""' '"abc"' '"A B"' '"X]"' 42; do
  ok "ticketPrefix $v ⇒ untagged"   "$(yn untagged "$(section "$BRIEF" "$(bundle "v$RANDOM" "$v")")")" yes
done

echo "== configured key ⇒ the brief carries it resolved =="
BODY="$(section "$BRIEF" "$(bundle set '"ABC"')")"
ok "ABC ⇒ ticketPrefix: ABC"                   "$(yn grep -q '^ticketPrefix: ABC ' <<<"$BODY")" yes
ok "…format ends [ABC-<n>]"                    "$(format_of "$BODY")" '<type>: <subject> [ABC-<n>]'
ok "…and names the zero-form [ABC-0]"          "$(yn grep -qF '`[ABC-0]`' <<<"$BODY")" yes
ok "…so it is not read as untagged"            "$(yn untagged "$BODY")" no

echo "== mutants: the old fallback and an ignored key both go RED =="
cp -R "$REPO/plugin/scripts" "$TMP/mut"
perl -pi -e 's/^  printf .ticketPrefix: none.*$/  printf "ticketPrefix: none — title is `<type>: <subject> [DPT-0]`.\\n"/' "$TMP/mut/dispatch-brief.sh"
ok "mutant brief really differs"     "$(yn cmp -s "$BRIEF" "$TMP/mut/dispatch-brief.sh")" no
ok "[DPT-0] fallback ⇒ RED"          "$(yn untagged "$(section "$TMP/mut/dispatch-brief.sh" "$D")")" no
cp -R "$REPO/plugin/scripts" "$TMP/ign"
perl -pi -e 's/cfg ticketPrefix ""/printf ""/' "$TMP/ign/dispatch-brief.sh"
ok "ignored-key mutant really differs" "$(yn cmp -s "$BRIEF" "$TMP/ign/dispatch-brief.sh")" no
ok "ignored key ⇒ RED"               "$(yn grep -q '^ticketPrefix: ABC ' <<<"$(section "$TMP/ign/dispatch-brief.sh" "$TMP/set")")" no

echo "== CONVENTIONS.md: untagged by default, the discipline intact =="
ok "documented format carries no tag"          "$(yn conv_untagged "$CONV")" yes
{ sed '/^- PR title format:/,$d' "$CONV"
  printf -- '- PR title format: `<type>: <subject> [<JIRA-ID>]` — e.g. `fix: retry on 429 [DPT-1234]`.\n'
  printf -- '  **`[DPT-0]` when neither does** — that is the normal case and the whole answer.\n'
} > "$TMP/conv-mutant.md"
ok "the old [DPT-0] text ⇒ RED"                "$(yn conv_untagged "$TMP/conv-mutant.md")" no
ok "the brief decides, not the config"         "$(yn grep -qF 'never read the' "$CONV")" yes
ok "…under \`## PR title\`"                    "$(yn grep -qF '`## PR title`' "$CONV")" yes
ok "never invent an id"                        "$(yn grep -qF 'Never invent an id' "$CONV")" yes
ok "never guess a project prefix"              "$(yn grep -qF 'never guess a' "$CONV")" yes
ok "never block a PR on a missing one"         "$(yn grep -qF 'never block a PR on the absence of one' "$CONV")" yes
ok "ticket URL still goes in the body"         "$(yn grep -qF 'ticket URL goes in the body' "$CONV")" yes

echo "== the seed and SCHEMA =="
ok "seed ships the key as null (absent)" \
  "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("ticketPrefix" in d and d["ticketPrefix"] is None)' "$SEED_CFG")" True
ok "SCHEMA row: not per-machine overridable"   "$(yn grep -q '^| `ticketPrefix` | \*\*no\*\*' "$SCHEMA")" yes
ok "…and absent means no tag"                  "$(yn grep -q '^| `ticketPrefix` |.*| \*\*no tag\*\*' "$SCHEMA")" yes
ok "no DPT anywhere under plugin/"             "$(grep -rl 'DPT' "$REPO/plugin" | wc -l | tr -d ' ')" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
