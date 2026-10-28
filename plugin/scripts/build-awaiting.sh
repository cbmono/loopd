#!/usr/bin/env bash
#
# build-awaiting.sh — render AWAITING.md. The SCRIPT owns the page's structure; the model
# owns only each row's trailing sentence.
#
#   Usage: build-awaiting.sh [--instance DIR] [--out FILE]
#                            [--trailer <task-path>=<sentence>]...
#                            [--merge   <task-path>=<pr markdown link>]...
#
# Exit: 0 rendered (or no AWAITING.md, which is the off switch) · 2 usage · 3 a path it
# could not read. Why the structure is not prose: docs/pm-design.md#step-8.
#
# `🧰 grant` AND `❓ answer` are different asks, and that is why `grant` has a glyph of
# its own: an `open_questions` entry asking for a tool, an install, a credential or an
# access grant renders as `🧰 **grant**`, never as `❓ **answer**`, and `is_grant()` below
# decides it — never the model. The **reply mechanism is the same** — the human still
# appends ` --- <answer>` to the entry — so the glyph changes what the human is being asked
# to *do*, not how they answer.
#
# Keep the `## 🔴 Awaiting you` heading and the `*` marker followed by one space exactly as
# `row()` renders them — session-banner.sh greps for both literally.
# **A new verb is free; a new marker is not**: the glyph sits AFTER the `* `, which is why
# one writer emits every row and no caller ever composes one.
#
# ROW ORDER IS AN EXECUTION ORDER, read top to bottom, so it is sorted after the walk rather
# than left in glob order: (1) a task's blocker above it, via `depends_on`, transitively
# through tasks that have no row; (2) then grant, unblock, do, answer, review, approve, merge, close, continue;
# (3) then glob order, so an unchanged bundle renders the same page. A cycle or a reference
# to no live task drops only that edge. The sort reorders `row()`'s output and never
# composes or drops a row: a failed sort renders glob order.
#
# A `Q<n>: do: …hand-off <id>…` entry is a stopped role session's HAND-OFF
# (session-handoff.sh): ONE `👉 **do**` row, whose sentence is the agent's own `needs` read
# from the per-clone `$AB_HANDOFFS/<id>.txt` — never from a tracked file — escaped, capped at
# a word boundary, with the PR and run references it names linked. It renders on a done task
# too until it is answered: jobs left for after the merge are the point of it. So does a
# `Q<n>: do: deploy …` entry (reflect-deploy.sh), as its own text and never a hand-off.
#
# A `close` row, like `continue`, renders only where `mine` clears the project.md, so it
# FAILS CLOSED: an `owner:` on a clone with no ownerGithubUser (task-owner.sh 1), or a
# malformed one (2), shows no close row. Nor does a project whose terminal task still shows a
# `👉 do` row: closing it would set `status: done` and drop that row from the page.
# A `👀 review` row — one per unanswered `D<n>` in project.md's `decisions:` — passes the
# same two gates, and sorts before `approve` without withholding it.
#
# GENERIC PLUGIN FILE — no org, repo or path literals.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2
usage() { echo "Usage: $(basename "$0") [--instance DIR] [--out FILE] [--trailer PATH=TEXT]... [--merge PATH=LINK]..." >&2; exit 2; }
fail3() { echo "build-awaiting: $1" >&2; exit 3; }

inst="$PWD"; out=""
trailer_paths=(); trailer_texts=(); merge_paths=(); merge_links=()
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --out)      [ $# -ge 2 ] || usage; out="$2";  shift 2 ;;
    --trailer)  [ $# -ge 2 ] || usage
                case "$2" in *=*) ;; *) usage ;; esac
                trailer_paths+=("${2%%=*}"); trailer_texts+=("${2#*=}"); shift 2 ;;
    --merge)    [ $# -ge 2 ] || usage
                case "$2" in *=*) ;; *) usage ;; esac
                merge_paths+=("${2%%=*}");   merge_links+=("${2#*=}");   shift 2 ;;
    -h|--help)  usage ;;
    *) usage ;;
  esac
done
inst="$(cd "$inst" 2>/dev/null && pwd)" || fail3 "no such instance directory"
[ -n "$out" ] || out="$inst/$AB_AWAITING"

# Resolve every caller-supplied path the same way the walk resolves the ones it finds.
# Without this, `/var/…` and `/private/var/…` are two spellings of one file and a --trailer
# silently does nothing — which looks exactly like the model not having passed one.
norm() { # <path>
  local d; d="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || { printf '%s' "$1"; return; }
  printf '%s/%s' "$d" "$(basename "$1")"
}
for ((_i = 0; _i < ${#trailer_paths[@]}; _i++)); do trailer_paths[$_i]="$(norm "${trailer_paths[$_i]}")"; done
for ((_i = 0; _i < ${#merge_paths[@]};   _i++)); do merge_paths[$_i]="$(norm "${merge_paths[$_i]}")"; done

# ABSENCE IS THE OFF SWITCH, and it is the script's rule rather than the caller's — the
# same shape write-snapshot.sh uses for SNAPSHOT.json. Never create the file.
[ -f "$out" ] || exit 0

fmfirst() { sed -n "s/^$2:[[:space:]]*\([^[:space:]].*\)/\1/p" "$1" | head -n1; }

# Entries of a `key: [ ... ]` flow list, one per line. Delegated rather than re-implemented:
# these lists carry backticks, commas, ` --- ` and square brackets, and a second parser is a
# second place for them to be cut in half. fold-answers.sh owns the one that round-trips.
# A parser failure is NOT an empty list: swallowing it renders a draft as a clean
# `approve` row while its unresolved questions are still on the page. Exit 3 instead.
entries() { # <file> <key>
  bash "$HERE/fold-answers.sh" --list "$1" "$2" 2>/dev/null
}

# The hand-off row's sentence. Agent text is ESCAPED, so it cannot make a link or format
# of its own; the links are ours: `owner/repo#N`, `<known repo>#N` (a `repos/` entry or the
# task's `target_repo`), `PR #N` on the task's repo, and a run id on the repo its own `-R`
# names, else the task's. Nothing inside a URL is linked. No text file ⇒ the entry's own.
handoff_text() { # <entry> <task-file>
  local id tr known
  id="$(printf '%s' "$1" | grep -oE 'hand-off [0-9a-f]{8}-[0-9a-f]{8}' | head -1)"; id="${id#hand-off }"
  tr="$(fmfirst "$2" target_repo)"
  [ -n "$tr" ] || tr="$(fmfirst "$(dirname "$(dirname "$2")")/project.md" target_repo)"
  known="$(ls "$inst/repos" 2>/dev/null | tr '\n' ' ')"
  [ -n "${org+x}" ] || org="$(bash "$HERE/resolve-config.sh" --instance "$inst" org 2>/dev/null)" || org=""
  python3 - "$1" "$tr" "$org" "$known" "$AB_HANDOFFS" "$inst/$AB_HANDOFFS/$id.txt" <<'PY' 2>/dev/null || printf '%s' "$1"
import os, re, sys
entry, tr, org, known, store, path = sys.argv[1:7]
tr = re.sub(r"\s+#.*$", "", tr).strip().strip("\"'")
tr = tr if re.fullmatch(r"[\w.-]+/[\w.-]+", tr) else ""
owner = tr.split("/")[0] if tr else org
known = set(known.split()) | ({tr.split("/")[1]} if tr else set())
try:
    text = open(path, encoding="utf-8").read().strip()
except OSError:
    text = ""
if not text:
    print(re.sub(r"([\\`*_\[\]()<>|~!#])", r"\\\1", entry), end=""); sys.exit(0)
tail = ""
if len(text) > 400:
    cut = text.rfind(" ", 0, 400)
    text = text[:cut if cut > 0 else 400]
    tail = " … (truncated, full text: `%s/%s`)" % (store, os.path.basename(path))
esc = lambda x: re.sub(r"([\\`*_\[\]()<>|~!#])", r"\\\1", x)
TOK = re.compile(r"(?P<url>https?://[^\s<>]+)"
                 r"|(?<![\w./#@-])(?:(?P<own>[A-Za-z0-9][\w.-]*)/)?(?P<repo>[A-Za-z][\w.-]*)#(?P<n>\d+)\b"
                 r"|\bPR #?(?P<pr>\d+)\b"
                 r"|\b(?P<verb>run(?: rerun| view| watch)?) (?P<run>\d{6,})\b")
out, pos = [], 0
for m in TOK.finditer(text):
    out.append(esc(text[pos:m.start()])); pos = m.end(); g = m.group
    if g("repo") and (g("own") or g("repo") in known) and (g("own") or owner):
        o = g("own") or owner
        out.append("[%s#%s](https://github.com/%s/%s/pull/%s)" % (g("repo"), g("n"), o, g("repo"), g("n")))
    elif g("pr") and tr:
        out.append("PR [%s#%s](https://github.com/%s/pull/%s)" % (tr.split("/")[1], g("pr"), tr, g("pr")))
    elif g("run"):
        # Its OWN command's `-R` only: the rest of this command, up to the next `gh `,
        # `;` or `then` — never a later command's.
        own = re.split(r"\bgh |;|\bthen\b", text[m.end():], maxsplit=1)[0]
        r = re.search(r"(?:-R|--repo)[ =]([\w.-]+/[\w.-]+)", own)
        rr = r.group(1) if r else tr
        out.append(esc(g("verb")) + " " + ("[%s](https://github.com/%s/actions/runs/%s)" % (g("run"), rr, g("run")) if rr else g("run")))
    else:
        out.append(esc(m.group(0)))
out.append(esc(text[pos:]))
q = re.match(r"(Q\d+):", entry)
print("".join(out) + tail + (" · then answer %s `done`" % q.group(1) if q else ""), end="")
PY
}

handoffs_of() { # <file> <rel> <title> -> one 👉 row per unanswered hand-off or deploy entry
  local e
  while IFS= read -r e; do
    case "$e" in
      *' --- '*) continue ;;
      Q[0-9]*': do: deploy '*) add "👉" do "$3" "$2" "$e" ;;
      Q[0-9]*': do: '*'hand-off '*) add "👉" do "$3" "$2" "$(handoff_text "$e" "$1")" ;;
    esac
  done <<EOF
$(entries "$1" open_questions || true)
EOF
}

title_of() { # <file>
  local t; t="$(fmfirst "$1" title)"
  t="${t%\"}"; t="${t#\"}"
  [ -n "$t" ] && printf '%s' "$t" || basename "$1" .md
}

# THE GLYPH IS NEVER THE MODEL'S. A question asking for a tool, an install, a credential or
# an access grant is a `grant`; everything else is an `answer`. Classified from the entry
# itself so the two asks cannot drift apart across ticks.
is_grant() { # <entry text>
  printf '%s' "$1" | grep -qiE '\b(install|grant|credential|token|access|api key|permission|enable the|tool)\b'
}

# On a shared instance the queue narrows to what THIS clone's human can decide. Exit 0 is
# the only clearance, exactly as the dispatch gate reads it; a missing script is a
# single-human instance and clears.
mine() { # <task-path>
  [ -f "$HERE/task-owner.sh" ] || return 0
  # From the instance root: task-owner.sh refuses anywhere else (exit 2), and a refusal
  # caused by the caller's cwd would silently empty the queue.
  ( cd "$inst" && bash "$HERE/task-owner.sh" "$1" ) >/dev/null 2>&1
}

# A paused project keeps its `merge` rows and nothing else: only the human merges, and a PR
# that finished during the pause must not wait for the resume. Exit 1 is the only skip.
paused() { # <path under projects/<slug>/>
  [ -f "$HERE/project-paused.sh" ] || return 1
  ( cd "$inst" && bash "$HERE/project-paused.sh" "$1" ) >/dev/null 2>&1
  [ $? -eq 1 ]
}

lookup() { # <path> <"trailer"|"merge">  -> prints the value, or nothing
  local p="$1" kind="$2" i n
  if [ "$kind" = trailer ]; then
    n=${#trailer_paths[@]}
    for ((i = 0; i < n; i++)); do
      [ "${trailer_paths[$i]}" = "$p" ] && { printf '%s' "${trailer_texts[$i]}"; return; }
    done
  else
    n=${#merge_paths[@]}
    for ((i = 0; i < n; i++)); do
      [ "${merge_paths[$i]}" = "$p" ] && { printf '%s' "${merge_links[$i]}"; return; }
    done
  fi
}

# A row is `* <glyph> **<verb>** — [<title>](<link>) · <trailer>` and nothing else. One
# writer for every row, so a new verb cannot arrive with a new marker: session-banner.sh
# greps the `* ` literally.
row() { printf '* %s **%s** — [%s](%s) · %s\n' "$1" "$2" "$3" "$4" "$5"; }

row_txt=(); row_node=(); row_sev=(); row_design=(); cur_design=""
node_lines=""; node=0
sev_of() { case "$1" in grant) echo 0 ;; unblock) echo 1 ;; do) echo 2 ;; answer) echo 3 ;; review) echo 4 ;;
                        approve) echo 5 ;; merge) echo 6 ;; close) echo 7 ;; continue) echo 8 ;; *) echo 9 ;; esac; }
add() { row_txt+=("$(row "$@")"); row_node+=("$node"); row_sev+=("$(sev_of "$2")")
        [ "$2" = approve ] && row_design+=("$cur_design") || row_design+=(""); }
# A live task becomes a sort node whether or not it renders a row, so an edge through an
# in-progress or other-owner task still orders what it separates.
add_node() { # <file> <rel> <slug>
  node=$((node + 1))
  local b; b="$(basename "$2" .md)"
  node_lines="${node_lines}N	$node	$3	$b	$2
"
  [ "$2" = "${2#/projects/*/tasks/}" ] && return
  local d
  # Unparsable `depends_on` is no edge, not a failed render: ordering is the only casualty.
  while IFS= read -r d; do
    [ -n "$d" ] && node_lines="${node_lines}D	$node	$d
"
  done <<EOF
$(entries "$1" depends_on || true)
EOF
}

# The default trailers, assigned rather than inlined: a backtick or an apostrophe inside a
# `${x:-…}` default is re-parsed by the shell and the script will not even load.
DEF_APPROVE='refined & clean, promote `draft → ready`'
DEF_UNBLOCK='blocked — see the task’s `# Notes`'
DEF_CLOSE='all tasks terminal → `/close-project '

# The `continue` row's sentence is the script's, not the model's: it carries the one line the
# human pastes to answer, and a per-tick rewording would lose it.
due="$(bash "$HERE/continue-checkpoint.sh" --instance "$inst" 2>/dev/null)" || due=""

for pm in "$inst"/projects/*/project.md; do
  [ -f "$pm" ] || continue
  [ -r "$pm" ] || fail3 "cannot read $pm"
  [ "$(fmfirst "$pm" status)" = done ] && continue
  slug="$(basename "$(dirname "$pm")")"
  ntask=0; nterm=0; owed=0
  held=0; paused "$pm" && held=1
  cur_design=""; [ -f "$(dirname "$pm")/design.md" ] && cur_design="${pm%project.md}design.md" && cur_design="${cur_design#"$inst"}"

  for f in "$(dirname "$pm")"/tasks/*.md; do
    [ -f "$f" ] || continue
    [ -r "$f" ] || fail3 "cannot read $f"
    rel="${f#"$inst"}"
    st="$(fmfirst "$f" status)"; st="${st%% *}"
    ntask=$((ntask + 1))
    case "$st" in
      done|cancelled)
        nterm=$((nterm + 1))
        if grep -qE 'hand-off |: do: deploy ' "$f" && mine "$f"; then
          n0=${#row_txt[@]}; add_node "$f" "$rel" "$slug"; handoffs_of "$f" "$rel" "$(title_of "$f")"
          [ "${#row_txt[@]}" -gt "$n0" ] && owed=1
        fi
        continue ;;
    esac
    add_node "$f" "$rel" "$slug"
    mine "$f" || continue
    t="$(title_of "$f")"
    trail="$(lookup "$f" trailer)"; [ -n "$trail" ] || trail="$(lookup "$rel" trailer)"
    mlink="$(lookup "$f" merge)"; [ -n "$mlink" ] || mlink="$(lookup "$rel" merge)"
    if [ "$held" = 1 ]; then
      [ -n "$mlink" ] && add "🔀" merge "$t" "$rel" "${trail:-$mlink}"
      continue
    fi

    # UNANSWERED questions only: an entry carrying ` --- ` is answered and belongs to
    # step 2's fold, not to the human's queue.
    qs=""; qn=0
    qlist="$(entries "$f" open_questions)" || fail3 "cannot read open_questions in $rel"
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      case "$e" in *' --- '*) continue ;; esac
      qn=$((qn + 1))
      case "$e" in
        Q[0-9]*': do: deploy '*) add "👉" do "$t" "$rel" "$e"; continue ;;
        Q[0-9]*': do: '*'hand-off '*) add "👉" do "$t" "$rel" "$(handoff_text "$e" "$f")"; continue ;;
      esac
      is_grant "$e" && { add "🧰" grant "$t" "$rel" "${trail:-$e}"; continue; }
      qs="${qs:+$qs; }$e"
    done <<EOF
$qlist
EOF
    [ -n "$qs" ] && add "❓" answer "$t" "$rel" "${trail:-$qs}"

    [ -n "$mlink" ] && add "🔀" merge "$t" "$rel" "${trail:-$mlink}"

    case "$st" in
      draft)
        # A draft with questions is already queued above as answer/grant; only a CLEAN
        # refined draft is the human's promote.
        crit="$(entries "$f" acceptance_criteria)" || fail3 "cannot read acceptance_criteria in $rel"
        if [ "$qn" = 0 ] && [ -n "$crit" ]; then
          add "✅" approve "$t" "$rel" "${trail:-$DEF_APPROVE}"
        fi ;;
      blocked)
        add "⛔" unblock "$t" "$rel" "${trail:-$DEF_UNBLOCK}" ;;
    esac
  done

  if [ "$held" = 0 ] && grep -q '^decisions:' "$pm" && mine "$pm"; then
    dlist="$(entries "$pm" decisions)" || fail3 "cannot read decisions in ${pm#"$inst"}"
    add_node "$pm" "${pm#"$inst"}" "$slug"
    while IFS= read -r e; do
      case "$e" in D[0-9]*:*) ;; *) continue ;; esac
      case "$e" in *' --- '*[![:space:]]*) [ -n "$(printf '%s' "${e##* --- }" | tr -d '[:space:]')" ] && continue ;; esac
      add "👀" review "$(title_of "$pm")" "${pm#"$inst"}" "$e"
    done <<EOF
$dlist
EOF
  fi

  if [ "$held" = 0 ] && [ "$owed" = 0 ] && [ "$ntask" -gt 0 ] && [ "$ntask" = "$nterm" ] && mine "$pm"; then
    add_node "$pm" "${pm#"$inst"}" "$slug"
    pt="$(title_of "$pm")"; ptrail="$(lookup "$pm" trailer)"
    add "🏁" close "$pt" "${pm#"$inst"}" "${ptrail:-$DEF_CLOSE$slug\`}"
  fi

  ck="$(printf '%s\n' "$due" | awk -F'\t' -v p="${pm#"$inst"}" '$1 == p { print; exit }')"
  if [ -n "$ck" ] && [ "$held" = 0 ] && mine "$pm"; then
    IFS=$'\t' read -r _ ckwho ckwhy ckrec <<EOF
$ck
EOF
    add_node "$pm" "${pm#"$inst"}" "$slug"
    add "⏳" continue "$(title_of "$pm")" "${pm#"$inst"}" \
      "$ckwho: should this continue? $ckwhy · yes ⇒ add \`continued: $ckrec\` to project.md · no ⇒ pause or close it"
  fi
done

order_rows() { # -> row indexes, one per line, in render order
  local i
  { printf '%s' "$node_lines"
    for ((i = 0; i < ${#row_txt[@]}; i++)); do
      printf 'R\t%s\t%s\t%s\n' "$i" "${row_node[$i]}" "${row_sev[$i]}"
    done
  } | awk -F'\t' '
    $1 == "N" { slug[$2] = $3; base[$2] = $4; rel[$2] = $5; nodes[++nn] = $2; next }
    $1 == "D" { dep[$2, ++nd[$2]] = $3; next }
    $1 == "R" { r = $2; rnode[r] = $3; rsev[r] = $4; rows[++nr] = r; nrows[$3]++; next }
    function resolve(d, e,   k, n, hits) {   # edges blocker -> dependent e
      gsub(/^[ \t]+|[ \t]+$/, "", d)
      if (d ~ /\//) {
        if (d !~ /^\//) d = "/" d
        if (d !~ /\.md$/) d = d ".md"
        for (k = 1; k <= nn; k++) if (rel[nodes[k]] == d) addedge(nodes[k], e)
        return
      }
      sub(/\.md$/, "", d)
      if (d == "") return
      for (k = 1; k <= nn; k++) {
        n = nodes[k]
        if (slug[n] == slug[e] && (base[n] == d || index(base[n], d "-") == 1)) addedge(n, e)
      }
    }
    function addedge(b, e) { if (!((b, e) in edge)) { edge[b, e] = 1; out[b, ++no[b]] = e } }
    END {
      for (k = 1; k <= nn; k++) { e = nodes[k]; for (j = 1; j <= nd[e]; j++) resolve(dep[e, j], e) }
      # reach[s, t]: t is reachable from s. An edge whose dependent reaches its blocker is
      # inside a cycle, and is dropped.
      for (k = 1; k <= nn; k++) {
        s = nodes[k]; h = 0; t = 0
        for (j = 1; j <= no[s]; j++) { x = out[s, j]; if (!((s, x) in reach)) { reach[s, x] = 1; q[++t] = x } }
        while (h < t) {
          y = q[++h]
          for (j = 1; j <= no[y]; j++) { x = out[y, j]; if (!((s, x) in reach)) { reach[s, x] = 1; q[++t] = x } }
        }
      }
      for (k in edge) { split(k, p, SUBSEP); if (!((p[2], p[1]) in reach)) { kept[p[1], p[2]] = 1; blockers[p[2]]++ } }
      # A task is cleared once every row of it and every blocker of it has rendered; a row
      # is free once every blocker of its task is cleared. Of the free rows, the smallest
      # (severity, glob position) renders next.
      left = nr
      while (left > 0) {
        do {
          moved = 0
          for (k = 1; k <= nn; k++) {
            n = nodes[k]
            if (!(n in cleared) && nrows[n] + 0 == 0 && waiting(n) == 0) { cleared[n] = 1; moved = 1
              for (j = 1; j <= no[n]; j++) if ((n, out[n, j]) in kept) pend[out[n, j]]++ }
          }
        } while (moved)
        best = ""
        for (j = 1; j <= nr; j++) {
          r = rows[j]
          if (r in done || waiting(rnode[r]) > 0) continue
          if (best == "" || rsev[r] + 0 < rsev[best] + 0 || (rsev[r] + 0 == rsev[best] + 0 && r + 0 < best + 0)) best = r
        }
        if (best == "") for (j = 1; j <= nr; j++) if (!(rows[j] in done)) { best = rows[j]; break }
        print best; done[best] = 1; nrows[rnode[best]]--; left--
      }
    }
    function waiting(n) { return blockers[n] - pend[n] }
  '
}

# Never drop a row and never print one twice: anything the sort did not return exactly
# once, in range, renders in glob order instead.
rows=""
ord="$(order_rows 2>/dev/null)" || ord=""
nrow=${#row_txt[@]}
if [ "$(printf '%s\n' "$ord" | grep -cE '^[0-9]+$')" != "$nrow" ] \
   || [ "$(printf '%s\n' "$ord" | grep -E '^[0-9]+$' | sort -un | awk -v n="$nrow" '$1 < n' | wc -l | tr -d ' ')" != "$nrow" ]; then
  ord="$(seq 0 $((nrow - 1)) 2>/dev/null)"
fi
[ "$nrow" -gt 0 ] || ord=""
linked=" "
while IFS= read -r i; do
  [ -n "$i" ] || continue
  dz="${row_design[$i]}"
  # One design link per project: its first promote row in render order, never again.
  if [ -n "$dz" ] && [ "${linked#* "$dz" }" = "$linked" ]; then
    rows="$rows${row_txt[$i]} · [design]($dz)
"; linked="$linked$dz "
  else
    rows="$rows${row_txt[$i]}
"
  fi
done <<EOF
$ord
EOF

n="$(printf '%s' "$rows" | grep -c '^\* ' || true)"
body="$rows"
[ "$n" -gt 0 ] || body="_None._
"

tmp="$out.tmp.$$"
{
  printf '# Awaiting you\n\n'
  printf 'Derived and gitignored — **do not hand-edit**. Rewritten from `projects/*/tasks/*.md`\n'
  printf 'by each dispatch tick that changed something. Set "awaiting": false in instance.config.json to turn the queue off.\n'
  printf 'Last refreshed: %s.\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '## 🔴 Awaiting you (%s)\n' "$n"
  printf '%s' "$body"
} > "$tmp" || { rm -f "$tmp"; fail3 "cannot write beside $out"; }
mv "$tmp" "$out" || { rm -f "$tmp"; fail3 "cannot replace $out"; }
echo "awaiting: $n item(s) -> $out"
