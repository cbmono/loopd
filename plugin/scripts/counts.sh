#!/usr/bin/env bash
#
# counts.sh — THE one definition of the bundle's numbers: in progress, in review, sessions
# working/idle/dead, need you. Sourced, after bundle-paths.sh:
#   ab_counts <root>        sets CNT_IN_PROGRESS CNT_IN_REVIEW CNT_WORKING CNT_IDLE CNT_DEAD
#                           CNT_TICK (working sessions that are the tick) CNT_NEED_YOU (`?`
#                           unknown), CNT_QUEUE (on|off|unreadable) and
#                           CNT_TASKS (`<word> TAB <json task path>` lines, or `?`) and
#                           CNT_STATUS (the same, `in-progress`/`in-review`, or `?`)
#   ab_write_counts <root>  writes them to AB_COUNTS (temp + mv), `?` as null, no free text
# status-line.sh prints them and the pane reads AB_COUNTS. No `gh`, no network, no `jq`.
# Reasoning: loopd-retirement-followups/task-004 (D4, D6).

ab_counts() {
  local root="$1" out a_cache a_ep a_rest agents l t
  local here; here="$(dirname "${BASH_SOURCE[0]:-$0}")"
  CNT_IN_PROGRESS='?'; CNT_IN_REVIEW='?'; CNT_NEED_YOU='?'; CNT_QUEUE=off
  CNT_WORKING='?'; CNT_IDLE='?'; CNT_DEAD='?'; CNT_TICK='?'; CNT_TASKS='?'; CNT_STATUS='?'
  read -r CNT_EPOCH CNT_AT <<<"$(date -u '+%s %Y-%m-%dT%H:%M:%SZ')"

  # Task frontmatter, directly — never SNAPSHOT.json, which only a tick writes. One awk pass,
  # first frontmatter block of each task document.
  if [ -d "$root/projects" ]; then
    set -- "$root"/projects/*/tasks/*.md
    if [ -e "$1" ]; then
      # A path is listed only in a shape that is JSON as it stands — nothing to escape.
      out="$(awk '
        function at(w) { if (match(FILENAME, /projects\/[A-Za-z0-9][A-Za-z0-9._-]*\/tasks\/[A-Za-z0-9][A-Za-z0-9._-]*\.md$/)) s = s w "\t\"" substr(FILENAME, RSTART) "\"\n" }
        FNR == 1 { fm = 0; hit = 0; if ($0 == "---") { fm = 1; next } }
        fm && $0 == "---" { fm = 0; next }
        fm && !hit && $0 ~ /^status:[[:space:]]*in-progress[[:space:]]*$/ { p++; hit = 1; at("in-progress") }
        fm && !hit && $0 ~ /^status:[[:space:]]*in-review[[:space:]]*$/   { r++; hit = 1; at("in-review") }
        END { printf "%d %d\n%s", p, r, s }
      ' "$@" 2>/dev/null)" && { read -r CNT_IN_PROGRESS CNT_IN_REVIEW <<<"${out%%$'\n'*}"
        CNT_STATUS=""; case "$out" in *$'\n'*) CNT_STATUS="${out#*$'\n'}" ;; esac; }
      [ -n "$CNT_IN_PROGRESS" ] && [ -n "$CNT_IN_REVIEW" ] || { CNT_IN_PROGRESS='?'; CNT_IN_REVIEW='?'; CNT_STATUS='?'; }
    else
      CNT_IN_PROGRESS=0; CNT_IN_REVIEW=0; CNT_STATUS=""
    fi
  fi

  # Sessions: PROCESSES behind this bundle's background sessions, not the registry's word.
  # `agent-sessions.sh view --counts` runs `claude agents --json` (~150 ms), so its answer is
  # cached per bundle for 10 s and every open session shares it. A failed read caches `?`,
  # never `0 working`. `v3` is the format; anything else in the file is unknown.
  a_cache="${XDG_CACHE_HOME:-$HOME/.cache}/loopd/counts-$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
  a_ep=""; a_rest=""; agents=""
  if [ -r "$a_cache" ]; then
    { read -r a_ep a_rest
      while IFS= read -r l; do agents="$agents$l"$'\n'; done; } < "$a_cache" 2>/dev/null
  fi
  case "$a_ep" in ''|*[!0-9]*) a_ep=0 ;; esac
  if [ $((CNT_EPOCH - a_ep)) -lt 0 ] || [ $((CNT_EPOCH - a_ep)) -ge 10 ]; then
    agents="$(bash "$here/agent-sessions.sh" view "$root" --counts </dev/null 2>/dev/null)" || agents='?'
    a_rest="v3 ${agents%%$'\n'*}"
    case "$agents" in *$'\n'*) agents="${agents#*$'\n'}"$'\n' ;; *) agents="" ;; esac
    if mkdir -p "${a_cache%/*}" 2>/dev/null; then
      printf '%s %s\n%s' "$CNT_EPOCH" "$a_rest" "$agents" > "$a_cache.$$" 2>/dev/null \
        && mv -f "$a_cache.$$" "$a_cache" 2>/dev/null
      rm -f "$a_cache.$$" 2>/dev/null
    fi
  fi
  case "$a_rest" in
    "v3 "*)
      read -r CNT_WORKING CNT_IDLE CNT_DEAD l <<<"${a_rest#v3 }"
      case "$CNT_WORKING:$CNT_IDLE:$CNT_DEAD:$l" in
        *[!0-9:]*|:*|*::*|*[0-9]) CNT_WORKING='?'; CNT_IDLE='?'; CNT_DEAD='?' ;;
        *) CNT_TASKS="" ;;
      esac ;;
  esac
  if [ "$CNT_TASKS" != '?' ]; then
    while IFS= read -r l; do
      t="${l#*$'\t'}"
      case "${l%%$'\t'*}" in
        working|idle|dead) ;;
        tick) case "$t" in ''|*[!0-9]*) ;; *) CNT_TICK="$t" ;; esac; continue ;;
        *) continue ;;
      esac
      case "$t" in \"*\") CNT_TASKS="$CNT_TASKS$l"$'\n' ;; esac
    done <<<"$agents"
  fi

  # Need you: AWAITING.md's own items, counted the way the banner counts them. OFF is chosen
  # (`awaiting: false`, or the file deleted); UNREADABLE is arrived at, and the bar says so.
  if ab_awaiting_on "$root" && [ -e "$root/$AB_AWAITING" ]; then
    CNT_QUEUE=unreadable
    if [ -r "$root/$AB_AWAITING" ]; then
      CNT_QUEUE=on
      CNT_NEED_YOU="$(awk '
        /^##[[:space:]].*Awaiting you/ { inblk = 1; next }
        inblk && /^##[[:space:]]/      { exit }
        inblk && /^[[:space:]]*\* /    { n++ }
        END { print n + 0 }
      ' "$root/$AB_AWAITING" 2>/dev/null)" || CNT_NEED_YOU='?'
      [ -n "$CNT_NEED_YOU" ] || CNT_NEED_YOU='?'
    fi
  fi
  [ "$CNT_QUEUE" = on ] || CNT_NEED_YOU='?'
}

_ab_jnum() { case "$2" in ''|*[!0-9]*) printf -v "$1" null ;; *) printf -v "$1" '%s' "$2" ;; esac; }

# `<word> TAB <json path>` lines to a JSON object; `?` is null.
_ab_jmap() {
  local l sep="" m="{"
  if [ "$2" = '?' ]; then printf -v "$1" null; return; fi
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    m="$m$sep${l#*$'\t'}:\"${l%%$'\t'*}\""; sep=","
  done <<<"$2"
  printf -v "$1" '%s}' "$m"
}

ab_write_counts() {
  local f="$1/$AB_COUNTS" tasks status p r w i d k n
  [ -d "${f%/*}" ] || return 0
  # Until /loopd:init adds the ignore line, a broad `git add` would commit this per-clone file.
  # Read .gitignore rather than ask git: the status line never runs git.
  if [ -e "$1/.git" ] && ! grep -qxE "/?${AB_COUNTS//./\\.}" "$1/.gitignore" 2>/dev/null; then return 0; fi
  _ab_jnum p "$CNT_IN_PROGRESS"; _ab_jnum r "$CNT_IN_REVIEW"; _ab_jnum n "$CNT_NEED_YOU"
  _ab_jnum w "$CNT_WORKING"; _ab_jnum i "$CNT_IDLE"; _ab_jnum d "$CNT_DEAD"; _ab_jnum k "$CNT_TICK"
  _ab_jmap tasks "$CNT_TASKS"; _ab_jmap status "$CNT_STATUS"
  printf '{"in_progress":%s,"in_review":%s,"sessions":{"working":%s,"idle":%s,"dead":%s,"tick_working":%s},"need_you":%s,"queue":"%s","task_sessions":%s,"task_status":%s,"written_at":"%s"}\n' \
    "$p" "$r" "$w" "$i" "$d" "$k" "$n" "$CNT_QUEUE" "$tasks" "$status" "$CNT_AT" > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null
  rm -f "$f.$$" 2>/dev/null
  return 0
}
