#!/usr/bin/env bash
# board-simple.test.sh — build-board.sh's simple mode, asserted on a rendered fixture
# (tests/fixtures/simple-board/mk.sh): default view, inbox order, rail, filters, keys,
# glossary, runs-nothing, brand, type and shape. Layout facts a grep cannot see (computed
# heights, rail position) were measured in a browser for the PR; here their CSS is pinned.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$TPL/plugin/scripts/build-board.sh"
WRITER="$TPL/plugin/scripts/write-snapshot.sh"
. "$TPL/plugin/scripts/bundle-paths.sh"
command -v python3 >/dev/null 2>&1 || { echo "  (python3 absent — skipped)"; echo "pass=0 fail=0"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-simple.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }
has() { grep -qF -- "$1" "$2" && echo yes || echo no; }

D="$TMP/bundle"
bash "$TPL/tests/fixtures/simple-board/mk.sh" "$D" || { echo "fixture failed"; exit 2; }
PAGE="$TMP/board.html"
( cd "$D" && bash "$GEN" --standalone --out "$PAGE" . ) >/dev/null 2>&1

# One python reader: the simple section's markup, its visible text, the CSS and the script.
part() { # <simple|text|css|script|order|chips|seams>
  python3 - "$PAGE" "$1" <<'PY'
import html.parser, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
a = page.index('<section class="simple"'); b = page.index('</section>', a)
simple = page[a:b]
what = sys.argv[2]
if what == "simple": print(simple)
elif what == "text":
    class T(html.parser.HTMLParser):
        out, skip = [], 0
        def handle_starttag(self, t, _a): self.skip += t in ("script", "style")
        def handle_endtag(self, t): self.skip -= t in ("script", "style")
        def handle_data(self, d):
            if not self.skip: self.out.append(d)
    p = T(); p.feed(simple); print(" ".join(p.out))
elif what == "css": print(page.split("<style>", 1)[1].split("</style>", 1)[0])
elif what == "script": print(re.search(r"<script>(.*?)</script>", page, re.S).group(1))
elif what == "order":
    print(" ".join(m.group(2) or m.group(1) for m in re.finditer(
        r'class="(s-confirms|s-stuck you|s-stuck quiet|s-q)"(?: data-ref="[^"]*" data-code="([^"]*)")?', simple)))
elif what == "chips":
    print(" | ".join(re.findall(r'class="s-chip[^"]*" data-pickf="[a-z]+">([^<]*)</button>', simple)))
elif what == "seams":
    print(" ".join(str(simple.count('data-fill="%s"' % k)) for k in ("q-text", "q-options", "q-depths", "p-need", "p-success")),
          page[page.index('<div class="loopd">'):].count('data-fill="q-text"'))
PY
}
CSS="$TMP/css"; part css > "$CSS"; JS="$TMP/js"; part script > "$JS"

echo "== SIMPLE BY DEFAULT =="
ok "both views are on the page, today's board inside .details" "$(has '<div class="loopd">
<div class="details"><div class="board" data-tab="all">' "$PAGE")" yes
ok "…and simple mode shows first"                 "$(has '.simple{order:-1;' "$CSS")" yes
ok "today's board is hidden unless Show details chose it" "$(has 'html[data-js] .loopd:not([data-view="details"]) .details,' "$CSS")" yes
ok "the script opens on the simple view"          "$(has "root.setAttribute('data-view','simple')" "$JS")" yes
ok "a drawer's Show details names its project"    "$(has 'data-details="invoices">Show details for the technical team' "$PAGE")" yes
ok "…and the details view filters on that project" "$(has "'/close-project '+slug" "$JS")" yes

echo "== INBOX AND RAIL =="
ok "inbox order: confirmations, questions oldest first, stuck you, stuck quiet" \
  "$(part order)" "s-confirms Q12 Q13 Q14 s-stuck you s-stuck quiet"
ok "only the first question is open"              "$(has '.s-qlist>.s-q:not(:first-child) :is(.s-after,[data-fill="q-options"],.s-ctx,.s-own,.s-acts,.s-qnone){display:none}' "$CSS")" yes
ok "the rail is 290px on the right"               "$(has '.s-grid{display:grid;grid-template-columns:minmax(0,1fr) 290px;' "$CSS")" yes
ok "under 820px the rail goes below"              "$(python3 -c 'import re,sys; c=open(sys.argv[1]).read(); m=re.search(r"@media \(max-width:820px\)\{(.*?)\n\}", c, re.S); print(bool(m and ".s-grid{grid-template-columns:minmax(0,1fr)}" in m.group(1)))' "$CSS")" True
ok "the rail keeps creation order"                "$(part simple | grep -oE 'class="s-rrow" data-drawer="[a-z]+"' | sed 's/.*="//;s/"//' | tr '\n' ' ')" "news invoices calendar supplier "
ok "an all-draft project is getting ready"        "$(part simple | grep -c 'Supplier onboarding</span><span class="s-right">getting ready…')" 1
ok "the seams moved into simple mode, once each"  "$(part seams)" "3 3 3 5 5 3"

echo "== FILTERS =="
ok "four filters, Everything first"               "$(part chips)" "Everything | Needs you · 4 | Active · 4 | Finished · 1"
ok "Everything is the default"                    "$(has '<section class="simple" data-filter="all"' "$PAGE")" yes
for w in localStorage sessionStorage document.cookie pushState replaceState; do
  ok "the script writes nothing: no $w"           "$(has "$w" "$JS")" no
done

echo "== KEYS AND TARGETS =="
for k in "/^[1-9]\$/.test(k)" "k==='Enter'" "k==='?'" "k==='l'||k==='L'" "k==='n'||k==='N'" "k==='Escape'"; do
  ok "a shortcut: $k"                             "$(has "$k" "$JS")" yes
done
ok "every control is 44px tall under 820px"      "$(has '.simple button,.s-q [data-fill="q-options"] li,.simple input,.simple textarea{min-height:44px}' "$CSS")" yes

echo "== COPY AND GLOSSARY =="
WORDS="$(sed -n '/^Simple mode never shows these words/,/^$/p' "$TPL/docs/operations.md" | grep -oE '`[^`]+`' | tr -d '`' | grep -v -e board-simple -e COPY.md)"
ok "the glossary list was read"                   "$(printf '%s\n' "$WORDS" | grep -c .)" 18
glossary_hits() { # <text file> -> the glossary words found, whole-word
  python3 - "$1" "$WORDS" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
print(" ".join(w for w in sys.argv[2].split() if re.search(r"(?<![\w.])%s(?![\w])" % re.escape(w), t, re.I)))
PY
}
part text > "$TMP/text"
ok "simple mode shows none of them"               "$(glossary_hits "$TMP/text")" ""
printf 'Your PR is in review\n' > "$TMP/planted"
ok "…while the same scan finds a planted one"     "$(glossary_hits "$TMP/planted")" "PR review"
ok "COPY.md: Write my own answer… (added by the script)" "$(has "'Write my own answer…'" "$JS")" yes
for c in "Your own answer" "Send answer" "More context" "Later" "Send my answer" "Back to options" \
         "That's everything we know about this question." "Nothing for you to do, we're on it." "Show details ›" \
         "Click a project to open it" "New project" "Start the project" "How you'll know it's finished." \
         "Tell us how you'll know it's done. One sentence is enough." "2 more after this"; do
  ok "COPY.md: $c"                                "$(has "$c" "$TMP/text")" yes
done
ok "Recommended tags the recommended option"      "$(has 'li[data-rec]::after{content:"Recommended"' "$CSS")" yes

echo "== RUNS NOTHING =="
for w in "fetch(" XMLHttpRequest sendBeacon WebSocket EventSource "window.open" "location=" ".submit("; do
  ok "the script makes no request: no $w"         "$(has "$w" "$JS")" no
done
for h in fonts.googleapis.com fonts.gstatic.com "<link"; do
  ok "the page loads no webfont: no $h"           "$(has "$h" "$PAGE")" no
done
ok "…the stacks name Inter and JetBrains Mono first, then system fonts" \
  "$(has "font:400 15px/1.55 'Inter',system-ui,sans-serif" "$PAGE")$(has "'JetBrains Mono',ui-monospace,Menlo,monospace" "$PAGE")" yesyes
ok "the form has no action and no method"         "$(part simple | grep -cE '<form[^>]*(action|method)=')" 0
ok "an answer shows the /loopd:answer command on the task's path" "$(has "c='/loopd:answer projects/'+r[0]+'/tasks/'+r[1]+'.md'" "$JS")" yes
ok "…built from the card's own ref"               "$(has '<article class="s-q" data-ref="news/task-003/Q12" data-code="Q12"' "$PAGE")" yes

echo "== ONE BRAND, TYPE AND SHAPE =="
SCSS="$TMP/scss"; sed -n '/SIMPLE MODE: the default view/,/prefers-reduced-motion/p' "$CSS" > "$SCSS"
ok "simple mode draws no hex of its own"          "$(grep -cE '#[0-9a-fA-F]{3,8}\b' "$SCSS")" 0
ok "the light theme follows prefers-color-scheme" "$(python3 -c 'import re,sys; c=open(sys.argv[1]).read(); m=re.search(r"@media \(prefers-color-scheme:light\)\{:root\{(.*?)\}\}", c, re.S); print(bool(m and "--pink-tint" in m.group(1) and "--signal-soft-text:#c2337f" in m.group(1)))' "$CSS")" True
ok "section labels: JetBrains Mono 11px, .12em"   "$(has ".s-label{font:700 11px/1.4 'JetBrains Mono',ui-monospace,Menlo,monospace;
  letter-spacing:.12em;" "$SCSS")" yes
ok "codes are JetBrains Mono"                     "$(has ".s-code{font:700 12px/1.4 'JetBrains Mono'" "$SCSS")" yes
ok "UI is Inter"                                  "$(has ".simple button{font-family:'Inter'" "$SCSS")" yes
ok "buttons outlined, radius 10"                  "$(tr -d '\n' < "$SCSS" | grep -c 'border:1px solid var(--line-2);border-radius:10px')" 1
ok "cards radius 12"                              "$(tr -d '\n' < "$SCSS" | grep -oE '\.s-(q|stuck)\{[^}]*border-radius:12px' | wc -l | tr -d ' ')" 2
ok "chips radius 999"                             "$(tr -d '\n' < "$SCSS" | grep -c '\.s-chip{[^}]*border-radius:999px')" 1

echo "== ESCAPING =="
mkdir -p "$D/projects/evil/tasks"
printf -- '---\ntype: Project\ntitle: "<img src=x onerror=alert(1)> & co"\nkind: build\nstatus: active\n---\n' > "$D/projects/evil/project.md"
printf -- '---\ntype: Task\ntitle: "<b>bold</b> blocker"\nkind: build\nstatus: blocked\n---\n' > "$D/projects/evil/tasks/task-001.md"
( cd "$D" && SNAPSHOT_NOW=2026-10-18T09:00:00Z bash "$WRITER" --quiet && bash "$GEN" --standalone --out "$PAGE" . ) >/dev/null 2>&1
ok "a hostile project title is escaped"           "$(part simple | grep -c '<img src=x')" 0
ok "…and still shown"                             "$(part simple | grep -c '&lt;img src=x onerror=alert(1)&gt; &amp; co' | awk '{print ($1>0)}')" 1
ok "a hostile task title is escaped"              "$(part simple | grep -c '<b>bold</b>')" 0

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
