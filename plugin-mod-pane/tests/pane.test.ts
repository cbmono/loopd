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
}

// Every stub the mod's hooks can reach, registered before the first call on `$`.
// `placed` is what the surface answers $.ui.open with: false is a terminal too narrow.
// `hold` makes the dispatch run stay in flight until the test lets it go (a mock-clock sleep).
function stubs(on: any, w: World, placed = true, hold?: () => Promise<void>) {
  on('session.start', () => ({ cwd: CWD }))
  on('command.register', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: CWD }))
  on('ui.log', (_$: any, e: any) => { w.logged.push(e.text); return { value: undefined } })
  on('ui.open', () => { w.opened += 1; return { value: placed ? { isPlaced: true } : { isPlaced: false, reason: 'the terminal is 80 columns' } } })
  on('ui.close', () => ({}))
  // Tick runs the dispatch COMMAND through the engine (prompt.submit refuses a text that
  // begins with `/`); the stub records what reached it. The prompt.submit stub stays so a
  // regression back to a prompt is counted too (asserted zero).
  on('command.run', async (_$: any, e: any) => { w.submitted.push(e); if (hold) await hold(); return {} })
  on('prompt.submit', (_$: any, e: any) => { w.prompted.push(e); return { text: e.text } })
  on('fs.exists', (_$: any, e: any) => ({ value: w.files.has(e.path) }))
  on('fs.stat', (_$: any, e: any) => {
    const f = w.files.get(e.path)
    return f ? { value: { kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false } } : { deny: 'ENOENT' }
  })
  on('fs.read', (_$: any, e: any) => {
    const f = w.files.get(e.path)
    w.reads += 1
    return f ? { value: f.text } : { deny: 'ENOENT' }
  })
}

function world(snapshot: unknown | null, withConfig = true): World {
  const files = new Map<string, { text: string; mtimeMs: number }>()
  if (withConfig) files.set(CONFIG, { text: '{}', mtimeMs: 1 })
  if (snapshot !== null) files.set(SNAPSHOT, { text: typeof snapshot === 'string' ? snapshot : JSON.stringify(snapshot), mtimeMs: 1000 })
  return { files, logged: [], submitted: [], prompted: [], reads: 0, opened: 0 }
}

async function open($: any) {
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: CWD })
  const out = await $.command.run({ command: 'board', args: '' })
  return out
}

// Every string the drawing shows, joined — the assertions below read the WHOLE pane so a
// line that must be absent (question text, a description) is asserted absent everywhere.
async function shown(ui: any): Promise<string> {
  const all = await ui.findAll({ type: 'Text' })
  return all.map((el: any) => el.text).join('\n')
}

test('/board opens the pane and draws the counts, the rail, in-flight tasks and projects', async ($, on) => {
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
  expect(w.logged).toEqual([])
  expect(w.reads).toBe(0)
  expect(w.submitted).toEqual([])
})
