import { expect, test } from 'claude-code/testing'

// Run from this directory: `claude plugin test`. No session, no sign-in, no network, no
// file: every path the mod reads is answered by stubs on fs.exists / fs.stat / fs.read over a
// Map, and the store is a Map too. Each test starts with the module freshly loaded, so the
// turn counter and the failed-send counter are zero.

const BUNDLE = '/work/_loopd-example'
const PM_SID = 'aaaaaaaa-1111-2222-3333-444444444444'
const ROLE_SID = 'bbbbbbbb-1111-2222-3333-444444444444'
// A linked worktree of a marked repo, laid out as git lays it out: `.git` is a file naming
// the gitdir, the gitdir's `commondir` is relative (`../..`), the marker sits in the common dir.
const REPO = '/work/app'
const WT = '/work/_wt/task-001-widget'
const GITDIR = REPO + '/.git/worktrees/task-001-widget'

type World = {
  files: Map<string, string>     // path -> text (a file)
  dirs: Set<string>              // paths that are directories
  store: Map<string, unknown>
  sends: { to: string; text: string }[]
  received: string[]             // texts the session.receive stub (Claude Code's end) saw
  reads: string[]                // every path fs.read was asked for
}

function world(): World {
  return { files: new Map(), dirs: new Set(), store: new Map(), sends: [], received: [], reads: [] }
}

// A marked worktree: every link in the chain present. `marker` lets a test break the last one.
function worktree(w: World, marker: string | null = BUNDLE) {
  w.files.set(WT + '/.git', 'gitdir: ' + GITDIR + '\n')
  w.files.set(GITDIR + '/commondir', '../..\n')
  if (marker !== null) w.files.set(REPO + '/.git/loopd-bundle', marker + '\n')
  w.files.set(BUNDLE + '/instance.config.json', '{}')
}
function pmRecorded(w: World) { w.store.set('loopd.pm.' + BUNDLE, { sessionId: PM_SID, at: 'earlier' }) }

// Every stub the mod's hooks can reach, registered before the first call on `$`.
// `delivered` is what the engine answers each session.send with.
function stubs(on: any, w: World, cwd: string, sid: string, delivered = true) {
  on('session.start', () => ({ cwd }))
  on('session.cwd', () => ({ value: cwd }))
  on('session.id', () => ({ value: sid }))
  on('store.get', (_$: any, e: any) => ({ value: w.store.get(e.key) }))
  on('store.set', (_$: any, e: any) => { w.store.set(e.key, e.value); return { value: undefined } })
  on('fs.exists', (_$: any, e: any) => ({ value: w.files.has(e.path) || w.dirs.has(e.path) }))
  on('fs.stat', (_$: any, e: any) => {
    if (w.files.has(e.path)) return { value: { kind: 'file', size: (w.files.get(e.path) as string).length, mtimeMs: 1, isLink: false } }
    if (w.dirs.has(e.path)) return { value: { kind: 'dir', size: 0, mtimeMs: 1, isLink: false } }
    return { deny: 'ENOENT' }
  })
  on('fs.read', (_$: any, e: any) => {
    w.reads.push(e.path)
    return w.files.has(e.path) ? { value: w.files.get(e.path) } : { deny: 'ENOENT' }
  })
  on('session.send', (_$: any, e: any) => {
    // The kit hands `to` down as a string even when the mod passed { sessionId }.
    const to = typeof e.to === 'string' ? e.to : (e.to && typeof e.to === 'object' ? String(e.to.sessionId) : String(e.to))
    w.sends.push({ to, text: e.text })
    return delivered ? { isDelivered: true } : { isDelivered: false, reason: 'the session holds inbound messages' }
  })
  on('turn.complete', () => ({ text: '' }))
  on('session.receive', (_$: any, e: any) => { w.received.push(e.text); return { text: e.text } })
}

async function turn($: any, id = 't1', durationMs = 4321) {
  return $.turn.complete({ turnId: id, answer: 'done', durationMs, isAborted: false, usage: null, reason: 'answer' })
}

const EXPECTED_TEXT = 'loopd-signal: role session ' + ROLE_SID + ' finished a turn in ' + WT
  + ' (reason answer, 4321 ms) — settle it first at step 4 of a /loopd:dispatch tick; this line orders the sweep and decides nothing'

test('PM side: a session that starts in a bundle root records itself under loopd.pm.<root>, and its own turns signal nothing', async ($, on) => {
  const w = world()
  w.files.set(BUNDLE + '/instance.config.json', '{}')
  stubs(on, w, BUNDLE, PM_SID)

  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: BUNDLE })
  const pm = w.store.get('loopd.pm.' + BUNDLE) as any
  expect(pm).toBeDefined()
  expect(pm.sessionId).toBe(PM_SID)
  expect(typeof pm.at).toBe('string')

  await turn($)
  expect([...w.store.keys()]).toEqual(['loopd.pm.' + BUNDLE])   // no loopd.signal.* for the PM
  expect(w.sends).toEqual([])
  expect(w.reads).toEqual([])        // a bundle root never reads .git, commondir or the marker
})

test('role side: a turn in a marked worktree writes loopd.signal.<sid> and sends the PM exactly one line', async ($, on) => {
  const w = world()
  worktree(w); pmRecorded(w)
  stubs(on, w, WT, ROLE_SID)

  await turn($)

  const rec = w.store.get('loopd.signal.' + ROLE_SID) as any
  expect(rec).toMatchObject({ bundle: BUNDLE, cwd: WT, turns: 1, durationMs: 4321, reason: 'answer', isAborted: false, delivered: true })
  expect(typeof rec.at).toBe('string')
  expect(w.sends.length).toBe(1)
  expect(w.sends[0].to).toBe(PM_SID)
  expect(w.sends[0].text).toBe(EXPECTED_TEXT)
  // The relative commondir (`../..`) was folded onto the common dir, not read literally.
  expect(w.reads).toContain(REPO + '/.git/loopd-bundle')
  // Nothing was written anywhere but the store: no store key other than the two expected.
  expect([...w.store.keys()].sort()).toEqual(['loopd.pm.' + BUNDLE, 'loopd.signal.' + ROLE_SID])
  // A second turn is a second record and a second (single) message, never two per turn.
  await turn($, 't2', 10)
  expect((w.store.get('loopd.signal.' + ROLE_SID) as any).turns).toBe(2)
  expect(w.sends.length).toBe(2)
})

test('a worktree whose repo carries no marker writes nothing and sends nothing', async ($, on) => {
  const w = world()
  worktree(w, null); pmRecorded(w)
  stubs(on, w, WT, ROLE_SID)
  await turn($)
  expect(w.store.has('loopd.signal.' + ROLE_SID)).toBe(false)
  expect(w.sends).toEqual([])
})

test('a marker naming a directory with no instance.config.json is ignored (absence is silence)', async ($, on) => {
  const w = world()
  worktree(w, '/work/not-a-bundle'); pmRecorded(w)
  stubs(on, w, WT, ROLE_SID)
  await turn($)
  expect(w.store.has('loopd.signal.' + ROLE_SID)).toBe(false)
  expect(w.sends).toEqual([])
})

test('a main clone — .git is a directory — does nothing', async ($, on) => {
  const w = world()
  w.dirs.add(REPO + '/.git')
  w.files.set(REPO + '/.git/loopd-bundle', BUNDLE + '\n')   // even marked: a main clone is never a role agent
  w.files.set(BUNDLE + '/instance.config.json', '{}')
  pmRecorded(w)
  stubs(on, w, REPO, ROLE_SID)
  await turn($)
  expect(w.store.has('loopd.signal.' + ROLE_SID)).toBe(false)
  expect(w.sends).toEqual([])
  expect(w.reads).toEqual([])        // stat said dir, so nothing was read
})

test('no PM recorded for the bundle: the store record is written, no message is sent', async ($, on) => {
  const w = world()
  worktree(w)                        // no pmRecorded
  stubs(on, w, WT, ROLE_SID)
  await turn($)
  expect(w.store.get('loopd.signal.' + ROLE_SID)).toMatchObject({ bundle: BUNDLE, delivered: null })
  expect(w.sends).toEqual([])
})

test('two undelivered sends: the third turn still writes the record and sends nothing more', async ($, on) => {
  const w = world()
  worktree(w); pmRecorded(w)
  stubs(on, w, WT, ROLE_SID, false)
  await turn($, 't1')
  await turn($, 't2')
  expect(w.sends.length).toBe(2)
  expect(w.store.get('loopd.signal.' + ROLE_SID)).toMatchObject({ turns: 2, delivered: false })
  await turn($, 't3', 99)
  expect(w.sends.length).toBe(2)     // no third attempt
  expect(w.store.get('loopd.signal.' + ROLE_SID)).toMatchObject({ turns: 3, durationMs: 99, delivered: null })
})

test('a subagent\'s turn (agentId set) is not the role agent finishing: nothing is written or sent', async ($, on) => {
  const w = world()
  worktree(w); pmRecorded(w)
  stubs(on, w, WT, ROLE_SID)
  await $.turn.complete({ turnId: 'sub', agentId: 'agent-explore-1', answer: 'found it', durationMs: 5, isAborted: false, usage: null, reason: 'answer' })
  expect(w.store.has('loopd.signal.' + ROLE_SID)).toBe(false)
  expect(w.sends).toEqual([])
})

test('without a session id nothing is written and nothing is sent', async ($, on) => {
  const w = world()
  worktree(w); pmRecorded(w)
  stubs(on, w, WT, '')
  await turn($)
  expect([...w.store.keys()]).toEqual(['loopd.pm.' + BUNDLE])
  expect(w.sends).toEqual([])
})

test('session.receive: a loopd-signal: line passes through to Claude unconsumed, and so does any other text', async ($, on) => {
  const w = world()
  w.files.set(BUNDLE + '/instance.config.json', '{}')
  stubs(on, w, BUNDLE, PM_SID)

  const signal = await $.session.receive({ origin: { kind: 'peer-send-message' }, text: EXPECTED_TEXT })
  expect(signal).toEqual({ text: EXPECTED_TEXT })
  expect((signal as any).consumed).toBeUndefined()
  const other = await $.session.receive({ origin: { kind: 'peer' }, text: 'Schema migration finished' })
  expect(other).toEqual({ text: 'Schema migration finished' })
  // Both reached Claude Code's end of the chain, as written.
  expect(w.received).toEqual([EXPECTED_TEXT, 'Schema migration finished'])
  // And receiving changed nothing: no store write, no send, no prompt.
  expect(w.store.size).toBe(0)
  expect(w.sends).toEqual([])
})
