#!/usr/bin/env bash
#
# local-tier-seed.test.sh — `install.sh` seeds `models` and `roleTiers` into the
# per-machine `instance.config.local.json`, never overwrites one a human already set,
# and no ordering of the two files ever resolves a role to nothing in silence.
#
# WHY. Those two keys decide what every dispatched agent COSTS, and that bill is one
# human's rather than a value one clone commits for everyone (SCHEMA.md → "Per-machine
# config overrides"). Making them per-machine is only half the job: the half that can
# go wrong is the migration. `resolve-model.sh` with NEITHER layer resolves to nothing,
# and a caller that ignores its exit code inherits the session model — for every role at
# once, with nothing anywhere saying so. So the design keeps the tracked pair as a
# FALLBACK while the installer seeds the local one, and this file asserts both halves:
#
#   1. THE SEED HAPPENS, on a fresh stamp and on a re-stamp of an instance that lacks
#      the keys, and what it writes is what `resolve-model.sh` then answers with.
#   2. THE FALLBACK STILL ANSWERS with no local file at all, which is the state of every
#      instance between a merge and the stamp that follows it — a merge is not a stamp.
#   3. A VALUE ALREADY THERE IS NEVER TOUCHED, including an explicit `null` (SCHEMA.md's
#      documented unset) and including a PARTIAL map, which `resolve-config.sh` merges
#      entry by entry. Topping a partial map up would be reconciling a human's edit.
#   4. ABSENCE IS NEVER SILENT. With neither layer, `resolve-model.sh` still prints
#      nothing on STDOUT (every caller captures it, and a word there becomes an alias)
#      and still exits 1 — but it now names the agent, the failed lookup and the
#      consequence on STDERR. The non-vacuity half matters just as much: a resolver that
#      complained on every call would be as useless as one that never complained, so the
#      success path is asserted to say nothing at all.
#   5. THE BANNER'S `FROM` COLUMN READS `local` once the seed has run, per leaf. That is
#      the human-visible point of the whole change: not that the value moved, but that
#      the human can see WHOSE decision is operating.
#
# AND `maxAgentsInFlight` IS ASSERTED ABSENT from the local file. It is in the same
# family and is genuinely per-machine, but seeding it was a separate decision the owner
# had not made; a test is how that stays a decision rather than drifting in.
#
# THE FIXTURE TEMPLATE IS A PLAIN DIRECTORY COPY, never this checkout: `install.sh`
# refuses to run from a git worktree by design, so a harness that passed its own checkout
# as the template would stamp NOTHING on a developer machine and stamp for real on CI —
# same commit, opposite results, neither about the code. Copied from `git ls-files` like
# team-setup.test.sh does, which is also what makes an uncommitted edit under review the
# thing that runs.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tierseed.XXXXXX")" || {
  echo "local-tier-seed.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# Every assertion below reads a JSON file or asks a resolver that needs python3. Without
# it there is nothing here to measure, and a harness that silently asserts less is worse
# than one that says it skipped.
if ! command -v python3 >/dev/null 2>&1; then
  echo "local-tier-seed.test: python3 absent — the seeder and every resolver need it." >&2
  echo "pass=0 fail=0"
  exit 0
fi

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
SCRIPTS="$TPL/plugin/scripts"

newinst() { local d="$TMP/i$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }
stamp()   { bash "$TPL/plugin/scripts/init-bundle.sh" "$1" >"$TMP/out" 2>&1; }
said()    { grep -q -- "$1" "$TMP/out" && echo yes || echo no; }
# One key or entry out of a JSON file, as text. `-` for a key that is not there and
# `null` for one that is there and null: the two are DIFFERENT answers here — present-and-
# null is a human's deliberate unset, and the seeder must leave it standing.
jget() { # <file> <key> [<entry>]
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable"); raise SystemExit(0)
k, e = sys.argv[2], sys.argv[3]
if k not in d:
    print("-"); raise SystemExit(0)
v = d[k]
if e:
    if not isinstance(v, dict):
        print("not-a-map"); raise SystemExit(0)
    if e not in v:
        print("-"); raise SystemExit(0)
    v = v[e]
print("null" if v is None else v if isinstance(v, str) else json.dumps(v, sort_keys=True))
PY
}
jcount() { # <file> <key> — how many entries the map has, or `-`
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable"); raise SystemExit(0)
v = d.get(sys.argv[2], None)
print(len(v) if isinstance(v, dict) else "-")
PY
}
MODEL()  { ( cd "$1" && bash "$SCRIPTS/resolve-model.sh" "$2" 2>/dev/null ); }
MERR()   { ( cd "$1" && bash "$SCRIPTS/resolve-model.sh" "$2" 2>&1 >/dev/null ); }
# Which layer won, for one leaf — the same question the banner's FROM column asks.
FROM()   { bash "$SCRIPTS/resolve-config.sh" --instance "$1" --source "$2" "${3:-}" 2>/dev/null | cut -f1; }
# Does EVERY role this instance would dispatch resolve to a model? The property the whole
# change exists for, asked of the real reader rather than of the bytes on disk.
all_resolve() { # <instance>
  local role bad=0
  while IFS= read -r role; do
    [ -n "$role" ] || continue
    [ -n "$(MODEL "$1" "$role")" ] || bad=$((bad+1))
  done <<EOF
$(bash "$SCRIPTS/resolve-config.sh" --instance "$1" --dump 2>/dev/null \
  | awk -F'\t' '$2=="roleTiers" && $3!="" { print $3 }')
EOF
  [ "$bad" -eq 0 ] && echo yes || echo no
}
nroles() { # how many roleTiers entries the merged view has
  bash "$SCRIPTS/resolve-config.sh" --instance "$1" --dump 2>/dev/null \
    | awk -F'\t' '$2=="roleTiers" && $3!="" { n++ } END { print n+0 }'
}

# =========================================================================== #
echo "-- 1. a fresh, non-interactive stamp seeds both keys into the LOCAL file"
I="$(newinst 1)"
stamp "$I"; RC=$?
LC="$I/instance.config.local.json"
ok "install.sh exits 0"                    "$RC" 0
ok "…and says what it wrote"               "$(said "wrote instance.config.local.json (models roleTiers")" yes
ok "the local file exists"                 "$(yn test -f "$LC")" yes
ok "…and parses as JSON"                   "$(yn python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$LC")" yes
ok "…carrying the four documented tiers"   "$(jcount "$LC" models)" 4
ok "…light→haiku"                          "$(jget "$LC" models light)" haiku
ok "…standard→sonnet"                      "$(jget "$LC" models standard)" sonnet
ok "…deep→opus"                            "$(jget "$LC" models deep)" opus
ok "…apex→fable"                           "$(jget "$LC" models apex)" fable
ok "…and the tracked roleTiers, entry for entry" \
   "$(jget "$LC" roleTiers)"               "$(jget "$I/instance.config.json" roleTiers)"
# The acceptance question for the whole task, asked of the real reader.
ok "EVERY role resolves to a model, no editing" "$(all_resolve "$I")" yes
ok "…and there is more than one of them"   "$([ "$(nroles "$I")" -ge 4 ] && echo yes || echo no)" yes
ok "software-engineer resolves"            "$(MODEL "$I" software-engineer)" opus
ok "cataloguer resolves"                   "$(MODEL "$I" cataloguer)" sonnet
# The human-visible half: the banner reports WHOSE decision is operating, per leaf.
ok "the banner's FROM says local for a role" "$(FROM "$I" roleTiers software-engineer)" local
ok "…and for a tier"                       "$(FROM "$I" models deep)" local
# …AND THE REAL BANNER SAYS SO, not merely the resolver the banner reads. The criterion
# is about the column a human looks at, so it is asserted against the hook's own output:
# `<role>  <tier>→<alias>  <from>`, whitespace-separated, last field.
BANNER="$TPL/plugin/hooks/session-banner.sh"
# `--full`: the SessionStart banner holds 12 lines and drops the two tables
# (ai-bridge-v3/task-025); the AGENT table is what this section is about.
BOUT="$(CLAUDE_PROJECT_DIR="$I" bash "$BANNER" --full 2>&1)"
brow() { head -n1 <<<"$(printf '%s\n' "$BOUT" | awk -v r="$1" '$1==r { print $NF }')"; }
# The gap before the arrow is variable: the tier is padded to the widest tier in the table
# (tests/session-banner.test.sh §2c), so the row is matched with `+` rather than one space.
ok "the banner prints a row for the role"   "$(printf '%s\n' "$BOUT" | awk '$1=="software-engineer"' | grep -cE 'deep +→ opus' | tr -d ' ')" 1
ok "…and its FROM column reads local"       "$(brow software-engineer)" local
ok "…for a second role on another tier too" "$(brow cataloguer)" local

# Not moved, and deliberately so — the owner did not ask for it.
ok "maxAgentsInFlight is NOT in the local file" "$(jget "$LC" maxAgentsInFlight)" -
ok "…and still resolves from the tracked one"  "$(FROM "$I" maxAgentsInFlight)" tracked
# A first non-TTY stamp asks no roster, so any identity in the file was DERIVED on this
# machine and never invented — the same value the derivation itself answers with, or the
# key absent when nothing here answers. The rest of that contract is
# tests/init-local-config.test.sh; this row only keeps the spend seed honest about it.
want="$( { command -v gh >/dev/null 2>&1 && gh api user --jq .login 2>/dev/null; } || true )"
[ -n "$want" ] || want="$(git config --get github.user 2>/dev/null || true)"
[ -n "$want" ] || want="-"
ok "ownerGithubUser is derived, not invented" "$(jget "$LC" ownerGithubUser)" "$want"
ok "…and the file is gitignored"           "$(yn grep -qxF 'instance.config.local.json' "$I/.gitignore")" yes

# =========================================================================== #
echo
echo "-- 2. a RE-stamp of an instance that lacks the keys seeds them"
# The live case: an instance stamped before this existed. Its local file holds identity
# and nothing else, exactly as the roster block used to write it.
I="$(newinst 2)"
stamp "$I" >/dev/null 2>&1
LC="$I/instance.config.local.json"
printf '{\n  "ownerGithubUser": "example-user-007"\n}\n' > "$LC"
ok "the pre-existing file has no models"   "$(jget "$LC" models)" -
stamp "$I"; RC=$?
ok "the re-stamp exits 0"                  "$RC" 0
ok "…and says it wrote them"               "$(said "wrote instance.config.local.json (models roleTiers")" yes
ok "models is now seeded"                  "$(jcount "$LC" models)" 4
ok "roleTiers is now seeded"               "$(jget "$LC" roleTiers)" "$(jget "$I/instance.config.json" roleTiers)"
ok "…and the identity that was there survived" "$(jget "$LC" ownerGithubUser)" example-user-007
ok "…and every role resolves"              "$(all_resolve "$I")" yes

# =========================================================================== #
echo
echo "-- 3. a value a human already set is NEVER overwritten, and never reconciled"
I="$(newinst 3)"
stamp "$I" >/dev/null 2>&1
LC="$I/instance.config.local.json"
# A PARTIAL roleTiers map plus no `models` at all. The partial map must survive intact —
# topping it up to the tracked seven would silently change six agents' provenance — while
# the key that IS missing is seeded.
printf '{\n  "roleTiers": { "software-engineer": "light" }\n}\n' > "$LC"
stamp "$I"; RC=$?
ok "the stamp exits 0"                     "$RC" 0
ok "the human's roleTiers is untouched"    "$(jget "$LC" roleTiers)" '{"software-engineer": "light"}'
ok "…exactly one entry, not topped up"     "$(jcount "$LC" roleTiers)" 1
ok "…and it says it left it alone"         "$(said 'already set — left alone')" no
ok "the MISSING key was still seeded"      "$(jcount "$LC" models)" 4
# THE PARTIAL OVERRIDE, end to end, on a real stamped instance: the entry the human named
# moves, and every entry they did not name keeps the tracked tier (SCHEMA.md:563).
ok "the named entry moves (light→haiku)"   "$(MODEL "$I" software-engineer)" haiku
ok "…and an unnamed one keeps its tier"    "$(MODEL "$I" project-manager)" opus
ok "…so every role still resolves"         "$(all_resolve "$I")" yes
ok "the named entry reads FROM local"      "$(FROM "$I" roleTiers software-engineer)" local
ok "…and the unnamed one FROM tracked"     "$(FROM "$I" roleTiers project-manager)" tracked

# Both keys already present: nothing is written, and it says so rather than being quiet.
BEFORE="$(cat "$LC")"
stamp "$I"; RC=$?
ok "a further stamp exits 0"               "$RC" 0
ok "…changes the file not one byte"        "$([ "$(cat "$LC")" = "$BEFORE" ] && echo yes || echo no)" yes
ok "…and reports that it left it alone"    "$(said 'already set — left alone')" yes

# THE FILE'S MODE TRAVELS WITH ITS CONTENT. The seeded key is written through a temp
# file, and a fresh temp takes the umask — so rewriting a local file somebody had
# tightened would quietly widen it. This file can hold a commit address; a permission
# that loosens itself on a re-stamp is exactly the kind of change nobody looks for.
I="$(newinst 8)"
stamp "$I" >/dev/null 2>&1
LC="$I/instance.config.local.json"
printf '{\n  "ownerGithubUser": "example-user-007"\n}\n' > "$LC"
chmod 600 "$LC"
stamp "$I" >/dev/null 2>&1
ok "a 0600 local file keeps its mode through the seed" \
   "$(ls -l "$LC" | cut -c1-10)" "-rw-------"
ok "…and was really seeded, so the check is not vacuous" "$(jcount "$LC" models)" 4

# An explicit null is SCHEMA.md's documented UNSET. Seeding over it would silently
# re-enable the thing the human switched off — the one edit that must not be "helped".
I="$(newinst 4)"
stamp "$I" >/dev/null 2>&1
LC="$I/instance.config.local.json"
printf '{\n  "models": null,\n  "roleTiers": null\n}\n' > "$LC"
stamp "$I" >/dev/null 2>&1
ok "an explicit null models survives"      "$(jget "$LC" models)" null
ok "…and an explicit null roleTiers too"   "$(jget "$LC" roleTiers)" null
ok "…and it says it left them alone"       "$(said 'already set — left alone')" yes
# A local null MASKS the tracked value (SCHEMA.md), so this instance now resolves to
# nothing — which is the state section 5 measures, and the installer must not hide it.
ok "…and the installer WARNS that roles now resolve to nothing" \
   "$(said 'resolve to NO model')" yes

# =========================================================================== #
echo
echo "-- 4. the TRACKED pair stays, and answers with no local file at all"
# The state of every instance between a merge and the stamp that follows it. If the
# tracked keys had been removed instead of kept, this is where every role would silently
# fall back to the session model.
ok "seed/instance.config.json still has models"    "$(jcount "$TPL/plugin/seed/instance.config.json" models)" 4
ok "…and still has roleTiers"                      "$([ "$(jcount "$TPL/plugin/seed/instance.config.json" roleTiers)" -ge 4 ] && echo yes || echo no)" yes
I="$(newinst 5)"
stamp "$I" >/dev/null 2>&1
rm -f "$I/instance.config.local.json"
ok "with the local file deleted, every role still resolves" "$(all_resolve "$I")" yes
ok "…from the tracked layer"                       "$(FROM "$I" roleTiers software-engineer)" tracked
ok "…and the alias is the tracked one"             "$(MODEL "$I" software-engineer)" opus

# THE SEEDER'S DEFAULTS AND THE SEED CONFIG MUST AGREE. The installer falls back to a
# hardcoded map only when the tracked file has no such key — an instance whose config
# predates it, or one somebody trimmed. Two copies of the same map drift, and the drift is
# invisible until a fresh install lands on the stale one, so it is asserted here.
DEFAULTS_MODELS="$(python3 - "$TPL/plugin/scripts/init-bundle.sh" <<'PY'
import json, re, sys
src = open(sys.argv[1]).read()
m = re.search(r'DEFAULTS = \{(.*?)\n\}\n', src, re.S)
block = m.group(1)
mm = re.search(r'"models": \{(.*?)\}', block, re.S)
print(json.dumps(dict(re.findall(r'"([^"]+)": "([^"]+)"', mm.group(1))), sort_keys=True))
PY
)"
ok "install.sh's default models == the seed's"  "$DEFAULTS_MODELS" "$(jget "$TPL/plugin/seed/instance.config.json" models)"
DEFAULTS_TIERS="$(python3 - "$TPL/plugin/scripts/init-bundle.sh" <<'PY'
import json, re, sys
src = open(sys.argv[1]).read()
m = re.search(r'DEFAULTS = \{(.*?)\n\}\n', src, re.S)
block = m.group(1)
mm = re.search(r'"roleTiers": \{(.*?)\n    \}', block, re.S)
print(json.dumps(dict(re.findall(r'"([^"]+)": "([^"]+)"', mm.group(1))), sort_keys=True))
PY
)"
ok "…and its default roleTiers too"             "$DEFAULTS_TIERS" "$(jget "$TPL/plugin/seed/instance.config.json" roleTiers)"

# And they are really used: a tracked config with neither key still produces a working
# instance, which is the "fresh install, no manual editing" promise for an older bundle.
I="$(newinst 6)"
stamp "$I" >/dev/null 2>&1
python3 - "$I/instance.config.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("models", None); d.pop("roleTiers", None)
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
rm -f "$I/instance.config.local.json"
stamp "$I" >/dev/null 2>&1
ok "a config with NEITHER key is seeded from the defaults" "$(jcount "$I/instance.config.local.json" models)" 4
ok "…and every role resolves from them"                    "$(all_resolve "$I")" yes
ok "…deep→opus, as documented"                             "$(MODEL "$I" software-engineer)" opus

# =========================================================================== #
echo
echo "-- 5. absence is never silent (the acceptance question)"
I="$(newinst 7)"; mkdir -p "$I"
printf '{\n  "org": "o"\n}\n' > "$I/instance.config.json"
OUT="$(MODEL "$I" software-engineer)"
ERR="$(MERR "$I" software-engineer)"
( cd "$I" && bash "$SCRIPTS/resolve-model.sh" software-engineer >/dev/null 2>&1 ); RC=$?
ok "stdout stays empty — a word there becomes an alias" "$([ -z "$OUT" ] && echo yes || echo no)" yes
ok "…and it still exits 1"                              "$RC" 1
ok "…but stderr is NOT empty"                           "$([ -n "$ERR" ] && echo yes || echo no)" yes
ok "…it names the agent"                                "$(grep -q "software-engineer" <<<"$ERR" && echo yes || echo no)" yes
ok "…names the consequence, not just the gap"           "$(grep -qi 'SESSION model' <<<"$ERR" && echo yes || echo no)" yes
ok "…and names where the fix goes"                      "$(grep -q 'instance.config.local.json' <<<"$ERR" && echo yes || echo no)" yes
# The second failure mode: a tier that exists but maps to no alias. Half a lookup is the
# half nobody checks, and it degrades exactly the same way.
printf '{\n  "roleTiers": { "software-engineer": "deep" }\n}\n' > "$I/instance.config.json"
ERR="$(MERR "$I" software-engineer)"
ok "a tier with no models entry is loud too"            "$([ -n "$ERR" ] && echo yes || echo no)" yes
ok "…and says which tier"                               "$(grep -q "'deep'" <<<"$ERR" && echo yes || echo no)" yes
# NON-VACUITY. A resolver that complained on every call would be as useless as one that
# never complained: the success path has to be silent, or nobody reads the failures.
printf '{\n  "roleTiers": { "software-engineer": "deep" },\n  "models": { "deep": "opus" }\n}\n' > "$I/instance.config.json"
ok "…while a resolvable agent prints NOTHING on stderr" \
   "$([ -z "$(MERR "$I" software-engineer)" ] && echo yes || echo no)" yes
ok "…and the alias on stdout"                           "$(MODEL "$I" software-engineer)" opus

# =========================================================================== #
echo
echo "-- 6. every prose caller carries the same instruction"
# A rule with no reader is not a rule, and these six are the readers: `resolve-model.sh`
# has no shell callers at all — every caller is an AGENT following a document. So the
# document is where "report that line rather than dispatching on a guess" has to live, and
# a caller that silently drops it is the failure this whole section is against.
for f in plugin/seed/CONVENTIONS.md docs/operations.md \
         plugin/skills/dispatch/SKILL.md plugin/skills/fanout/SKILL.md \
         plugin/skills/audit/SKILL.md plugin/tick-steps/step-3-dispatch.md; do
  ok "$(basename "$f") names resolve-model.sh"  "$(yn grep -q 'resolve-model\.sh' "$TPL/$f")" yes
  ok "…and says to report that line"            "$(yn grep -q 'report that line' "$TPL/$f")" yes
done
# SCHEMA.md is the one place the overridable set is listed, so the seeding contract and
# the deliberate exception belong there rather than in six documents.
SCHEMA="$TPL/plugin/seed/SCHEMA.md"
ok "SCHEMA.md says the installer seeds them"    "$(yn grep -q 'SEEDED into the local file' "$SCHEMA")" yes
ok "…and that the tracked pair is the fallback" "$(yn grep -q 'tracked pair is the' "$SCHEMA")" yes
ok "…and that a merge is not a stamp"           "$(yn grep -q 'a merge is not a stamp' "$SCHEMA")" yes
ok "…and that maxAgentsInFlight is NOT seeded"  "$(yn grep -q 'maxAgentsInFlight` is deliberately NOT seeded' "$SCHEMA")" yes

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
