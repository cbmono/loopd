import { expect, mock, test } from 'claude-code/testing'

// Run from this directory: `claude plugin test`. No session, no sign-in, no network, no
// file: the two files the mod reads are answered by stubs on fs.exists / fs.stat / fs.read.
// Each test starts with the module freshly loaded, so `kind` is 'unread'.

const CWD = '/work/_loopd-example'
const CONFIG = CWD + '/instance.config.json'
const SNAPSHOT = CWD + '/.loopd/SNAPSHOT.json'
const PANE_ID = 'loopd-board'

// What Claude Code passes a ui.render hook for this pane, apart from the surface.
const PANE = {
  plugin: 'loopd-mod-pane',
  component: 'Pane',
  requestId: PANE_ID,
  viewport: { columns: 140, rows: 40, isFullscreen: true },
  props: {
    title: 'loopd board',
    isFocused: true,
    bodyColumns: 100,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

// A snapshot of the shape write-snapshot.sh emits (its header is the field list).
const SNAP = {
  _schema: 'ai-bridge board snapshot v1',
  group: 'example',
  generated_at: '2026-10-08T01:02:03Z',
  counts: { projects: 2, tasks: 4, awaiting: 3 },
  projects: [
    {
      slug: 'alpha', title: 'Alpha project', description: 'never drawn', kind: 'build', status: 'active',
      autonomy: 'gated', owner: 'example-user-007', awaiting_close: false,
      phase_progress: { done: 1, total: 3 }, phases: [], deliverable_paths: [],
      tasks: [
        { id: 'task-001', title: 'Ship the widget', kind: 'build', status: 'in-progress', assignee: 'software-engineer',
          phase: '', in_flight: true, pr_mergeable: 'UNKNOWN', awaiting: '', open_questions: 0, open_question_ids: [],
          advisor_notes: 0, depends_on: [], prs: [{ repo: 'o/r', number: 7, url: 'https://github.com/o/r/pull/7' }] },
        { id: 'task-002', title: 'Decide the colour', kind: 'build', status: 'draft', assignee: '',
          phase: '', in_flight: false, pr_mergeable: 'UNKNOWN', awaiting: 'answer', open_questions: 2, open_question_ids: ['Q1', 'Q2'],
          advisor_notes: 0, depends_on: [], prs: [] },
        { id: 'task-003', title: 'Merge me', kind: 'build', status: 'in-review', assignee: 'software-engineer',
          phase: '', in_flight: false, pr_mergeable: 'MERGEABLE', awaiting: 'merge', open_questions: 0, open_question_ids: [],
          advisor_notes: 0, depends_on: [], prs: [{ repo: 'o/r', number: 8, url: 'https://github.com/o/r/pull/8' }] },
      ],
    },
    {
      slug: 'beta', title: 'Beta research', description: 'never drawn', kind: 'research', status: 'active',
      autonomy: 'gated', owner: '', awaiting_close: true,
      phase_progress: { done: 2, total: 2 }, phases: [], deliverable_paths: [],
      tasks: [
        { id: 'task-001', title: 'Done already', kind: 'research', status: 'done', assignee: 'cataloguer',
          phase: '', in_flight: false, pr_mergeable: 'UNKNOWN', awaiting: '', open_questions: 0, open_question_ids: [],
          advisor_notes: 0, depends_on: [], prs: [] },
      ],
    },
  ],
}

type World = {
  files: Map<string, { text: string; mtimeMs: number }>
  logged: string[]
  submitted: unknown[]
  prompted: unknown[]
  reads: number
  opened: number
  registered: string[]
  onRun?: (e: any) => void
  failReads?: Set<string>
}

// Every stub the mod's hooks can reach, registered before the first call on `$`.
// `placed` is what the surface answers $.ui.open with: false is a terminal too narrow.
// `hold` makes the dispatch run stay in flight until the test lets it go (a mock-clock sleep).
function stubs(on: any, w: World, placed = true, hold?: () => Promise<void>) {
  on('session.start', () => ({ cwd: CWD }))
  on('command.register', (_$: any, e: any) => { w.registered.push(e.name); return { value: undefined } })
  on('session.cwd', () => ({ value: CWD }))
  on('ui.log', (_$: any, e: any) => { w.logged.push(e.text); return { value: undefined } })
  on('ui.open', () => { w.opened += 1; return { value: placed ? { isPlaced: true } : { isPlaced: false, reason: 'the terminal is 80 columns' } } })
  on('ui.close', () => ({}))
  // Tick runs the dispatch COMMAND through the engine (prompt.submit refuses a text that
  // begins with `/`); the stub records what reached it. The prompt.submit stub stays so a
  // regression back to a prompt is counted too (asserted zero).
  on('command.run', async (_$: any, e: any) => { w.submitted.push(e); if (hold) await hold(); if (w.onRun) w.onRun(e); return {} })
  on('turn.complete', () => ({ text: '' }))
  on('prompt.submit', (_$: any, e: any) => { w.prompted.push(e); return { text: e.text } })
  on('fs.exists', (_$: any, e: any) => ({ value: w.files.has(e.path) }))
  on('fs.stat', (_$: any, e: any) => {
    const f = w.files.get(e.path)
    return f ? { value: { kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false } } : { deny: 'ENOENT' }
  })
  on('fs.list', (_$: any, e: any) => {
    const dir = e.path.replace(/\/+$/, '') + '/'
    const out = new Map<string, any>()
    for (const [path, f] of w.files) {
      if (!path.startsWith(dir)) continue
      const rest = path.slice(dir.length), slash = rest.indexOf('/')
      const name = slash < 0 ? rest : rest.slice(0, slash)
      out.set(name, slash < 0 ? { name, kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false } : { name, kind: 'dir', size: 0, mtimeMs: 0, isLink: false })
    }
    return out.size ? { value: [...out.values()] } : { deny: 'ENOENT' }
  })
  on('fs.read', (_$: any, e: any) => {
    const f = w.files.get(e.path)
    w.reads += 1
    if (w.failReads && w.failReads.delete(e.path)) return { deny: 'EACCES' }
    return f ? { value: f.text } : { deny: 'ENOENT' }
  })
}

function world(snapshot: unknown | null, withConfig = true): World {
  const files = new Map<string, { text: string; mtimeMs: number }>()
  if (withConfig) files.set(CONFIG, { text: '{}', mtimeMs: 1 })
  if (snapshot !== null) files.set(SNAPSHOT, { text: typeof snapshot === 'string' ? snapshot : JSON.stringify(snapshot), mtimeMs: 1000 })
  return { files, logged: [], submitted: [], prompted: [], reads: 0, opened: 0, registered: [] }
}

async function open($: any) {
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: CWD })
  const out = await $.command.run({ command: 'pane', args: '' })
  return out
}

// Every string the drawing shows, joined — the assertions below read the WHOLE pane so a
// line that must be absent (question text, a description) is asserted absent everywhere.
async function shown(ui: any): Promise<string> {
  const all = await ui.findAll({ type: 'Text' })
  return all.map((el: any) => el.text).join('\n')
}

test('/pane opens the pane and draws the counts, the rail, in-flight tasks and projects', async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on)

  const out = await open($)
  expect(out).toEqual({})
  expect(w.opened).toBe(1)
  expect(w.logged).toEqual([])      // placed, so no transcript fallback line

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  // Header counts come from counts.*, whole.
  expect(text).toContain('2 project(s) · 4 task(s) · 3 awaiting you')
  // The need-you rail: verbs counted off tasks' `awaiting`, plus one close per awaiting_close.
  expect(text).toContain('need you: approve 0 · answer 1 · merge 1 · unblock 0 · close 1')
  // In flight: slug/id, the ROLE, status, the PR's mergeability and the title.
  expect(text).toContain('alpha/task-001 · software-engineer · in-progress · PR UNKNOWN · Ship the widget')
  expect(text).toContain('in flight (1)')
  // Per-project rows.
  expect(text).toContain('alpha · active · phases 1/3 · tasks 3 · in flight 1 · awaiting 2 · Alpha project')
  expect(text).toContain('beta · active · phases 2/2 · tasks 1 · in flight 0 · awaiting 1 · Beta research')
  expect(text).toContain('snapshot written 2026-10-08T01:02:03Z')
  // The allowlist, from the other side: nothing the snapshot carries that the board must
  // not show is drawn — and the description/owner fields are not drawn either.
  expect(text).not.toContain('never drawn')
  expect(text).not.toContain('example-user-007')
  expect(text).not.toContain('Q1')
  expect(text).not.toContain('github.com')
  // Both buttons exist, by key.
  expect(await ui.find({ key: 'tick' })).toBeDefined()
  expect(await ui.find({ key: 'refresh' })).toBeDefined()
  await ui.unmount()
})

test('outside a loopd bundle the pane says so and draws nothing else', async ($, on) => {
  const w = world(SNAP, false)   // a snapshot, but no instance.config.json: not a bundle
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('not a loopd bundle')
  expect(text).not.toContain('awaiting you')
  expect(text).not.toContain('need you')
  // Never read the snapshot when the cwd is not a bundle: no walk up, no second path.
  expect(w.reads).toBe(0)
  await ui.unmount()
})

test('no snapshot: the one off-switch line, with the touch that turns it on', async ($, on) => {
  const w = world(null)
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('board OFF')
  expect(text).toContain('touch .loopd/SNAPSHOT.json')
  expect(text).not.toContain('need you')
  expect(w.reads).toBe(0)
  await ui.unmount()
})

test('malformed JSON is one error line and no throw; wrong types draw as 0', async ($, on) => {
  const w = world('{ this is not json')
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  let text = await shown(ui)
  expect(text).toContain('not valid JSON')
  expect(text).not.toContain('need you')

  // Valid JSON, wrong types (conventions 11d): every number goes through toint().
  w.files.set(SNAPSHOT, { text: JSON.stringify({ counts: { projects: 'many', tasks: null, awaiting: -3 }, projects: 'nope', group: 7 }), mtimeMs: 2000 })
  await ui.press({ key: 'refresh' })
  text = await shown(ui)
  expect(text).toContain('0 project(s) · 0 task(s) · 0 awaiting you')
  expect(text).toContain('projects (0)')
  await ui.unmount()
})

test('a title carrying a newline, a tab, ESC and a bidi override is drawn without them, and a number is never clipped', async ($, on) => {
  const snap = JSON.parse(JSON.stringify(SNAP))
  snap.projects[0].tasks[0].title = 'Ship\nthe\u001b[2Jwidget\u202e now\tplease'
  snap.projects[0].title = 'Alpha\u0000project'
  snap.counts.tasks = 1234567890
  const w = world(snap)
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  // print-board.sh's rule, matched exactly: every category-C code point is dropped and
  // the whitespace controls become one space \u2014 so the newline is a space, the tab is a
  // space, ESC and the bidi override are gone, and the `[2J` that followed ESC arrives as
  // inert text (its own docstring says so). A CSI stripper would be a blocklist of known
  // sequences, which conventions 11 rejects; a terminal acts on none of this without ESC.
  expect(text).toContain('Ship the[2Jwidget now please')
  expect(text).toContain('Alphaproject')
  expect(text).not.toContain('\u001b')
  expect(text).not.toContain('\u202e')
  expect(text).not.toContain('\n  alpha/task-001 \u00b7 software-engineer \u00b7 in-progress \u00b7 PR UNKNOWN \u00b7 Ship\n')  // no forged row
  expect(text).toContain('1234567890 task(s)')
  await ui.unmount()
})

test('Tick runs exactly /loopd:dispatch, once per press, never as a prompt', async ($, on) => {
  const w = world(SNAP)
  const clock = mock.clock(on)
  // The real engine queues a plugin's command run until the session is idle; the stub
  // stands in for that wait by sleeping on the mock clock until the test advances it.
  stubs(on, w, true, () => clock.sleep(1000))
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'tick' })
  // A refused run is drawn, so a failure here shows the engine's reason in the dump.
  expect(await shown(ui)).not.toContain('tick refused')
  expect(w.submitted.length).toBe(1)
  expect((w.submitted[0] as any).command).toBe('loopd:dispatch')
  expect(w.prompted).toEqual([])            // never as a prompt: the engine refuses a `/` text there
  expect(await shown(ui)).toContain('tick queued')
  // A second press while the first is still in flight is one tick, not two.
  await ui.press({ key: 'tick' })
  expect(w.submitted.length).toBe(1)
  // Once the run has gone through, the footer clears and the next press is a new tick.
  await clock.advance(1000)
  expect(await shown(ui)).not.toContain('tick queued')
  await ui.press({ key: 'tick' })
  expect(w.submitted.length).toBe(2)
  await ui.unmount()
})

test('the poll re-reads only when the mtime moved, and Refresh re-reads regardless', async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  expect(w.reads).toBe(1)
  // Three polls over an unchanged file: stat only, no read.
  await clock.advance(5000)
  await clock.advance(5000)
  await clock.advance(5000)
  expect(w.reads).toBe(1)
  // The writer rewrote the file: the next poll reads it and the drawing follows.
  const moved = JSON.parse(JSON.stringify(SNAP)); moved.counts.awaiting = 9
  w.files.set(SNAPSHOT, { text: JSON.stringify(moved), mtimeMs: 2000 })
  await clock.advance(5000)
  expect(w.reads).toBe(2)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('9 awaiting you')
  // Refresh reads even with no mtime change.
  await ui.press({ key: 'refresh' })
  expect(w.reads).toBe(3)
  // Nothing was run or submitted by a timer or a refresh.
  expect(w.submitted).toEqual([])
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('where no surface places the pane, one transcript line carries the summary', async ($, on) => {
  const w = world(SNAP)
  stubs(on, w, false)   // a narrow terminal: the pane is open but waits undrawn
  mock.clock(on)
  await open($)
  expect(w.logged).toEqual(['loopd board: 2 project(s) · 4 task(s) · 3 awaiting you'])
})

test('a non-interactive session registers the command and says nothing', async ($, on) => {
  const w = world(SNAP)
  stubs(on, w)
  mock.clock(on)
  await $.session.start({ surface: 'terminal', isInteractive: false, cwd: CWD })
  expect(w.registered).toEqual(['pane'])
  expect(w.logged).toEqual([])
  expect(w.reads).toBe(0)
  expect(w.submitted).toEqual([])
})

// ---------------------------------------------------------------- simple mode
// The task documents the simple mode reads, shaped as a bundle writes them. Everything an
// operator sees — roles, worktrees, branches, PR links, blocker text — is in them on purpose,
// so the absence assertions below are about what the pane DRAWS, not what the fixture lacks.
const P = CWD + '/projects'
function task(fm: string, body = ''): string { return '---\ntype: Task\n' + fm + '\n---\n\n# Context\n\nx\n' + body }
const DOCS: Record<string, string> = {
  [P + '/alpha/project.md']: '---\ntype: Project\ntitle: "Alpha project"\nstatus: active\n---\n',
  [P + '/alpha/tasks/task-001-widget.md']: task('title: "Ship the widget"\nstatus: in-progress\nassignee: software-engineer\nworktree: /work/_wt/task-001\nbranch: alpha-task-001\nsession: 0e2a071d\npr: [ "https://github.com/o/r/pull/7" ]\nopen_questions: [ ]'),
  [P + '/alpha/tasks/task-002-colour.md']: task(
    'title: "Decide the colour"\nstatus: draft\nopen_questions: [ "Q1: Which colour, given the brand, ships first?", "Q2: Old one? --- already answered" ]',
    '\n## Question details\n\n### Q1\nRecommendation: Blue, the brand colour\nOptions:\n1. Blue, the brand colour\n2. Green\n3. Let the designer pick\nContext:\n- Depth 1: one\n- Depth 2: two\n- Depth 3: three\n'),
  [P + '/alpha/tasks/task-003-stuck.md']: task('title: "Import the archive"\nstatus: blocked\nassignee: devops-engineer\nlast_blocker: "PR checks red in the worktree after round 2 of the agent session"\nopen_questions: [ ]'),
  [P + '/alpha/tasks/task-004-done.md']: task("title: 'Done already'\nstatus: done\nopen_questions: [ ]"),
  [P + '/alpha/tasks/task-005-dropped.md']: task('title: "Dropped"\nstatus: cancelled\nopen_questions: [ ]'),
  [P + '/alpha/tasks/task-006-name.md']: task('title: "Name it"\nstatus: draft\nopen_questions:\n  - "Q1: What should it be called?"'),
  [P + '/beta/project.md']: '---\ntype: Project\ntitle: "Beta closed"\nstatus: done\n---\n',
  [P + '/beta/tasks/task-001-x.md']: task('title: "Never shown"\nstatus: blocked\nopen_questions: [ "Q1: hidden?" ]'),
  [P + '/gamma/tasks/task-001-broken.md']: task('title: "Broken list"\nstatus: draft\nopen_questions: [ "Q1: unterminated'),
}
function bundle(snapshot: unknown | null = SNAP): World {
  const w = world(snapshot)
  for (const [path, text] of Object.entries(DOCS)) w.files.set(path, { text, mtimeMs: 1000 })
  return w
}
const SIMPLE = { options: { mode: 'simple' } }
// Everything the pane shows: Text, and the labels of its Buttons and Inputs.
async function everything(ui: any): Promise<string> {
  const els = [...await ui.findAll({ type: 'Text' }), ...await ui.findAll({ type: 'Button' }), ...await ui.findAll({ type: 'Input' })]
  return els.map((el: any) => [el.text, el.props.label, el.props.placeholder].filter(Boolean).join(' ')).join('\n')
}

test('ONE SWITCH: with no option stored, the manifest default draws the operator board', async ($, on) => {
  const w = bundle()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('need you: approve 0')
  expect(text).not.toContain('Questions for you')
  await ui.unmount()
})

test('ONE SWITCH: instance.config.json saying simple does not switch the mode — only the option does', async ($, on) => {
  const w = bundle()
  w.files.set(CONFIG, { text: '{"mode":"simple","pane":{"mode":"simple"}}', mtimeMs: 1 })
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('need you:')
  await ui.unmount()
})

test('SIMPLE SHOWS THREE THINGS: a bar per project, each open question, each blocked task — nothing else', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const text = await everything(ui)
  // Projects: done/total off the task statuses (cancelled is not counted), a closed project left out.
  expect(text).toContain('██░░░░░░░░ 1/5 done · Alpha project')
  expect(text).toContain('0/1 done · gamma')
  expect(text).not.toContain('Beta closed')
  expect(text).not.toContain('Never shown')
  // A question: its text, the recommendation first, the other options, a text field, More.
  expect(text).toContain('Which colour, given the brand, ships first?')
  const labels = (await ui.findAll({ type: 'Button' })).map((b: any) => b.props.label)
  expect(labels.slice(0, 4)).toEqual(['Recommended: Blue, the brand colour', 'Green', 'Let the designer pick', 'More'])
  expect(await ui.find({ key: 'q1-text' })).toBeDefined()
  // A question with no details block: the text field and More, no options.
  expect(text).toContain('What should it be called?')
  expect(await ui.find({ key: 'q2-opt1' })).toBeUndefined()
  expect(await ui.find({ key: 'q2-text' })).toBeDefined()
  expect(await ui.find({ key: 'q2-more' })).toBeDefined()
  // An answered entry is not a question; an unparseable list is said, not guessed at.
  expect(text).not.toContain('Old one?')
  expect(text).toContain('Could not read the questions in "Broken list"')
  // A blocked task: one plain sentence with its verb, and never the blocker text.
  expect(text).toContain('Unblock "Import the archive" in Alpha project: it cannot move until you do.')
  // NOTHING ELSE: no operator vocabulary anywhere the pane draws.
  for (const banned of [/agent/i, /tick/i, /\bPR\b/, /pull/i, /session/i, /usage/i, /\bround/i, /worktree/i, /branch/i, /engineer/i, /snapshot/i, /github/i]) {
    expect(text).not.toMatch(banned)
  }
  // Read from the task documents, never from the snapshot.
  expect(w.files.has(SNAPSHOT)).toBe(true)
  await ui.unmount()
})

test('PINK MEANS YOU: a question and a blocked task are drawn #ff7ac2, every other line is not', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const pink = (await ui.findAll({ type: 'Text' })).filter((el: any) => el.props.color !== undefined)
  expect(pink.map((el: any) => el.props.color)).toEqual(['#ff7ac2', '#ff7ac2', '#ff7ac2'])
  expect(pink.map((el: any) => el.text.trim())).toEqual([
    'Which colour, given the brand, ships first?',
    'What should it be called?',
    'Unblock "Import the archive" in Alpha project: it cannot move until you do.',
  ])
  await ui.unmount()
})

test('EVERY ACTION IS A COMMAND: option, text and more each run /loopd:answer, one at a time', SIMPLE, async ($, on) => {
  const w = bundle()
  const clock = mock.clock(on)
  stubs(on, w, true, () => clock.sleep(1000))
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'q1-more' })
  expect(w.submitted[0]).toMatchObject({ command: 'loopd:answer', args: 'projects/alpha/tasks/task-002-colour.md Q1 more' })
  await clock.advance(1000)
  expect(await shown(ui)).toContain('is in the conversation')
  await ui.press({ key: 'q1-opt2' })
  expect(w.submitted[1]).toMatchObject({ command: 'loopd:answer', args: 'projects/alpha/tasks/task-002-colour.md Q1 2' })
  // While it is queued nothing else can be pressed, and the question says so.
  expect(await shown(ui)).toContain('Sending your answer…')
  expect(await ui.find({ key: 'q1-opt1' })).toBeUndefined()
  expect(await ui.find({ key: 'q2-text' })).toBeUndefined()
  await clock.advance(1000)
  // The run is through but the document has not moved: still held, so it cannot be answered twice.
  expect(await shown(ui)).toContain('Sending your answer…')
  expect(await ui.find({ key: 'q1-opt1' })).toBeUndefined()
  await ui.input({ key: 'q2-text', text: '  Widget\tPro  ' })
  expect(w.submitted[2]).toMatchObject({ command: 'loopd:answer', args: 'projects/alpha/tasks/task-006-name.md Q1 --text Widget Pro' })
  await clock.advance(1000)
  expect(w.submitted.length).toBe(3)
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('an answered question leaves the pane on the next read; a refused run is said', SIMPLE, async ($, on) => {
  const w = bundle()
  const path = P + '/alpha/tasks/task-002-colour.md'
  w.onRun = () => w.files.set(path, { text: DOCS[path].replace('open_questions: [ "Q1:', 'open_questions: [ ]\nanswered: [ "Q1:'), mtimeMs: 2000 })
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'q1-opt1' })
  expect(await shown(ui)).not.toContain('Which colour')
  w.onRun = () => { throw new Error('the command is not available') }
  await ui.press({ key: 'q1-more' })
  expect(await shown(ui)).toContain('Could not send that answer: ')
  expect(await shown(ui)).toContain('What should it be called?')
  await ui.unmount()
})

test('the bar follows the task documents: the poll re-reads only a file whose mtime moved', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const first = w.reads
  await clock.advance(5000)
  expect(w.reads).toBe(first)
  const path = P + '/alpha/tasks/task-006-name.md'
  w.files.set(path, { text: DOCS[path].replace('status: draft', 'status: done'), mtimeMs: 3000 })
  await clock.advance(5000)
  expect(w.reads).toBe(first + 1)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('████░░░░░░ 2/5 done · Alpha project')
  expect(w.submitted).toEqual([])
  await ui.unmount()
})

test('a failed read is retried on the next scan, not cached under the unchanged mtime', SIMPLE, async ($, on) => {
  const w = bundle()
  w.failReads = new Set([P + '/alpha/tasks/task-002-colour.md'])
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await shown(ui)).toContain('Could not read the questions in "task-002-colour.md"')
  await ui.press({ key: 'refresh' })
  expect(await shown(ui)).toContain('Which colour, given the brand, ships first?')
  await ui.unmount()
})

test('a held answer is released when its own turn ends without moving the document', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await clock.advance(10000)
  await ui.press({ key: 'q1-opt2' })
  expect(await ui.find({ key: 'q1-opt1' })).toBeUndefined()
  // A turn that was already running before the press is not the answer's turn.
  await clock.advance(1000)
  await $.turn.complete({ turnId: 'before', answer: '', durationMs: 5000, isAborted: false, usage: null, reason: 'answer' })
  expect(await shown(ui)).toContain('Sending your answer…')
  // The answer's turn ends and answer.sh wrote nothing (it refused): the controls come back.
  await clock.advance(1000)
  await $.turn.complete({ turnId: 'answer', answer: '', durationMs: 500, isAborted: false, usage: null, reason: 'answer' })
  expect(await shown(ui)).not.toContain('Sending your answer…')
  expect(await shown(ui)).toContain('did not change the task')
  expect(await ui.find({ key: 'q1-opt1' })).toBeDefined()
  await ui.unmount()
})

// ---------------------------------------------------------------- a new project
// The four fields, as a person types them: a quote in the title proves the escaping.
const FORM = { title: 'Garden "log"', what: 'A log of what grows', whom: 'The allotment group', done: 'Every bed has an entry; a weekly summary' }
const CREATE_ARGS = '"A log of what grows" kind=build autonomy=yolo title="Garden \\"log\\"" need="The allotment group" success_criteria="Every bed has an entry; a weekly summary" --no-ask'
async function fill(ui: any, form: Record<string, string>) {
  for (const [k, v] of Object.entries(form)) await ui.input({ key: 'new-' + k, text: v })
}
// What /loopd:new-project leaves on disk: a project and its one seed task, no questions yet.
function scaffold(w: World, autonomy = 'yolo') {
  w.files.set(P + '/garden-log/project.md', { text: '---\ntype: Project\ntitle: "Garden \\"log\\""\nstatus: active\nautonomy: ' + autonomy + '\n---\n', mtimeMs: 4000 })
  w.files.set(P + '/garden-log/tasks/task-001-garden-log.md', { text: task('title: "Garden log"\nstatus: draft\nopen_questions: [ ]'), mtimeMs: 4000 })
}

test('FOUR FIELDS, ONE COMMAND: a filled form runs /loopd:new-project once with the four values', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await fill(ui, FORM)
  expect(w.submitted).toEqual([])
  await ui.press({ key: 'new-create' })
  expect(w.submitted.length).toBe(1)
  expect(w.submitted[0]).toMatchObject({ command: 'loopd:new-project', args: CREATE_ARGS })
  // Queued: the button is gone, so a second press cannot create it twice; no timer re-runs it.
  expect(await ui.find({ key: 'new-create' })).toBeUndefined()
  expect(await shown(ui)).toContain('Creating "Garden "log""…')
  await clock.advance(60000)
  expect(w.submitted.length).toBe(1)
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('KIT: an empty title runs nothing, and says why', SIMPLE, async ($, on) => {
  const w = bundle()
  stubs(on, w)
  mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await fill(ui, { ...FORM, title: '   ' })
  await ui.press({ key: 'new-create' })
  expect(w.submitted).toEqual([])
  expect(await shown(ui)).toContain('Fill in all four fields to create a project.')
  expect(await ui.find({ key: 'new-create' })).toBeDefined()
  await ui.unmount()
})

test('THE PERSON SEES THE RESULT: the new project appears on the next read, then its first questions', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = () => scaffold(w)
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await fill(ui, FORM)
  await ui.press({ key: 'new-create' })
  // A directory with no project document yet is not the result.
  const doc = w.files.get(P + '/garden-log/project.md')!
  w.files.delete(P + '/garden-log/project.md')
  await clock.advance(5000)
  expect(await shown(ui)).toContain('Creating "Garden "log""…')
  w.files.set(P + '/garden-log/project.md', doc)
  await clock.advance(5000)
  let text = await shown(ui)
  expect(text).toContain('0/1 done · Garden "log"')
  expect(text).toContain('Created "Garden "log"". Its first questions will appear here.')
  expect(await ui.find({ key: 'new-create' })).toBeDefined()
  // The form is empty again, ready for the next one.
  expect((await ui.find({ key: 'new-title' })).props.value).toBe('')
  const path = P + '/garden-log/tasks/task-001-garden-log.md'
  w.files.set(path, { text: task('title: "Garden log"\nstatus: draft\nopen_questions: [ "Q1: Which beds come first?" ]'), mtimeMs: 5000 })
  await clock.advance(5000)
  text = await shown(ui)
  expect(text).toContain('Garden "log" · Garden log')
  expect(text).toContain('Which beds come first?')
  await ui.unmount()
})

test('a project the operator must approve step by step says so in one sentence', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = () => scaffold(w, 'gated')
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await fill(ui, FORM)
  await ui.press({ key: 'new-create' })
  await clock.advance(5000)
  expect(await shown(ui)).toContain('Created "Garden "log"". It moves only as far as the operator approves.')
  await ui.unmount()
})

test('NOTHING IS WRITTEN BY THE MOD: a refused or failed create is one line, never retried', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = () => { throw new Error('the command is not available') }
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await fill(ui, FORM)
  await ui.press({ key: 'new-create' })
  expect((await shown(ui)).split('\n').filter(l => l.includes('Could not create the project: ')).length).toBe(1)
  // Failed: the run went through, its turn ended, and no project appeared.
  w.onRun = undefined
  await clock.advance(10000)
  await ui.press({ key: 'new-create' })
  await clock.advance(1000)
  await $.turn.complete({ turnId: 'create', answer: '', durationMs: 500, isAborted: false, usage: null, reason: 'answer' })
  expect(await shown(ui)).toContain('The project was not created — the conversation says why.')
  expect(await ui.find({ key: 'new-create' })).toBeDefined()
  expect((await ui.find({ key: 'new-title' })).props.value).toBe(FORM.title)
  await clock.advance(60000)
  expect(w.submitted.length).toBe(2)
  expect(w.prompted).toEqual([])
  await ui.unmount()
})

test('a project someone else adds while a create is pending is not taken for it', SIMPLE, async ($, on) => {
  const w = bundle()
  w.onRun = () => w.files.set(P + '/other-thing/project.md', { text: '---\ntype: Project\ntitle: "Other thing"\nstatus: active\nautonomy: gated\n---\n', mtimeMs: 4000 })
  stubs(on, w)
  const clock = mock.clock(on)
  await open($)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await fill(ui, FORM)
  await ui.press({ key: 'new-create' })
  await clock.advance(5000)
  let text = await shown(ui)
  expect(text).toContain('Other thing')
  expect(text).not.toContain('Created "')
  expect(text).toContain('Creating "Garden "log""…')
  scaffold(w)
  await clock.advance(5000)
  text = await shown(ui)
  expect(text).toContain('Created "Garden "log"". Its first questions will appear here.')
  expect((await ui.find({ key: 'new-title' })).props.value).toBe('')
  await ui.unmount()
})
