#!/usr/bin/env bash
#
# resolve-effort.test.sh — `resolve-effort.sh` answers `roleEffort[<agent>]` local-first,
# prints nothing (exit 0) for an absent key or map, refuses an unknown level (exit 1, one
# line naming role and value), and `--all` gives the single call's answer row for row.
# Also: the seed map has one entry per `roleTiers` key, every plugin agent's frontmatter
# `effort:` equals its seed entry, and a stamp seeds the map into the local file.
# Mirrors resolve-model-all.test.sh. ok() compares actual to expected, in that order.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/reff.XXXXXX")" || { echo "resolve-effort.test: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "resolve-effort.test: python3 absent — the resolver needs it." >&2
  echo "pass=0 fail=0"; exit 0
fi

RE="$REPO/plugin/scripts/resolve-effort.sh"
SEED="$REPO/plugin/seed/instance.config.json"
newinst() { local d="$TMP/i$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
EFF() { bash "$RE" --instance "$1" "$2" 2>/dev/null; }
RC()  { bash "$RE" --instance "$1" "$2" >/dev/null 2>&1; echo $?; }
ALL() { bash "$RE" --all --instance "$1" 2>"$TMP/all.err"; echo "$?" > "$TMP/all.rc"; }
jkeys() { python3 -c 'import json,sys; print(" ".join(sorted((json.load(open(sys.argv[1])).get(sys.argv[2]) or {}).keys())))' "$1" "$2"; }
jval()  { python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get(sys.argv[2]) or {}).get(sys.argv[3], "-"))' "$1" "$2" "$3"; }

TRACKED='{
  "org": "o",
  "roleTiers":  { "project-manager": "deep", "software-engineer": "deep", "explorer": "light" },
  "roleEffort": { "project-manager": "medium", "software-engineer": "high", "explorer": "low" }
}'

echo "-- 1. tracked only: the single call"
I="$(newinst 1)"; printf '%s\n' "$TRACKED" > "$I/instance.config.json"
ok "project-manager → medium"                    "$(EFF "$I" project-manager)" medium
ok "software-engineer → high"                    "$(EFF "$I" software-engineer)" high
ok "…exit 0 with nothing on stderr"              "$(RC "$I" software-engineer):$(bash "$RE" --instance "$I" software-engineer 2>&1 >/dev/null | wc -c | tr -d ' ')" "0:0"

echo "-- 2. local beats tracked, per entry"
printf '{\n  "roleEffort": { "software-engineer": "xhigh" }\n}\n' > "$I/instance.config.local.json"
ok "the local entry wins"                        "$(EFF "$I" software-engineer)" xhigh
ok "…an entry it does not name stays tracked"    "$(EFF "$I" project-manager)" medium
ALL "$I" > "$TMP/all.2"
ok "--all: the local row reads from local"       "$(awk -F'\t' '$1=="software-engineer"{print $2 "," $3}' "$TMP/all.2")" local,xhigh
ok "--all: the tracked row reads from tracked"   "$(awk -F'\t' '$1=="explorer"{print $2 "," $3}' "$TMP/all.2")" tracked,low
ok "--all: three columns, every row"             "$(awk -F'\t' 'NF!=3' "$TMP/all.2" | wc -l | tr -d ' ')" 0
ok "--all equals the single call, row for row"   "$(awk -F'\t' '{print $1, $3}' "$TMP/all.2" | while read -r r l; do [ "$(EFF "$I" "$r")" = "$l" ] || echo "$r"; done | wc -l | tr -d ' ')" 0
ok "--all exits 0"                               "$(cat "$TMP/all.rc")" 0

echo "-- 3. absence is an answer: nothing printed, exit 0"
ok "a role with no entry prints nothing"         "[$(EFF "$I" plan-architect)]" "[]"
ok "…and exits 0"                                "$(RC "$I" plan-architect)" 0
I="$(newinst 3)"; printf '{\n  "org": "o",\n  "roleTiers": { "explorer": "light" }\n}\n' > "$I/instance.config.json"
ok "no roleEffort map at all prints nothing"     "[$(EFF "$I" explorer)]" "[]"
ok "…exit 0"                                     "$(RC "$I" explorer)" 0
ALL "$I" > "$TMP/all.3"
ok "--all on no map: empty, exit 0"              "$(wc -c <"$TMP/all.3" | tr -d ' '):$(cat "$TMP/all.rc")" "0:0"
printf '%s\n' "$TRACKED" > "$I/instance.config.json"
printf '{\n  "roleEffort": null\n}\n' > "$I/instance.config.local.json"
ok "a local null map unsets the tracked one"     "[$(EFF "$I" software-engineer)]:$(RC "$I" software-engineer)" "[]:0"

echo "-- 4. an unknown level is refused, loudly"
I="$(newinst 4)"; printf '%s\n' "$TRACKED" | sed 's/"high"/"hgih"/' > "$I/instance.config.json"
ok "prints nothing"                              "[$(EFF "$I" software-engineer)]" "[]"
ok "…exits 1"                                    "$(RC "$I" software-engineer)" 1
ERR="$(bash "$RE" --instance "$I" software-engineer 2>&1 >/dev/null)"
ok "…one stderr line"                            "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" 1
ok "…naming the role and the value"              "$(yn grep -q "'hgih' for 'software-engineer'" <<<"$ERR")" yes
ok "a known role beside it still resolves"       "$(EFF "$I" project-manager)" medium
# Equality, never substring: two levels, a level's prefix, or one inside a longer word.
for bad in "low medium" "medium high" "med" "hig" "xhigh max" "lowest"; do
  printf '{\n  "roleEffort": { "auditor": "%s" }\n}\n' "$bad" > "$I/instance.config.local.json"
  ok "'$bad' is refused: nothing printed, exit 1" "[$(EFF "$I" auditor)]:$(RC "$I" auditor)" "[]:1"
done
rm -f "$I/instance.config.local.json"
ALL "$I" > "$TMP/all.4"
ok "--all exits 1"                               "$(cat "$TMP/all.rc")" 1
ok "…the bad row prints with an EMPTY level"     "$(awk -F'\t' '$1=="software-engineer"{print "[" $3 "]"}' "$TMP/all.4")" "[]"
ok "…every other row is intact"                  "$(awk -F'\t' '$1=="explorer"{print $3}' "$TMP/all.4")" low
ok "…and stderr names it"                        "$(yn grep -q "'hgih' for 'software-engineer'" "$TMP/all.err")" yes

echo "-- 5. the parser refuses what resolve-model.sh refuses"
rc_of() { bash "$RE" "$@" >/dev/null 2>&1; echo $?; }
ok "an unknown flag is exit 2"                   "$(rc_of --bogus)" 2
ok "--all with an agent name is exit 2"          "$(rc_of --all explorer)" 2
ok "a bare trailing --instance is exit 2"        "$(rc_of --all --instance)" 2
ok "no arguments is exit 2"                      "$(rc_of)" 2
ok "it delegates precedence to resolve-config.sh" "$(yn grep -q 'resolve-config\.sh' "$RE")" yes
ok "…and reads no JSON of its own"               "$(yn grep -q 'json\.load' "$RE")" no

echo "-- 6. the seed map, the stamp's defaults and the agents' frontmatter agree"
ok "seed roleEffort has one entry per roleTiers key" "$(jkeys "$SEED" roleEffort)" "$(jkeys "$SEED" roleTiers)"
I="$(newinst 6)"; cp "$SEED" "$I/instance.config.json"
ok "the seed's map resolves with no error"       "$(bash "$RE" --all --instance "$I" >/dev/null 2>&1; echo $?)" 0
DEF="$(python3 - "$REPO/plugin/scripts/init-bundle.sh" <<'PY'
import json, re, sys
src = open(sys.argv[1]).read()
block = re.search(r'DEFAULTS = \{(.*?)\n\}\n', src, re.S).group(1)
mm = re.search(r'"roleEffort": \{(.*?)\n    \}', block, re.S)
print(json.dumps(dict(re.findall(r'"([^"]+)": "([^"]+)"', mm.group(1))), sort_keys=True))
PY
)"
ok "init-bundle.sh's default roleEffort == the seed's" "$DEF" "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["roleEffort"], sort_keys=True))' "$SEED")"
fm() { awk -v k="$2" 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f && index($0, k ": ")==1 {print substr($0, length(k)+3); exit}' "$1"; }
for a in "$REPO"/plugin/agents/*.md; do
  n="$(basename "$a" .md)"; want="$(jval "$SEED" roleEffort "$n")"
  [ "$want" = - ] && want=high   # failure-analyst: no roleTiers entry, diagnosis is adjudication
  ok "$n frontmatter effort == its seed entry"   "$(fm "$a" effort)" "$want"
done

echo "-- 7. a stamp seeds roleEffort into the local file, and warns on an unknown level"
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$REPO" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue; mkdir -p "$TPL/$(dirname "$f")"; cp "$REPO/$f" "$TPL/$f" 2>/dev/null || true
done
cp "$RE" "$TPL/plugin/scripts/resolve-effort.sh" 2>/dev/null
chmod +x "$TPL"/plugin/scripts/*.sh 2>/dev/null || true
I="$(newinst 7)"
bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/stamp.out" 2>&1; RCS=$?
ok "the stamp exits 0"                           "$RCS" 0
ok "the local file carries the seed's roleEffort" "$(jkeys "$I/instance.config.local.json" roleEffort)" "$(jkeys "$SEED" roleEffort)"
ok "resolve-effort.sh project-manager → medium"  "$(EFF "$I" project-manager)" medium
ok "resolve-effort.sh software-engineer → high"  "$(EFF "$I" software-engineer)" high
ok "a clean stamp warns about no level"          "$(grep -c 'unknown effort' "$TMP/stamp.out" | tr -d ' ')" 0
printf '{\n  "roleEffort": { "auditor": "turbo" }\n}\n' > "$I/instance.config.local.json"
bash "$TPL/plugin/scripts/init-bundle.sh" "$I" >"$TMP/stamp2.out" 2>&1
ok "a re-stamp leaves the human's map alone"     "$(jval "$I/instance.config.local.json" roleEffort auditor)" turbo
ok "…and warns, naming role and value"           "$(grep -c "warn  unknown effort 'turbo' for 'auditor'" "$TMP/stamp2.out" | tr -d ' ')" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
