#!/usr/bin/env bash
#
# companion-alternative-llm.test.sh — the `loopd-llm` companion: v1's three secrecy
# properties carried over intact, the per-machine opt-in gate, the banner's backend
# warning, and the one boundary that is not a preference — NO KEY LITERAL IS EVER TRACKED.
#
# WHY A FIXTURE BUNDLE AND A STUB `claude`. The launcher execs a real binary and reads a
# bundle's config; every case below points at trees this file wrote, and the child is a
# `claude` STUB that dumps its own environment — the only way to assert what the exec'd
# process really receives rather than inferring it from the banner.
#
# BOTH DIRECTIONS, EVERY TIME. "It doesn't print the key" passes trivially for a script
# that prints nothing, so every secrecy assertion is paired with one proving the useful
# output still happens and the key still reaches where it is supposed to.
#
# ok() compares actual to expected, in that argument order. Fixtures live under mktemp; no
# real .env and no real key is ever read, and the fixture key is deliberately NOT
# key-shaped so section 5's detector stays honest about this very file.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
LAUNCH="$REPO/plugin-llm/bin/ai-bridge-deepseek"
CAP="$REPO/plugin-llm/companion/llm.md"
BANNER="$REPO/plugin/hooks/session-banner.sh"
MJ="$REPO/.claude-plugin/marketplace.json"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/companion-llm.XXXXXX")" || {
  echo "companion-alternative-llm.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd)" || { echo "companion-alternative-llm.test: could not resolve $TMP" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
cnt() { printf '%s' "$1" | grep -c -- "$2" 2>/dev/null || true; }

# ---------------------------------------------------------------- the fixture machine
# A bundle that HAS opted in, so the ported v1 cases exercise the launcher and not the
# gate; section 2 moves that one field and nothing else.
BUNDLE="$TMP/bundle"; mkdir -p "$BUNDLE"
printf 'x\n' > "$BUNDLE/SCHEMA.md"
printf '{ "org": "x" }\n' > "$BUNDLE/instance.config.json"
optin() { printf '%s\n' "$1" > "$BUNDLE/instance.config.local.json"; }
optin '{ "allowSubstituteBackend": true }'

# A key whose first five and last three characters are both distinctive — so a leak of
# EITHER end of v1's old "redacted preview" is caught, not just the whole value.
KEY="FIXTUREKEY-QQQQQ-not-a-real-credential-ZZZ"
HEAD5="FIXTU"          # what "${KEY:0:5}" used to print
TAIL3="ZZZ"            # what "${KEY: -3}" used to print
SHORT="tiny"           # <= 8 chars: the length-sanity branch

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
env > "$CHILD_ENV"
STUB
chmod +x "$BIN/claude"
CHILD="$TMP/childenv"

echo
echo "== 1. v1's --print-env: no key, still useful =="
OUT="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"; RC=$?
ok "--print-env exits 0"                            "$RC" 0
ok "…prints no whole key"                           "$(cnt "$OUT" "$KEY")"   0
ok "…prints no leading key fragment"                "$(cnt "$OUT" "$HEAD5")" 0
ok "…prints no trailing key fragment"               "$(cnt "$OUT" "$TAIL3")" 0
# Non-vacuity: the flag exists to show which endpoint and which model IDs are in play —
# a wrong model ID silently costs money, so this must still print.
ok "…still reports the endpoint"                    "$(cnt "$OUT" '^ANTHROPIC_BASE_URL=https://')" 1
ok "…still reports the opus-tier model"             "$(cnt "$OUT" '^ANTHROPIC_DEFAULT_OPUS_MODEL=.')" 1
ok "…still reports the subagent model"              "$(cnt "$OUT" '^CLAUDE_CODE_SUBAGENT_MODEL=.')" 1
ok "…and names the token as set, not its value"     "$(cnt "$OUT" '^ANTHROPIC_AUTH_TOKEN=(set')" 1
# A static guard: the slicing expression must not come back, in any of its three spellings.
# `-E` because `\|` alternation is a GNU BRE extension and this harness ships to machines
# we never see — a grep without it would match nothing and pass while the slicing was there.
ok "no key-slicing expression left in the script"   "$(grep -Ec 'KEY_HINT|KEY:0|KEY: -' "$LAUNCH")" 0

# THE ONE DELIBERATE CHANGE FROM v1, asserted rather than left to the header: subagents
# default to the PRO tier, because a loopd instance dispatches role agents as subagents.
ok "…subagents default to the PRO tier, not flash"  "$(cnt "$OUT" '^CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-pro$')" 1
OUT2="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$KEY" DEEPSEEK_SUBAGENT_MODEL="deepseek-v4-flash" \
         bash "$LAUNCH" --print-env 2>&1 )"
ok "…and the knob still lowers it"                  "$(cnt "$OUT2" '^CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash$')" 1

echo
echo "== 2. the launch banner: printed, key-free =="
rm -f "$CHILD"
ERR="$( cd "$BUNDLE" && PATH="$BIN:$PATH" CHILD_ENV="$CHILD" DEEPSEEK_API_KEY="$KEY" \
        ANTHROPIC_API_KEY="anthropic-must-not-travel" bash "$LAUNCH" 2>&1 >/dev/null )"; RC=$?
ok "a session launch exits 0"                       "$RC" 0
ok "banner prints no whole key"                     "$(cnt "$ERR" "$KEY")"   0
ok "banner prints no leading key fragment"          "$(cnt "$ERR" "$HEAD5")" 0
ok "banner prints no trailing key fragment"         "$(cnt "$ERR" "$TAIL3")" 0
ok "banner never prints the Anthropic credential"   "$(cnt "$ERR" 'anthropic-must-not-travel')" 0
# Non-vacuity: the banner is unsuppressible by design — forgetting which backend you are
# on is the failure it guards. A key-free banner must not become a missing banner.
ok "…the banner still fires"                        "$(cnt "$ERR" 'DeepSeek session')" 1
ok "…and still says this is NOT Anthropic"          "$(cnt "$ERR" 'NOT Anthropic')" 1
ok "…and still names the key's source"              "$(cnt "$ERR" 'key     :')" 1

echo
echo "== 3. the child environment: the two load-bearing properties =="
# Asserted at the real boundary. The first case is the second's non-vacuity partner: the
# DeepSeek token DOES travel, and the Anthropic one does NOT.
ok "child received the DeepSeek token"              "$(grep -c "^ANTHROPIC_AUTH_TOKEN=$KEY\$" "$CHILD")" 1
ok "child has NO ANTHROPIC_API_KEY at all"          "$(grep -c '^ANTHROPIC_API_KEY=' "$CHILD")" 0
ok "child points at the DeepSeek endpoint"          "$(grep -c '^ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic$' "$CHILD")" 1

echo
echo "== 4. .env is parsed, never sourced; and the length check replaces the preview =="
PROJ="$TMP/proj"; mkdir -p "$PROJ"
cat > "$PROJ/.env" <<EOF
EVIL=\$(touch "$PROJ/pwned")
DEEPSEEK_API_KEY=$KEY
EOF
rm -f "$PROJ/pwned"
OUT="$( cd "$PROJ" && bash "$LAUNCH" --bundle "$BUNDLE" --print-env 2>&1 )"; RC=$?
ok ".env supplies the key (exit 0)"                 "$RC" 0
ok "…the file was PARSED, not sourced"              "$(yn test ! -e "$PROJ/pwned")" yes
ok "…and no fragment of that key is printed"        "$(cnt "$OUT" "$HEAD5")" 0
ok "…only the .env PATH is named, not the value"    "$(cnt "$OUT" '\.env')" 1

OUT="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$SHORT" bash "$LAUNCH" --print-env 2>&1 )"
ok "a too-short key is still called out"            "$(cnt "$OUT" 'check it')" 1
ok "…and even then the key is not echoed"           "$(cnt "$OUT" "$SHORT")" 0
OUT="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"
ok "a normal-length key raises no warning"          "$(cnt "$OUT" 'check it')" 0

# The https guard: it is the reason the key never rides plaintext, and a refactor of the
# surrounding block is exactly what would drop it.
OUT="$( cd "$BUNDLE" && DEEPSEEK_BASE_URL="http://api.deepseek.com/anthropic" \
        DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"; RC=$?
ok "an http:// endpoint is refused"                 "$([ "$RC" -ne 0 ] && echo yes || echo no)" yes
ok "…and the refusal prints no key fragment"        "$(cnt "$OUT" "$HEAD5")" 0

echo
echo "== 5. the opt-in is PER MACHINE, and it is the whole gate =="
# One fixture, one field moved. The tracked-config case is what makes this a per-machine
# gate rather than a config key: a resolver reading both layers would pass it.
WARN1='NOT Anthropic. Every prompt, file read, and tool result in'
WARN2='this session is sent to DeepSeek. Confirm this repo.s code'
WARN3='is cleared to go there.'

rm -f "$BUNDLE/instance.config.local.json"
OUT="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"; RC=$?
ok "no opt-in at all -> exit 3"                     "$RC" 3
ok "…and it names the file and the key"             "$(cnt "$OUT" 'allowSubstituteBackend.*: true')" 1
ok "…and prints the governance warning, line 1"     "$(cnt "$OUT" "$WARN1")" 1
ok "…line 2"                                        "$(cnt "$OUT" "$WARN2")" 1
ok "…line 3"                                        "$(cnt "$OUT" "$WARN3")" 1
ok "…and it exports nothing"                        "$(cnt "$OUT" '^ANTHROPIC_BASE_URL=')" 0

optin '{ "allowSubstituteBackend": false }'
OUT="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"; RC=$?
ok "an explicit false -> exit 3"                    "$RC" 3

# THE TRACKED FILE MAY NOT OPT IN. Same value, other layer.
rm -f "$BUNDLE/instance.config.local.json"
printf '{ "org": "x", "allowSubstituteBackend": true }\n' > "$BUNDLE/instance.config.json"
OUT="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"; RC=$?
ok "the TRACKED config cannot opt in -> exit 3"     "$RC" 3
printf '{ "org": "x" }\n' > "$BUNDLE/instance.config.json"

# Non-vacuity in the direction that matters: the SAME fixture with the local flag clears.
optin '{ "allowSubstituteBackend": true }'
OUT="$( cd "$BUNDLE" && DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"; RC=$?
ok "…the same fixture WITH the local flag -> exit 0" "$RC" 0

# Outside a bundle there is nothing to opt in, so there is no session.
OUT="$( cd "$TMP" && DEEPSEEK_API_KEY="$KEY" bash "$LAUNCH" --print-env 2>&1 )"; RC=$?
ok "outside a bundle -> exit 3"                     "$RC" 3

# The warning is ONE string in ONE place, so the refusal and the banner cannot drift.
ok "the warning has exactly one definition"         "$(grep -c "$WARN3" "$LAUNCH")" 1
ok "…and the launch banner prints it too"           "$(cnt "$ERR" "$WARN1")" 1

echo
echo "== 6. keys come from the environment or a gitignored .env — never a tracked file =="
# (a) BY DETECTION, over every tracked file in this repo. `sk-` bounded on the left so a
#     task slug (`task-044-the-dwd-…`) is not a credential, and the tail charset excludes
#     `-` so only a real key shape reaches 24 characters.
KEYRE='(^|[^A-Za-z0-9_-])sk-(ant-api[0-9]{2}-|[A-Za-z0-9]{24,})'
scan() { # <repo dir> -> number of tracked files carrying a key literal
  ( cd "$1" && git ls-files -z 2>/dev/null | xargs -0 grep -IlE "$KEYRE" 2>/dev/null | grep -c . ) || true
}
ok "no tracked file in this repo carries a key"     "$(scan "$REPO")" 0

# NON-VACUITY: the identical scan over a fixture repo that DOES carry one must find it.
# Without this the assertion above passes on a scanner that matches nothing.
PLANT="$TMP/planted"; mkdir -p "$PLANT"
git -C "$PLANT" init -q >/dev/null 2>&1
# ASSEMBLED, never written out: a harness asserting that no tracked file carries a key
# literal may not be the tracked file that carries one. (It was, first time out.)
P='sk-'
printf 'DEEPSEEK_API_KEY=%s0123456789abcdef0123456789abcdef\n' "$P" > "$PLANT/config.env"
printf 'ANTHROPIC_API_KEY=%sant-api03-AAAAbbbbCCCCddddEEEE\n' "$P" > "$PLANT/other.txt"
git -C "$PLANT" add -A >/dev/null 2>&1
ok "…while a planted key IS found, in both shapes"  "$(scan "$PLANT")" 2

# (b) STRUCTURALLY. A `.env` git already tracks is refused rather than read — the seed
#     .gitignore line is a default, and a default is not a guarantee.
TRACKED="$TMP/tracked"; mkdir -p "$TRACKED"
git -C "$TRACKED" init -q >/dev/null 2>&1
printf 'DEEPSEEK_API_KEY=%s\n' "$KEY" > "$TRACKED/.env"
git -C "$TRACKED" add -f .env >/dev/null 2>&1
OUT="$( cd "$TRACKED" && bash "$LAUNCH" --bundle "$BUNDLE" --print-env 2>&1 )"; RC=$?
ok "a TRACKED .env -> exit 5, refused"              "$RC" 5
ok "…and the refusal says why"                      "$(cnt "$OUT" 'TRACKED by git')" 1
ok "…and prints no fragment of it"                  "$(cnt "$OUT" "$HEAD5")" 0
# Non-vacuity: the same file, untracked, is read normally.
git -C "$TRACKED" rm --cached -q .env >/dev/null 2>&1
OUT="$( cd "$TRACKED" && bash "$LAUNCH" --bundle "$BUNDLE" --print-env 2>&1 )"; RC=$?
ok "…the SAME .env, untracked, is read -> exit 0"   "$RC" 0

# (c) THE DEFAULT A STAMPED BUNDLE GETS.
ok "the seed .gitignore ignores .env"               "$(grep -cxF '.env' "$REPO/plugin/seed/.gitignore")" 1
ok "…and /${PN}:init appends it to an older bundle" \
   "$(grep -c "grep -qxF '.env'" "$REPO/plugin/scripts/init-bundle.sh")" 1

echo
echo "== 7. the banner warns off ANTHROPIC_BASE_URL in ITS OWN environment =="
# Companion-independent by design: an empty registry, so nothing is installed, and the
# warning must still fire. That is the hand-exported substitution the flag exists for.
BB="$TMP/bb"; mkdir -p "$BB"
printf '{ "org": "x" }\n' > "$BB/instance.config.json"
EMPTY="$TMP/empty-cfg"; mkdir -p "$EMPTY"
banner() { CLAUDE_PROJECT_DIR="$BB" CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_CONFIG_DIR="$EMPTY" \
           ANTHROPIC_BASE_URL="${1-}" bash "$BANNER" --no-color 2>/dev/null; }
ok "a substituted backend is called out"            \
   "$(banner 'https://api.deepseek.com/anthropic' | grep -c 'NOT ANTHROPIC')" 1
ok "…and the backend is NAMED"                      \
   "$(banner 'https://api.deepseek.com/anthropic' | grep -c 'backend is api.deepseek.com')" 1
ok "…with no companion installed at all"            \
   "$(yn test ! -e "$EMPTY/plugins/installed_plugins.json")" yes
ok "…and it says the session's contents go there"   \
   "$(banner 'https://api.deepseek.com/anthropic' | grep -c 'goes there')" 1
# A different host is a different name: a fixed string would pass both of these.
ok "another backend is named as itself"             \
   "$(banner 'https://gateway.example.org/v1' | grep -c 'backend is gateway.example.org')" 1
# STAY SILENT is the other rendering, and the one that must not leak.
ok "unset -> the banner says nothing about a backend" \
   "$(CLAUDE_PROJECT_DIR="$BB" CLAUDE_PLUGIN_ROOT="$REPO/plugin" CLAUDE_CONFIG_DIR="$EMPTY" \
      bash "$BANNER" --no-color 2>/dev/null | grep -c 'NOT ANTHROPIC')" 0
# It re-prints on /<plugin>:welcome because that form EXECS this hook — asserted on the
# skill's own contract, so a second copy of the banner could not satisfy it.
# Three exec sites since 2x/task-006: the md form, the plain form (both --no-logo) and the
# pass-through — every one of them the hook itself, none a second rendering.
ok "/${PN}:welcome execs the hook, not a copy"  \
   "$(grep -c 'exec bash "$hook"' "$REPO/plugin/scripts/welcome.sh")" 3

echo
echo "== 8. it ships as a companion, on the contract core already has =="
ok "the marketplace registers loopd-llm"        "$(grep -c '"name": "loopd-llm"' "$MJ")" 1
ok "…from ./plugin-llm"                             "$(grep -c '"source": "./plugin-llm"' "$MJ")" 1
ok "the capability file is at the fixed path"       "$(yn test -f "$CAP")" yes
ok "it ships no hook and no agent"                  \
   "$(find "$REPO/plugin-llm" -type d \( -name hooks -o -name agents \) | grep -c .)" 0
# Core's own code, not its docs: plugin/README.md lists every companion by name.
ok "no core script or hook runs the launcher"       \
   "$(grep -rlE 'ai-bridge-deepseek|plugin-llm' "$REPO/plugin/scripts" "$REPO/plugin/hooks" | grep -c .)" 0
ok "the capability file records the opt-in layer"   \
   "$(grep -c 'instance.config.local.json' "$CAP")" 1
ok "…and states the subagent question as UNMEASURED" "$(grep -c 'UNMEASURED' "$CAP")" 1

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
