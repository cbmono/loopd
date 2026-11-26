#!/usr/bin/env bash
#
# script-classes.test.sh — plugin/data/script-classes.txt gives every plugin/scripts/*.sh
# exactly one class, read by plugin/scripts/script-classes.sh.
#
# A gap: a script with no entry, an entry with no script, a name listed twice, a class neither
# read-only nor writing, a writing entry with no reason, or a read-only script that reaches a
# writing one. Reach is refs() of gate-files-complete.test.sh, followed through every .sh it
# resolves (lib/ included), so the class is transitive.
# Usage: script-classes.test.sh [<tree>] — checks <tree> alone, exit 1 on a gap.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
READER="$REPO/plugin/scripts/script-classes.sh"
. "$REPO/tests/gate-files-complete.test.sh"
CACHE="$(mktemp -d)" || exit 2
trap 'rm -rf "$CACHE"' EXIT

sh_refs() { # <tree> <file> — the .sh files it names, cached per tree and file
  local k; k="$CACHE/$(printf '%s' "$1" | cksum | cut -d' ' -f1)/$2"
  [ -f "$k" ] || { mkdir -p "${k%/*}" && refs "$1" "$2" | grep '\.sh$' > "$k"; }
  cat "$k"
}

reach() { # <tree> <file> — every .sh it reaches, itself excluded
  local seen=" $2 " queue="$2" f r
  while [ -n "$queue" ]; do
    f="${queue%% *}"; queue="${queue#"$f"}"; queue="${queue# }"
    for r in $(sh_refs "$1" "$f"); do
      case "$seen" in *" $r "*) continue ;; esac
      seen="$seen$r "; queue="${queue:+$queue }$r"; echo "$r"
    done
  done
}

gaps() { # <tree> <list> — one line per gap
  local tree="$1" list="$2" d w ro r
  d="$(mktemp -d "$CACHE/gaps.XXXXXX")" || return 2
  awk '{ if (++n[$1] == 2) print "DUPLICATE " $1
         if ($2 != "read-only" && $2 != "writing") print "BAD-CLASS " $1 " " $2
         else if ($2 == "writing" && NF < 3) print "NO-REASON " $1 }' "$list"
  (cd "$tree/plugin/scripts" && ls -- *.sh) | LC_ALL=C sort > "$d/scripts"
  cut -d' ' -f1 "$list" | LC_ALL=C sort -u > "$d/listed"
  comm -23 "$d/scripts" "$d/listed" | sed 's/^/UNCLASSIFIED /'
  comm -13 "$d/scripts" "$d/listed" | sed 's/^/NO-SCRIPT /'
  w=" $("$READER" writing "$list" | tr '\n' ' ')"
  for ro in $("$READER" read-only "$list"); do
    [ -f "$tree/plugin/scripts/$ro" ] || continue
    for r in $(reach "$tree" "plugin/scripts/$ro"); do
      case "$r" in plugin/scripts/*/*) continue ;; esac
      case "$w" in *" ${r#plugin/scripts/} "*) echo "REACHES $ro ${r#plugin/scripts/}" ;; esac
    done
  done
}

check_tree() { # <tree> — prints each gap, returns 1 on any
  local list="$1/plugin/data/script-classes.txt" out
  [ -r "$list" ] || { echo "NO-LIST plugin/data/script-classes.txt"; return 1; }
  out="$(gaps "$1" "$list")" || { echo "UNKNOWN the gap walk could not run"; return 1; }
  [ -z "$out" ] && return 0
  printf '%s\n' "$out"; return 1
}

if [ $# -gt 0 ]; then check_tree "$1"; exit; fi

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1 — got [$2] want [$3]"; fail=$((fail+1)); fi; }
TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$CACHE" "$TMP"' EXIT

fixture() { # <dir> <list line>... — ro.sh calls mid.sh, which sources lib/x.sh; x.sh runs wr.sh
  local d="$1"; shift
  mkdir -p "$d/plugin/scripts/lib" "$d/plugin/data"
  printf '%s\n' '#!/usr/bin/env bash' 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"' '"$HERE/mid.sh"' \
    'echo "wr.sh in a message"' > "$d/plugin/scripts/ro.sh"
  printf '%s\n' '#!/usr/bin/env bash' '. "$(dirname "${BASH_SOURCE[0]:-$0}")/lib/x.sh"' > "$d/plugin/scripts/mid.sh"
  printf '%s\n' '#!/usr/bin/env bash' '"$(dirname "${BASH_SOURCE[0]}")/../wr.sh"' > "$d/plugin/scripts/lib/x.sh"
  echo '#!/usr/bin/env bash' > "$d/plugin/scripts/wr.sh"
  printf '%s\n' "$@" > "$d/plugin/data/script-classes.txt"
}
run() { out="$(bash "$0" "$TMP/$1")"; rc=$?; }
has() { grep -cxF -- "$1" <<<"$out"; }

GOOD=("mid.sh writing runs wr.sh" "ro.sh writing runs wr.sh" "wr.sh writing writes a file")

echo "== fixtures: each gap is red, the clean list is green =="
fixture "$TMP/good" "${GOOD[@]}"; run good
ok "a list naming each script once, by effect, passes" "$rc" 0
fixture "$TMP/missing" "mid.sh writing runs wr.sh" "ro.sh writing runs wr.sh"; run missing
ok "a script with no entry fails" "$rc" 1
ok "…and is named" "$(has 'UNCLASSIFIED wr.sh')" 1
fixture "$TMP/extra" "${GOOD[@]}" "gone.sh read-only"; run extra
ok "an entry with no script fails" "$rc" 1
ok "…and is named" "$(has 'NO-SCRIPT gone.sh')" 1
fixture "$TMP/twice" "${GOOD[@]}" "wr.sh writing writes a file"; run twice
ok "a script listed twice fails" "$rc" 1
ok "…and is named" "$(has 'DUPLICATE wr.sh')" 1
fixture "$TMP/class" "mid.sh writing runs wr.sh" "ro.sh writing runs wr.sh" "wr.sh readonly"; run class
ok "a class neither read-only nor writing fails" "$rc" 1
ok "…and is named" "$(has 'BAD-CLASS wr.sh readonly')" 1
fixture "$TMP/reason" "mid.sh writing runs wr.sh" "ro.sh writing runs wr.sh" "wr.sh writing"; run reason
ok "a writing entry with no reason fails" "$rc" 1
ok "…and is named" "$(has 'NO-REASON wr.sh')" 1
fixture "$TMP/reach" "mid.sh read-only" "ro.sh read-only" "wr.sh writing writes a file"; run reach
ok "a read-only script reaching a writing one, two hops and a lib/ file away, fails" "$rc" 1
ok "…naming the caller" "$(has 'REACHES ro.sh wr.sh')" 1
ok "…and the middle script too" "$(has 'REACHES mid.sh wr.sh')" 1
ok "a basename in a message is not a call" "$(grep -c '^REACHES' <<<"$out")" 2
fixture "$TMP/collide" "lib_x.sh read-only" "mid.sh read-only" "ro.sh read-only" "wr.sh writing writes a file"
echo '#!/usr/bin/env bash' > "$TMP/collide/plugin/scripts/lib_x.sh"; run collide
ok "lib_x.sh walked first does not hide lib/x.sh's call to a writer" "$(has 'REACHES ro.sh wr.sh')" 1
fixture "$TMP/leaf" "mid.sh writing runs wr.sh" "ro.sh writing runs wr.sh" "wr.sh read-only"; run leaf
ok "a read-only script reached by writing ones passes" "$rc" 0

echo "== the reader task-002's rule writer uses =="
ok "read-only prints the read-only names" "$("$READER" read-only "$TMP/leaf/plugin/data/script-classes.txt" | tr '\n' ' ')" "wr.sh "
ok "writing prints the writing names, in list order" "$("$READER" writing "$TMP/leaf/plugin/data/script-classes.txt" | tr '\n' ' ')" "mid.sh ro.sh "
"$READER" bogus >/dev/null 2>&1; ok "an unknown class is a usage error" "$?" 2
"$READER" read-only "$TMP/nope" >/dev/null 2>&1; ok "an unreadable list is exit 2, never an empty answer" "$?" 2
ok "with no list it reads the shipped one" "$("$READER" read-only | grep -cxF merge-queue.sh)" 1

echo "== this repo =="
out="$(check_tree "$REPO")"; rc=$?
[ -z "$out" ] || printf '        %s\n' "$out"
ok "every plugin/scripts/*.sh is classified once, and no read-only script reaches a writer" "$rc" 0
n_scripts="$(cd "$REPO/plugin/scripts" && ls -- *.sh | wc -l | tr -d ' ')"
ok "the two classes together name every script" "$(( $("$READER" read-only | wc -l) + $("$READER" writing | wc -l) ))" "$n_scripts"
for s in commit-as.sh reclaim-worktree.sh release-bump.sh question-sweep.sh migrate-bundle.sh \
         normalise-config.sh refresh-seeds.sh close-project-folder.sh answer.sh clearance-receipt.sh \
         tick-lock.sh control.sh web-queue.sh; do
  ok "$s is writing" "$("$READER" writing | grep -cxF "$s")" 1
done
for s in merge-queue.sh; do
  ok "$s is read-only" "$("$READER" read-only | grep -cxF "$s")" 1
done

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
