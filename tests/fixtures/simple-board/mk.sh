#!/usr/bin/env bash
# mk.sh <dir> — a bundle shaped like Web Board Simple.dc.html's 4m state, in plain words.
set -euo pipefail
D="$1"; R="$(cd "$(dirname "$0")/../../.." && pwd)"
. "$R/plugin/scripts/bundle-paths.sh"
mkdir -p "$D/$AB_DIR"; : > "$D/$AB_SCHEMA"
printf '{ "org": "fixture-org" }\n' > "$D/instance.config.json"
proj() { # <slug> <title> <description> <need> <success>
  mkdir -p "$D/projects/$1/tasks"
  printf -- '---\ntype: Project\ntitle: %s\nkind: build\nstatus: active\ndescription: "%s"\nneed: "%s"\nsuccess_criteria: [ "%s" ]\ntimestamp: 2026-09-1%sT00:00:00Z\n---\n' \
    "$2" "$3" "$4" "$5" "$(ls "$D/projects" | wc -l | tr -d ' ')" > "$D/projects/$1/project.md"; }
task() { # <slug> <id> <status> <title> [<extra frontmatter>] [<body>]
  printf -- '---\ntype: Task\ntitle: %s\nkind: build\nstatus: %s\n%s---\n%s' "$4" "$3" "${5:-}" "${6:-}" \
    > "$D/projects/$1/tasks/$2.md"; }
proj news "Newsletter signup" "A signup box on our website that adds people to our monthly newsletter." \
  "People who visit our website and want to hear about new products." "Every new signup gets the next newsletter"
task news task-001 done "Signup box on the home page"
task news task-002 done "Store each new address"
task news task-003 in-progress "Confirmation email" \
  $'timestamp: 2026-09-01T00:00:00Z\nopen_questions: [ "Q12: Should new subscribers confirm their email before they join the list?" ]\n' \
  $'\n## Question details\n\n### Q12\nRecommendation: Yes, send a confirmation email first\nOptions:\n1. Yes, send a confirmation email first\n2. No, add them to the list straight away\nContext:\n- Depth 1: Confirming means your list only has real addresses that want your emails.\n- Depth 2: Without it, anyone can sign up someone else, and mistyped addresses stay on the list.\n- Depth 3: Email services watch how often your messages bounce. A list full of wrong addresses can push your newsletter into spam folders for everyone.\n'
task news task-004 ready "Welcome email" \
  $'timestamp: 2026-09-02T00:00:00Z\nopen_questions: [ "Q13: What should the welcome email say?" ]\n' \
  $'\n## Question details\n\n### Q13\nRecommendation: A short thank-you with a link to the latest issue\nOptions:\n1. Just a short thank-you\n2. A short thank-you with a link to the latest issue\n3. A thank-you and a discount code\n'
proj invoices "Invoice reminders" "Friendly reminders for unpaid invoices." "Our finance team." "Every late invoice gets one reminder"
task invoices task-001 done "Find unpaid invoices"
task invoices task-002 blocked "Reminders can't be sent until the company email account is connected"
task invoices task-003 draft "First reminder" \
  $'timestamp: 2026-09-03T00:00:00Z\nopen_questions: [ "Q14: When should the first reminder go out?" ]\n'
proj calendar "Team holiday calendar" "One calendar for everyone's time off." "The whole team." "Everyone books time off in one place"
task calendar task-001 done "Calendar page"
task calendar task-002 done "Time-off form"
task calendar task-003 in-review "Calendar sync" $'pr_mergeable: CONFLICTING\n'
proj supplier "Supplier onboarding" "Collect what we need from a new supplier." "Our buyers." "Every supplier is set up before the first order"
task supplier task-001 draft "Supplier form"
proj contact "Website contact form" "A contact form on the website." "Visitors." "Every message reaches the shared inbox"
task contact task-001 done "Contact form"
: > "$D/$AB_SNAPSHOT"
( cd "$D" && SNAPSHOT_NOW=2026-10-18T09:00:00Z bash "$R/plugin/scripts/write-snapshot.sh" --quiet )
