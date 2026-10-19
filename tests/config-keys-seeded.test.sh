#!/usr/bin/env bash
#
# config-keys-seeded.test.sh — every key the machinery reads through resolve-config.sh is
# one `welcome.sh check` knows, i.e. it is in plugin/seed/instance.config.json (or is one
# of the per-machine keys welcome.sh names). #397 and #399 each added a read key without
# seeding it, and check then called that key one "nothing reads". Exit 0 = all pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
SH="$TPL/plugin/scripts/welcome.sh"
SEED="$TPL/plugin/seed/instance.config.json"
command -v jq >/dev/null 2>&1 || { echo "config-keys-seeded.test: jq is required" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/config-keys-seeded.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
  -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }

# A call site is `resolve-config.sh"`, a variable holding it, or a `cfg` wrapper around it;
# the key is the first lowerCamel word after `--instance "<dir>"` and `--json|--source`.
read_keys() {
  local f
  grep -rlE 'resolve-config\.sh' "$TPL/plugin" --include='*.sh' | while IFS= read -r f; do
    [ "${f##*/}" = resolve-config.sh ] && continue
    awk '/\\$/ { sub(/\\$/, ""); buf = buf $0; next } { print buf $0; buf = "" }' "$f" \
      | grep -vE '^[[:space:]]*#' \
      | grep -oE '(resolve-config\.sh"|"\$(RC|RESOLVER|resolver)"|\$\(cfg|^[[:space:]]*cfg)( +--instance +"[^"]*")?( +--(json|source))? +[a-z][A-Za-z0-9]*\b' \
      | awk '{print $NF}'
  done | sort -u
}
KEYS="$(read_keys)"

echo "== the extractor sees the readers it must (else every assertion below is vacuous) =="
for k in mergeAtReviewCap reclaimIgnoreOk maxStallRounds roleMinutes continueAfterTasks; do
  ok "read key found: $k" "$(printf '%s\n' "$KEYS" | grep -cx "$k" | tr -d ' ')" 1
done

echo "== SEEDED: the two keys #397 and #399 added, each with its \$-doc line and default =="
ok "mergeAtReviewCap seeded false" "$(jq -c '.mergeAtReviewCap' "$SEED")" false
ok "reclaimIgnoreOk seeded []" "$(jq -c '.reclaimIgnoreOk' "$SEED")" "[]"
for k in mergeAtReviewCap reclaimIgnoreOk; do
  ok "\$$k doc line present" "$(jq -r --arg k "\$$k" 'has($k) and (.[$k] | type == "string")' "$SEED")" true
done

# Every read key goes in the LOCAL file, where welcome.sh also knows the per-machine ones.
INST="$TMP/inst"; mkdir -p "$INST"
printf '{\n  "org": "example-org"\n}\n' > "$INST/instance.config.json"
printf '%s\n' "$KEYS" | jq -R . | jq -s 'map({(.): null}) | add' > "$INST/instance.config.local.json"
GIT -C "$INST" init -q; GIT -C "$INST" add -A; GIT -C "$INST" commit -qm instance

echo "== NO FALSE WARNING: welcome.sh check knows every key read through resolve-config.sh =="
OUT="$(env -u CLAUDE_PLUGIN_ROOT bash "$SH" check --instance "$INST" --template "$TMP/no-checkout" 2>&1)"
ok "no read key is called one nothing reads" "$(printf '%s\n' "$OUT" | grep -c 'nothing reads' | tr -d ' ')" 0
ok "…and the row reports healthy" \
  "$(printf '%s\n' "$OUT" | grep -c 'every top-level key is one the machinery knows' | tr -d ' ')" 1

echo "== PINNED: a read key missing from the seed fails the row above =="
mkdir -p "$TMP/plugin/seed"
jq 'del(.mergeAtReviewCap)' "$SEED" > "$TMP/plugin/seed/instance.config.json"
OUT="$(CLAUDE_PLUGIN_ROOT="$TMP/plugin" bash "$SH" check --instance "$INST" --template "$TMP/no-checkout" 2>&1)"
ok "unseeded mergeAtReviewCap is named as a key nothing reads" \
  "$(printf '%s\n' "$OUT" | grep 'nothing reads' | grep -c 'instance\.config\.local\.json:mergeAtReviewCap' | tr -d ' ')" 1

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
