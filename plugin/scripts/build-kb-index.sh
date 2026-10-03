#!/usr/bin/env bash
# build-kb-index.sh — regenerate knowledge/index.md from document frontmatter, or
# `--check` that the file, the documents and their links agree. From a bundle root.
#
#   build-kb-index.sh [--check | --print] [--strict]
#
# Exit: 0 clean · 1 a defect (with --strict, a warning too) · 2 usage/no KB here.
# A row is derived, never hand-written: its summary is the doc's `lesson:` (else
# `description:`), `|` is escaped, and superseded Findings render in their own
# section. A broken link in knowledge/** WARNs, and so does a dangling `source:`.
# Reasoning and the defect list: ai-bridge-next/task-007, task-019.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

MODE=build; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)  MODE=check ;;
    --print)  MODE=print ;;
    --strict) STRICT=1 ;;
    -h|--help) sed -n '2,11p' "$0" >&2; exit 2 ;;
    *) echo "build-kb-index: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

[ -d knowledge ] || { echo "build-kb-index: run from a bundle root (no knowledge/ here)." >&2; exit 2; }
INDEX=knowledge/index.md
VOCAB=knowledge/vocab.md
FINDING_STATUSES="current superseded corrected archived"
FINDING_MAX_LINES=40
SUMMARY_MAX=240
# The KB journal shards per month once it is shared; a single-writer bundle keeps the
# flat file, and the footer names whichever this bundle actually has.
JOURNAL=/knowledge/log.md
[ -d knowledge/log ] && JOURNAL=/knowledge/log/

errors=0; warns=0
err()  { printf '  ERROR  %s\n         %s\n' "$1" "$2" >&2; errors=$((errors+1)); }
warn() { printf '  WARN   %s\n         %s\n' "$1" "$2" >&2; warns=$((warns+1)); }

# --- frontmatter ------------------------------------------------------------
fm() {
  awk 'NR==1 && $0!="---" { exit } /^---$/ { n++; if (n==2) exit; next } n==1 { print }' "$1"
}
field() { # <frontmatter> <key>
  printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 \
    | sed 's/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/'
}
# `key: [a, b]` and the block form both flatten to one item per line.
listfield() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v k="$2" '
    $0 ~ "^" k ":" { inb=1; rest=$0; sub(/^[^:]*:/, "", rest); gsub(/[][,]/, " ", rest); print rest; next }
    inb && /^[[:space:]]+-[[:space:]]*/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next }
    inb && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inb=0 }
  ' | tr ' ' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"\(.*\)"$/\1/' | grep -v '^$' || true
}
esc() { printf '%s' "$1" | sed 's/|/\\|/g'; }

slug_of() { local b; b=$(basename "$1"); printf '%s' "${b%.md}"; }
docs_in() { find "knowledge/$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort; }

# --- controlled vocabulary --------------------------------------------------
# Every canonical tag and every alias, space-delimited, from vocab.md's table.
VOCAB_TERMS=" "
HAVE_VOCAB=0
if [ -r "$VOCAB" ]; then
  HAVE_VOCAB=1
  VOCAB_TERMS=" $(awk -F'|' '/^\|/ && !/^\|[[:space:]]*-/ {
        t=$2; a=$4
        gsub(/[`[:space:]]/, "", t); gsub(/[`[:space:]]/, "", a)
        if (t == "" || t == "Tag") next
        print t; n=split(a, p, ","); for (i=1;i<=n;i++) if (p[i] != "" && p[i] != "—") print p[i]
      }' "$VOCAB" | LC_ALL=C sort -u | tr '\n' ' ')"
fi
in_vocab() { case "$VOCAB_TERMS" in *" $1 "*) return 0 ;; esac; return 1; }

# --- document facts ---------------------------------------------------------
title_of()   { field "$1" title; }
status_of()  { field "$1" status | sed 's/[[:space:]]*#.*//'; }
summary_of() { local s; s=$(field "$1" lesson); [ -n "$s" ] || s=$(field "$1" description); printf '%s' "$s"; }

# --- render -----------------------------------------------------------------
render_rows() { # <kind> <want: current|superseded|archived> <last-column: status|superseded_by|none>
  local kind=$1 want=$2 last=$3 f fmv st printed=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    fmv=$(fm "$f"); st=$(status_of "$fmv"); [ -n "$st" ] || st=current
    case "$want:$st" in
      superseded:superseded|archived:archived) : ;;
      current:superseded|current:archived|superseded:*|archived:*) continue ;;
    esac
    local title summary path tail
    title=$(esc "$(title_of "$fmv")"); [ -n "$title" ] || title=$(slug_of "$f")
    summary=$(esc "$(summary_of "$fmv")")
    path="\`/knowledge/$kind/$(slug_of "$f").md\`"
    case "$last" in
      status)         tail=" $(esc "$st") |" ;;
      superseded_by)  tail=" $(esc "$(field "$fmv" superseded_by)")" ; [ "$tail" != " " ] || tail=" —"; tail="$tail |" ;;
      none)           tail="" ;;
    esac
    printf '| %s | %s | %s |%s\n' "$title" "$summary" "$path" "$tail"
    printed=1
  done <<< "$(docs_in "$kind")"
  [ "$printed" = 1 ] || case "$last" in
    none) printf '| _(none yet)_ | | |\n' ;;
    *)    printf '| _(none yet)_ | | | |\n' ;;
  esac
}

generate() {
  # The heredoc is QUOTED (its markdown is full of backticks), so the one path in it is
  # substituted afterwards rather than expanded in place.
  cat <<'EOF' | sed "s|__AB_SCHEMA__|$AB_SCHEMA|g"
# Knowledge Base — index

Compact catalog of this control panel's OKF knowledge base (`Service`s, `Finding`s,
`Runbook`s, `Team`s, `Reference`s — types in `/__AB_SCHEMA__`). **This index is the KB's lookup
surface:** scan it to find prior work, then open only the specific doc(s) you need —
**don't bulk-read `knowledge/`**.

**Derived — do not hand-edit.** `build-kb-index.sh` rebuilds every row below from document
frontmatter, and `--check` fails when this file and the documents disagree. Tags come from
[the controlled vocabulary](/knowledge/vocab.md). Superseded rows are **history**: read
them to understand a decision, never cite them as current guidance.

## Services

| Service | What it is | Path | Status |
|---|---|---|---|
EOF
  render_rows services current status
  cat <<'EOF'

## Findings — decisions, learnings, gotchas

| Finding | Summary | Path | Status |
|---|---|---|---|
EOF
  render_rows findings current status
  cat <<'EOF'

### Superseded findings — history, not current guidance

| Finding | Summary | Path | Superseded by |
|---|---|---|---|
EOF
  render_rows findings superseded superseded_by
  # Only when one exists, so adding the status re-renders no existing index.
  local archived; archived=$(render_rows findings archived status)
  case "$archived" in *'_(none yet)_'*) : ;; *)
    cat <<'EOF'

### Archived findings — history, not current guidance: no brief cited them

| Finding | Summary | Path | Status |
|---|---|---|---|
EOF
    printf '%s\n' "$archived" ;;
  esac
  cat <<'EOF'

## Runbooks

| Runbook | When to use | Path | Status |
|---|---|---|---|
EOF
  render_rows runbooks current status
  cat <<'EOF'

## References — durable specs & contracts

| Reference | What it specifies | Path | Status |
|---|---|---|---|
EOF
  render_rows references current status
  cat <<'EOF'

## Teams — who owns what / routing

| Team | Owns | Path |
|---|---|---|
EOF
  render_rows teams current none
  printf '\n---\n[KB log](%s) — what changed and when.\n' "$JOURNAL"
}

# --- checks -----------------------------------------------------------------
# Cells split on UNESCAPED `|` only, so a row that forgot the backslash shows up as
# the wrong cell count rather than as a silently shifted column.
check_index() {
  [ -r "$INDEX" ] || { err "$INDEX" "no index file — run build-kb-index.sh"; return; }
  local line n=0 section="" want body cells count path summary status
  while IFS= read -r line; do
    n=$((n+1))
    case "$line" in
      '## '*|'### '*) section="$line"; continue ;;
      '|'*) : ;;
      *) continue ;;
    esac
    case "$line" in *'---|'*) continue ;; esac
    case "$line" in '| Service |'*|'| Finding |'*|'| Runbook |'*|'| Reference |'*|'| Team |'*) continue ;; esac
    case "$line" in *'_(none yet)_'*) continue ;; esac
    want=4; case "$section" in *Teams*) want=3 ;; esac
    body=${line#|}; body=${body%|}
    cells=${body//\\|/$'\001'}
    count=$(printf '%s' "$cells" | tr -cd '|' | wc -c | tr -d ' ')
    count=$((count+1))
    if [ "$count" -ne "$want" ]; then
      err "$INDEX:$n" "row has $count cells, expected $want — escape a literal pipe as \\| ($(printf '%.60s' "$line"))"
      continue
    fi
    summary=$(printf '%s' "$cells" | cut -d'|' -f2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    path=$(printf '%s' "$cells" | cut -d'|' -f3 | grep -oE '[A-Za-z0-9._/-]+\.md' | head -1)
    [ -n "$summary" ] || err "$INDEX:$n" "empty summary cell — the row is the KB's whole lookup surface"
    if [ -z "$path" ]; then
      err "$INDEX:$n" "row names no document path"
    else
      local rel="${path#/}"; case "$rel" in knowledge/*) : ;; *) rel="knowledge/${rel#knowledge/}" ;; esac
      [ -f "$rel" ] || err "$INDEX:$n" "index row points at no file: $path"
    fi
    case "$section" in
      *Findings*|*findings*)
        status=$(printf '%s' "$cells" | cut -d'|' -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$section" in
          '### Superseded'*) : ;;   # last column is the replacement, not a status
          *) case " $FINDING_STATUSES " in
               *" $status "*) : ;;
               *) err "$INDEX:$n" "status '$status' is outside {${FINDING_STATUSES// /, }}" ;;
             esac ;;
        esac ;;
    esac
  done < "$INDEX"
}

check_docs() {
  local kind f fmv slug st tag n edges=0
  local indexed=""
  [ -r "$INDEX" ] && indexed=" $(grep -oE '[A-Za-z0-9._/-]+\.md' "$INDEX" | sed 's#.*/##; s#\.md$##' | LC_ALL=C sort -u | tr '\n' ' ')"
  for kind in services findings runbooks teams references; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      slug=$(slug_of "$f"); fmv=$(fm "$f")
      case "$indexed" in *" $slug "*) : ;; *) err "$f" "no index row — an unindexed doc is one nobody can find or cite" ;; esac
      [ -n "$(summary_of "$fmv")" ] || err "$f" "no lesson: and no description: — the index row would have an empty summary"
      [ "$kind" = findings ] || continue
      st=$(status_of "$fmv")
      case " $FINDING_STATUSES " in
        *" $st "*) : ;;
        *) err "$f" "status '$st' is outside {${FINDING_STATUSES// /, }}" ;;
      esac
      n=$(grep -c '' "$f")
      # validate-bundle.sh's rule: the mandatory `provenance:` line is not counted.
      [ -z "$(field "$fmv" provenance)" ] || n=$((n-1))
      au=$(field "$fmv" author)
      if [ -n "$au" ] && ! printf '%s' "$au" | grep -qE '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'; then
        warn "$f" "author: '$au' is not a GitHub login — provenance has to survive a file move"
      fi
      [ "$n" -le "$FINDING_MAX_LINES" ] || warn "$f" "Finding is $n lines; $AB_CONVENTIONS 'Write less' caps it at $FINDING_MAX_LINES"
      if [ -z "$(field "$fmv" lesson)" ]; then
        warn "$f" "no one-line 'lesson:' — the index row falls back to description:"
      elif [ "$(printf '%s' "$(summary_of "$fmv")" | wc -c | tr -d ' ')" -gt "$SUMMARY_MAX" ]; then
        warn "$f" "summary is over $SUMMARY_MAX characters — shorten the lesson:"
      fi
      for tag in $(listfield "$fmv" tags); do
        if [ "$HAVE_VOCAB" = 0 ]; then warn "$f" "tags: '$tag' cannot be checked — no $VOCAB in this bundle"
        elif ! in_vocab "$tag"; then err "$f" "tag '$tag' is not in $VOCAB — use a listed tag or an alias, never a new one"; fi
      done
      for tag in $(listfield "$fmv" superseded_by) $(listfield "$fmv" supersedes); do
        edges=$((edges+1))
        [ -f "knowledge/findings/$tag.md" ] || err "$f" "supersession edge names no Finding: $tag"
      done
      if [ -n "$(field "$fmv" superseded_by)" ] && [ "$st" != superseded ]; then
        err "$f" "carries superseded_by: but status is '$st' — supersede sets both"
      fi
    done <<< "$(docs_in "$kind")"
  done
  printf 'build-kb-index: %d supersession edge(s).\n' "$edges"
}

# --- bundle-relative links --------------------------------------------------
# A link an agent can follow: absolute `/…` from the bundle root, or a relative
# `*.md`. Fenced blocks are skipped — theirs are illustrations, not references.
links_in() { # <file> -> "line<TAB>target", one per markdown inline link
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    { line = $0
      while (match(line, /\]\([^()[:space:]]*/)) {
        print NR "\t" substr(line, RSTART+2, RLENGTH-2)
        line = substr(line, RSTART+RLENGTH)
      } }
  ' "$1"
}

# --- the `source:` field ----------------------------------------------------
# TOKENISATION, because the field is free-form and the number is meaningless without
# it: split the value on commas and whitespace; every token starting with `/` is a
# bundle path and must resolve. A URL carries no such token, so it is not checked.
# WARN, not ERROR: a bundle measured at 322 dangling of 514 would have its `--check`
# red until every one was rewritten by hand (SCHEMA.md, "A `source:` is a durable URL").

# macOS ships no `readlink -f`, so the leaf's link chain is walked by hand.
physical() { # <path> -> its target with `..` and every symlink resolved, or nothing
  local d b l n=0
  d=$(dirname "$1"); b=$(basename "$1")
  while [ "$n" -lt 32 ]; do
    d=$(cd "$d" 2>/dev/null && pwd -P) || return 1
    [ -L "$d/$b" ] || break
    l=$(readlink "$d/$b")
    case "$l" in /*) : ;; *) l="$d/$l" ;; esac
    d=$(dirname "$l"); b=$(basename "$l"); n=$((n+1))
  done
  printf '%s/%s\n' "${d%/}" "$b"
}

check_source() {
  local kind f fmv val tok root
  root=$(pwd -P)
  for kind in services findings runbooks teams references; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      fmv=$(fm "$f"); val=$(field "$fmv" source)
      [ -n "$val" ] || continue
      while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        case "$tok" in /*) : ;; *) continue ;; esac
        tok=${tok%%#*}
        # `.$tok` would resolve `/..` against the bundle's PARENT, so it must be
        # refused before the existence test, not by it.
        case "$tok/" in
          */../*) warn "$f" "source: escapes the bundle root: $tok"; continue ;;
        esac
        if [ ! -e ".$tok" ]; then
          warn "$f" "source: resolves to nothing: $tok — $AB_SCHEMA wants the task's PR URL, or a blob/<sha> permalink when there is no PR"
          continue
        fi
        # A committed symlink spells no `..` and still leaves the bundle, so
        # containment is decided on the physical target, not on the text.
        case "$(physical ".$tok")" in
          "$root"|"$root"/*) : ;;
          *) warn "$f" "source: escapes the bundle root: $tok" ;;
        esac
      done <<< "$(printf '%s\n' "$val" | tr ',' ' ' | tr -s '[:space:]' '\n')"
    done <<< "$(docs_in "$kind")"
  done
}

check_links() {
  local f n target path
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS=$'\t' read -r n target; do
      target=${target%%#*}
      [ -n "$target" ] || continue
      case "$target" in *://*|mailto:*|tel:*) continue ;; esac
      if [ "${target#/}" != "$target" ]; then
        path=".$target"
      else
        case "$target" in *.md) : ;; *) continue ;; esac
        path="$(dirname "$f")/$target"
      fi
      [ -e "$path" ] || warn "$f:$n" "bundle-relative link resolves to nothing: $target"
    done <<< "$(links_in "$f")"
  done <<< "$(find knowledge -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)"
}

if [ "$MODE" = print ]; then generate; exit 0; fi

if [ "$MODE" = check ]; then
  check_index
  check_docs
  check_source
  check_links
  if [ -r "$INDEX" ] && ! diff -q <(generate) "$INDEX" >/dev/null 2>&1; then
    err "$INDEX" "does not match the documents — run build-kb-index.sh to regenerate it"
  fi
  printf 'build-kb-index: %d error(s), %d warning(s).\n' "$errors" "$warns"
  [ "$errors" -eq 0 ] || exit 1
  [ "$STRICT" = 1 ] && [ "$warns" -gt 0 ] && { echo "(--strict: warnings are failures)"; exit 1; }
  exit 0
fi

TMP_INDEX="$INDEX.tmp.$$"
trap 'rm -f "$TMP_INDEX"' EXIT INT TERM
if ! generate > "$TMP_INDEX" || ! mv "$TMP_INDEX" "$INDEX"; then
  echo "build-kb-index: could not write $INDEX" >&2; exit 1
fi
rows=$(grep -cE '^\| ' "$INDEX"); headers=$(grep -cE '^\|[- ]*(Service|Finding|Runbook|Reference|Team) \|' "$INDEX")
printf 'build-kb-index: wrote %s (%d row(s)).\n' "$INDEX" "$((rows - headers))"
