#!/usr/bin/env bash
#
# resolve-model-all.test.sh — `resolve-model.sh --all` answers for every role in one call,
# gives the SAME answer the single call gives for each of them, names a role that does
# not resolve instead of hiding it, and the bundle stamp asks it exactly once.
#
# WHY. `/loopd:init` ends by asking "does every role resolve to a model?" of the real
# reader, once per role: eight bash+python starts, 0.49 s of a 1.14 s stamp, at ~220
# stamp call sites in this suite. `--all` is that question asked once. The property that
# makes it safe is that it is NOT a second implementation — both modes run one
# `resolve_one` over one `--dump` — and a property is proven by measuring, not by reading:
#
#   1. EVERY ROLE, EXACTLY ONCE, in a stable order, four columns per row.
#   2. THE SAME ANSWER AS THE SINGLE CALL, row for row — the single call is run for every
#      role and the two tables are diffed, across a tracked tier override AND a local
#      role override, so the merged path is what is being compared.
#   3. `from` IS WHICH FILE WON, per leaf, as `resolve-config.sh --source` reports it, and
#      `<tier-winner>/<model-winner>` when the two leaves disagree.
#   4. A ROLE THAT DOES NOT RESOLVE IS NAMED, NOT DROPPED: its row prints with an empty
#      model column, every other row still prints, stderr says which role, and the exit
#      code is the single call's 1. No roles at all is exit 1 with a line on stderr.
#   5. THE PARSER STILL REFUSES what it refused: an unknown flag, `--all <agent>`, a bare
#      `--instance`, no arguments — exit 2. And the single call still works both ways.
#   6. THE STAMP ASKS ONCE. A `bash -x` stamp invokes `resolve-model.sh` exactly one time,
#      and its warning still names exactly the role that resolves to nothing.
#
# THE FIXTURE TEMPLATE IS A PLAIN DIRECTORY COPY, never this checkout, for the reason
# local-tier-seed.test.sh gives. Only §6 needs it; §1–5 write two JSON files by hand.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rmall.XXXXXX")" || {
  echo "resolve-model-all.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "resolve-model-all.test: python3 absent — the resolver needs it." >&2
  echo "pass=0 fail=0"
  exit 0
fi

SCRIPTS="$REPO/plugin/scripts"
RM="$SCRIPTS/resolve-model.sh"
RC="$SCRIPTS/resolve-config.sh"
TAB="$(printf '\t')"

newinst() { local d="$TMP/i$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
ALL()   { bash "$RM" --all --instance "$1" 2>"$TMP/all.err"; echo "rc=$?" >"$TMP/all.rc"; }
ALLRC() { sed 's/^rc=//' "$TMP/all.rc"; }
MODEL() { bash "$RM" --instance "$1" "$2" 2>/dev/null; }
# Which layer won one leaf — the banner's FROM question, asked of the one implementation.
FROM()  { bash "$RC" --instance "$1" --source "$2" "$3" 2>/dev/null | cut -f1; }
roles() { bash "$RC" --instance "$1" --dump 2>/dev/null | awk -F'\t' '$2=="roleTiers" && $3!="" { print $3 }' | sort; }
# The single call, run for every role, in the --all row shape — the table --all must equal.
expected_table() { # <instance>
  local role tier model tf mf from
  while IFS= read -r role; do
    [ -n "$role" ] || continue
    tier="$(bash "$RC" --instance "$1" roleTiers "$role" 2>/dev/null || true)"
    model="$(MODEL "$1" "$role" || true)"
    tf="$(FROM "$1" roleTiers "$role")"; from="$tf"
    if [ -n "$model" ]; then
      mf="$(FROM "$1" models "$tier")"; [ "$mf" = "$tf" ] || from="$tf/$mf"
    fi
    printf '%s\t%s\t%s\t%s\n' "$role" "$from" "$tier" "$model"
  done <<EOF
$(roles "$1")
EOF
}

TRACKED='{
  "org": "o",
  "models":    { "light": "haiku", "standard": "sonnet", "deep": "opus", "apex": "fable" },
  "roleTiers": { "project-manager": "deep", "software-engineer": "deep", "qa-reviewer": "deep",
                 "cataloguer": "standard", "plan-architect": "apex", "explorer": "light" }
}'

# =========================================================================== #
echo "-- 1. every role, exactly once, four columns, stable — tracked only"
I="$(newinst 1)"; printf '%s\n' "$TRACKED" > "$I/instance.config.json"
ALL "$I" > "$TMP/all.1"
ok "exit 0 when every role resolves"             "$(ALLRC)" 0
ok "…and stderr is empty on the success path"    "$(wc -c <"$TMP/all.err" | tr -d ' ')" 0
ok "one row per roleTiers entry"                 "$(wc -l <"$TMP/all.1" | tr -d ' ')" "$(roles "$I" | wc -l | tr -d ' ')"
ok "…each role exactly once"                     "$(cut -f1 "$TMP/all.1" | sort | uniq -d | wc -l | tr -d ' ')" 0
ok "…and it is the roleTiers set, no more, no less" "$(cut -f1 "$TMP/all.1" | sort | tr '\n' ' ')" "$(roles "$I" | tr '\n' ' ')"
ok "every row has four tab-separated columns"    "$(awk -F'\t' 'NF!=4' "$TMP/all.1" | wc -l | tr -d ' ')" 0
ok "…none of them with an empty cell here"       "$(awk -F'\t' '$1==""||$2==""||$3==""||$4==""' "$TMP/all.1" | wc -l | tr -d ' ')" 0
ALL "$I" > "$TMP/all.1b"
ok "two runs are byte-identical (stable order)"  "$(yn cmp -s "$TMP/all.1" "$TMP/all.1b")" yes
ok "the table equals the single call, role for role" "$(diff "$TMP/all.1" <(expected_table "$I") | wc -l | tr -d ' ')" 0
ok "…spot check: software-engineer → opus"       "$(awk -F'\t' '$1=="software-engineer"{print $4}' "$TMP/all.1")" opus
ok "…every from reads tracked"                   "$(cut -f2 "$TMP/all.1" | sort -u | tr '\n' ' ')" "tracked "

# =========================================================================== #
echo
echo "-- 2. the same answer across BOTH overrides — a tracked tier, a local role, a local tier"
I="$(newinst 2)"
# The tracked file moves deep→sonnet; the local file moves ONE role to light and retiers
# ONE alias (standard→haiku). Four provenance shapes result and all four are asserted.
printf '%s\n' "$TRACKED" | sed 's/"deep": "opus"/"deep": "sonnet"/' > "$I/instance.config.json"
printf '{\n  "roleTiers": { "cataloguer": "light" },\n  "models": { "standard": "haiku" }\n}\n' > "$I/instance.config.local.json"
ALL "$I" > "$TMP/all.2"
ok "exit 0"                                      "$(ALLRC)" 0
ok "the table equals the single call, role for role" "$(diff "$TMP/all.2" <(expected_table "$I") | wc -l | tr -d ' ')" 0
ok "the tracked tier override is in the row (deep→sonnet)" "$(awk -F'\t' '$1=="software-engineer"{print $3"→"$4}' "$TMP/all.2")" "deep→sonnet"
ok "…the single call says the same"              "$(MODEL "$I" software-engineer)" sonnet
ok "the local role override is in the row (cataloguer light→haiku)" "$(awk -F'\t' '$1=="cataloguer"{print $3"→"$4}' "$TMP/all.2")" "light→haiku"
ok "…the single call says the same"              "$(MODEL "$I" cataloguer)" haiku
ok "from: role local, alias tracked → local/tracked" "$(awk -F'\t' '$1=="cataloguer"{print $2}' "$TMP/all.2")" local/tracked
ok "from: both leaves tracked → tracked"         "$(awk -F'\t' '$1=="software-engineer"{print $2}' "$TMP/all.2")" tracked
ok "from: an unnamed role keeps tracked, standard alias local → tracked/local" \
   "$(awk -F'\t' '$1=="plan-architect"{print $2}' "$TMP/all.2")" tracked
# No role sits on `standard` in this fixture, so put one there: the fourth shape.
printf '{\n  "roleTiers": { "cataloguer": "light", "qa-reviewer": "standard" },\n  "models": { "standard": "haiku" }\n}\n' > "$I/instance.config.local.json"
ALL "$I" > "$TMP/all.2b"
ok "from: role local, alias local → local"       "$(awk -F'\t' '$1=="qa-reviewer"{print $2}' "$TMP/all.2b")" local
ok "…and that row's alias is the local one"      "$(awk -F'\t' '$1=="qa-reviewer"{print $4}' "$TMP/all.2b")" haiku
ok "…matching resolve-config --source for both leaves" "$(FROM "$I" roleTiers qa-reviewer)/$(FROM "$I" models standard)" local/local
ok "…and the whole table still equals the single calls" "$(diff "$TMP/all.2b" <(expected_table "$I") | wc -l | tr -d ' ')" 0

# =========================================================================== #
echo
echo "-- 3. a role that does not resolve is NAMED, and the rest still print"
I="$(newinst 3)"; printf '%s\n' "$TRACKED" > "$I/instance.config.json"
# apex unset locally (SCHEMA.md's documented unset), plus a role on a tier nothing maps.
printf '{\n  "models": { "apex": null },\n  "roleTiers": { "ghost": "nowhere" }\n}\n' > "$I/instance.config.local.json"
ALL "$I" > "$TMP/all.3"
ok "exit 1 — the single call's failure code"     "$(ALLRC)" 1
ok "every role is still listed"                  "$(cut -f1 "$TMP/all.3" | sort | tr '\n' ' ')" "$(roles "$I" | tr '\n' ' ')"
ok "the unset tier's role has an EMPTY model"    "$(awk -F'\t' '$1=="plan-architect"{print "[" $4 "]"}' "$TMP/all.3")" "[]"
ok "…and still names its tier and its from"      "$(awk -F'\t' '$1=="plan-architect"{print $2 "," $3}' "$TMP/all.3")" tracked,apex
ok "the unmapped tier's role has an EMPTY model" "$(awk -F'\t' '$1=="ghost"{print "[" $4 "]"}' "$TMP/all.3")" "[]"
ok "the resolved rows are intact"                "$(awk -F'\t' '$1=="software-engineer"{print $4}' "$TMP/all.3")" opus
ok "…and still equal the single calls"           "$(diff "$TMP/all.3" <(expected_table "$I") | wc -l | tr -d ' ')" 0
ok "a row with an empty model is still four columns" "$(awk -F'\t' 'NF!=4' "$TMP/all.3" | wc -l | tr -d ' ')" 0
ok "stderr names the first failing role"         "$(yn grep -q "no model for 'ghost'" "$TMP/all.err")" yes
ok "…and the second"                             "$(yn grep -q "no model for 'plan-architect'" "$TMP/all.err")" yes
ok "…names the consequence"                      "$(yn grep -q 'SESSION model' "$TMP/all.err")" yes
ok "…and does NOT name a role that resolved"     "$(yn grep -q "no model for 'software-engineer'" "$TMP/all.err")" no
ok "…its first line is the single call's first line, verbatim" \
   "$(grep "no model for 'ghost'" "$TMP/all.err")" "$(head -n1 <<<"$(bash "$RM" --instance "$I" ghost 2>&1 >/dev/null)")"
# `IFS=tab read` — the shape the stamp parses rows with — reads the empty model correctly
# BECAUSE it is the trailing field; this pins the column order the header explains.
read_model() { local r f t m; while IFS="$TAB" read -r r f t m; do [ "$r" = "$1" ] && printf '[%s|%s|%s]' "$f" "$t" "$m"; done <"$TMP/all.3"; }
ok "a tab-IFS read sees from, tier, and the empty model" "$(read_model plan-architect)" "[tracked|apex|]"
ok "…and the full row of a resolved role"        "$(read_model explorer)" "[tracked|light|haiku]"

echo
echo "-- 3b. no roles at all is loud, not an empty success"
I="$(newinst 4)"; printf '{\n  "org": "o"\n}\n' > "$I/instance.config.json"
ALL "$I" > "$TMP/all.4"
ok "exit 1"                                      "$(ALLRC)" 1
ok "stdout is empty"                             "$(wc -c <"$TMP/all.4" | tr -d ' ')" 0
ok "stderr says there are no roleTiers"          "$(yn grep -q 'NO roleTiers' "$TMP/all.err")" yes
printf '%s\n' "$TRACKED" > "$I/instance.config.json"
printf '{\n  "roleTiers": null\n}\n' > "$I/instance.config.local.json"
ALL "$I" > "$TMP/all.4b"
ok "a local null roleTiers masks the tracked map — exit 1" "$(ALLRC)" 1
ok "…stdout empty"                               "$(wc -c <"$TMP/all.4b" | tr -d ' ')" 0

# =========================================================================== #
echo
echo "-- 4. the parser refuses what it refused"
I="$(newinst 5)"; printf '%s\n' "$TRACKED" > "$I/instance.config.json"
rc_of() { bash "$RM" "$@" >/dev/null 2>&1; echo $?; }
ok "an unknown flag is exit 2"                   "$(rc_of --bogus --instance "$I")" 2
ok "--all with an agent name is exit 2"          "$(rc_of --all explorer --instance "$I")" 2
ok "…and names the stray argument"               "$(yn grep -q "got 'explorer'" <<<"$(bash "$RM" --all explorer --instance "$I" 2>&1)")" yes
ok "a bare trailing --instance is exit 2 (no spin)" "$(rc_of --all --instance)" 2
ok "no arguments at all is exit 2"               "$(rc_of)" 2
ok "--help exits 0"                              "$(rc_of --help)" 0
ok "…and the usage names --all"                  "$(yn grep -q -- '--all' <<<"$(bash "$RM" --help)")" yes

echo
echo "-- 5. the single call is unchanged, both directions"
ok "resolves (explorer → haiku)"                 "$(MODEL "$I" explorer)" haiku
ok "…with nothing on stderr"                     "$(bash "$RM" --instance "$I" explorer 2>&1 >/dev/null | wc -c | tr -d ' ')" 0
ok "…and exit 0"                                 "$(bash "$RM" --instance "$I" explorer >/dev/null 2>&1; echo $?)" 0
ok "an unknown agent prints nothing"             "[$(MODEL "$I" nobody)]" "[]"
ok "…exits 1"                                    "$(bash "$RM" --instance "$I" nobody >/dev/null 2>&1; echo $?)" 1
ok "…and says so on stderr, naming the agent"    "$(yn grep -q "no model for 'nobody'" <<<"$(bash "$RM" --instance "$I" nobody 2>&1 >/dev/null)")" yes
ok "…where the fix goes"                         "$(yn grep -q 'instance.config.local.json' <<<"$(bash "$RM" --instance "$I" nobody 2>&1 >/dev/null)")" yes
ok "it still delegates precedence to resolve-config.sh" "$(yn grep -q 'resolve-config\.sh' "$RM")" yes
ok "…and reads no JSON of its own"               "$(yn grep -q 'json\.load' "$RM")" no

# =========================================================================== #
echo
echo "-- 6. the stamp asks ONCE, and its warning still names the role"
make_tpl() { # <dir> — a throwaway plain-directory copy of the template
  local d="$1" f
  mkdir -p "$d"
  ( cd "$REPO" && git ls-files . ) | while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$d/$(dirname "$f")"; cp "$REPO/$f" "$d/$f" 2>/dev/null || true
  done
  chmod +x "$d/plugin/scripts/init-bundle.sh" "$d"/plugin/scripts/*.sh 2>/dev/null || true
}
TPL="$TMP/tpl"; make_tpl "$TPL"
I="$(newinst 6)"
# A local file with `models` already present (so the seed leaves it) and apex unset: the
# stamp seeds roleTiers, and exactly one of them then resolves to nothing.
printf '{\n  "models": { "light": "haiku", "standard": "sonnet", "deep": "opus", "apex": null }\n}\n' > "$I/instance.config.local.json"
bash -x "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/stamp.out" 2>"$TMP/stamp.trace"; RCS=$?
ok "the stamp exits 0"                           "$RCS" 0
ok "resolve-model.sh is invoked exactly once"    "$(grep -c 'resolve-model\.sh' "$TMP/stamp.trace" | tr -d ' ')" 1
ok "…with --all"                                 "$(grep -c 'resolve-model\.sh --instance .* --all' "$TMP/stamp.trace" | tr -d ' ')" 1
# The trace carries each `echo` twice — as the `+ echo …` trace line and as its output —
# so the warning is read from the non-trace lines only.
grep -v '^+' "$TMP/stamp.trace" > "$TMP/stamp.err"
ok "the warning names the role that resolves to nothing" "$(yn grep -q 'session happens to be: plan-architect$' "$TMP/stamp.err")" yes
ok "…and only that one"                          "$(grep -c 'session happens to be:' "$TMP/stamp.err" | tr -d ' ')" 1
# The other direction: a stamp where every role resolves warns about none of them.
I="$(newinst 7)"
bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/stamp2.out" 2>&1; RCS=$?
ok "a clean stamp exits 0"                       "$RCS" 0
ok "…and prints no resolve-to-nothing warning"   "$(yn grep -q 'resolve to NO model' "$TMP/stamp2.out")" no
ok "…while --all on it exits 0 with every role"  "$(bash "$RM" --all --instance "$I" >/dev/null 2>&1; echo $?)" 0

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
