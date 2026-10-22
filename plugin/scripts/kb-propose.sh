#!/usr/bin/env bash
# kb-propose.sh — the scheduled half of the reflector: it PROPOSES. From a bundle root.
#
#   kb-propose.sh [--instance DIR] [--proposer <command>] [--project <slug>]
#
# Runs the archive sweep (`kb-usage.sh sweep --propose`), then <command>; each stdout line
# is `<kind> · <slug> · <field>=<value> · <with|-> · <why>`. The sweep rides inside the
# command that derives the next report id, so no tick can issue a report and skip it.
# The surviving proposals become ONE draft task document — the report, and the only thing
# that reaches the human, through build-awaiting.sh, which nothing here calls. It writes
# nothing under knowledge/, never AWAITING.md, and never reaches kb-apply.sh.
# Exit: 0 a report was written · 1 nothing to propose · 2 usage, or the proposer failed.
# Grammar and the split: SCHEMA.md "The reflection report".
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

KINDS="status edit merge rename supersede"
PROTECTED="ledger provenance"
INST="$PWD"; PROPOSER=""; PROJECT="knowledge-reflection"
need2() { [ "$1" -ge 2 ] || { echo "kb-propose: $2 needs a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) need2 $# "$1"; INST="$2";     shift 2 ;;
    --proposer) need2 $# "$1"; PROPOSER="$2"; shift 2 ;;
    --project)  need2 $# "$1"; PROJECT="$2";  shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" >&2; exit 2 ;;
    *) echo "kb-propose: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
INST="$(cd "$INST" 2>/dev/null && pwd)" || { echo "kb-propose: no such instance directory" >&2; exit 2; }
cd "$INST" || exit 2
[ -d knowledge ] || { echo "kb-propose: run from a bundle root (no knowledge/ here)" >&2; exit 2; }
case "$PROJECT" in ""|.|..|*[!A-Za-z0-9._-]*) echo "kb-propose: --project wants a slug" >&2; exit 2 ;; esac

drop() { echo "kb-propose: dropped — $1" >&2; }
split5() { # <line> -> F1..F4 and F5, which keeps any ` · ` the reason carries
  local s="$1"
  F1="${s%%" · "*}"; s="${s#*" · "}"
  F2="${s%%" · "*}"; s="${s#*" · "}"
  F3="${s%%" · "*}"; s="${s#*" · "}"
  F4="${s%%" · "*}"; s="${s#*" · "}"
  F5="$s"
}
fingerprint() { cksum <"$1" | awk '{print $1 "-" $2}'; }
fmfield() { sed -n '2,/^---$/p' "$1" | sed -n "s/^$2:[[:space:]]*\([^[:space:]].*\)/\1/p" | head -n1; }

for t in "projects/$PROJECT"/tasks/*.md; do
  [ -f "$t" ] && [ "$(fmfield "$t" status)" = draft ] || continue
  echo "kb-propose: not due — $t is still waiting on the human" >&2; exit 1
done

RAW="$(bash "$HERE/kb-usage.sh" --instance "$INST" sweep --propose)" \
  || { echo "kb-propose: the archive sweep failed — proposing nothing" >&2; exit 2; }
if [ -n "$PROPOSER" ]; then
  more="$(bash -c "$PROPOSER")" || { echo "kb-propose: the proposer failed — proposing nothing" >&2; exit 2; }
  RAW="$RAW
$more"
elif [ -z "$RAW" ]; then
  echo "kb-propose: not due — no proposer configured and nothing to archive" >&2; exit 1
fi
n=0; PROPOSALS=""; NAMED=""; HUMAN=""; ARCHIVED=""; TAGGED=""
while IFS= read -r line; do
  [ -n "${line//[[:space:]]/}" ] || continue
  [ "$(grep -o ' · ' <<<"$line" | wc -l)" -ge 4 ] || { drop "not five ' · ' fields: $line"; continue; }
  split5 "$line"
  case " $KINDS " in *" $F1 "*) ;; *) drop "kind '$F1' is not one of: $KINDS"; continue ;; esac
  case "$F2" in ""|*[!A-Za-z0-9._-]*) drop "'$F2' is not a slug"; continue ;; esac
  MATCH=( knowledge/*/"$F2".md )
  [ -f "${MATCH[0]}" ] || { drop "no item named $F2 under knowledge/*/"; continue; }
  [ "${#MATCH[@]}" -eq 1 ] || { drop "$F2 names ${#MATCH[@]} items"; continue; }
  # A doc a person wrote is queued only in the one shape kb-apply.sh --human-docs accepts.
  prov="$(fmfield "${MATCH[0]}" provenance)"
  case "$prov" in
    machine) ;;
    mixed|human)
      case "$F1 $F3" in "edit tags="*|"status status=archived") ;;
        *) drop "$F2 is provenance: $prov, which takes only 'edit · tags=' or 'status · status=archived'"; continue ;;
      esac ;;
    *) drop "$F2 has provenance '${prov:-absent}', not machine|mixed|human"; continue ;;
  esac
  [[ "$F3" =~ ^[a-z][a-z0-9_]*=[^[:space:]] ]] || { drop "'$F3' is not field=value"; continue; }
  case " $PROTECTED " in *" ${F3%%=*} "*) drop "'${F3%%=*}' is not a proposal's to write"; continue ;; esac
  if [ "$F4" != - ]; then
    case "$F4" in ""|*[!A-Za-z0-9._,-]*) drop "'$F4' is not a slug list"; continue ;; esac
  fi
  case "$F1" in merge|rename|supersede)
    [ "$F4" != - ] || { drop "$F2: a $F1 must name the other item(s)"; continue; } ;;
  esac
  case ",$F4," in *",$F2,"*) drop "$F2: --with names the item itself"; continue ;; esac
  case " $NAMED " in *" $F2 "*) drop "$F2 is already named by a proposal"; continue ;; esac
  [[ "$F5" =~ [^[:space:]] ]] || { drop "$F2: an empty reason"; continue; }
  case "$F3$F4$F5" in *'"'*|*\\*|*\`*|*\$*) drop "$F2: a field carries a quote, a backslash or a shell metacharacter"; continue ;; esac
  n=$((n + 1)); NAMED="$NAMED $F2"
  if [ "$prov" != machine ]; then
    HUMAN="${HUMAN:+$HUMAN,}$F2"
    case "$F3" in status=archived) ARCHIVED="$ARCHIVED
- \`$F2\` (provenance: $prov)" ;;
      *) TAGGED="$TAGGED
- \`$F2\` (provenance: $prov) · \`$F3\`" ;;
    esac
  fi
  PROPOSALS="$PROPOSALS
P$n · $F1 · $F2 · $F3 · $F4 · $(fingerprint "${MATCH[0]}") · $F5"
done <<EOF
$RAW
EOF

[ "$n" -gt 0 ] || { echo "kb-propose: not due — the proposer named nothing to change" >&2; exit 1; }

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "projects/$PROJECT/tasks" || exit 2
if [ ! -f "projects/$PROJECT/project.md" ]; then
  cat >"projects/$PROJECT/project.md" <<EOP
---
type: Project
title: Knowledge reflection
description: "Reports from kb-propose.sh. Each is a draft task the human reads and then applies with /loopd:kb-apply, or cancels to decline. Nothing here dispatches an agent."
kind: build
status: active
retain: true
timestamp: $NOW
---

# Context

Written by \`kb-propose.sh\`. A report here is never promoted to \`ready\`: the human applies
it with \`/loopd:kb-apply <report>\` or cancels it to decline. \`retain: true\` keeps the
folder once every report is terminal.
EOP
fi

last="$(ls "projects/$PROJECT/tasks" 2>/dev/null | sed -n 's/^task-\([0-9][0-9]*\).*/\1/p' | sort -n | tail -1)"
id="$(printf '%03d' $(( 10#${last:-0} + 1 )))"
REPORT="projects/$PROJECT/tasks/task-$id-knowledge-reflection.md"
APPLY="/loopd:kb-apply $REPORT${HUMAN:+ --human-docs $HUMAN}"

cat >"$REPORT" <<EOR
---
type: Task
title: "Knowledge reflection — $n proposal(s) to review"
kind: build
status: draft
assignee: human
acceptance_criteria: [ ]
open_questions:
  - "Apply the $n proposal(s) in this report? Read them, then run \`$APPLY\`. Decline by cancelling this task."
timestamp: $NOW
---

# Proposals

Nothing under \`knowledge/\` has changed. Each line below is one proposal, and
\`/loopd:kb-apply\` applies exactly these and nothing else.
EOR
printf '%s\n' "$PROPOSALS" >>"$REPORT"
[ -z "$HUMAN" ] || cat >>"$REPORT" <<EOR

## Human-written docs this report changes

A person wrote or edited these, so applying this report changes them only when you name
every one of them:

\`$APPLY\`

Archived (\`status=archived\`):${ARCHIVED:-
- none}

Tag edits (\`tags=\`):${TAGGED:-
- none}
EOR
cat >>"$REPORT" <<EOR

# Notes

Written by \`kb-propose.sh\` at $NOW. The fingerprint in each line is the item as it stood
then: an item edited since makes the whole report stale, and \`/loopd:kb-apply\` refuses it
rather than applying a proposal about an older file.
EOR

printf 'KB REFLECTION: %s proposal(s) in %s — the human applies it with /loopd:kb-apply.\n' "$n" "$REPORT"
exit 0
