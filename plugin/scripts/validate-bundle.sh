#!/usr/bin/env bash
#
# validate-bundle.sh — check that this bundle is machine-readable from frontmatter
# alone: every concept document has a known `type`, a `status` in that type's enum,
# a `timestamp`, and every structural cross-reference resolves.
#
#   Usage: validate-bundle.sh [--strict] [--changed] [<path>...]
#          --strict   treat warnings as failures too
#          --changed  only the documents git reports as changed or untracked
#                     (exit 2 outside a work tree — "no changes" is not an answer
#                     git could not have given)
#          <path>...  only the documents named (a path that is not a concept
#                     document is reported as SKIP, never as an error)
#
# WHY THIS EXISTS, AND WHAT IT DELIBERATELY DOES NOT CHECK.
# Measured across three live instances (2026-08-21, ~570 documents) BEFORE it was
# written, because a validator that reports problems nobody has is one people learn
# to ignore:
#   · status enums:      23 violations, all in `knowledge/`. The first measurement
#                        reported ZERO and was wrong: it sampled only Objective,
#                        Project, Phase and Task and never looked at Finding or
#                        Service. Findings carry `open` and `active` where the enum
#                        is `current|superseded`, and six Services carry `current`
#                        where theirs is `active|deprecated` — someone applied the
#                        Finding enum to a Service. Enum checking is NOT a
#                        future-typo guard; it is catching live drift, and the drift
#                        is concentrated exactly where nobody was looking.
#   · missing timestamp: 16 documents across two instances.
#   · frontmatter refs:  15 of 115 dangling (13%). This was the motivating rot. `/close-project` removes a project
#                        folder by design, so a surviving `depends_on:` or
#                        `objective:` pointing into it breaks silently.
#   · `Reference`:       the fifth knowledge kind, `knowledge/references/*.md`. It was
#                        ALREADY collected (the location filter is `knowledge/<kind>/`,
#                        not a list of four names) and already checked for type,
#                        timestamp and dangling refs — measured on the one live
#                        instance that has the directory: 7 documents, 0 findings. The
#                        single gap was its `status`, unchecked because `Reference` had
#                        no enum, so the exact drift class this script was built for —
#                        one type's enum applied to another — was invisible there.
#                        `current|superseded` is what all 7 already carry, so adding it
#                        is a no-op on live data and a real check on the next edit.
#                        Root documents typed `Reference` (SCHEMA.md, AUTONOMY.md) are
#                        NOT in a schema-defined location, so no enum reaches them.
#   · `owner`:           deliberately NOT checked. It is neither an enum nor a
#                        structural reference — it names a person outside the bundle,
#                        so nothing here can resolve it, and a warning about a name
#                        this script cannot verify is exactly the noise that buries
#                        real errors. `task-owner.sh` validates the shape at
#                        the one moment it matters: when the loop decides to dispatch.
#   · `id` / `updated`:  NOT required, and not added. No document in any instance
#                        carried either. The file path is already the identifier —
#                        a duplicate `id` can only drift from it — and OKF names the
#                        time field `timestamp`, so renaming it would diverge from
#                        the spec this bundle claims to follow. The v2 plan asked
#                        for both; the data said no.
#
# WHAT COUNTS AS A CONCEPT DOCUMENT. Only the schema-defined locations:
# `objectives/*.md` (OPTIONAL — a bundle with none is valid), `projects/*/project.md`,
# `projects/*/phases/*.md`, `projects/*/tasks/*.md`, `knowledge/<kind>/*.md`. Everything
# else — `index.md`, `log.md`, `sources/`, `deliverables/`, a doc a human dropped into a
# project — is content or navigation. The first version of this script validated those
# too and buried 6 real errors under 77 warnings, which is exactly how a validator
# teaches people to ignore it.
#
# BODY PROSE IS NOT CHECKED. A body may cite a closed project's task as history —
# that is the record working as intended. Only FRONTMATTER references, which
# machinery actually follows, must resolve. A `Finding`'s `source:` is provenance no
# machinery follows, so it is NOT checked here: `build-kb-index.sh --check` owns it,
# at WARN (SCHEMA.md, "A `source:` is a durable URL").
#
# `artifacts:` WARNS rather than fails: a research task legitimately declares a
# deliverable before it is written.
#
# A `Finding` over 40 lines, or without a one-line `lesson:`, WARNS for the same reason —
# `CONVENTIONS.md` -> "Write less" sets both, and the 133 findings that predate the rule
# average 110 lines. A warning puts them on the cataloguer's list; an error would fail
# every bundle that has one, which is every bundle.
#
# EVERY PER-DOCUMENT CHECK RUNS ON EVERY SCOPE — full bundle, `--changed`, or the paths
# you name. The Finding cap reached only a full run while nothing else could name one
# document, so the loop was: write it long, trim it at the next full run. The author now
# gets the warning at the moment of writing.
#
# BUNDLE-LEVEL CHECKS ARE SCOPED OUT WHEN PATHS ARE NAMED: the `knowledge/index.md`
# drift check is the one, and it runs on a named scope only when the index itself is
# named. Otherwise a stale index buried every named document's verdict under its warning.
#
# Run from a control-panel instance root. Generic: no org/repo/path literals.
# Bash + awk only — no jq, no python — so it ships into every instance unchanged.
#
# Verified by tests/validate-bundle.test.sh.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]:-$0}")/bundle-paths.sh" || exit 2

STRICT=0; CHANGED=0; NAMED=(); NAMED_INDEX=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --changed) CHANGED=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "usage: $0 [--strict] [--changed] [<path>...]" >&2; exit 2 ;;
    *) NAMED+=("$1") ;;
  esac
  shift
done

ab_is_bundle . || {
  echo "validate-bundle: run from a control-panel instance root (instance.config.json)." >&2
  exit 2
}

# Closed enums, per type. SCHEMA.md is the contract; this is its enforcement, so
# keep the two in step.
enum_for() {
  case "$1" in
    Objective) echo "active paused achieved dropped" ;;
    Project)   echo "active paused done" ;;
    Phase)     echo "not-started active done" ;;
    Task)      echo "draft ready in-progress in-review blocked cancelled done" ;;
    Finding)   echo "current superseded corrected" ;;
    Service)   echo "active deprecated" ;;
    Reference) echo "current superseded" ;;
    *)         echo "" ;;
  esac
}

KNOWN_TYPES="Objective Project Phase Task Agent Service Finding Team Runbook Reference"
# Who wrote a knowledge document — SCHEMA.md, "provenance:". Its own enum, because Team and
# Runbook have no status, so enum_for never reaches them.
KB_TYPES="Service Finding Team Runbook Reference"
PROVENANCE_ENUM="machine mixed human"

# CONVENTIONS.md -> "Write less". Lowering it is free; raising it is a rule change.
FINDING_MAX_LINES=40
# CONVENTIONS.md -> the `do_not_repeat` cap. `do-not-repeat.sh append` refuses past it;
# this reports a list already over it, which is the PM's cue to fold the oldest into `# Notes`.
DO_NOT_REPEAT_MAX=10

errors=0; warns=0; checked=0

# Print the frontmatter block. Exit 3 when the file does not open with `---`, and
# exit 4 when it opens but never closes — an unterminated block used to return the
# whole file, so a malformed document with valid-looking fields passed validation.
frontmatter() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# Collect path references from the given frontmatter keys, in BOTH YAML forms:
#   depends_on: [ /a.md, /b.md ]     (inline)
#   depends_on:                       (block)
#     - /a.md
# The line-based first version saw only the inline form, so a valid block sequence
# was silently skipped and the validator could report success while a structural
# reference dangled. No instance uses block style today; nothing forbids it.
refs_for() { # <frontmatter> <key-alternation> <path-regex>
  printf '%s\n' "$1" | awk -v keys="$2" '
    $0 ~ "^(" keys "):" { inblock=1; rest=$0; sub(/^[^:]*:/, "", rest); print rest; next }
    inblock && /^[[:space:]]+-[[:space:]]*/ { print; next }
    inblock && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inblock=0 }
  ' | grep -oE "$3" | sort -u || true
}
# Entries of a list-valued key, one per line, in BOTH YAML forms — flow
# (`k: [ a, "b, c" ]`) and block (`k:` then `  - a`), quoted or bare.
list_entries() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v key="$2" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function emit(s,   q) {
      s = trim(s); q = substr(s, 1, 1)
      if (length(s) > 1 && (q == "\"" || q == SQ) && substr(s, length(s)) == q)
        s = substr(s, 2, length(s) - 2)
      if (s != "") print s
    }
    function flow(t,   i, n, ch, inq, q, cur) {
      n = length(t); cur = ""; inq = 0
      for (i = 1; i <= n; i++) {
        ch = substr(t, i, 1)
        if (inq) {
          if (ch == "\\") { cur = cur ch substr(t, i + 1, 1); i++; continue }
          if (ch == q) inq = 0
          cur = cur ch; continue
        }
        if (ch == "\"" || ch == SQ) { inq = 1; q = ch; cur = cur ch; continue }
        if (ch == ",") { emit(cur); cur = ""; continue }
        cur = cur ch
      }
      emit(cur)
    }
    BEGIN { SQ = sprintf("%c", 39) }
    $0 ~ "^" key ":" {
      rest = trim(substr($0, length(key) + 2))
      # From the LAST `]`, so a trailing `# comment` is not read as an entry.
      if (rest ~ /^\[/) { sub(/^\[/, "", rest); sub(/\][^]]*$/, "", rest); flow(rest); inblock = 0 }
      else if (rest == "" || rest ~ /^#/) inblock = 1
      else { emit(rest); inblock = 0 }
      next
    }
    inblock && /^[[:space:]]+-[[:space:]]*/ { line = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", line); emit(line); next }
    inblock && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inblock = 0 }
  '
}

# How many entries a list-valued key holds. `list_entries` is the one splitter, so flow
# and block form cannot disagree about the same content. It used to count quoted flow
# entries only, and read a block-form list as zero — a shape that let the write it holds
# through in silence.
flow_entries() { # <frontmatter> <key>
  list_entries "$1" "$2" | awk 'END { print NR }'
}

# IS THE FRONTMATTER WELL FORMED? Print one message per structural fault, empty when
# clean. Bash + awk only, like the rest of this file — so this is NOT a YAML parse and
# does not pretend to be one. It is the three fault classes that have actually been
# measured in bundles, each of which made a document unreadable to every YAML consumer
# while sailing past the field checks below:
#
#   1. TWO LIST ENTRIES ON ONE LINE — `- "a"  - "b"`. An agent appending to a block list
#      wrote the new entry on the previous entry's line. Produced by a project-manager
#      tick; committed, pushed, and reported clean by this script for a day. Matched
#      from the start of a structural entry and over escaped quotes, so `\"  - \"`
#      inside one entry's text is content, not a delimiter.
#   2. AN UNESCAPED QUOTE INSIDE A SELF-CONTAINED ENTRY — the scalar ends early and the
#      rest of the line parses as garbage. Seen from prose quotation marks and from a
#      JSON array pasted into a criterion. Only flagged when the line both opens and
#      closes with a quote, so a legal multi-line scalar is not touched.
#   3. AN UNQUOTED VALUE CONTAINING A COLON-SPACE PAIR — `description: a: b` is a YAML
#      mapping error, and a one-line description is where it turns up.
#
# A class is added here when it has been seen, not when it can be imagined: every check
# runs on every document in every bundle, so a speculative one buys false positives on
# somebody's valid prose. Block scalars (`key: |`, `key: >`) are skipped entirely for
# the same reason: their content is text, and all three rules would read it as syntax.
fm_wellformed() { # <frontmatter>
  printf '%s\n' "$1" | awk '
    function unescaped_quotes(t,   i, c, n, prev) {
      n = 0; prev = ""
      for (i = 1; i <= length(t); i++) {
        c = substr(t, i, 1)
        if (c == "\"" && prev != "\\") n++
        prev = (prev == "\\" && c == "\\") ? "" : c
      }
      return n
    }
    # Index of the closing quote of a quoted scalar, escape-aware; 0 when it runs on to
    # the next line, which is a legal multi-line scalar and no business of this rule.
    function close_quote(t,   i, c, prev) {
      prev = substr(t, 1, 1)
      for (i = 2; i <= length(t); i++) {
        c = substr(t, i, 1)
        if (c == "\"" && prev != "\\") return i
        prev = (prev == "\\" && c == "\\") ? "" : c
      }
      return 0
    }
    function indent(t,   p) { p = match(t, /[^ \t]/); return p ? p - 1 : length(t) }
    function block_header(t) {
      return t ~ /^[ \t]*([A-Za-z_][A-Za-z0-9_-]*:|-)[ \t]*[|>][0-9+-]*[ \t]*(#.*)?$/
    }
    # A block scalar is opaque text, so none of the three rules may read it. Skipping it
    # is what keeps prose containing `"  - "` or a colon-space pair from being a fault.
    {
      if (in_block) {
        if ($0 ~ /^[ \t]*$/) next
        if (indent($0) > block_indent) next
        in_block = 0
      }
      if (block_header($0)) { block_indent = indent($0); in_block = 1; next }
    }
    # 1. a second entry opened on this line
    /^[ \t]*-[ \t]+"([^"\\]|\\.)*"[ \t]+-[ \t]+"/ {
      printf "line %d: a list entry is opened on another entry'\''s line (\"  - \") — it belongs on its own line\n", NR
      next
    }
    # 2. a self-contained entry carrying unescaped inner quotes
    /^[ \t]*-[ \t]*"/ {
      body = $0
      sub(/^[ \t]*-[ \t]*/, "", body)
      sub(/[ \t]+$/, "", body)
      # An inline comment is not part of the scalar, and its own quotes are not inner
      # ones — rule 3 already strips one. Only past the closing quote, so a malformed
      # entry that also carries a `#` still counts every quote it opened.
      q = close_quote(body)
      if (q > 0 && substr(body, q + 1) ~ /^[ \t]+#/) body = substr(body, 1, q)
      if (body ~ /^".*"$/ && unescaped_quotes(body) != 2) {
        printf "line %d: %d unescaped double quotes in a quoted entry — escape the inner ones as \\\"\n", NR, unescaped_quotes(body)
      }
      next
    }
    # 3. an unquoted scalar holding a colon-space pair
    /^[A-Za-z_][A-Za-z0-9_]*:[ \t]+[^ \t]/ {
      val = $0
      sub(/^[A-Za-z_][A-Za-z0-9_]*:[ \t]+/, "", val)
      sub(/[ \t]+#.*$/, "", val)
      first = substr(val, 1, 1)
      key = $0; sub(/:.*$/, "", key)
      if (first == "`" || first == "@") {
        printf "line %d: unquoted value for %s opens on %s, which YAML reserves at the start of a plain scalar — quote the value\n", NR, key, first
      } else if (first != "\"" && first != "'\''" && first != "[" && first != "{" \
          && first != "|" && first != ">" && first != "&" && first != "*" \
          && val ~ /: /) {
        printf "line %d: unquoted value for %s contains a colon-space pair — quote the value\n", NR, key
      }
    }
  '
}

fail() { printf '  ERROR  %s\n         %s\n' "$1" "$2"; errors=$((errors+1)); }
warn() { printf '  WARN   %s\n         %s\n' "$1" "$2"; warns=$((warns+1)); }

collect_files() {
  find ./objectives -maxdepth 1 -name '*.md' 2>/dev/null || true
  find ./projects -maxdepth 2 -name 'project.md' 2>/dev/null || true
  find ./projects -path '*/phases/*.md' 2>/dev/null || true
  find ./projects -path '*/tasks/*.md' 2>/dev/null || true
  find ./knowledge -mindepth 2 -maxdepth 2 -type f -name '*.md' 2>/dev/null || true
}

FILE_LIST="$(collect_files | grep -vE '/(index|log)\.md$' | sort -u || true)"

# A scope narrows the SAME list, so `collect_files` stays the one answer to "is this a
# concept document" and the ignore rules hold on every run.
HERE="$(pwd -P)"
# An absolute path and `$PWD` disagree through a symlinked parent (/tmp on macOS), so the
# form is canonicalised rather than prefix-stripped.
canon() { # <path> -> ./<path> relative to the bundle root, else unchanged
  local d b
  case "$1" in /*) ;; *) printf './%s\n' "${1#./}"; return ;; esac
  d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || { printf '%s\n' "$1"; return; }
  b="$(basename "$1")"
  case "$d" in
    "$HERE")   printf './%s\n' "$b" ;;
    "$HERE"/*) printf './%s\n' "${d#"$HERE"/}/$b" ;;
    *)         printf '%s\n' "$1" ;;
  esac
}

if [[ $CHANGED -eq 1 || ${#NAMED[@]} -gt 0 ]]; then
  scope=()
  if [[ $CHANGED -eq 1 ]]; then
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
      echo "validate-bundle: --changed needs a git work tree; without one 'no changes' and 'could not look' are the same answer." >&2
      exit 2
    }
    while IFS= read -r p; do
      [[ -z "$p" ]] || scope+=("$(canon "$p")")
    done < <({ git diff --name-only --relative HEAD; git ls-files -o --exclude-standard; } 2>/dev/null || true)
  fi
  # A path you NAMED and did not get is worth a line; in --changed every other file is one.
  for p in ${NAMED[@]+"${NAMED[@]}"}; do
    scope+=("$(canon "$p")")
    [[ "${scope[${#scope[@]}-1]}" != ./knowledge/index.md ]] || { NAMED_INDEX=1; continue; }
    printf '%s\n' "$FILE_LIST" | grep -qFx "${scope[${#scope[@]}-1]}" \
      || printf '  SKIP   %s\n         not a concept document — %s names the locations that are\n' "$p" "$AB_SCHEMA"
  done
  FILE_LIST="$(printf '%s\n' ${scope[@]+"${scope[@]}"} | sort -u | grep -Fxf <(printf '%s\n' "$FILE_LIST") - || true)"
fi

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  rel="${file#./}"
  fm_rc=0
  fm="$(frontmatter "$file")" || fm_rc=$?
  if [[ $fm_rc -eq 3 ]] || { [[ $fm_rc -eq 0 ]] && [[ -z "$fm" ]]; }; then
    fail "$rel" "no YAML frontmatter, but it sits in a schema-defined location"
    continue
  fi
  if [[ $fm_rc -eq 4 ]]; then
    fail "$rel" "frontmatter opens with --- but is never closed by a second ---"
    continue
  fi
  checked=$((checked+1))

  # STRUCTURE BEFORE FIELDS. A document whose frontmatter does not hold together is
  # unreadable to every YAML consumer, and the field checks below — sed and grep over
  # lines — cannot see that: they happily find `type:` in a block whose next line has
  # already broken the parse. So this runs first, and a fault here stops the document,
  # the way an unterminated block above does.
  fm_faults="$(fm_wellformed "$fm")"
  if [[ -n "$fm_faults" ]]; then
    while IFS= read -r fault; do
      [[ -n "$fault" ]] && fail "$rel" "malformed frontmatter — $fault"
    done <<< "$fm_faults"
    continue
  fi

  type="$(printf '%s\n' "$fm" | sed -n 's/^type:[[:space:]]*//p' | head -1)"
  if [[ -z "$type" ]]; then
    fail "$rel" "missing required field: type"
    continue
  fi
  case " $KNOWN_TYPES " in
    *" $type "*) : ;;
    *) fail "$rel" "unknown type '$type' (known: $KNOWN_TYPES)" ;;
  esac

  allowed="$(enum_for "$type")"
  if [[ -n "$allowed" ]]; then
    status="$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*#.*//;s/[[:space:]]*$//')"
    if [[ -z "$status" ]]; then
      fail "$rel" "type $type requires a status (one of: $allowed)"
    else
      case " $allowed " in
        *" $status "*) : ;;
        *) fail "$rel" "status '$status' is not valid for type $type (one of: $allowed)" ;;
      esac
    fi
  fi

  if ! printf '%s\n' "$fm" | grep -q '^timestamp:[[:space:]]*[^[:space:]]'; then
    fail "$rel" "missing required field: timestamp"
  fi

  if [[ " $KB_TYPES " == *" $type "* ]]; then
    prov="$(printf '%s\n' "$fm" | sed -n 's/^provenance:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*#.*//;s/[[:space:]]*$//')"
    if [[ -z "$prov" ]]; then
      fail "$rel" "type $type requires provenance (one of: $PROVENANCE_ENUM) — migrate-bundle.sh --apply fills it from git"
    elif [[ " $PROVENANCE_ENUM " != *" $prov "* ]]; then
      fail "$rel" "provenance '$prov' is not one of: $PROVENANCE_ENUM ($AB_SCHEMA, 'provenance:')"
    fi
  fi

  if [[ "$type" == Finding ]]; then
    lines="$(grep -c '' "$file" || true)"
    # `provenance:` and `ledger:` are not the author's to shorten, so neither is counted.
    [[ -z "${prov:-}" ]] || lines=$((lines-1))
    if grep -q '^ledger:' <<<"$fm"; then lines=$((lines-1)); fi
    if [[ -n "$lines" && "$lines" -gt $FINDING_MAX_LINES ]]; then
      warn "$rel" "Finding is $lines lines; $AB_CONVENTIONS 'Write less' caps it at $FINDING_MAX_LINES — the history behind it belongs in the task doc"
    fi
    if ! printf '%s\n' "$fm" | grep -q '^lesson:[[:space:]]*[^[:space:]]'; then
      warn "$rel" "Finding has no one-line 'lesson:' — the takeaway the next agent needs, required by $AB_CONVENTIONS 'Write less'"
    fi
    # `author:` is the GitHub login that filed it. Provenance has to survive a file move,
    # so it is frontmatter and never the path — there are no per-user folders in the KB.
    author="$(printf '%s\n' "$fm" | sed -n 's/^author:[[:space:]]*//p' | head -1 \
              | sed 's/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/')"
    if [[ -n "$author" ]] && ! printf '%s' "$author" | grep -qE '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'; then
      warn "$rel" "author: '$author' is not a GitHub login ($AB_SCHEMA, 'author:')"
    fi
    # The index row, the tags and the supersession edges are build-kb-index.sh's half of
    # the contract; it reads knowledge/index.md, which is not a concept document.
    if printf '%s\n' "$fm" | grep -q '^superseded_by:[[:space:]]*[^[:space:]]' \
       && [[ "$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1)" != superseded ]]; then
      fail "$rel" "carries superseded_by: but status is not 'superseded' — $AB_SCHEMA 'Superseding a Finding' sets both"
    fi
  fi

  if [[ "$type" == Task ]]; then
    n="$(flow_entries "$fm" do_not_repeat)"
    if [[ "$n" -gt $DO_NOT_REPEAT_MAX ]]; then
      warn "$rel" "do_not_repeat carries $n entries; $AB_CONVENTIONS caps it at $DO_NOT_REPEAT_MAX — the project-manager folds the oldest into '# Notes'"
    fi

    # `open_caveats` holds a TERMINAL write only — `done`/`cancelled`. Any other status
    # with a caveat outstanding is the normal working state and stays silent.
    if [[ "$status" == done || "$status" == cancelled ]]; then
      while IFS= read -r caveat; do
        [[ -n "$caveat" ]] || continue
        fail "$rel" "status '$status' is held by an open caveat ($AB_SCHEMA 'open_caveats' — clear it with evidence, in its own edit): $caveat"
      done <<< "$(list_entries "$fm" open_caveats)"
    fi
  fi

  structural="$(refs_for "$fm" 'objective|project|phase|depends_on' '/(objectives|projects|knowledge|agents)/[A-Za-z0-9._/-]+[.]md')"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || fail "$rel" "dangling reference: $ref"
  done <<< "$structural"

  declared="$(refs_for "$fm" 'artifacts' '/projects/[A-Za-z0-9._/-]+[.]md')"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || warn "$rel" "declared artifact does not exist yet: $ref"
  done <<< "$declared"
done <<< "$FILE_LIST"

# knowledge/index.md is DERIVED. A row the generator would not produce is a row somebody
# hand-wrote, and a hand-written row is the conflict magnet the generator exists to remove.
kb_gen="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)/build-kb-index.sh"
if [[ ( ${#NAMED[@]} -eq 0 || $NAMED_INDEX -eq 1 ) && -r knowledge/index.md && -x "$kb_gen" ]]; then
  if ! bash "$kb_gen" --print 2>/dev/null | diff -q - knowledge/index.md >/dev/null 2>&1; then
    warn "knowledge/index.md" "carries rows the generator would not produce — it is derived, never hand-edited."
    ab_say_run "         Regenerate it with:" build-kb-index.sh
    ab_say_run "         Name each row with:" build-kb-index.sh --check
  fi
fi

echo "---"
printf 'validate-bundle: %d documents checked, %d errors, %d warnings.\n' "$checked" "$errors" "$warns"
[[ $errors -eq 0 ]] || exit 1
if [[ $STRICT -eq 1 && $warns -gt 0 ]]; then
  echo "(--strict: warnings are failures)"
  exit 1
fi
exit 0
